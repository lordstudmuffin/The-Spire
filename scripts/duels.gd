class_name Duels
extends Node
## Player-vs-player duels on Floor 1 (original rules and text).
##
## Flow: "/duel Name [first|half|full]" sends a challenge; the challenged
## player answers with "/duel accept" or "/duel decline" within INVITE_TTL.
## Both must be online and within INVITE_RANGE of each other. Duels work
## anywhere, inside a settlement's Inner Area (SAFE_ZONES) too: by mutual
## consent a duel is the one way to trade blows there. A COUNTDOWN then runs (big centred number), "DUEL!", and
## the fight uses the EXISTING attack paths: Player._hit_cone finds the duel
## opponent next to the mobs and sends the hit to the server (net_hit here),
## which validates it exactly like Enemy.net_hit (kind, cooldown, range,
## facing, one hit per swing) and then telegraphs it for WINDUP seconds so
## the defender can parry (Player.defend, with the same latency allowance as
## against mobs) or guard. A parry stuns and pushes the attacker back.
##
## Modes: "first" (First Strike: the first clean hit for at least
## FIRST_STRIKE_PCT of max HP wins, or taking the other under half),
## "half" (first under half HP) and "full" (down to 1 HP; nobody dies in a
## duel). Ends also on leaving FORFEIT_RANGE (forfeit), disconnect, or death
## to a mob. Wins and losses go on the record / save as "duels".
##
## Server-authoritative: all duel state lives on the server (this node on the
## server), clients only get events (net_apply "duel" {"ev": ...}). Offline
## there is nobody to duel; the smoke test drives the srv_* functions and
## tick() directly with fake peers.
##
## VFX hooks (behind has_method on VFX.get_for): duel_countdown(n),
## duel_start(a: Node3D, b: Node3D), duel_end(winner: Node3D, loser: Node3D),
## duel_incoming(attacker: Node3D, windup: float), duel_ring(center: Vector3,
## radius: float, on: bool).

const INVITE_TTL := 30.0
const INVITE_RANGE := 15.0
const FORFEIT_RANGE := 40.0
const ANNOUNCE_RANGE := 40.0
const COUNTDOWN := 60   # Aincrad-style: a full minute to get ready (big numbers for the last 10)
## PvP telegraph: a swing on a duel opponent lands this long after the server
## accepts it (shorter than a mob's Enemy.WINDUP), so the defender can parry.
const WINDUP := 0.3
const PARRY_STUN := 0.8
## A perfect parry (Player.PERFECT_WINDOW) stuns the attacker this long.
const PERFECT_STUN := 1.2
const PARRY_PUSH := 7.0
const HIT_RANGE := 4.0
const FIRST_STRIKE_PCT := 0.05
const HALF_PCT := 0.5
const MODES := {"first": "First Strike", "half": "Half Loss", "full": "Total Loss"}
const DEFAULT_MODE := "first"
## Where mobs never roam and duels never start: the walled town, Hollowbrook
## and Talven (world.gd keeps mobs out of the same circles).
const SAFE_ZONES := [[Vector3(0, 0, 15), 36.0], [Vector3(-144, 0, 84), 18.0], [Vector3(-42, 0, -162), 13.0]]

## Test hook: every event the server delivers (peer, data).
signal server_event(peer: int, data: Dictionary)

# --- Server state ---------------------------------------------------------------
## target peer -> {"from": peer, "mode": String, "t": seconds}
var invites := {}
## duel id -> {"id", "a", "b", "mode", "phase": "count"|"fight", "t0", "count", "center", "hit_by": {peer: swing}}
var duels := {}
var duel_of := {}   # peer -> duel id
var _pending := []  # telegraphed strikes awaiting WINDUP
var _time := 0.0    # internal clock, seconds (tests drive tick() directly)
var _next_id := 1
var paused := false  # tests: stop _process from ticking on its own

# --- Client state ---------------------------------------------------------------
var my_duel := {}         # {"id", "opponent", "opponent_name", "mode", "phase"}
var pending_invite := {}  # {"from", "mode"}
var hud: Node = null
var auto_accept := false  # --duel bots accept any challenge
var _count_label: Label = null
var _opp_bar: Control = null  # PlayerStatus duel gauge (visuals thread)
var _label_serial := 0

# --- --duel soak bot --------------------------------------------------------------
const BOT_MEET := Vector3(2, 0, -34)   # just outside the north gate, out of town
var _bot_done := false
var _bot_next_invite := 0.0
var _bot_t := 0.0


static func build(w: Node3D) -> Node:
	var n := Duels.new()
	n.name = "Duels"
	n.add_to_group("duels")
	w.add_child(n)
	return n


func _process(delta: float) -> void:
	if paused:
		return
	if Net.online and multiplayer.is_server():
		tick(delta)


static func mode_name(mode: String) -> String:
	return str(MODES.get(mode, MODES[DEFAULT_MODE]))


static func in_safe_zone(pos: Vector3) -> bool:
	for z in SAFE_ZONES:
		var c: Vector3 = z[0]
		if Vector2(pos.x - c.x, pos.z - c.z).length() < float(z[1]):
			return true
	return false


# =============================================================================
# Server
# =============================================================================

func _err(text: String) -> Dictionary:
	return {"error": text}


func _node_of(peer: int) -> Node3D:
	return Net._srv_player_node(peer) as Node3D


func _pos_of(peer: int) -> Variant:
	var n := _node_of(peer)
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return null
	return n.srv_position() if n.has_method("srv_position") else n.global_position


func _is_host(peer: int) -> bool:
	return peer == multiplayer.get_unique_id() and not Net.dedicated


func _online(peer: int) -> bool:
	return Net._srv_is_online(peer) or (not Net.online and _node_of(peer) != null)


func _name(peer: int) -> String:
	var n := Net.srv_name_of(peer)
	if n == "":
		var node := _node_of(peer)
		if node != null:
			n = str(node.get("display_name"))
	return n if n != "" else "?"


## [hp, max_hp] as the server knows it (the record, or GameState for the host).
func _hp_of(peer: int) -> Array:
	if Net.srv_records.has(peer):
		var rec: Dictionary = Net.srv_records[peer]
		return [float(rec["hp"]), Net.RecordState.new(rec).max_hp()]
	return [GameState.hp, GameState.max_hp()]


## Duel damage: armour soaks as everywhere else, but never lethal (the loser
## keeps 1 HP). Returns the HP actually removed.
func _apply_damage(peer: int, amount: float) -> float:
	if Net.srv_records.has(peer):
		var rec: Dictionary = Net.srv_records[peer]
		var rs = Net.RecordState.new(rec)
		var prev := float(rec["hp"])
		var dmg: float = max(amount - rs.armor_defense() * 0.5, 1.0)
		rec["hp"] = maxf(prev - dmg, 1.0)
		HiddenClasses.note(rs, "hurt")
		Net._send(peer, Net.net_hp, [float(rec["hp"]), rs.max_hp(), prev])
		return prev - float(rec["hp"])
	var prev_hp := GameState.hp
	var d: float = max(amount - GameState.armor_defense() * 0.5, 1.0)
	GameState.hp = maxf(prev_hp - d, 1.0)
	GameState.health_changed.emit(GameState.hp, GameState.max_hp())
	GameState.note_hidden("hurt")
	return prev_hp - GameState.hp


## Server -> one peer: a duel event. The host (or the offline test harness)
## gets it straight into on_net; connected clients through net_apply.
func _deliver(peer: int, data: Dictionary) -> void:
	server_event.emit(peer, data)
	if peer == multiplayer.get_unique_id() and (not Net.online or not Net.dedicated):
		on_net("duel", data)
	elif Net.online and multiplayer.is_server():
		Net._send(peer, Net.net_apply, ["duel", data])


func _system_to(peer: int, text: String) -> void:
	if peer == multiplayer.get_unique_id() and (not Net.online or not Net.dedicated):
		Net.chat_received.emit("", text, "system")
	elif Net.online and multiplayer.is_server():
		Net._send(peer, Net.net_system, [text])


## Peers (by server position) within `radius` of `center`, duelists included.
func _peers_near(center: Vector3, radius: float) -> Array:
	var out := []
	if get_tree() == null:
		return out
	for p in get_tree().get_nodes_in_group("players"):
		var pos: Vector3 = p.srv_position() if p.has_method("srv_position") else p.global_position
		if pos.distance_to(center) <= radius:
			out.append(int(p.get("peer_id")))
	return out


## Why `a` and `b` cannot duel right now, or "".
func _pair_check(a: int, b: int) -> String:
	if b == 0 or not _online(b):
		return "No such player online."
	if a == b:
		return "You cannot duel yourself."
	if duel_of.has(a):
		return "You are already in a duel."
	if duel_of.has(b):
		return "%s is already duelling." % _name(b)
	var pa = _pos_of(a)
	var pb = _pos_of(b)
	if not (pa is Vector3) or not (pb is Vector3):
		return "No such player online."
	if pa.distance_to(pb) > INVITE_RANGE + Net.RANGE_SLACK:
		return "%s is too far away (duels start within %d m)." % [_name(b), int(INVITE_RANGE)]
	return ""


## Server: `from` challenges the player called `target_name` to a `mode` duel.
func srv_invite(from: int, target_name: String, mode := DEFAULT_MODE) -> Dictionary:
	mode = mode.to_lower()
	if not MODES.has(mode):
		return _err("Unknown duel mode. Modes: first, half, full.")
	# Permadeath climbers fight First Strike only (either side).
	var tpeer := -1
	for p in Net.srv_records:
		if str(Net.srv_records[p].get("name", "")).to_lower() == target_name.to_lower():
			tpeer = p
	for p in [from, tpeer]:
		if Net.srv_records.has(p) and Permadeath.rec_on(Net.srv_records[p]) and mode != "first":
			mode = "first"
	var target := Net.srv_peer_by_name(target_name)
	if target == 0 and not Net.online:
		# Offline harness: find a player node by name.
		for p in get_tree().get_nodes_in_group("players"):
			if str(p.get("display_name")).to_lower() == Net.sanitize_name(target_name).to_lower():
				target = int(p.get("peer_id"))
	var why := _pair_check(from, target)
	if why != "":
		return _err(why)
	var inv: Dictionary = invites.get(target, {})
	if not inv.is_empty() and _time - float(inv["t"]) < INVITE_TTL and int(inv["from"]) != from:
		return _err("%s already has a duel challenge pending." % _name(target))
	invites[target] = {"from": from, "mode": mode, "t": _time}
	print("[duel] %s challenged %s (%s)" % [_name(from), _name(target), mode_name(mode)])
	_deliver(target, {"ev": "invited", "from": _name(from), "from_peer": from, "mode": mode, "mode_name": mode_name(mode), "ttl": INVITE_TTL})
	return {"op": "invite", "invited": _name(target), "mode": mode, "mode_name": mode_name(mode)}


## Server: `peer` answers its pending challenge.
func srv_respond(peer: int, accept: bool) -> Dictionary:
	var inv: Dictionary = invites.get(peer, {})
	invites.erase(peer)
	if inv.is_empty():
		return _err("Nobody has challenged you.")
	var from := int(inv["from"])
	if _time - float(inv["t"]) > INVITE_TTL:
		_system_to(from, "Your duel challenge to %s expired." % _name(peer))
		return _err("That challenge has expired.")
	if not accept:
		_deliver(from, {"ev": "declined", "by": _name(peer)})
		return {"op": "decline"}
	var why := _pair_check(peer, from)
	if why != "":
		_system_to(from, "%s accepted, but the duel could not start: %s" % [_name(peer), why])
		return _err(why)
	var id := _start(from, peer, str(inv["mode"]))
	return {"op": "accept", "duel": id, "opponent": _name(from), "mode": str(inv["mode"])}


## Server: `peer` gives up its duel (or the harness ends one).
func srv_yield(peer: int) -> Dictionary:
	var id := int(duel_of.get(peer, 0))
	if id == 0 or not duels.has(id):
		return _err("You are not in a duel.")
	var d: Dictionary = duels[id]
	var other: int = d["b"] if d["a"] == peer else d["a"]
	_end(id, other, peer, "yield")
	return {"op": "yield"}


func _start(a: int, b: int, mode: String) -> int:
	var id := _next_id
	_next_id += 1
	var pa: Vector3 = _pos_of(a)
	var pb: Vector3 = _pos_of(b)
	duels[id] = {"id": id, "a": a, "b": b, "mode": mode, "phase": "count", "t0": _time, "count": COUNTDOWN + 1,
		"center": (pa + pb) * 0.5, "hit_by": {}}
	duel_of[a] = id
	duel_of[b] = id
	print("[duel] #%d %s vs %s (%s) begins" % [id, _name(a), _name(b), mode_name(mode)])
	for pair in [[a, b], [b, a]]:
		_deliver(pair[0], {"ev": "begin", "duel": id, "opponent": _name(pair[1]), "opponent_peer": pair[1], "mode": mode,
			"mode_name": mode_name(mode), "count": COUNTDOWN})
	return id


## One telegraphed strike resolved: parry / block / hit, then the win check.
func _resolve(s: Dictionary) -> void:
	var id := int(s["duel"])
	if not duels.has(id) or str(duels[id]["phase"]) != "fight":
		return
	var d: Dictionary = duels[id]
	var attacker := int(s["attacker"])
	var defender := int(s["defender"])
	var p := _node_of(attacker)
	var t := _node_of(defender)
	if p == null or t == null or not is_instance_valid(p) or not is_instance_valid(t):
		return
	if t.has_method("is_dying") and t.is_dying():
		return
	var p_pos: Vector3 = p.srv_position()
	var t_pos: Vector3 = t.srv_position()
	if p_pos.distance_to(t_pos) > (HIT_RANGE + Net.RANGE_SLACK) * 1.2:
		return  # the defender stepped out during the telegraph
	# Judged by the defender's Player.srv_strike (i-frames, parry, guard, and
	# on a live server the late-press grace), then finished in _on_defended.
	if t.has_method("srv_strike"):
		t.srv_strike(p_pos, _on_defended.bind(s, p_pos))
	else:
		_on_defended("", s, p_pos)


func _on_defended(outcome: String, s: Dictionary, p_pos: Vector3) -> void:
	var id := int(s["duel"])
	if not duels.has(id) or str(duels[id]["phase"]) != "fight":
		return
	var d: Dictionary = duels[id]
	var attacker := int(s["attacker"])
	var defender := int(s["defender"])
	var p := _node_of(attacker)
	var t := _node_of(defender)
	if p == null or t == null or not is_instance_valid(p) or not is_instance_valid(t):
		return
	if t.has_method("is_dying") and t.is_dying():
		return
	var t_pos: Vector3 = t.srv_position()
	# Tell the defender's machine what the server judged (as Enemy does).
	if outcome != "":
		var shown := "perfect" if outcome == "parry" and bool(t.get("last_parry_perfect")) else outcome
		if not Net.online or t.peer_id == multiplayer.get_unique_id():
			t.defend_fx(shown, p_pos)
		elif multiplayer.get_peers().has(t.peer_id):
			t.net_defended.rpc_id(t.peer_id, shown, p_pos, t.guard, t._stun)
	var dmg := float(s["dmg"])
	var dealt := 0.0
	var clean := false
	match outcome:
		"parry":
			var stun := PERFECT_STUN if bool(t.get("last_parry_perfect")) else PARRY_STUN
			var push := (p_pos - t_pos) * Vector3(1, 0, 1)
			push = push.normalized() * PARRY_PUSH if push.length() > 0.01 else Vector3.ZERO
			if p.has_method("pvp_staggered"):
				p.pvp_staggered(stun, push)
			Net.note_hidden(defender, "parry")
			_deliver(attacker, {"ev": "parried", "by": _name(defender), "stun": stun, "push": push})
		"dodge":
			Net.note_hidden(defender, "dodge")
		"block":
			dealt = _apply_damage(defender, dmg * (1.0 - Player.BLOCK_REDUCTION))
		_:
			dealt = _apply_damage(defender, dmg)
			clean = true
	var hp := _hp_of(defender)
	for peer in [attacker, defender]:
		_deliver(peer, {"ev": "hit", "attacker": attacker, "defender": defender, "amount": dealt, "outcome": outcome,
			"kind": int(s["kind"]), "hp": hp[0], "max": hp[1]})
	if dealt <= 0.0 and not clean:
		return
	var frac: float = hp[0] / maxf(hp[1], 1.0)
	var won := false
	match str(d["mode"]):
		"first":
			won = (clean and dealt >= FIRST_STRIKE_PCT * hp[1]) or frac < HALF_PCT
		"half":
			won = frac < HALF_PCT
		"full":
			won = hp[0] <= 1.0
	if won:
		_end(id, attacker, defender, "win")


func _end(id: int, winner: int, loser: int, reason: String) -> void:
	if not duels.has(id):
		return
	var d: Dictionary = duels[id]
	duels.erase(id)
	duel_of.erase(d["a"])
	duel_of.erase(d["b"])
	_pending = _pending.filter(func(s): return int(s["duel"]) != id)
	var wn := _name(winner)
	var ln := _name(loser)
	# Tally on the records (the save, for the host).
	for pair in [[winner, "won"], [loser, "lost"]]:
		var peer: int = pair[0]
		if Net.srv_records.has(peer):
			var rec: Dictionary = Net.srv_records[peer]
			if not (rec.get("duels") is Dictionary):
				rec["duels"] = {"won": 0, "lost": 0}
			rec["duels"][pair[1]] = int(rec["duels"].get(pair[1], 0)) + 1
			Net.save_record(rec)
		elif _is_host(peer):
			GameState.duels[pair[1]] = int(GameState.duels.get(pair[1], 0)) + 1
	var text := ""
	match reason:
		"win":
			text = "%s won the duel against %s (%s)." % [wn, ln, mode_name(str(d["mode"]))]
		"range":
			text = "%s walked away: %s wins the duel by forfeit." % [ln, wn]
		"yield":
			text = "%s yielded: %s wins the duel." % [ln, wn]
		"left":
			text = "%s left: %s wins the duel by forfeit." % [ln, wn]
		"death":
			text = "%s fell to a monster mid-duel: %s wins by default." % [ln, wn]
		_:
			text = "The duel between %s and %s ended (%s)." % [wn, ln, reason]
	print("[duel] #%d over: %s" % [id, text])
	var told := {}
	for peer in [winner, loser]:
		told[peer] = true
		var data := {"ev": "end", "winner": wn, "loser": ln, "winner_peer": winner, "loser_peer": loser, "reason": reason,
			"won": peer == winner, "text": text}
		if Net.srv_records.has(peer):
			data["patch"] = Net.patch_for_client(Net.srv_records[peer])
		_deliver(peer, data)
	# Nearby players hear the result (and see the end effect).
	for peer in _peers_near(d["center"], ANNOUNCE_RANGE):
		if told.has(peer):
			continue
		told[peer] = true
		_deliver(peer, {"ev": "end", "winner": wn, "loser": ln, "winner_peer": winner, "loser_peer": loser, "reason": reason,
			"spectator": true, "text": text})


## A duelist that can no longer fight: disconnected, or died to a mob.
func _lost_cause(peer: int) -> String:
	var n := _node_of(peer)
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return "left"
	if Net.online and not Net.srv_records.has(peer) and not _is_host(peer):
		return "left"
	if n.has_method("is_dying") and n.is_dying():
		return "death"
	if Net.srv_records.has(peer) and Time.get_ticks_msec() < int(Net._death_grace.get(peer, 0)):
		return "death"
	return ""


## Server clock: invites expire, countdowns run, strikes land, forfeits.
func tick(delta: float) -> void:
	_time += delta
	for target in invites.keys():
		var inv: Dictionary = invites[target]
		if _time - float(inv["t"]) > INVITE_TTL:
			invites.erase(target)
			_system_to(int(inv["from"]), "Your duel challenge to %s expired." % _name(target))
			_deliver(target, {"ev": "expired", "from": _name(int(inv["from"]))})
	for id in duels.keys():
		if not duels.has(id):
			continue
		var d: Dictionary = duels[id]
		var a: int = d["a"]
		var b: int = d["b"]
		var la := _lost_cause(a)
		var lb := _lost_cause(b)
		if la != "":
			_end(id, b, a, la)
			continue
		if lb != "":
			_end(id, a, b, lb)
			continue
		var pa: Vector3 = _pos_of(a)
		var pb: Vector3 = _pos_of(b)
		if pa.distance_to(pb) > FORFEIT_RANGE:
			var c: Vector3 = d["center"]
			var runner: int = a if pa.distance_to(c) >= pb.distance_to(c) else b
			_end(id, b if runner == a else a, runner, "range")
			continue
		if str(d["phase"]) == "count":
			var n := COUNTDOWN - int(floor(_time - float(d["t0"])))
			if n < int(d["count"]):
				d["count"] = n
				if n <= 0:
					d["phase"] = "fight"
					d["t_fight"] = _time
					print("[duel] #%d DUEL!" % id)
					var told := {}
					for peer in [a, b]:
						told[peer] = true
						_deliver(peer, {"ev": "start", "a": _name(a), "b": _name(b), "a_peer": a, "b_peer": b, "center": d["center"]})
					for peer in _peers_near(d["center"], ANNOUNCE_RANGE):
						if not told.has(peer):
							told[peer] = true
							_deliver(peer, {"ev": "start", "a": _name(a), "b": _name(b), "a_peer": a, "b_peer": b, "center": d["center"], "spectator": true})
				else:
					for peer in [a, b]:
						_deliver(peer, {"ev": "count", "n": n})
	if not _pending.is_empty():
		var due := []
		var keep := []
		for s in _pending:
			if float(s["at"]) <= _time:
				due.append(s)
			else:
				keep.append(s)
		_pending = keep
		for s in due:
			_resolve(s)


## Server: a peer dropped (world._on_peer_left).
func on_peer_left(peer: int) -> void:
	invites.erase(peer)
	for target in invites.keys():
		if int(invites[target]["from"]) == peer:
			invites.erase(target)
	var id := int(duel_of.get(peer, 0))
	if id != 0 and duels.has(id):
		var d: Dictionary = duels[id]
		_end(id, d["b"] if d["a"] == peer else d["a"], peer, "left")


## The move a net kind stands for, validated against the attacker's record
## exactly as Enemy.net_hit does: {"mult", "cooldown"} or {} when refused.
static func move_for(sender: int, kind: int, p: Node) -> Dictionary:
	if kind == -1:
		return {"mult": 1.0, "cooldown": Player.ATTACK_COOLDOWN}
	if kind == Player.KIND_FINISHER:
		return {"mult": float(Player.COMBO[2]["mult"]), "cooldown": Player.FINISHER_COOLDOWN}
	if kind >= 0 and kind < Player.SKILLS.size():
		return {"mult": float(Player.SKILLS[kind]["mult"]), "cooldown": float(Player.SKILLS[kind]["cooldown"])}
	if HiddenClasses.is_art_kind(kind):
		var art := HiddenClasses.art_for_kind(kind)
		if art.is_empty() or Net.srv_hidden_class(sender) != str(art["class"]):
			return {}
		if bool(art.get("after_parry", false)):
			var since_parry: int = Time.get_ticks_msec() - int(p.last_parry_ms)
			if since_parry > int((HiddenClasses.COUNTER_WINDOW + HiddenClasses.COUNTER_LATENCY) * 1000.0):
				return {}
		return {"mult": float(art["mult"]), "cooldown": float(art["cooldown"])}
	if UniqueSkills.is_unique_kind(kind):
		var art := UniqueSkills.art_for_kind(kind)
		if art.is_empty() or not Net.srv_holds_unique(sender, UniqueSkills.TWIN_FANG):
			return {}
		return {"mult": float(art["mult"]), "cooldown": float(art["cooldown"])}
	return {}


## Server: `sender` claims a swing of `kind` reached `target`. Validated
## like Enemy.net_hit (same cooldown table, so one swing cannot hit a mob and
## the opponent on separate cooldowns), then queued as a telegraphed strike.
## Returns "" when accepted, otherwise the reason (tests, logs).
func srv_hit(sender: int, target: int, kind: int, from_dir: Vector3, swing: int) -> String:
	var id := int(duel_of.get(sender, 0))
	if id == 0 or not duels.has(id):
		return "not duelling"
	var d: Dictionary = duels[id]
	if str(d["phase"]) != "fight":
		return "not started"
	var opponent: int = d["b"] if d["a"] == sender else d["a"]
	if target != opponent:
		return "not your opponent"
	var p := _node_of(sender)
	var t := _node_of(target)
	if p == null or t == null:
		return "no node"
	if p.is_stunned() or (p.has_method("is_dying") and p.is_dying()):
		return "stunned"
	var p_pos: Vector3 = p.srv_position()
	var t_pos: Vector3 = t.srv_position()
	if p_pos.distance_to(t_pos) > HIT_RANGE + Net.RANGE_SLACK:
		return "out of range"
	var facing: Vector3 = -p.model.global_transform.basis.z
	var to: Vector3 = t_pos - p_pos
	to.y = 0.0
	if to.length() > 0.6 and facing.dot(to.normalized()) < -0.2:
		return "facing away"
	var move := move_for(sender, kind, p)
	if move.is_empty():
		return "bad kind"
	var key := "%d:%d" % [sender, kind]
	var now := Time.get_ticks_msec()
	var last: Array = Enemy._swing_times.get(key, [-100000, -1])
	var same_swing: bool = last[1] == swing and now - int(last[0]) <= Enemy.SWING_WINDOW_MS
	if not same_swing:
		if now - int(last[0]) < int(float(move["cooldown"]) * 900.0) or not Enemy.combo_gate_ok(sender, kind, now):
			return "cooldown"
		Enemy._swing_times[key] = [now, swing]
	if int(d["hit_by"].get(sender, -1)) == swing and swing != 0:
		return "duplicate swing"
	d["hit_by"][sender] = swing
	from_dir.y = 0.0
	from_dir = from_dir.normalized() if from_dir.length_squared() > 0.0001 else Vector3.FORWARD
	_pending.append({"duel": id, "attacker": sender, "defender": target, "kind": kind, "dmg": float(p.srv_attack) * float(move["mult"]) * (Net.srv_art_power(sender) if kind >= 0 else 1.0),
		"dir": from_dir, "at": _time + WINDUP})
	_deliver(target, {"ev": "incoming", "from": sender, "windup": WINDUP, "pos": p_pos})
	return ""


## Client -> server: my swing reached my duel opponent (Player._hit_cone).
@rpc("any_peer", "call_remote", "reliable")
func net_hit(target: int, kind: int, from_dir: Vector3, swing: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var why := srv_hit(sender, target, kind, from_dir, swing)
	if why != "" and why != "cooldown" and why != "duplicate swing" and Net._rate_ok(sender, "duel_warn", 3000):
		print("[duel] refused hit from peer %d (%s): %s" % [sender, _name(sender), why])


## World.srv_action "duel": {"op": invite|accept|decline|yield, "name", "mode"}.
func srv(peer: int, _rs, payload: Dictionary, _pos: Vector3) -> Dictionary:
	match str(payload.get("op", "")):
		"invite":
			return srv_invite(peer, str(payload.get("name", "")), str(payload.get("mode", DEFAULT_MODE)))
		"accept":
			return srv_respond(peer, true)
		"decline":
			return srv_respond(peer, false)
		"yield":
			return srv_yield(peer)
	return _err("Duel: /duel Name [first|half|full], /duel accept, /duel decline, /duel yield")


# =============================================================================
# Client
# =============================================================================

## Am I duelling `peer` right now (hits on anyone else never leave the client)?
func is_opponent(peer: int) -> bool:
	return not my_duel.is_empty() and str(my_duel.get("phase", "")) == "fight" and int(my_duel.get("opponent", -1)) == peer


func opponent_peer() -> int:
	return int(my_duel.get("opponent", 0)) if not my_duel.is_empty() else 0


## Attacker side of a swing that reached the opponent (from Player._hit_cone).
func client_hit(attacker: Node, target_peer: int, kind: int, dir: Vector3, swing: int) -> void:
	if not Net.online:
		return
	if multiplayer.is_server():
		srv_hit(int(attacker.get("peer_id")), target_peer, kind, dir, swing)
	else:
		net_hit.rpc_id(1, target_peer, kind, dir, swing)


func _local_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D if get_tree() else null


func _player_by_peer(peer: int) -> Node3D:
	if get_tree() == null:
		return null
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.get("peer_id")) == peer:
			return p
	return null


func _fx() -> Node:
	return VFX.get_for(self) if is_inside_tree() else null


func _hud() -> Node:
	if hud == null or not is_instance_valid(hud):
		hud = get_tree().get_first_node_in_group("hud") if get_tree() else null
	return hud


func _line(text: String) -> void:
	Net.chat_received.emit("", text, "system")


## The big centred number / "DUEL!" (a plain Label under the HUD, group
## "duel_countdown" so the visuals thread can restyle it).
func _show_big(text: String, secs: float, color := Color(1.0, 0.92, 0.6)) -> void:
	var h := _hud()
	if h == null:
		return
	if _count_label == null or not is_instance_valid(_count_label):
		_count_label = Label.new()
		_count_label.name = "DuelCountdown"
		_count_label.add_to_group("duel_countdown")
		_count_label.set_anchors_preset(Control.PRESET_CENTER)
		_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_count_label.add_theme_font_size_override("font_size", 96)
		_count_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0, 0.9))
		_count_label.add_theme_constant_override("outline_size", 10)
		_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_count_label.z_index = 50
		h.add_child(_count_label)
		UITheme.style_duel_label(_count_label)
	_count_label.text = text
	_count_label.add_theme_color_override("font_color", color)
	_count_label.reset_size()
	_count_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_count_label.visible = true
	_count_label.scale = Vector2(1.4, 1.4)
	_count_label.pivot_offset = _count_label.size * 0.5
	var tw := create_tween()
	tw.tween_property(_count_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_label_serial += 1
	var mine := _label_serial
	get_tree().create_timer(secs, false).timeout.connect(func():
		if _label_serial == mine and _count_label != null and is_instance_valid(_count_label):
			_count_label.visible = false)


## Client: a duel event or a command result from the server (net_apply
## "duel"); the host and the offline harness arrive here directly.
func on_net(kind: String, res: Dictionary) -> void:
	if kind != "duel":
		return
	if not res.has("ev"):
		var line := str(res["error"]) if res.has("error") else result_text(res)
		if line != "":
			_line(line)
		return
	var h := _hud()
	var me := _local_player()
	match str(res["ev"]):
		"invited":
			pending_invite = {"from": str(res.get("from", "")), "mode": str(res.get("mode", DEFAULT_MODE))}
			_line("%s challenges you to a duel (%s). Type /duel accept or /duel decline within %d s." % [pending_invite["from"], str(res.get("mode_name", "")), int(res.get("ttl", INVITE_TTL))])
			if h != null and h.has_method("toast"):
				h.toast("Duel challenge", "%s  ·  %s" % [pending_invite["from"], str(res.get("mode_name", ""))], "Duel", UITheme.GOLD)
			Audio.play("ui_open")
			if auto_accept:
				get_tree().create_timer(0.8, false).timeout.connect(func(): request({"op": "accept"}))
		"declined":
			_line("%s declined your duel." % str(res.get("by", "")))
		"expired":
			pending_invite = {}
			_line("The duel challenge from %s expired." % str(res.get("from", "")))
		"begin":
			pending_invite = {}
			my_duel = {"id": int(res.get("duel", 0)), "opponent": int(res.get("opponent_peer", 0)), "opponent_name": str(res.get("opponent", "")),
				"mode": str(res.get("mode", DEFAULT_MODE)), "phase": "count"}
			_line("Duel with %s: %s. Get ready." % [my_duel["opponent_name"], str(res.get("mode_name", ""))])
			if h != null and h.has_method("toast"):
				h.toast("Duel: %s" % my_duel["opponent_name"], str(res.get("mode_name", "")), "Duel", UITheme.GOLD)
			_show_big(str(int(res.get("count", COUNTDOWN))), 1.1)
			var hroot = h.get("_root") if h != null else null
			if hroot is Control:
				_free_opp_bar()
				_opp_bar = PlayerStatus.make_duel_gauge(hroot, my_duel["opponent_name"])
			var fx := _fx()
			if fx and fx.has_method("duel_countdown"):
				fx.call("duel_countdown", int(res.get("count", COUNTDOWN)))
		"count":
			var n := int(res.get("n", 0))
			if n > 10 and n % 10 != 0:
				return  # the long lead-in stays quiet; every 10 s and the last 10 show
			_show_big(str(n), 1.1, Color(1.0, 0.92, 0.6) if n > 3 else Color(1.0, 0.55, 0.4))
			Audio.play("ui_tick")
			var fx := _fx()
			if fx and fx.has_method("duel_countdown"):
				fx.call("duel_countdown", n)
		"start":
			var a := _player_by_peer(int(res.get("a_peer", 0)))
			var b := _player_by_peer(int(res.get("b_peer", 0)))
			if not bool(res.get("spectator", false)):
				my_duel["phase"] = "fight"
				_show_big("DUEL!", 1.2, Color(1.0, 0.45, 0.35))
				Audio.play("ui_confirm")
				Audio.play("skill_charge")
				InputSetup.rumble(0.5, 0.9, 0.25)
				if me != null and (bool(me.get("bot")) or auto_accept):
					me.set("bot_duel_target", _player_by_peer(opponent_peer()))
			else:
				_line("%s and %s cross blades." % [str(res.get("a", "")), str(res.get("b", ""))])
			var fx := _fx()
			if fx and fx.has_method("duel_start"):
				fx.call("duel_start", a, b)
			if fx and fx.has_method("duel_ring") and res.get("center") is Vector3:
				fx.call("duel_ring", res["center"], FORFEIT_RANGE, true)
		"incoming":
			var from := _player_by_peer(int(res.get("from", 0)))
			if me != null and bool(me.get("bot")) and me.has_method("bot_incoming"):
				me.bot_incoming(float(res.get("windup", WINDUP)))
			var fx := _fx()
			if fx and from != null and fx.has_method("duel_incoming"):
				fx.call("duel_incoming", from, float(res.get("windup", WINDUP)))
		"parried":
			if me != null and me.has_method("pvp_staggered"):
				me.pvp_staggered(float(res.get("stun", PARRY_STUN)), res.get("push", Vector3.ZERO) if res.get("push") is Vector3 else Vector3.ZERO)
			_line("%s parried your blow." % str(res.get("by", "")))
		"hit":
			if _opp_bar != null and is_instance_valid(_opp_bar) and int(res.get("defender", 0)) == opponent_peer() and res.has("hp"):
				_opp_bar.call("set_hp", float(res["hp"]), float(res.get("max", 100.0)))
			if me == null or int(res.get("attacker", 0)) != int(me.get("peer_id")):
				return
			var t := _player_by_peer(int(res.get("defender", 0)))
			var fx := _fx()
			if fx and t != null and float(res.get("amount", 0.0)) > 0.0:
				var at: Vector3 = t.global_position + Vector3(0, 1.1, 0)
				fx.hit(at, (t.global_position - me.global_position).normalized(), VFX.kind_color(int(res.get("kind", -1))), int(res.get("kind", -1)) >= 0)
		"end":
			var w := _player_by_peer(int(res.get("winner_peer", 0)))
			var l := _player_by_peer(int(res.get("loser_peer", 0)))
			_line(str(res.get("text", "")))
			if not bool(res.get("spectator", false)):
				my_duel = {}
				var bar := _opp_bar
				get_tree().create_timer(2.2, false).timeout.connect(func():
					if bar == _opp_bar:
						_free_opp_bar())
				if me != null:
					me.set("bot_duel_target", null)
					if auto_accept:
						bot_finish(me)
				var won := bool(res.get("won", false))
				_show_big("VICTORY" if won else "DEFEAT", 2.2, Color(1.0, 0.85, 0.35) if won else Color(0.75, 0.8, 1.0))
				if h != null and h.has_method("toast"):
					h.toast("You won the duel" if won else "You lost the duel", str(res.get("text", "")), "Duel", UITheme.GOLD if won else UITheme.ROSE)
				Audio.play("level_up" if won else "guard_break")
			var fx := _fx()
			if fx and fx.has_method("duel_end"):
				fx.call("duel_end", w, l)
			if fx and fx.has_method("duel_ring"):
				fx.call("duel_ring", Vector3.ZERO, FORFEIT_RANGE, false)


func _free_opp_bar() -> void:
	if _opp_bar != null and is_instance_valid(_opp_bar):
		_opp_bar.queue_free()
	_opp_bar = null


## The chat command's request: a connected client asks the server, the
## listen host runs it directly; offline there is nobody to fight.
func request(payload: Dictionary) -> Dictionary:
	if Net.remote_client():
		if not Net.request_action("duel", payload):
			return _err("Slow down a moment.")
		return {"pending": true}
	if not Net.online or not multiplayer.is_server():
		return _err("There is nobody to duel offline.")
	var me := _local_player()
	var res := srv(multiplayer.get_unique_id(), null, payload, me.global_position if me != null else Vector3.ZERO)
	return res


## Chat: "/duel Name [first|half|full]", "/duel accept", "/duel decline",
## "/duel yield". Returns true when the line was a duel command.
static func chat_command(text: String, hud_node: Node, system: Callable) -> bool:
	var t := text.strip_edges()
	var low := t.to_lower()
	if not (low == "/duel" or low.begins_with("/duel ")):
		return false
	var node = hud_node.get_tree().get_first_node_in_group("duels") if hud_node and hud_node.is_inside_tree() else null
	if node == null:
		system.call("There are no duels on this floor.")
		return true
	node.hud = hud_node
	var args := t.substr(5).strip_edges().split(" ", false)
	if args.is_empty():
		system.call("Duel: /duel Name [first|half|full] (First Strike by default), /duel accept, /duel decline, /duel yield")
		return true
	var payload := {}
	match args[0].to_lower():
		"accept", "decline", "yield":
			payload = {"op": args[0].to_lower()}
		"forfeit":
			payload = {"op": "yield"}
		_:
			payload = {"op": "invite", "name": args[0], "mode": args[1].to_lower() if args.size() > 1 else DEFAULT_MODE}
	var res: Dictionary = node.request(payload)
	if res.has("error"):
		system.call(str(res["error"]))
	elif not res.get("pending", false):
		system.call(result_text(res))
	return true


static func result_text(res: Dictionary) -> String:
	match str(res.get("op", "")):
		"invite":
			return "You challenged %s to a duel (%s)." % [str(res.get("invited", "")), str(res.get("mode_name", ""))]
		"accept":
			return "Challenge accepted."
		"decline":
			return "Challenge declined."
		"yield":
			return "You yielded."
	return ""


# =============================================================================
# --duel soak bot (client side): walk out of the north gate, challenge the
# other bot once, accept any challenge, fight through the normal bot hunt.
# =============================================================================

func bot_tick(world: Node, player: Node3D, delta: float) -> bool:
	if _bot_done or player == null:
		return false
	auto_accept = true
	_bot_t += delta
	if not my_duel.is_empty():
		# Countdown: stand still (hunting would walk out of range); fight:
		# the normal bot brain with bot_duel_target set (Player._bot_think).
		if str(my_duel.get("phase", "")) == "fight":
			player.bot = true
		else:
			player.bot = false
			player.velocity.x = 0.0
			player.velocity.z = 0.0
		return true
	if _bot_t < 3.0:
		return true
	var meet := BOT_MEET + Vector3(1.5 * float(absi(hash(str(player.get("display_name")))) % 3 - 1), 0, 0)
	var flat: Vector3 = (meet - player.global_position) * Vector3(1, 0, 1)
	if flat.length() > 2.5:
		player.bot = false
		if world.has_method("_chore_walk"):
			world._chore_walk(meet, delta)
		return true
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	var other: Node3D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p != player and p.global_position.distance_to(player.global_position) < INVITE_RANGE - 2.0:
			other = p
	if other == null or _bot_t < _bot_next_invite or not pending_invite.is_empty():
		return true
	# The lower name challenges, so the two do not cross challenges.
	if str(player.get("display_name")) < str(other.get("display_name")):
		_bot_next_invite = _bot_t + 6.0
		print("[bot] challenging %s to a duel" % str(other.get("display_name")))
		request({"op": "invite", "name": str(other.get("display_name")), "mode": DEFAULT_MODE})
	return true


## The --duel bot's duel ended: back to hunting mobs.
func bot_finish(player: Node3D) -> void:
	_bot_done = true
	if player != null:
		player.bot = true
