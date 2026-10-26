class_name BossBrain
extends Node
## Server-authoritative boss state machine. Sits under a boss Enemy as the
## child "BossBrain" (the world adds it in _spawn_mob_fn on every peer, so the
## node path matches and RPCs reach it). Only the authority (offline, or the
## server) ever runs tick(); clients hold a display copy that derives the HP
## bars from the replicated hp and receives events through net_event.
##
## Pattern for every later boss:
##   - stacked HP bars (bar_count / current_bar / bar_fraction): a bar break
##     is an event ("bar_break"), calls in adds and gives the party a beat;
##   - the final bar is a phase change ("enrage": a roar with stagger immunity,
##     then the second moveset from PRESETS[preset]["phases"][1]);
##   - every move is telegraphed ("telegraph" event, then "impact"): slam is
##     an AoE ring you dodge (never parried), charge is a line that is parried
##     at the moment it reaches you, sweep is a wide arc you parry;
##   - parries build the Enemy's posture as before (3 = stagger, riposte);
##   - leash: nobody alive on the arena for reset_grace seconds -> full reset
##     ("reset"), adds removed; adds also vanish when the boss dies.
##
## Visual hooks (all behind has_method on VFX.get_for(enemy); the visuals
## thread fills them in): boss_engage(enemy), boss_sweep_warning(enemy, reach,
## arc_deg, secs), boss_sweep_impact(enemy, reach, arc_deg),
## boss_charge_warning(enemy, from, to, secs), boss_charge_impact(enemy, pos),
## boss_slam_warning(enemy, pos, radius, secs), boss_slam_impact(enemy, pos,
## radius), boss_bar_break(enemy, bar_left, bars), boss_enrage(enemy, secs),
## boss_reset(enemy). Fallbacks use the existing ring / dust_ring / glint.

## Every event, on every peer: "engage", "telegraph" {move, secs, pos, ...},
## "impact" {move, pos, ...}, "bar_break" {bar, bars}, "enrage" {secs},
## "phase" {phase}, "reset" {reason}, "death". The HUD / boss plate listen here.
signal boss_event(kind: String, data: Dictionary)

enum State { IDLE, ENGAGE, WINDUP, CHARGE, RECOVER, BREAK, ENRAGE }
const STATE_NAMES := ["idle", "engage", "windup", "charge", "recover", "break", "enrage"]
const MOVES := ["sweep", "charge", "slam"]

## Tuning per boss. Phase 0 is the opening moveset, phase 1 the final bar's.
## Windups are seconds of telegraph; "mult" scales Enemy.damage; "cooldown"
## is the [min, max] pause between moves; "chain" is the chance a sweep is
## followed at once by a second one.
##
## "warlord" is the Floor 1 Guardian, a kobold warlord in the mould of the
## first floor's boss in the old stories: four bars; a guard of armored
## halberdiers at the start and three more on every bar break; axe and
## buckler for three bars (a 180-degree cleave to parry, a buckler rush, a
## leaping smash that lands where you stood); at the last bar he throws both
## away and draws a long curved blade ("weapon_swap"): twice as fast, a full
## spinning cut that chains, longer leaps. No arena hazards: the room is
## bare stone, the fight is him and his guard.
## Optional keys: "start_adds" (spawned on engage), "max_adds" (living cap),
## "leap" per phase {"min","max","recover"}: the slam becomes a leap onto the
## target's spot, "rockfall" (see _hazard_tick), "swap" (event on enrage).
const PRESETS := {
	"warlord": {
		"bars": 4,
		"reset_grace": 4.0,
		"break_time": 1.2,
		"enrage_time": 2.0,
		"start_adds": 3,
		"adds": [3, 3],
		"max_adds": 6,
		"swap": {"from": "axe and buckler", "to": "curved longblade"},
		"phases": [
			{
				"windup": {"sweep": 0.6, "charge": 0.7, "slam": 1.0},
				"cooldown": [1.6, 2.6],
				"sweep_reach": 1.6, "sweep_arc": 180.0, "sweep_mult": 1.0,
				"charge_min": 4.0, "charge_max": 9.0, "charge_speed": 12.0, "charge_mult": 1.3,
				"slam_radius": 4.0, "slam_mult": 2.4, "slam_cd": 7.0,
				"leap": {"min": 6.0, "max": 14.0, "recover": 2.0},
				"chain": 0.0,
			},
			{
				"windup": {"sweep": 0.45, "charge": 0.5, "slam": 0.75},
				"cooldown": [0.7, 1.3],
				"sweep_reach": 1.9, "sweep_arc": 360.0, "sweep_mult": 1.15, "style": "whirl",
				"charge_min": 4.0, "charge_max": 18.0, "charge_speed": 22.0, "charge_mult": 1.7,
				"slam_radius": 4.5, "slam_mult": 2.2, "slam_cd": 5.0,
				"leap": {"min": 5.0, "max": 18.0, "recover": 1.4},
				"chain": 0.55,
			},
		],
	},
}

@export var preset := "warlord"
var tuning: Dictionary = PRESETS["warlord"]
var enemy: Enemy
## Leash: the fight happens inside this circle (world.ARENA_POS / ARENA_RADIUS).
var arena_center := Vector3.ZERO
var arena_radius := 18.0
const LEASH_PAD := 6.0
## World hook (authority): Callable(brain, count) -> Array of Enemy adds.
var spawn_adds: Callable
var adds: Array = []

var bars := 4
var phase := 1
var state := State.IDLE
var move := ""
var rng := RandomNumberGenerator.new()
var _timer := 0.0
var _cooldown := 0.0
var _slam_cd := 0.0
var _away := 0.0
var _engaged := false
var _bar_seen := 0
var _target: Node3D
var _charge_end := Vector3.ZERO
var _charge_hit := {}
var _charge_line: Array = []   # players on the line when the charge started
var _slam_at := Vector3.ZERO   # where the slam lands (a leap's target spot)
var swapped := false           # the last-bar weapon swap happened
var _threatened: Array = []    # players inside the slam ring at the warning
var _home_set := false
var _hazards: Array = []       # pending rockfalls: {pos, radius, t}
var _hazard_cd := 0.0
var _report := {"adds_spawned": 0, "breaks": 0, "resets": 0, "slams": 0, "charges": 0, "sweeps": 0, "rocks": 0}


func _ready() -> void:
	enemy = get_parent() as Enemy
	tuning = PRESETS.get(preset, PRESETS["warlord"])
	bars = int(tuning.get("bars", 4))
	_bar_seen = bars  # a boss spawns full; the first hit may already break a bar
	rng.seed = hash(preset) + int(Time.get_ticks_msec())
	if enemy != null and Net.is_authority():
		enemy.died.connect(_on_boss_died)


# ------------------------------------------------------------- bars / state --

func bar_count() -> int:
	return bars


func bar_hp() -> float:
	return maxf(float(enemy.max_hp), 1.0) / float(bars) if enemy else 1.0


## The bar being chipped now: bars (full) down to 1 (last), 0 when dead.
func current_bar() -> int:
	if enemy == null or enemy.hp <= 0.0:
		return 0
	return clampi(ceili(enemy.hp / bar_hp() - 0.0001), 1, bars)


## Fill of the current bar, 0..1.
func bar_fraction() -> float:
	var b := current_bar()
	if b == 0:
		return 0.0
	return clampf((enemy.hp - float(b - 1) * bar_hp()) / bar_hp(), 0.0, 1.0)


func state_name() -> String:
	return STATE_NAMES[state]


## Final-bar moveset on. Clients that joined late derive it from the bar.
func is_enraged() -> bool:
	if phase >= 2:
		return true
	return not Net.is_authority() and current_bar() == 1


## During the bar-break beat and the enrage roar parries still deflect but
## build no posture (Enemy._parried checks this).
func stagger_immune() -> bool:
	return state == State.BREAK or state == State.ENRAGE


func _ph() -> Dictionary:
	var phases: Array = tuning["phases"]
	return phases[mini(phase - 1, phases.size() - 1)]


func _reach() -> float:
	return 1.3 + enemy.size.z * 0.5


# --------------------------------------------------------------------- tick --

## Authority, once per physics frame from Enemy._physics_process. Returns the
## movement the Enemy applies: {"target": Vector3, "spd": float}.
func tick(delta: float, _nearest: Node3D) -> Dictionary:
	var e := enemy
	if e == null or not Net.is_authority():
		return {}
	if not _home_set:
		_home_set = true
		if arena_center == Vector3.ZERO:
			arena_center = e.home
	var pos := e.global_position
	_cooldown = maxf(_cooldown - delta, 0.0)
	_slam_cd = maxf(_slam_cd - delta, 0.0)
	_check_bars()
	var fighters := _fighters()
	_hazard_tick(delta, fighters)
	if _engaged:
		if fighters.is_empty():
			_away += delta
			if _away >= float(tuning.get("reset_grace", 4.0)):
				reset("leash")
				return _hold(pos)
		else:
			_away = 0.0
	if e._stagger > 0.0:
		e._stagger = maxf(e._stagger - delta, 0.0)
		if state == State.WINDUP or state == State.CHARGE:
			_cancel()
			state = State.RECOVER
			_timer = 0.3
		return _hold(pos)
	match state:
		State.IDLE:
			var t := _pick_target(fighters)
			if t == null:
				return _wander(delta)
			_engaged = true
			_target = t
			state = State.ENGAGE
			_cooldown = 0.8
			_emit("engage", {})
			if int(tuning.get("start_adds", 0)) > 0:
				_spawn_adds(_add_count(int(tuning["start_adds"])))
			return _hold(pos)
		State.ENGAGE:
			var t := _pick_target(fighters)
			if t == null:
				return {"target": e.home, "spd": e.speed * 0.6}
			_target = t
			var d := _pos_of(t).distance_to(pos)
			if _cooldown <= 0.0:
				var choice := _choose(d)
				if choice != "":
					_begin(choice, t)
					return _hold(pos)
			return {"target": _clamp(_pos_of(t)), "spd": e.speed}
		State.WINDUP:
			_timer -= delta
			if _timer <= 0.0:
				_resolve()
				return _hold(pos)
			# Turn toward the mark while the telegraph plays, but hold position.
			var face := _charge_end if move == "charge" else (_pos_of(_target) if _valid(_target) else pos)
			return {"target": face, "spd": 0.0}
		State.CHARGE:
			_timer -= delta
			_charge_tick()
			var arrived := pos.distance_to(_charge_end) < 1.2
			var blocked := e.get_slide_collision_count() > 0 and e.velocity.length() < 1.0 and _timer < 0.3
			if _timer <= 0.0 or arrived or blocked:
				_end_charge()
				return _hold(pos)
			return {"target": _charge_end, "spd": float(_ph()["charge_speed"])}
		State.RECOVER, State.BREAK, State.ENRAGE:
			_timer -= delta
			if _timer <= 0.0:
				if state == State.ENRAGE:
					phase = 2
					_emit("phase", {"phase": 2})
				state = State.ENGAGE
			var face := _pos_of(_target) if _valid(_target) else pos
			return {"target": face, "spd": 0.0}
	return _hold(pos)


func _hold(pos: Vector3) -> Dictionary:
	return {"target": pos, "spd": 0.0}


func _wander(delta: float) -> Dictionary:
	var e := enemy
	e._wander_timer -= delta
	if e._wander_timer <= 0.0:
		e._wander_timer = rng.randf_range(2.0, 5.0)
		e._wander_target = e.home + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
	return {"target": e._wander_target, "spd": e.speed * 0.4}


## Keep chase targets inside the arena so the boss never leaves it.
func _clamp(p: Vector3) -> Vector3:
	var flat := p - arena_center
	flat.y = 0.0
	if flat.length() > arena_radius:
		return arena_center + flat.normalized() * arena_radius + Vector3(0, p.y - arena_center.y, 0)
	return p


func _valid(n: Node3D) -> bool:
	return n != null and is_instance_valid(n) and n.is_inside_tree()


## Where the server believes a player stands (Player.srv_position).
func _pos_of(p: Node3D) -> Vector3:
	return p.srv_position() if p.has_method("srv_position") else p.global_position


func _alive(p: Node3D) -> bool:
	return _valid(p) and not (p.has_method("is_dying") and p.is_dying())


## Living players on the arena (within the leash).
func _fighters() -> Array:
	var out: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if _alive(p) and _pos_of(p).distance_to(arena_center) <= arena_radius + LEASH_PAD:
			out.append(p)
	return out


func _pick_target(fighters: Array) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var pos := enemy.global_position
	for p in fighters:
		var d := _pos_of(p).distance_to(pos)
		if d < best_d and d < enemy.aggro_range:
			best_d = d
			best = p
	return best


# -------------------------------------------------------------------- moves --

## Pick a move for the distance to the target, "" to keep closing in.
func _choose(d: float) -> String:
	var ph := _ph()
	var reach := _reach()
	var leap: Dictionary = ph.get("leap", {})
	if _slam_cd <= 0.0 and not leap.is_empty() and d >= float(leap["min"]) and d <= float(leap["max"]) and rng.randf() < 0.55:
		return "slam"  # leaping smash onto the target's spot
	if d <= float(ph["slam_radius"]) * 0.8 and _slam_cd <= 0.0 and rng.randf() < 0.6:
		return "slam"
	if d <= reach * float(ph["sweep_reach"]):
		return "sweep"
	if d >= float(ph["charge_min"]) and d <= float(ph["charge_max"]):
		return "charge"
	return ""


## Start a telegraphed move: the boss stops, everyone sees the warning, and
## the blow resolves windup seconds later (_resolve).
func _begin(m: String, t: Node3D) -> void:
	var e := enemy
	var ph := _ph()
	move = m
	state = State.WINDUP
	_target = t
	_timer = float(ph["windup"][m])
	e._windup_target = t
	var pos := e.global_position
	var data := {"move": m, "secs": _timer, "pos": pos}
	match m:
		"sweep":
			data["reach"] = _reach() * float(ph["sweep_reach"])
			data["arc"] = float(ph["sweep_arc"])
			data["style"] = str(ph.get("style", "cleave"))
		"charge":
			var tp := _pos_of(t)
			var dir := tp - pos
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.01 else -e.global_transform.basis.z
			_charge_end = _clamp(pos + dir * minf(tp.distance_to(pos) + 2.5, float(ph["charge_max"]) + 2.0))
			_charge_end.y = pos.y
			_charge_line = _players_on_line(pos, _charge_end, _reach() + 1.0)
			data["to"] = _charge_end
		"slam":
			# Close in: a ground smash where he stands. From range: a leap that
			# lands on the spot the target held when he crouched (step off it).
			_slam_at = pos
			var leap: Dictionary = ph.get("leap", {})
			var td := _pos_of(t).distance_to(pos)
			if not leap.is_empty() and td >= float(leap["min"]):
				_slam_at = _clamp(_pos_of(t))
				_slam_at.y = pos.y
				data["leap"] = true
				data["from"] = pos
			data["pos"] = _slam_at
			data["radius"] = float(ph["slam_radius"])
			_threatened = []
			for p in get_tree().get_nodes_in_group("players"):
				if _alive(p) and _pos_of(p).distance_to(_slam_at) < float(ph["slam_radius"]) * 1.8:
					_threatened.append(p)
	_emit("telegraph", data)


func _cancel() -> void:
	move = ""
	_timer = 0.0
	enemy._windup_target = null
	_charge_hit.clear()


## Windup over: the move lands (or, for a charge, the run begins).
func _resolve() -> void:
	var e := enemy
	var ph := _ph()
	var pos := e.global_position
	match move:
		"sweep":
			_report["sweeps"] += 1
			var reach := _reach() * float(ph["sweep_reach"])
			var arc := float(ph["sweep_arc"])
			var fwd := -e.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
			for p in get_tree().get_nodes_in_group("players"):
				if not _alive(p):
					continue
				var to := _pos_of(p) - pos
				to.y = 0.0
				var d := to.length()
				var in_arc := d < 0.5 or rad_to_deg(acos(clampf(fwd.dot(to.normalized()), -1.0, 1.0))) <= arc * 0.5
				if d < reach * 1.1 and in_arc:
					_strike(p, e.damage * float(ph["sweep_mult"]), true)
				elif d < reach * 2.0 and in_arc and "peer_id" in p:
					Net.note_hidden(p.peer_id, "dodge")
			_emit("impact", {"move": "sweep", "pos": pos, "reach": reach, "arc": arc})
			_after_move(0.45)
			if rng.randf() < float(ph["chain"]):
				_cooldown = 0.15  # rage: a second sweep follows at once
		"slam":
			_report["slams"] += 1
			var radius := float(ph["slam_radius"])
			var leapt := _slam_at.distance_to(pos) > 1.0
			if leapt:
				e.global_position = Vector3(_slam_at.x, pos.y, _slam_at.z)
				e.velocity = Vector3.ZERO
				pos = e.global_position
			for p in get_tree().get_nodes_in_group("players"):
				if not _alive(p):
					continue
				var d := _pos_of(p).distance_to(pos)
				if d < radius:
					# Not parryable: inside the ring you take it (a guard
					# still eats the blow as a block, but the parry never fires).
					var outcome := ""
					if p.has_method("is_stunned") and p.is_stunned():
						outcome = "stunned"
					elif bool(p.get("blocking")):
						outcome = "block"
					e._show_defence(p, outcome)
					var dmg := e.damage * float(ph["slam_mult"])
					e._damage_player(p, dmg * (1.0 - Player.BLOCK_REDUCTION) if outcome == "block" else dmg)
				elif _threatened.has(p) and "peer_id" in p:
					Net.note_hidden(p.peer_id, "dodge")
			_threatened.clear()
			_slam_cd = float(ph["slam_cd"])
			_emit("impact", {"move": "slam", "pos": pos, "radius": radius, "leap": leapt})
			# A leap leaves him open on landing: the party's window to punish.
			_after_move(float(ph.get("leap", {}).get("recover", 0.7)) if leapt else 0.7)
		"charge":
			_report["charges"] += 1
			state = State.CHARGE
			_charge_hit.clear()
			var dist := pos.distance_to(_charge_end)
			_timer = clampf(dist / float(ph["charge_speed"]) + 0.25, 0.4, 2.2)
			_emit("charge", {"from": pos, "to": _charge_end, "secs": _timer})
		_:
			_after_move(0.3)


func _after_move(recover: float) -> void:
	var ph := _ph()
	move = ""
	enemy._windup_target = null
	state = State.RECOVER
	_timer = recover
	var cd: Array = ph["cooldown"]
	_cooldown = rng.randf_range(float(cd[0]), float(cd[1]))


## Running: anyone the body reaches is struck once (parryable: the hit is
## telegraphed by the charge itself and lands the moment it arrives).
func _charge_tick() -> void:
	var e := enemy
	var ph := _ph()
	var pos := e.global_position
	var fwd := -e.global_transform.basis.z
	for p in get_tree().get_nodes_in_group("players"):
		if not _alive(p) or _charge_hit.has(p.get_instance_id()):
			continue
		var to := _pos_of(p) - pos
		to.y = 0.0
		if to.length() < _reach() * 0.9 and (to.length() < 0.5 or fwd.dot(to.normalized()) > 0.1):
			_charge_hit[p.get_instance_id()] = true
			_strike(p, e.damage * float(ph["charge_mult"]), true)


func _end_charge() -> void:
	var pos := enemy.global_position
	# Those who stood on the line and were never reached stepped out of it.
	for p in _charge_line:
		if _alive(p) and not _charge_hit.has(p.get_instance_id()) and "peer_id" in p:
			Net.note_hidden(p.peer_id, "dodge")
	_charge_line.clear()
	_charge_hit.clear()
	_emit("impact", {"move": "charge", "pos": pos})
	_after_move(0.6)


func _players_on_line(a: Vector3, b: Vector3, width: float) -> Array:
	var out: Array = []
	var ab := b - a
	ab.y = 0.0
	var len := ab.length()
	if len < 0.01:
		return out
	var dir := ab / len
	for p in get_tree().get_nodes_in_group("players"):
		if not _alive(p):
			continue
		var ap := _pos_of(p) - a
		ap.y = 0.0
		var along := ap.dot(dir)
		if along < -1.0 or along > len + 1.0:
			continue
		if (ap - dir * along).length() <= width:
			out.append(p)
	return out


## One blow on one player through Player.defend (the server judges), exactly
## like Enemy._resolve_strike: parry -> posture, block -> chip, else damage.
func _strike(t: Node3D, dmg: float, parryable: bool) -> String:
	var e := enemy
	if t.has_method("is_dying") and t.is_dying():
		return ""
	var outcome := ""
	if parryable and t.has_method("defend"):
		outcome = t.defend(e.global_position)
	e._show_defence(t, outcome)
	match outcome:
		"parry":
			e._parried(t)
		"block":
			e._damage_player(t, dmg * (1.0 - Player.BLOCK_REDUCTION))
		_:
			e._damage_player(t, dmg)
	return outcome


# ------------------------------------------------------------ arena hazard --

## Rockfall: armed once the boss is engaged and down to tuning.rockfall
## .from_bar; lands pending stones and marks new ones on its own clock, so it
## keeps pressure on during wind-ups, staggers and the enrage roar alike.
func _hazard_tick(delta: float, fighters: Array) -> void:
	var rf: Dictionary = tuning.get("rockfall", {})
	for h in _hazards.duplicate():
		h["t"] = float(h["t"]) - delta
		if float(h["t"]) <= 0.0:
			_hazards.erase(h)
			_land_rock(h["pos"], float(h["radius"]), enemy.damage * float(rf.get("mult", 1.0)))
	if rf.is_empty() or not _engaged or fighters.is_empty() or current_bar() > int(rf.get("from_bar", 1)):
		return
	_hazard_cd -= delta
	if _hazard_cd > 0.0:
		return
	var cd: Array = rf.get("cd", [6.0, 6.0])
	_hazard_cd = rng.randf_range(float(cd[0]), float(cd[1]))
	var radius := float(rf.get("radius", 2.4))
	var secs := float(rf.get("secs", 1.4))
	for i in int(rf.get("count", 3)):
		var at: Vector3
		if i == 0:
			at = _pos_of(fighters[rng.randi() % fighters.size()])
		else:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * (arena_radius - radius)
			at = arena_center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		at.y = arena_center.y
		_hazards.append({"pos": at, "radius": radius, "t": secs})
		_emit("hazard", {"pos": at, "radius": radius, "secs": secs})


func _land_rock(at: Vector3, radius: float, dmg: float) -> void:
	_report["rocks"] += 1
	for p in get_tree().get_nodes_in_group("players"):
		if not _alive(p):
			continue
		var flat := (_pos_of(p) - at) * Vector3(1, 0, 1)
		if flat.length() >= radius or absf(_pos_of(p).y - at.y) > 4.0:
			continue
		var outcome := ""
		if p.has_method("is_stunned") and p.is_stunned():
			outcome = "stunned"
		elif bool(p.get("blocking")):
			outcome = "block"
		enemy._show_defence(p, outcome)
		enemy._damage_player(p, dmg * (1.0 - Player.BLOCK_REDUCTION) if outcome == "block" else dmg)
	_emit("hazard_land", {"pos": at, "radius": radius})


func pending_hazards() -> int:
	return _hazards.size()


# ------------------------------------------------------- bars / phase / adds --

## Enemy.take_hit calls this right after hp changes (and tick polls it), so a
## bar break fires on the hit that caused it.
func on_damaged() -> void:
	if Net.is_authority() and enemy != null and not enemy._dead:
		_check_bars()


func _check_bars() -> void:
	var b := current_bar()
	if b < _bar_seen and b > 0:
		var broke := _bar_seen
		_bar_seen = b
		_on_bar_break(broke, b)


## A bar broke: the Guardian reels for a beat (stagger-immune), posture
## clears, 2-3 adds answer the call. Breaking into the last bar is the phase
## change: a longer roar, then the second moveset.
func _on_bar_break(broke: int, left: int) -> void:
	var e := enemy
	_report["breaks"] += 1
	_cancel()
	e._posture = 0
	e._stagger = 0.0
	var cnt: Array = tuning.get("adds", [2, 3])
	_spawn_adds(_add_count(rng.randi_range(int(cnt[0]), int(cnt[1]))))
	_emit("bar_break", {"bar": left, "bars": bars, "broke": broke})
	if left == 1 and phase < 2:
		state = State.ENRAGE
		_timer = float(tuning.get("enrage_time", 1.8))
		_emit("enrage", {"secs": _timer})
		if tuning.has("swap"):
			_emit("weapon_swap", tuning["swap"])
	else:
		state = State.BREAK
		_timer = float(tuning.get("break_time", 1.2))
	_cooldown = 0.6


## Guards called for a wave: the wave size, trimmed for a small party (a solo
## climber faces two, a group the full wave) and to the living cap.
func _add_count(wave: int) -> int:
	var n := mini(wave, 1 + _fighters().size())
	return clampi(mini(n, int(tuning.get("max_adds", 99)) - living_adds()), 0, wave)


func _spawn_adds(count: int) -> void:
	if count <= 0:
		return
	_prune_adds()
	if not spawn_adds.is_valid():
		return
	var made = spawn_adds.call(self, count)
	if made is Array:
		for a in made:
			if a is Node:
				adds.append(a)
				_report["adds_spawned"] += 1


func _prune_adds() -> void:
	adds = adds.filter(func(a): return a is Node and is_instance_valid(a) and a.is_inside_tree() and a.visible)


func living_adds() -> int:
	_prune_adds()
	return adds.size()


## Adds vanish (no rewards) on boss death or reset.
func clear_adds() -> void:
	for a in adds:
		if a is Node and is_instance_valid(a):
			if a.has_method("vanish"):
				a.vanish()
			else:
				a.queue_free()
	adds.clear()


## Full reset (leash): back home at full health, bars and phase restored,
## adds gone. Everyone is told so the plate and bars snap back.
func reset(reason := "leash") -> void:
	var e := enemy
	_report["resets"] += 1
	_cancel()
	clear_adds()
	e.hp = e.max_hp
	e._posture = 0
	e._stagger = 0.0
	e._knock = Vector3.ZERO
	e._hit_cd = 0.0
	e._hit_by.clear()
	e.velocity = Vector3.ZERO
	if e.is_inside_tree():
		e.global_position = e.home
	e._update_label()
	phase = 1
	swapped = false
	_bar_seen = bars
	state = State.IDLE
	_engaged = false
	_away = 0.0
	_cooldown = 0.0
	_slam_cd = 0.0
	_hazards.clear()
	_hazard_cd = 0.0
	_target = null
	_emit("reset", {"reason": reason})


func _on_boss_died(_e: Enemy) -> void:
	_cancel()
	_hazards.clear()
	clear_adds()
	state = State.IDLE
	_emit("death", {})


## One line for world._print_report.
func report() -> String:
	return "bar=%d/%d phase=%d state=%s adds=%d spawned=%d breaks=%d resets=%d moves=s%d/c%d/g%d rocks=%d" % [
		current_bar(), bars, phase, state_name(), living_adds(), _report["adds_spawned"], _report["breaks"],
		_report["resets"], _report["sweeps"], _report["charges"], _report["slams"], _report["rocks"]]


# ------------------------------------------------------------------ events --

func _emit(kind: String, data: Dictionary) -> void:
	if Net.online:
		net_event.rpc(kind, data)
	else:
		net_event(kind, data)


## Everyone: a boss event (sounds, visual hooks, bot reactions, display state),
## then the signal for the HUD and the boss plate.
@rpc("authority", "call_local", "reliable")
func net_event(kind: String, data: Dictionary) -> void:
	var e := enemy
	if e == null:
		return
	var fx := VFX.get_for(e)
	var pos: Vector3 = data.get("pos", e.global_position) if data.get("pos") is Vector3 else e.global_position
	match kind:
		"engage":
			Audio.play("boss_roar", pos, 0.06, -2.0, 0.9)
			if fx and fx.has_method("boss_engage"):
				fx.call("boss_engage", e)
		"telegraph":
			var mv := str(data.get("move", ""))
			var secs := float(data.get("secs", Enemy.WINDUP_BOSS))
			e._swing_local(secs, mv != "slam")
			match mv:
				"sweep":
					Audio.play("grunt", pos, 0.1, 2.0, 0.6)
					if fx and fx.has_method("boss_sweep_warning"):
						fx.call("boss_sweep_warning", e, float(data.get("reach", 6.0)), float(data.get("arc", 150.0)), secs)
				"charge":
					Audio.play("boss_charge", pos, 0.06, 0.0, 1.0)
					if fx and fx.has_method("boss_charge_warning"):
						fx.call("boss_charge_warning", e, pos, data.get("to", pos), secs)
					elif fx:
						fx.ring(data.get("to", pos) + Vector3(0, 0.1, 0), Color(1.0, 0.5, 0.2), 3.0, secs)
				"slam":
					Audio.play("skill_charge", pos, 0.05, 2.0, 0.7)
					if fx and fx.has_method("boss_slam_warning"):
						fx.call("boss_slam_warning", e, pos, float(data.get("radius", 5.0)), secs)
					if fx and bool(data.get("leap", false)) and fx.has_method("boss_leap"):
						fx.call("boss_leap", e, data.get("from", e.global_position), pos, secs)
					elif fx:
						fx.ring(pos + Vector3(0, 0.1, 0), Color(1.0, 0.35, 0.15), float(data.get("radius", 5.0)) * 2.0, secs)
		"charge":
			# The warning already drew the line; the run itself is the body moving.
			if fx and not fx.has_method("boss_charge_warning"):
				fx.puff(pos, 2.5)
		"impact":
			var mv := str(data.get("move", ""))
			match mv:
				"slam":
					Audio.play("slam", pos, 0.05, 4.0)
					if fx and fx.has_method("boss_slam_impact"):
						fx.call("boss_slam_impact", e, pos, float(data.get("radius", 5.0)))
					else:
						e._slam_fx()
				"charge":
					Audio.play("slam", pos, 0.08, 0.0, 0.8)
					if fx and fx.has_method("boss_charge_impact"):
						fx.call("boss_charge_impact", e, pos)
					elif fx:
						fx.dust_ring(pos, 2.5)
				"sweep":
					Audio.play("swing", pos, 0.1, 2.0, 0.6)
					if fx and fx.has_method("boss_sweep_impact"):
						fx.call("boss_sweep_impact", e, float(data.get("reach", 6.0)), float(data.get("arc", 150.0)))
		"bar_break":
			Audio.play("boss_bar_break", pos, 0.05, 2.0)
			if fx and fx.has_method("boss_bar_break"):
				fx.call("boss_bar_break", e, int(data.get("bar", 1)), int(data.get("bars", bars)))
			elif fx:
				fx.ring(pos + Vector3(0, e.size.y * 0.6, 0), Color(0.6, 0.9, 1.0), 6.0, 0.6)
		"enrage":
			Audio.play("boss_roar", pos, 0.04, 4.0, 0.75)
			if fx and fx.has_method("boss_enrage"):
				fx.call("boss_enrage", e, float(data.get("secs", 1.8)))
			elif fx:
				fx.flash(pos + Vector3(0, e.size.y * 0.7, 0), Color(1.0, 0.3, 0.2), 4.0)
			var me := get_tree().get_first_node_in_group("player")
			if me and me.has_method("shake"):
				me.shake(0.4)
		"hazard":
			var hr := float(data.get("radius", 2.4))
			var hs := float(data.get("secs", 1.4))
			Audio.play("skill_charge", pos, 0.1, -4.0, 0.5)
			if fx and fx.has_method("boss_rockfall_warning"):
				fx.call("boss_rockfall_warning", e, pos, hr, hs)
			elif fx:
				fx.ring(pos + Vector3(0, 0.1, 0), Color(1.0, 0.55, 0.2), hr * 2.0, hs)
		"hazard_land":
			Audio.play("slam", pos, 0.1, -2.0, 1.2)
			if fx and fx.has_method("boss_rockfall_impact"):
				fx.call("boss_rockfall_impact", e, pos, float(data.get("radius", 2.4)))
			elif fx:
				fx.dust_ring(pos, float(data.get("radius", 2.4)))
		"weapon_swap":
			# He casts down the axe and buckler and draws the long blade.
			# Model hook: Enemy.swap_weapon(data); VFX hook boss_weapon_swap.
			swapped = true
			Audio.play("anvil", pos, 0.05, 2.0, 0.6)
			Audio.play("skill_charge", pos, 0.05, 0.0, 1.3)
			if e.has_method("swap_weapon"):
				e.call("swap_weapon", data)
			if fx and fx.has_method("boss_weapon_swap"):
				fx.call("boss_weapon_swap", e, data)
			elif fx:
				fx.flash(pos + Vector3(0, e.size.y * 0.7, 0), Color(1.0, 0.85, 0.5), 3.0)
		"phase":
			phase = int(data.get("phase", 2))
		"reset":
			phase = 1
			swapped = false
			state = State.IDLE
			if fx and fx.has_method("boss_reset"):
				fx.call("boss_reset", e)
		"death":
			pass
	boss_event.emit(kind, data)
