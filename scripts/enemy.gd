class_name Enemy
extends CharacterBody3D
## Mob: wanders around its spawn, chases the nearest player when close,
## deals contact damage, drops XP/money/materials and respawns after a delay.
## Online the server runs the AI and owns hp; clients only draw what arrives.

signal died(enemy: Enemy)

@export var display_name := "Field Boar"
@export var mob_level := 1
@export var max_hp := 40.0
@export var damage := 6.0
@export var xp_reward := 25
@export var money_reward := 5
@export var color := Color(0.55, 0.35, 0.25)
@export var aggro_range := 9.0
@export var speed := 3.2
@export var drops := {}  # material id -> chance (0..1)
@export var is_boss := false
@export var respawns := true
@export var size := Vector3(0.9, 0.8, 1.3)
@export var quest_id := ""  # quest advanced on the killer when this dies
## Ranged mobs (Floor 2 wisps): hold at ~60% of this distance and fire a bolt
## every BOLT_PERIOD s while a player is inside it. 0 = melee only.
@export var ranged := 0.0
## Rigged creature model override: {"pack", "name", "fit", "tint", "yaw",
## "lift", "scale"}; empty = the MODELS entry of this mob's rig kind.
@export var model := {}

const SLAM_RANGE := 5.0
const BOLT_PERIOD := 2.6
const SUMMON_PERIOD := 18.0
var _slam_timer := 6.0
var _bolt_timer := 1.5
var _summon_timer := 9.0
## Boss summon hook: the world sets Callable(enemy) that spawns adds. Only
## the authority ever calls it.
var summon: Callable

var hp := 0.0
var home := Vector3.ZERO
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _hit_cd := 0.0
## Telegraphed strikes: the attack animation starts, the blow lands WINDUP
## seconds later only if the target is still in reach. Stepping or dashing
## out at the last moment is a dodge (a hidden "reaction" point, UniqueSkills).
const WINDUP := 0.42
const WINDUP_BOSS := 0.6
var _windup := 0.0
var _windup_target: Node3D
## Parried strikes build posture; a full bar staggers the mob (it stops,
## can't strike, and takes riposte damage). Bosses take three parries.
const STAGGER_TIME := 1.5
const STAGGER_TIME_BOSS := 2.2
const RIPOSTE_MULT := 1.5
var _posture := 0
var _stagger := 0.0
var _knock := Vector3.ZERO
var _mesh: MeshInstance3D
var _label: Label3D
var _plate: MobPlate
var _dead := false
var _last_hitter := 1
var _shown_hp := -1.0
# Visual rig (built from primitives; see _build_visual).
var _rig: Node3D
var _breath: Node3D
var _orbit: Node3D
var _limbs: Array = []  # [node, phase, base_x, amplitude]
var _anim_t := 0.0
var _idle_t := 0.0
var _run_blend := 0.0
var _prev_pos := Vector3.ZERO
var _visual_height := 0.0
# Cosmetic state (scripts/vfx.gd): toon materials for the hit flash
# ([mat, emission, strength]), dissolve material cache, flash tween, the
# smallest hit seen (clients guess crits from it) and slam detection.
var _flash_mats: Array = []
var _dissolve_cache: Array = []
var _flash_tw: Tween
var _min_hit := INF
var _slam_armed := false
# Rigged model state (see "creature models" below): the clip player, the clip
# role playing, when a one-shot (attack/hit) clip gives the body back, and
# whether the far-distance freeze is on.
var _anim: AnimationPlayer
var _anim_state := ""
var _attack_until := 0.0
var _anim_frozen := false


## Builds an enemy from a plain dictionary (what the network spawner sends).
static func from_data(d: Dictionary) -> Enemy:
	var e := Enemy.new()
	e.display_name = d.get("name", e.display_name)
	e.mob_level = int(d.get("level", 1))
	e.max_hp = float(d.get("hp", 40))
	e.damage = float(d.get("dmg", 6))
	e.xp_reward = int(d.get("xp", 25))
	e.money_reward = int(d.get("money", 5))
	e.color = Color(d.get("color", "8c5940"))
	e.aggro_range = float(d.get("aggro", 9))
	e.speed = float(d.get("speed", 3.2))
	e.drops = d.get("drops", {})
	e.is_boss = bool(d.get("boss", false))
	e.respawns = bool(d.get("respawns", true))
	var sz: Array = d.get("size", [0.9, 0.8, 1.3])
	e.size = Vector3(sz[0], sz[1], sz[2])
	e.quest_id = d.get("quest", "")
	e.ranged = float(d.get("ranged", 0))
	var md = d.get("model", {})
	e.model = md if md is Dictionary else {}
	var p: Array = d.get("pos", [0, 1, 0])
	e.position = Vector3(p[0], p[1], p[2])
	return e


func _ready() -> void:
	add_to_group("enemies")
	home = global_position
	hp = max_hp
	# Layer 4 = mobs: collide with the world (1) and players (2), not each other.
	collision_layer = 4
	collision_mask = 1 | 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2
	add_child(shape)

	_build_visual()

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = maxf(size.y, _visual_height) + 0.6
	_label.font_size = 40
	_label.outline_size = 8
	add_child(_label)
	# Styled plate (cursor crystal, name, HP bar) replaces the text label on
	# rendering clients; the label stays as the headless/debug fallback.
	if DisplayServer.get_name() != "headless":
		_plate = MobPlate.new()
		_plate.position.y = _label.position.y
		add_child(_plate)
		_label.visible = false
	_update_label()

	if Net.online:
		var sync := MultiplayerSynchronizer.new()
		sync.name = "Sync"
		var cfg := SceneReplicationConfig.new()
		for prop in [".:position", ".:rotation", ".:hp", ".:visible", "Mesh:scale"]:
			cfg.add_property(NodePath(prop))
		sync.replication_config = cfg
		add_child(sync)


func _update_label() -> void:
	_label.text = "%s  Lv%d\n%d / %d" % [display_name, mob_level, ceil(hp), max_hp]
	if _plate:
		_plate.set_info(display_name, mob_level, mob_level - GameState.level, is_boss)
		_plate.set_hp(hp / maxf(1.0, max_hp))
	_shown_hp = hp


func _physics_process(delta: float) -> void:
	if not Net.is_authority():
		# Client: mirror what the server sends. Dead mobs must not block anyone.
		var was_dead := _dead
		_dead = not visible
		if _dead and not was_dead:
			Audio.play("boss_death" if is_boss else "death", global_position, 0.15, 0.0, 0.8)
			_death_fx()
		collision_layer = 0 if _dead else 4
		if hp != _shown_hp:
			if _shown_hp >= 0.0 and hp < _shown_hp and visible:
				var dealt := _shown_hp - hp
				# Clients don't know the move; a hit well above the smallest
				# one seen on this mob reads as a Sword Art (cosmetic only).
				var crit := _min_hit < INF and dealt >= _min_hit * 1.5
				_min_hit = minf(_min_hit, dealt)
				_popup("-%d" % int(round(dealt)), Color(1.0, 0.85, 0.3), crit)
				_hit_sfx(dealt)
				_hit_fx(Vector3.ZERO, crit)
			_update_label()
		# Boss slam arrives as the replicated squash; dust when it snaps back.
		if is_boss:
			if _mesh.scale.y < 0.7:
				_slam_armed = true
			elif _slam_armed and _mesh.scale.y > 0.9:
				_slam_armed = false
				_slam_fx()
		return
	if _dead:
		return
	_hit_cd = max(_hit_cd - delta, 0.0)
	if not is_on_floor():
		velocity.y -= gravity * delta
	if global_position.y < home.y - 30.0:
		# Knocked off the island: put it back instead of losing it forever.
		global_position = home
		velocity = Vector3.ZERO

	var player := _nearest_player()
	var target := _wander_target
	var spd := speed * 0.4
	if player and player.global_position.distance_to(global_position) < aggro_range \
			and player.global_position.distance_to(home) < aggro_range * 2.5:
		target = player.global_position
		spd = speed
		var reach := 1.3 + size.z * 0.5
		var dist := player.global_position.distance_to(global_position)
		if _stagger > 0.0:
			_stagger = maxf(_stagger - delta, 0.0)
			spd = 0.0
			target = global_position
		elif _windup > 0.0:
			_windup -= delta
			spd *= 0.25
			if _windup <= 0.0:
				_resolve_strike(reach)
		elif dist < reach and _hit_cd == 0.0:
			_windup = WINDUP_BOSS if is_boss else WINDUP
			_windup_target = player
			_swing()
		if ranged > 0.0:
			# Keep a casting distance instead of closing in, and lob bolts.
			if dist < ranged * 0.6:
				target = global_position
				spd = 0.0
			_bolt_timer -= delta
			if _bolt_timer <= 0.0 and dist < ranged:
				_bolt_timer = BOLT_PERIOD
				_bolt(player)
		if is_boss:
			_slam_timer -= delta
			if _slam_timer <= 0.0:
				_slam()
			if summon.is_valid():
				_summon_timer -= delta
				if _summon_timer <= 0.0:
					_summon_timer = SUMMON_PERIOD
					summon.call(self)
	else:
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_wander_timer = randf_range(2.0, 5.0)
			_wander_target = home + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))

	var to := target - global_position
	to.y = 0
	var move := Vector3.ZERO
	if to.length() > 0.8:
		move = to.normalized() * spd
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 6.0 * delta)
	velocity.x = move.x + _knock.x
	velocity.z = move.z + _knock.z
	_knock = _knock.move_toward(Vector3.ZERO, 30 * delta)
	move_and_slide()


func _resolve_strike(reach: float) -> void:
	_hit_cd = 1.0
	var t := _windup_target
	_windup_target = null
	if t == null or not is_instance_valid(t) or not t.is_inside_tree():
		return
	if t.has_method("is_dying") and t.is_dying():
		return
	var d := t.global_position.distance_to(global_position)
	if d < reach * 1.1:
		var outcome: String = t.defend(global_position) if t.has_method("defend") else ""
		_show_defence(t, outcome)
		match outcome:
			"parry":
				_parried(t)
			"block":
				_damage_player(t, damage * (1.0 - Player.BLOCK_REDUCTION))
			_:
				_damage_player(t, damage)
	elif d < reach * 2.6 and "peer_id" in t:
		Net.note_hidden(t.peer_id, "dodge")


## Tell the defender's machine what happened (the server judged it).
func _show_defence(t: Node3D, outcome: String) -> void:
	if outcome == "":
		return
	if not Net.online or t.peer_id == multiplayer.get_unique_id():
		t.defend_fx(outcome, global_position)
	elif multiplayer.get_peers().has(t.peer_id):
		t.net_defended.rpc_id(t.peer_id, outcome, global_position, t.guard, t._stun)


func _parried(t: Node3D) -> void:
	_hit_cd = maxf(_hit_cd, 1.2)
	_posture += 1
	Net.note_hidden(t.peer_id, "parry")
	if _posture >= (3 if is_boss else 1):
		_posture = 0
		_stagger = STAGGER_TIME_BOSS if is_boss else STAGGER_TIME
		_windup = 0.0
		if Net.online:
			net_staggered.rpc(_stagger)
		else:
			net_staggered(_stagger)


## Everyone: the mob reels (stagger look and sound; the hit window is the
## server's _stagger).
@rpc("authority", "call_local", "reliable")
func net_staggered(seconds: float) -> void:
	_stagger = clampf(seconds, 0.0, 3.0)
	Audio.play("stagger", global_position, 0.05)
	var fx := VFX.get_for(self)
	if fx and fx.has_method("stagger"):
		fx.call("stagger", self, seconds)
	elif fx:
		fx.ring(global_position + Vector3(0, size.y * 0.9, 0), Color(1.0, 0.85, 0.3), 1.4, 0.4)
	if _anim != null:
		_anim.speed_scale = 0.25
		get_tree().create_timer(seconds, false).timeout.connect(func():
			if is_instance_valid(self) and _anim != null:
				_anim.speed_scale = 1.0)


func is_staggered() -> bool:
	return _stagger > 0.0


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("players"):
		var d: float = p.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _damage_player(p: Node3D, amount: float) -> void:
	# Offline / host: the local GameState. Server, remote player: the record
	# (Player.take_damage -> Net.srv_damage), which then informs the owner.
	if not Net.online or p.peer_id == multiplayer.get_unique_id() or multiplayer.get_peers().has(p.peer_id):
		p.take_damage(amount)


## Boss ground slam: telegraphed by a squash, then hits everyone nearby hard.
func _slam() -> void:
	_slam_timer = randf_range(5.0, 8.0)
	Audio.play("grunt", global_position, 0.1, 4.0, 0.6)
	_swing()
	var tw := create_tween()
	tw.tween_property(_mesh, "scale", Vector3(1.3, 0.6, 1.3), 0.6)
	tw.tween_callback(func():
		if _dead:
			return
		Audio.play("slam", global_position, 0.05, 4.0)
		_slam_fx()
		for p in get_tree().get_nodes_in_group("players"):
			if p.global_position.distance_to(global_position) < SLAM_RANGE:
				_damage_player(p, damage * 2.5))
	tw.tween_property(_mesh, "scale", Vector3.ONE, 0.2)


## Ranged attack (authority): a glowing bolt flies for 0.45 s, then the
## target takes damage if it is still inside the bolt's range. The same
## _damage_player path as contact hits, so armour and rpc routing match.
func _bolt(p: Node3D) -> void:
	var from := global_position + Vector3(0, maxf(size.y, _visual_height) * 0.7, 0)
	var to := p.global_position + Vector3(0, 1.0, 0)
	_swing()
	if Net.online:
		net_bolt.rpc(from, to)
	else:
		net_bolt(from, to)
	var tw := create_tween()
	tw.tween_interval(0.45)
	tw.tween_callback(func():
		if _dead or not is_instance_valid(p):
			return
		if p.global_position.distance_to(global_position) < ranged + 2.0:
			_damage_player(p, damage))


## Cosmetic bolt everyone draws (Floor 2 wisps): a bright mote that streaks
## from the caster to where the target stood and bursts.
@rpc("authority", "call_local", "unreliable")
func net_bolt(from: Vector3, to: Vector3) -> void:
	Audio.play("crit", from, 0.1, 6.0, 0.5)
	var root := get_tree().current_scene if get_tree().current_scene else get_parent()
	if root == null:
		return
	var core := MeshInstance3D.new()
	core.mesh = _sph(0.22)
	core.material_override = _pm(Color(0.75, 1.0, 0.95), 0.0, Color(0.4, 1.0, 0.85), 3.5)
	core.position = from
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var tail := MeshInstance3D.new()
	tail.mesh = _cy(0.0, 0.14, 0.9)
	tail.material_override = _pm(Color(0.45, 0.9, 0.8), 0.0, Color(0.3, 0.9, 0.75), 2.0)
	tail.position = Vector3(0, -0.45, 0)
	core.add_child(tail)
	core.look_at_from_position(from, to, Vector3.UP)
	core.rotate_object_local(Vector3.RIGHT, PI / 2)
	var tw := core.create_tween()
	tw.tween_property(core, "position", to, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		var fx := VFX.get_for(self)
		if fx:
			fx.sparkle(to)
		core.queue_free())


## Authority: everyone plays this mob's attack clip (or a lunge on rigs
## without one). Cosmetic; the damage went through _damage_player already.
func _swing() -> void:
	if Net.online:
		net_swing.rpc()
	else:
		net_swing()


@rpc("authority", "call_local", "unreliable")
func net_swing() -> void:
	if _dead or _rig == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _anim != null:
		_anim.speed_scale = 1.0
		var clip_len := _set_anim("attack", false)
		if clip_len > 0.0:
			_attack_until = now + minf(clip_len, 1.2)
			return
	# No attack clip: a short lunge forward and back.
	var tw := create_tween()
	tw.tween_property(_rig, "position:z", -size.z * 0.3, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_rig, "position:z", 0.0, 0.18)


## Server-side record of each peer's last swing per move kind, for cooldowns.
## Value: [time_ms, swing_serial]. A swing may hit several mobs (AoE), so
## hits that share the serial within a short window are all accepted.
static var _swing_times := {}
const SWING_WINDOW_MS := 250
## Which swing serial last hit this mob, per peer, so one swing lands once.
var _hit_by := {}


static func forget_peer(peer: int) -> void:
	for key in _swing_times.keys():
		if str(key).begins_with("%d:" % peer):
			_swing_times.erase(key)


## A client asks the server to apply a hit of a given kind (-1 basic swing,
## 0.. a Sword Art). The server checks range and cooldown, then computes the
## damage itself from the attacker's level, so a modified client gains nothing.
@rpc("any_peer", "call_remote", "reliable")
func net_hit(kind: int, from_dir: Vector3, swing: int = 0) -> void:
	if not multiplayer.is_server() or _dead:
		return
	var sender := multiplayer.get_remote_sender_id()
	from_dir.y = 0.0
	from_dir = from_dir.normalized() if from_dir.length_squared() > 0.0001 else Vector3.FORWARD
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id != sender:
			continue
		# Range from where the SERVER has accepted the attacker to be, not the
		# position it just synced (Player.srv_position).
		var p_pos: Vector3 = p.srv_position()
		if p_pos.distance_to(global_position) > 4.0 + size.z:
			return
		# Facing check: the mob must be roughly in front of the attacker.
		var facing: Vector3 = -p.model.global_transform.basis.z
		var to: Vector3 = global_position - p_pos
		to.y = 0.0
		if to.length() > 0.6 and facing.dot(to.normalized()) < -0.2:
			return
		var mult := 1.0
		var cooldown := Player.ATTACK_COOLDOWN
		if kind >= 0 and kind < Player.SKILLS.size():
			mult = Player.SKILLS[kind]["mult"]
			cooldown = Player.SKILLS[kind]["cooldown"]
		elif UniqueSkills.is_unique_kind(kind):
			# Unique Sword Arts: only the realm's holder may land them.
			var art := UniqueSkills.art_for_kind(kind)
			if art.is_empty() or not Net.srv_holds_unique(sender, UniqueSkills.TWIN_FANG):
				return
			mult = float(art["mult"])
			cooldown = float(art["cooldown"])
		elif kind != -1:
			return
		var key := "%d:%d" % [sender, kind]
		var now := Time.get_ticks_msec()
		var last: Array = _swing_times.get(key, [-100000, -1])
		var same_swing: bool = last[1] == swing and now - int(last[0]) <= SWING_WINDOW_MS
		if not same_swing:
			if now - int(last[0]) < int(cooldown * 900.0):
				return
			_swing_times[key] = [now, swing]
		if int(_hit_by.get(sender, -1)) == swing and swing != 0:
			return  # This swing already landed on this mob.
		_hit_by[sender] = swing
		# The server uses the attack the owner reported, already clamped to
		# what a legit player of that level could reach (Player.attack_cap).
		take_hit(float(p.srv_attack) * mult, from_dir, sender, kind)
		return


func take_hit(amount: float, from_dir: Vector3, hitter := 1, kind := -1) -> void:
	if _dead or not Net.is_authority():
		return
	if _stagger > 0.0:
		amount *= RIPOSTE_MULT  # riposte on a staggered mob
		kind = maxi(kind, 0)    # reads as a heavy (crit) hit
	hp -= amount
	_last_hitter = hitter
	# Offline, and for the listen-server host, the popup is drawn here; clients
	# draw theirs when the replicated hp drops.
	var crit := kind >= 0
	_popup("-%d" % int(round(amount)), Color(1.0, 0.85, 0.3), crit)
	_hit_sfx(amount)
	_hit_fx(from_dir, crit, VFX.kind_color(kind))
	_knock = from_dir * (2.0 if is_boss else 8.0)
	if hp <= 0:
		_die()
	else:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.2, 0.8, 1.2), 0.05)
		tw.tween_property(_mesh, "scale", Vector3.ONE, 0.1)
		_update_label()


func _die() -> void:
	_dead = true
	_windup = 0.0
	_windup_target = null
	Net.note_hidden(_last_hitter, "kill")
	Audio.play("boss_death" if is_boss else "death", global_position, 0.15, 0.0, 0.8)
	if not Net.online:
		_grant_local()
	else:
		# Server: XP/Col are split across the killer's party members in range
		# (Net.party_split) and levelled on the server records; each client
		# is then told its share. Drops and quest credit go to the killer.
		var shares: Dictionary = Net.srv_reward_kill(_last_hitter, xp_reward, money_reward, global_position, drops, quest_id)
		for peer in shares:
			if peer == multiplayer.get_unique_id():
				_grant_share(int(shares[peer][0]), int(shares[peer][1]), peer == _last_hitter)
			elif multiplayer.get_peers().has(peer):
				net_reward_split.rpc_id(peer, int(shares[peer][0]), int(shares[peer][1]), peer == _last_hitter)
	died.emit(self)
	visible = false
	_death_fx()
	_mesh.scale = Vector3.ONE
	_hit_by.clear()
	process_mode = Node.PROCESS_MODE_DISABLED
	remove_from_group("enemies")
	if respawns:
		get_tree().create_timer(8.0, false).timeout.connect(_respawn)
	else:
		queue_free()


## Impact sound for a hit: punch on beasts, metal on armoured kobolds and
## sentinels, bell/plate on the Guardian; beasts grunt (pitched-down soft hit).
func _hit_sfx(amount: float) -> void:
	if not Audio.enabled:
		return
	var n := display_name.to_lower()
	var ev := "hit_flesh"
	if is_boss:
		ev = "hit_heavy"
	elif "sentinel" in n or "golem" in n or "sergeant" in n or "gravelmaw" in n or "drowned" in n or "knight" in n:
		ev = "hit_metal"
	Audio.play(ev, global_position, 0.1, clampf(amount / 15.0, 0.0, 4.0))
	if ev == "hit_flesh" and randf() < 0.5:
		Audio.play("grunt", global_position, 0.15, -4.0, 0.7 if "boar" in n else 0.85)


## Hit-stop: a crit near the local player freezes time for a few frames so
## Sword Art hits land with weight. Never on a dedicated server, and only
## offline (online the world can't stop; the shake carries it instead).
const HIT_STOP := 0.05
static var _stop_until := 0


func _hit_stop() -> void:
	if not Audio.enabled:
		return
	var me := get_tree().get_first_node_in_group("player") as Node3D
	if me == null or me.global_position.distance_to(global_position) > 14.0:
		return
	if Net.online:
		if me.has_method("shake"):
			me.shake(0.12)
		return
	var now := Time.get_ticks_msec()
	if now < _stop_until or Engine.time_scale < 1.0:
		return
	_stop_until = now + int(HIT_STOP * 1000.0) + 120
	Engine.time_scale = 0.05
	get_tree().create_timer(HIT_STOP, true, false, true).timeout.connect(func():
		if Engine.time_scale == 0.05:
			Engine.time_scale = 1.0)


## Floating damage number: pops in with a scale bounce, drifts up and to the
## side, then fades and frees itself. Sword Art hits are bigger and hotter.
func _popup(text: String, color := Color(1.0, 0.85, 0.3), crit := false) -> void:
	if crit:
		_hit_stop()
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 84 if crit else 58
	l.outline_size = 16 if crit else 11
	l.outline_modulate = Color(0.12, 0.05, 0.02, 1.0)
	l.modulate = Color(1.0, 0.42, 0.18) if crit else color
	l.no_depth_test = true
	l.render_priority = 10
	var sx := randf_range(-0.45, 0.45)
	l.position = Vector3(sx, size.y + 0.9, 0)
	l.scale = Vector3.ONE * 0.25
	add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	var peak := 1.35 if crit else 1.15
	tw.tween_property(l, "scale", Vector3.ONE * peak, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(l, "scale", Vector3.ONE, 0.12)
	tw.tween_property(l, "position:y", l.position.y + (1.5 if crit else 1.2), 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:x", sx + signf(sx) * 0.35, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.35)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.5).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)


## Hit reaction: sparks and a flash where the blow lands, the toon materials
## blink white, and the rig squashes (clients get the server's squash through
## "Mesh:scale", so only the flash is added here). Cosmetic only.
func _hit_fx(from_dir: Vector3, crit := false, tint := Color(1.0, 0.95, 0.75)) -> void:
	if crit:
		Audio.play("crit", global_position, 0.08)
	var fx := VFX.get_for(self)
	if fx == null:
		return
	var at := global_position + Vector3(0, maxf(size.y, _visual_height) * 0.55, 0)
	var dir := from_dir
	if dir.length_squared() < 0.001:
		var cam := get_viewport().get_camera_3d()
		dir = (global_position - cam.global_position) if cam else Vector3.FORWARD
	at -= dir.normalized() * size.z * 0.35
	fx.hit(at, dir, tint, crit)
	_flash(0.3 if crit else 0.2)
	var now := Time.get_ticks_msec() / 1000.0
	if _anim != null and now >= _attack_until:
		var clip_len := _set_anim("hit", false)
		if clip_len > 0.0:
			_attack_until = now + minf(clip_len, 0.5)


## Blink every toon material under "Mesh" to white and ease it back.
func _flash(dur: float) -> void:
	if _flash_mats.is_empty():
		# Merged rigs carry their toon materials per surface; anything else
		# (a kept part) as material_override. MeshMerge lists both once.
		for m in MeshMerge.materials_of(_mesh):
			if m is ShaderMaterial and m.get_shader_parameter("emission_strength") != null:
				_flash_mats.append([m, m.get_shader_parameter("emission_color"), float(m.get_shader_parameter("emission_strength"))])
	if _flash_mats.is_empty():
		return
	if _flash_tw and _flash_tw.is_valid():
		_flash_tw.kill()
	_flash_tw = create_tween()
	_flash_tw.tween_method(_set_flash, 1.0, 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_flash(t: float) -> void:
	for e in _flash_mats:
		var m: ShaderMaterial = e[0]
		m.set_shader_parameter("emission_color", (e[1] as Color).lerp(Color(1, 1, 1, 1), t))
		m.set_shader_parameter("emission_strength", lerpf(float(e[2]), 3.5, t))


## Death: the rig burns away for 0.6 s (see VFX.dissolve) while the mob
## itself is already hidden/disabled exactly as before.
func _death_fx() -> void:
	var fx := VFX.get_for(self)
	if fx == null or _rig == null:
		return
	if _flash_tw and _flash_tw.is_valid():
		_flash_tw.kill()
	_set_flash(0.0)
	var edge := Color(1.0, 0.45, 0.15) if not is_boss else Color(0.6, 0.9, 1.0)
	# Rigged models act out their death clip first; the burn starts partway
	# through it (the rig keeps animating under the VFX node meanwhile).
	var delay := 0.0
	if _anim != null:
		_anim.speed_scale = 1.0
		_anim.active = true
		_anim_frozen = false
		var clip_len := _set_anim("death", false)
		if clip_len > 0.0:
			delay = clampf(clip_len * 0.7, 0.3, 1.4)
	# Crystal shatter when the visuals provide it (same arguments as dissolve
	# plus `big` for bosses); the burn-away dissolve is the fallback.
	if fx.has_method("shatter"):
		fx.call("shatter", _mesh, _rig, _dissolve_cache, edge, is_boss, delay)
	else:
		fx.dissolve(_mesh, _rig, _dissolve_cache, edge, 0.6, delay)
	_min_hit = INF


## Boss slam landing: dust ring, debris and a camera kick for nearby players.
func _slam_fx() -> void:
	var fx := VFX.get_for(self)
	if fx == null:
		return
	fx.dust_ring(global_position, SLAM_RANGE * 0.8)
	var me := get_tree().get_first_node_in_group("player")
	if me and me.has_method("shake") and me.global_position.distance_to(global_position) < SLAM_RANGE * 2.5:
		me.shake(0.35)


## Rewards land on the killer's own machine, where their GameState lives.
func _grant_local() -> void:
	_grant_share(xp_reward, money_reward, true)


## `xp`/`money` is this machine's share of the kill (the whole reward solo,
## a party_split share online); only the killer rolls drops and quest credit.
func _grant_share(xp: int, money: int, killer: bool) -> void:
	var fx := VFX.get_for(self)
	if fx:
		fx.sparkle(global_position + Vector3(0, size.y * 0.6, 0))
	GameState.add_xp(maxi(xp, 0))
	GameState.add_money(maxi(money, 0))
	if not killer or Net.remote_client():
		return  # online, drops and quest credit are rolled on the server record (net_apply "loot")
	for mat in drops:
		if randf() < drops[mat]:
			GameState.add_material(mat)
	if quest_id != "":
		GameState.advance_quest(quest_id)


@rpc("authority", "call_remote", "reliable")
func net_reward() -> void:
	_grant_local()


## Server -> one party member (or the killer): your share of this kill.
@rpc("authority", "call_remote", "reliable")
func net_reward_split(xp: int, money: int, killer: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_grant_share(clampi(xp, 0, 1000000), clampi(money, 0, 1000000), killer)


func _respawn() -> void:
	if not is_inside_tree():
		return
	global_position = home
	hp = max_hp
	_dead = false
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	add_to_group("enemies")
	_update_label()
	_attack_until = 0.0
	_anim_state = ""
	_set_anim("idle")


# ============================================================ visuals =====
# Everything below only builds and animates the creature's look. "Mesh" stays
# a MeshInstance3D (no mesh of its own) so "Mesh:scale" replication and the
# squash tweens keep working; the parts hang under it.

func _process(delta: float) -> void:
	if _rig == null or not visible:
		return
	var pos := global_position
	var flat := pos - _prev_pos
	flat.y = 0.0
	var spd := flat.length() / maxf(delta, 0.001) if _prev_pos != Vector3.ZERO else 0.0
	_prev_pos = pos
	var run := clampf(spd / maxf(speed, 0.5), 0.0, 1.0)
	_run_blend = lerpf(_run_blend, run, minf(delta * 8.0, 1.0))
	if _anim != null:
		_process_model()
		return
	_idle_t += delta
	_anim_t += delta * (5.0 + 9.0 * _run_blend)
	for l in _limbs:
		var n: Node3D = l[0]
		n.rotation.x = l[2] + sin(_anim_t + l[1]) * l[3] * _run_blend
	if _breath:
		var b := 1.0 + 0.03 * sin(_idle_t * 2.0) * (1.0 - _run_blend * 0.5)
		_breath.scale = Vector3(1.0, b, 1.0)
	_rig.position.y = absf(sin(_anim_t)) * 0.05 * size.y * _run_blend
	if _orbit:
		_orbit.rotation.y += delta * 1.2
		_orbit.position.y = _orbit.get_meta("base_y", 0.0) + sin(_idle_t * 1.5) * 0.05


## Merged rigs, one per kind + colour + size: the primitive builders below run
## once per key into a template whose static parts MeshMerge folds into one
## ArrayMesh per animated pivot; the template is packed and every mob of that
## kind instantiates it (shared meshes, its own copies of the toon materials).
static var _rig_cache := {}   # key -> {"scene": PackedScene, "height": float}


func _rig_kind() -> String:
	var n := display_name.to_lower()
	if "drowned" in n or "mirelord" in n:
		return "drowned"
	if "toad" in n:
		return "toad"
	if "stag" in n:
		return "stag"
	if "wisp" in n:
		return "wisp"
	if is_boss or "gravelmaw" in n:
		return "king"
	if "boar" in n:
		return "boar"
	if "wolf" in n:
		return "wolf"
	if "sergeant" in n:
		return "sergeant"
	if "kobold" in n:
		return "kobold"
	if "sentinel" in n or "golem" in n:
		return "sentinel"
	for k in ["slime", "bat", "rat"]:
		if k in n:
			return k
	return "boar"


func _build_kind(kind: String) -> void:
	match kind:
		"drowned":
			_build_drowned_knight()
		"toad":
			_build_toad()
		"stag":
			_build_stag()
		"wisp":
			_build_wisp()
		"king":
			_build_kobold(maxf(size.y, 1.0), 2)
		"wolf":
			_build_wolf()
		"sergeant":
			_build_kobold(size.y * 1.1, 1)
		"kobold":
			_build_kobold(maxf(size.y * 1.3, 1.0), 0)
		"sentinel":
			_build_sentinel()
		_:
			_build_boar()


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	add_child(_mesh)
	# A dedicated/headless process never draws: collisions, hitboxes, labels
	# and replication are independent of the visual, so it builds none (and
	# never loads a model).
	if Net.dedicated or DisplayServer.get_name() == "headless":
		return
	var spec := _model_spec() if use_models else {}
	if str(spec.get("name", "")) != "" and AssetLib.has_prop(str(spec.get("pack", "")), str(spec["name"])) and _build_model(spec):
		return
	_build_primitive()


## Primitive rig of this mob's kind (the pre-model look; still used when a
## model is missing or the data names none).
func _build_primitive() -> void:
	var kind := _rig_kind()
	var key := "%s|%s|%.3f,%.3f,%.3f" % [kind, color.to_html(false), size.x, size.y, size.z]
	if not _rig_cache.has(key):
		var tmpl := Node3D.new()
		tmpl.name = "Rig"
		_rig = tmpl
		_limbs.clear()
		_breath = null
		_orbit = null
		_build_kind(kind)
		for l in _limbs:
			var ln: Node3D = l[0]
			ln.set_meta("limb", [l[1], l[2], l[3]])
			MeshMerge.mark(ln)
		if _breath:
			_breath.set_meta("breath", true)
			MeshMerge.mark(_breath)
		if _orbit:
			_orbit.set_meta("orbit", true)
			MeshMerge.mark(_orbit)
		# Wisps stay unmerged: their look is a glow shell, a white core and
		# tendrils layered in the transparent queue (15 parts, cheap).
		if kind != "wisp":
			MeshMerge.merge(tmpl)
		MeshMerge.own(tmpl)
		var ps := PackedScene.new()
		ps.pack(tmpl)
		tmpl.free()
		_rig_cache[key] = {"scene": ps, "height": _visual_height}
	var entry: Dictionary = _rig_cache[key]
	_visual_height = entry["height"]
	_rig = entry["scene"].instantiate()
	_mesh.add_child(_rig)
	_limbs.clear()
	_breath = null
	_orbit = null
	for n in _rig.find_children("*", "Node3D", true, false):
		if n.has_meta("limb"):
			var l: Array = n.get_meta("limb")
			_limbs.append([n, l[0], l[1], l[2]])
		if n.has_meta("breath"):
			_breath = n
		if n.has_meta("orbit"):
			_orbit = n
	MeshMerge.localize_materials(_rig)


# -- primitive helpers --------------------------------------------------------

func _pm(color: Color, width := 0.02, emission := Color.BLACK, strength := 0.0) -> ShaderMaterial:
	return ToonMaterial.part(color, width, emission, strength)


func _sph(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 20
	m.rings = 10
	return m


func _cap(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 14
	m.rings = 5
	return m


func _bx(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m


func _cy(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 16
	return m


func _nd(parent: Node3D, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	return n


func _pt(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


## Registers a limb pivot for the run cycle.
func _limb(n: Node3D, phase: float, base_x := 0.0, amp := 0.6) -> void:
	_limbs.append([n, phase, base_x, amp])


func _eye_pair(parent: Node3D, pos: Vector3, r: float, iris: Color, glow := 0.6, slit := false) -> void:
	var white := _pm(Color(1, 1, 1), 0.0)
	var im := _pm(iris, 0.0, iris, glow)
	var black := _pm(Color(0.05, 0.04, 0.06), 0.0)
	var shine := _pm(Color(1, 1, 1), 0.0, Color(1, 1, 1), 1.0)
	for side: float in [-1.0, 1.0]:
		var p := Vector3(pos.x * side, pos.y, pos.z)
		_pt(parent, _sph(r), white, p, Vector3.ZERO, Vector3(1, 1.1, 0.5))
		_pt(parent, _sph(r * 0.7), im, p + Vector3(0, 0, -r * 0.3), Vector3.ZERO, Vector3(1, 1.1, 0.5))
		if slit:
			_pt(parent, _bx(r * 0.3, r * 1.1, r * 0.2), black, p + Vector3(0, 0, -r * 0.55))
		else:
			_pt(parent, _sph(r * 0.38), black, p + Vector3(0, 0, -r * 0.55), Vector3.ZERO, Vector3(1, 1.1, 0.5))
		_pt(parent, _sph(r * 0.2), shine, p + Vector3(-r * 0.25 * side, r * 0.3, -r * 0.7))


# -- Field Boar ----------------------------------------------------------------

func _build_boar() -> void:
	var w := size.x
	var h := size.y
	var l := size.z
	_visual_height = h * 1.1
	var m := _pm(color)
	var md := _pm(color.darkened(0.4))
	var mb := _pm(color.lightened(0.3))
	var mp := _pm(Color(0.9, 0.62, 0.6))
	var tusk := _pm(Color(0.97, 0.95, 0.85), 0.012)
	var body := _nd(_rig, Vector3(0, h * 0.56, 0))
	_breath = body
	_pt(body, _cap(w * 0.42, l * 0.7), m, Vector3(0, 0, l * 0.05), Vector3(PI / 2, 0, 0))
	_pt(body, _sph(w * 0.44), m, Vector3(0, 0.0, l * 0.36), Vector3.ZERO, Vector3(1, 1.05, 1))  # rump
	_pt(body, _cap(w * 0.34, l * 0.6), mb, Vector3(0, -h * 0.12, l * 0.02), Vector3(PI / 2, 0, 0))  # belly
	# Bristly mane ridge.
	for i in 6:
		_pt(body, _cy(0.0, w * 0.11, h * 0.26), md, Vector3(0, w * 0.4, l * (0.28 - i * 0.12)), Vector3(-0.6 + i * 0.1, 0, 0))
	# Head.
	var head := _nd(body, Vector3(0, -h * 0.02, -l * 0.45))
	_pt(head, _sph(w * 0.36), m, Vector3.ZERO, Vector3.ZERO, Vector3(0.95, 0.95, 1.05))
	_pt(head, _cy(w * 0.17, w * 0.22, l * 0.24), md, Vector3(0, -h * 0.1, -l * 0.2), Vector3(PI / 2 - 0.15, 0, 0))  # snout
	_pt(head, _cy(w * 0.17, w * 0.17, 0.02), mp, Vector3(0, -h * 0.08, -l * 0.32), Vector3(PI / 2 - 0.15, 0, 0))  # nose disc
	for side: float in [-1.0, 1.0]:
		_pt(head, _sph(w * 0.035), _pm(Color(0.1, 0.05, 0.05), 0.0), Vector3(side * w * 0.06, -h * 0.08, -l * 0.335))
		_pt(head, _cy(0.0, w * 0.05, l * 0.2), tusk, Vector3(side * w * 0.16, -h * 0.14, -l * 0.3), Vector3(-0.5, 0, side * -0.5))
		_pt(head, _sph(w * 0.11), md, Vector3(side * w * 0.27, h * 0.3, l * 0.02), Vector3(0, 0, side * -0.6), Vector3(0.45, 1.0, 0.7))  # ear
		_pt(head, _sph(w * 0.07), mp, Vector3(side * w * 0.27, h * 0.3, l * 0.0), Vector3(0, 0, side * -0.6), Vector3(0.3, 0.8, 0.5))
	_eye_pair(head, Vector3(w * 0.2, h * 0.1, -l * 0.26), w * 0.065, Color(0.9, 0.5, 0.2), 0.4)
	# Angry brows.
	for side: float in [-1.0, 1.0]:
		_pt(head, _bx(w * 0.14, w * 0.03, w * 0.03), md, Vector3(side * w * 0.2, h * 0.2, -l * 0.27), Vector3(0, 0, side * 0.45))
	# Stubby legs with hooves.
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var leg := _nd(_rig, Vector3(sx * w * 0.28, h * 0.32, sz * l * 0.3))
			_pt(leg, _cy(w * 0.11, w * 0.09, h * 0.3), m, Vector3(0, -h * 0.15, 0))
			_pt(leg, _bx(w * 0.2, h * 0.08, w * 0.2), md, Vector3(0, -h * 0.29, -w * 0.02))
			_limb(leg, 0.0 if sx * sz > 0 else PI, 0.0, 0.55)
	# Curly tail.
	_pt(body, _cy(0.025, 0.018, l * 0.22), md, Vector3(0, w * 0.2, l * 0.5), Vector3(0.9, 0, 0))
	_pt(body, _sph(0.045), md, Vector3(0, w * 0.27, l * 0.6))


# -- Dire Wolf -----------------------------------------------------------------

func _build_wolf() -> void:
	var w := size.x
	var h := size.y
	var l := size.z
	_visual_height = h * 1.3
	var m := _pm(color)
	var md := _pm(color.darkened(0.35))
	var ml := _pm(color.lightened(0.45))
	var body := _nd(_rig, Vector3(0, h * 0.64, 0))
	_breath = body
	_pt(body, _cap(w * 0.27, l * 0.55), m, Vector3(0, 0, l * 0.08), Vector3(PI / 2, 0, 0), Vector3(1, 1, 1))
	_pt(body, _sph(w * 0.31), m, Vector3(0, 0.0, -l * 0.2), Vector3.ZERO, Vector3(1, 1.15, 1))  # chest
	_pt(body, _sph(w * 0.35), md, Vector3(0, h * 0.06, -l * 0.26), Vector3.ZERO, Vector3(1.1, 0.9, 0.9))  # ruff
	_pt(body, _cap(w * 0.2, l * 0.5), ml, Vector3(0, -h * 0.12, l * 0.02), Vector3(PI / 2, 0, 0))  # belly
	_pt(body, _sph(w * 0.27), m, Vector3(0, 0.0, l * 0.36), Vector3.ZERO, Vector3(1, 1, 1))  # haunch
	# Neck + head, raised forward.
	_pt(body, _cap(w * 0.16, l * 0.22), m, Vector3(0, h * 0.14, -l * 0.38), Vector3(-0.9, 0, 0))
	var head := _nd(body, Vector3(0, h * 0.3, -l * 0.5))
	_pt(head, _sph(w * 0.22), m, Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.95, 1.05))
	_pt(head, _cap(w * 0.11, l * 0.2), m, Vector3(0, -h * 0.05, -l * 0.17), Vector3(PI / 2 + 0.1, 0, 0))  # muzzle
	_pt(head, _cap(w * 0.08, l * 0.14), ml, Vector3(0, -h * 0.12, -l * 0.15), Vector3(PI / 2 + 0.1, 0, 0))  # lower jaw
	_pt(head, _sph(w * 0.055), _pm(Color(0.08, 0.06, 0.08), 0.0), Vector3(0, -h * 0.02, -l * 0.3))  # nose
	for side: float in [-1.0, 1.0]:
		_pt(head, _cy(0.0, w * 0.085, h * 0.3), md, Vector3(side * w * 0.14, h * 0.22, l * 0.02), Vector3(-0.2, 0, side * -0.3))
		_pt(head, _cy(0.0, w * 0.05, h * 0.2), _pm(Color(0.85, 0.6, 0.6), 0.0), Vector3(side * w * 0.135, h * 0.2, l * 0.0), Vector3(-0.2, 0, side * -0.3))
		_pt(head, _bx(w * 0.14, w * 0.03, w * 0.03), md, Vector3(side * w * 0.11, h * 0.09, -l * 0.15), Vector3(0, 0, side * 0.5))  # brow
		# Fangs.
		_pt(head, _cy(0.0, 0.015, 0.06), _pm(Color(1, 1, 0.95), 0.0), Vector3(side * w * 0.05, -h * 0.1, -l * 0.26), Vector3(PI, 0, 0))
	_eye_pair(head, Vector3(w * 0.11, h * 0.03, -l * 0.16), w * 0.055, Color(1.0, 0.85, 0.2), 1.2)
	# Long legs with paws.
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var leg := _nd(_rig, Vector3(sx * w * 0.2, h * 0.5, sz * l * 0.28))
			_pt(leg, _cy(w * 0.1, w * 0.07, h * 0.3), m, Vector3(0, -h * 0.15, 0))
			_pt(leg, _cy(w * 0.065, w * 0.06, h * 0.26), m, Vector3(0, -h * 0.38, 0))
			_pt(leg, _sph(w * 0.085), md, Vector3(0, -h * 0.47, -w * 0.03), Vector3.ZERO, Vector3(1, 0.6, 1.3))
			_limb(leg, 0.0 if sx * sz > 0 else PI, 0.0, 0.7)
	# Tail swept up and back.
	var tail := _nd(body, Vector3(0, h * 0.02, l * 0.5), Vector3(1.0, 0, 0))
	_pt(tail, _cap(w * 0.09, l * 0.38), m, Vector3(0, l * 0.2, 0))
	_pt(tail, _cy(0.0, w * 0.07, l * 0.14), ml, Vector3(0, l * 0.44, 0))
	_limb(tail, PI / 2, 1.0, 0.25)


# -- Kobolds (scout 0, sergeant 1, king 2) --------------------------------------

func _build_kobold(hgt: float, rank: int) -> void:
	var H := hgt
	_visual_height = H * (1.15 if rank == 2 else 1.0)
	var m := _pm(color)
	var md := _pm(color.darkened(0.4))
	var ml := _pm(color.lightened(0.4))
	var leather := _pm(Color(0.36, 0.24, 0.14))
	var wood := _pm(Color(0.45, 0.3, 0.16))
	var metal := _pm(Color(0.7, 0.72, 0.78))
	var gold := _pm(Color(0.95, 0.75, 0.25), 0.015, Color(0.9, 0.6, 0.1), 0.3)
	var hip_y := H * 0.3
	# Hunched torso leaning forward.
	var torso := _nd(_rig, Vector3(0, hip_y, 0), Vector3(-0.35, 0, 0))
	_breath = torso
	_pt(torso, _cap(H * 0.14, H * 0.26), m, Vector3(0, H * 0.14, 0), Vector3.ZERO, Vector3(1.1, 1, 0.85))
	_pt(torso, _sph(H * 0.12), ml, Vector3(0, H * 0.1, -H * 0.05), Vector3.ZERO, Vector3(0.9, 1.1, 0.6))  # belly
	# Loincloth + belt.
	_pt(torso, _cy(H * 0.14, H * 0.15, H * 0.04), leather, Vector3(0, H * 0.0, 0))
	_pt(torso, _bx(H * 0.14, H * 0.16, 0.02), leather, Vector3(0, -H * 0.07, -H * 0.12), Vector3(0.15, 0, 0))
	if rank >= 1:
		# Shoulder plate on the shield side.
		_pt(torso, _sph(H * 0.085), metal, Vector3(-H * 0.16, H * 0.26, 0), Vector3(0, 0, 0.3), Vector3(1, 0.7, 1))
	if rank == 2:
		_pt(torso, _bx(H * 0.34, H * 0.55, 0.03), _pm(Color(0.45, 0.12, 0.2)), Vector3(0, H * 0.02, H * 0.14), Vector3(0.1, 0, 0))  # cape
		_pt(torso, _cy(H * 0.12, H * 0.18, H * 0.06), _pm(Color(0.9, 0.9, 0.95)), Vector3(0, H * 0.3, 0.0))  # fur ruff
	# Head with snout, ears, horns.
	var head := _nd(torso, Vector3(0, H * 0.36, -H * 0.02), Vector3(0.35, 0, 0))
	_pt(head, _sph(H * 0.13), m, Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.92, 1.05))
	_pt(head, _cap(H * 0.07, H * 0.1), m, Vector3(0, -H * 0.03, -H * 0.13), Vector3(PI / 2, 0, 0))  # snout
	_pt(head, _cap(H * 0.05, H * 0.08), ml, Vector3(0, -H * 0.07, -H * 0.12), Vector3(PI / 2, 0, 0))  # jaw
	_pt(head, _sph(H * 0.03), _pm(Color(0.08, 0.06, 0.08), 0.0), Vector3(0, -H * 0.02, -H * 0.2))  # nose
	for side: float in [-1.0, 1.0]:
		_pt(head, _cy(0.0, H * 0.05, H * 0.18), m, Vector3(side * H * 0.14, H * 0.05, H * 0.01), Vector3(0, 0, side * -1.3))  # ear
		_pt(head, _cy(0.0, H * 0.03, H * 0.1), md, Vector3(side * H * 0.06, H * 0.12, H * 0.02), Vector3(-0.3, 0, side * -0.5))  # horn
		_pt(head, _cy(0.0, 0.012, H * 0.05), _pm(Color(1, 1, 0.9), 0.0), Vector3(side * H * 0.035, -H * 0.075, -H * 0.17), Vector3(PI, 0, 0))  # fang
		_pt(head, _bx(H * 0.07, H * 0.015, H * 0.02), md, Vector3(side * H * 0.055, H * 0.06, -H * 0.1), Vector3(0, 0, side * 0.5))  # brow
	_eye_pair(head, Vector3(H * 0.055, H * 0.02, -H * 0.1), H * 0.035, Color(1.0, 0.3, 0.15) if rank == 2 else Color(1.0, 0.8, 0.2), 1.0, true)
	if rank == 1:
		# Dented iron helmet with a nose guard.
		var hm := SphereMesh.new()
		hm.radius = H * 0.145
		hm.height = H * 0.145
		hm.is_hemisphere = true
		_pt(head, hm, metal, Vector3(0, H * 0.02, 0))
		_pt(head, _bx(H * 0.03, H * 0.12, 0.02), metal, Vector3(0, -H * 0.02, -H * 0.14))
		_pt(head, _cy(0.0, H * 0.02, H * 0.12), metal, Vector3(0, H * 0.2, 0))
	if rank == 2:
		# Crown: a ring with spikes.
		var ring := TorusMesh.new()
		ring.inner_radius = H * 0.11
		ring.outer_radius = H * 0.145
		_pt(head, ring, gold, Vector3(0, H * 0.1, 0))
		for i in 6:
			var a := TAU * i / 6.0
			_pt(head, _cy(0.0, H * 0.025, H * 0.1), gold, Vector3(cos(a) * H * 0.125, H * 0.16, sin(a) * H * 0.125))
	# Arms (pivots at the shoulders of the tilted torso).
	for side: float in [-1.0, 1.0]:
		var arm := _nd(torso, Vector3(side * H * 0.15, H * 0.25, 0), Vector3(-0.5, 0, side * -0.25))
		_pt(arm, _cap(H * 0.04, H * 0.16), m, Vector3(0, -H * 0.1, 0))
		_pt(arm, _cap(H * 0.035, H * 0.14), m, Vector3(0, -H * 0.24, 0))
		_pt(arm, _sph(H * 0.045), md, Vector3(0, -H * 0.32, 0))
		var hand := _nd(arm, Vector3(0, -H * 0.32, 0))
		if side < 0:
			# Round shield on the left arm.
			var sr := H * (0.12 if rank == 2 else 0.16)
			var sh := _cy(sr, sr, 0.03)
			_pt(hand, sh, wood if rank == 0 else metal, Vector3(-H * 0.04, 0, -H * 0.02), Vector3(0.0, 0.6, PI / 2))
			_pt(hand, _sph(H * 0.035), metal, Vector3(-H * 0.06, 0, -H * 0.035))
		else:
			if rank == 2:
				# Great axe.
				_pt(hand, _cy(0.018, 0.022, H * 0.9), wood, Vector3(0, H * 0.25, 0))
				_pt(hand, _cy(H * 0.2, H * 0.2, 0.035), metal, Vector3(0, H * 0.62, 0), Vector3(0, 0, PI / 2), Vector3(1, 1, 1))
				_pt(hand, _bx(0.05, H * 0.15, H * 0.1), md, Vector3(0, H * 0.62, 0))
				_pt(hand, _cy(0.0, 0.03, H * 0.15), metal, Vector3(0, H * 0.77, 0))
			else:
				# Spear.
				_pt(hand, _cy(0.012, 0.015, H * 1.1), wood, Vector3(0, H * 0.25, 0))
				_pt(hand, _cy(0.0, 0.03, H * 0.16), metal, Vector3(0, H * 0.86, 0))
				_pt(hand, _bx(0.06, 0.05, 0.015), _pm(Color(0.7, 0.15, 0.1)), Vector3(0, H * 0.76, 0))
		_limb(arm, PI if side < 0 else 0.0, -0.5, 0.4)
	# Legs.
	for side: float in [-1.0, 1.0]:
		var leg := _nd(_rig, Vector3(side * H * 0.09, hip_y, 0))
		_pt(leg, _cap(H * 0.05, H * 0.12), m, Vector3(0, -H * 0.08, 0))
		_pt(leg, _cap(H * 0.04, H * 0.12), m, Vector3(0, -H * 0.2, H * 0.02), Vector3(0.25, 0, 0))
		_pt(leg, _bx(H * 0.09, H * 0.04, H * 0.18), md, Vector3(0, -H * 0.28, -H * 0.04))
		for t in 3:
			_pt(leg, _cy(0.0, H * 0.015, H * 0.05), ml, Vector3((t - 1) * H * 0.03, -H * 0.28, -H * 0.14), Vector3(-PI / 2, 0, 0))
		_limb(leg, 0.0 if side < 0 else PI, 0.0, 0.7)
	# Tail.
	var tail := _nd(_rig, Vector3(0, hip_y, H * 0.08), Vector3(1.2, 0, 0))
	_pt(tail, _cap(H * 0.035, H * 0.3), m, Vector3(0, H * 0.15, 0))
	_pt(tail, _cy(0.0, H * 0.03, H * 0.1), md, Vector3(0, H * 0.33, 0))
	_limb(tail, PI / 2, 1.2, 0.2)


# -- Ruin Sentinel (stone golem) -----------------------------------------------

func _build_sentinel() -> void:
	var w := size.x
	var h := size.y
	_visual_height = h * 1.05
	var m := _pm(color, 0.025)
	var md := _pm(color.darkened(0.35), 0.025)
	var moss := _pm(Color(0.35, 0.5, 0.25), 0.0)
	var glow := _pm(Color(0.5, 0.95, 1.0), 0.0, Color(0.4, 0.9, 1.0), 2.5)
	var torso := _nd(_rig, Vector3(0, h * 0.55, 0))
	_breath = torso
	_pt(torso, _bx(w * 0.8, h * 0.3, w * 0.5), m, Vector3(0, h * 0.1, 0))
	_pt(torso, _bx(w * 0.45, h * 0.1, w * 0.36), md, Vector3(0, -h * 0.1, 0))
	_pt(torso, _bx(w * 0.22, h * 0.1, 0.02), glow, Vector3(0, h * 0.12, -w * 0.255))  # chest rune
	_pt(torso, _bx(w * 0.06, h * 0.18, 0.02), glow, Vector3(0, h * 0.1, -w * 0.255))
	_pt(torso, _sph(w * 0.14), moss, Vector3(w * 0.3, h * 0.22, -w * 0.1), Vector3.ZERO, Vector3(1, 0.4, 1))
	# Head: a brooding block with one glowing eye slit.
	_pt(torso, _bx(w * 0.34, h * 0.14, w * 0.34), m, Vector3(0, h * 0.33, -w * 0.02))
	_pt(torso, _bx(w * 0.4, h * 0.05, w * 0.4), md, Vector3(0, h * 0.4, -w * 0.02))  # brow slab
	_pt(torso, _bx(w * 0.22, h * 0.03, 0.02), glow, Vector3(0, h * 0.33, -w * 0.19))
	# Shoulders and arms.
	for side: float in [-1.0, 1.0]:
		_pt(torso, _bx(w * 0.32, h * 0.14, w * 0.42), m, Vector3(side * w * 0.52, h * 0.24, 0), Vector3(0, 0, side * 0.15))
		var arm := _nd(torso, Vector3(side * w * 0.55, h * 0.18, 0))
		_pt(arm, _bx(w * 0.22, h * 0.26, w * 0.22), md, Vector3(0, -h * 0.14, 0))
		_pt(arm, _bx(w * 0.3, h * 0.22, w * 0.3), m, Vector3(0, -h * 0.38, 0))
		_pt(arm, _bx(w * 0.12, h * 0.04, 0.02), glow, Vector3(0, -h * 0.38, -w * 0.155))
		_limb(arm, PI if side < 0 else 0.0, 0.0, 0.35)
	# Legs.
	for side: float in [-1.0, 1.0]:
		var leg := _nd(_rig, Vector3(side * w * 0.22, h * 0.35, 0))
		_pt(leg, _bx(w * 0.26, h * 0.2, w * 0.3), m, Vector3(0, -h * 0.1, 0))
		_pt(leg, _bx(w * 0.3, h * 0.12, w * 0.42), md, Vector3(0, -h * 0.29, -w * 0.05))
		_limb(leg, 0.0 if side < 0 else PI, 0.0, 0.5)
	# Floating rune ring.
	_orbit = _nd(_rig, Vector3(0, h * 0.62, 0))
	_orbit.set_meta("base_y", h * 0.62)
	var ring := TorusMesh.new()
	ring.inner_radius = w * 0.62
	ring.outer_radius = w * 0.66
	_pt(_orbit, ring, glow, Vector3.ZERO)
	for i in 4:
		var a := TAU * i / 4.0
		_pt(_orbit, _bx(0.08, 0.12, 0.08), md, Vector3(cos(a) * w * 0.64, 0, sin(a) * w * 0.64), Vector3(0.4, a, 0.3))


# ============================================================ Floor 2 =====
# Mirewood mobs. Same rig conventions: parts hang under "Mesh"/"Rig", limbs
# register with _limb for the run cycle, _breath and _orbit animate idle.

# -- Mire Toad (slow, tanky) ---------------------------------------------------

func _build_toad() -> void:
	var w := size.x
	var h := size.y
	var l := size.z
	_visual_height = h * 1.15
	var m := _pm(color)
	var md := _pm(color.darkened(0.4))
	var ml := _pm(color.lightened(0.35))
	var belly := _pm(Color(0.86, 0.82, 0.6))
	var wart := _pm(color.darkened(0.55), 0.0)
	var body := _nd(_rig, Vector3(0, h * 0.5, 0))
	_breath = body
	# Squat lump of a body, wider than tall, with a pale throat/belly.
	_pt(body, _sph(w * 0.5), m, Vector3(0, 0, 0), Vector3.ZERO, Vector3(1.0, 0.78, 1.15))
	_pt(body, _sph(w * 0.46), belly, Vector3(0, -h * 0.14, -l * 0.08), Vector3.ZERO, Vector3(0.92, 0.6, 1.05))
	_pt(body, _sph(w * 0.3), ml, Vector3(0, -h * 0.05, -l * 0.42), Vector3.ZERO, Vector3(1.0, 0.8, 0.8))  # throat sac
	# Mossy back: a ridge of warts and a few moss tufts. The warts sit on the
	# body ellipsoid (radii 0.5w, 0.39w, 0.575w) so they show from every side.
	for i in 9:
		var a := TAU * i / 9.0
		var rr := w * 0.32
		var wx := cos(a) * rr
		var wz := sin(a) * rr * 1.1
		var ys := w * 0.39 * sqrt(maxf(1.0 - pow(wx / (w * 0.5), 2.0) - pow(wz / (w * 0.575), 2.0), 0.0))
		_pt(body, _sph(w * 0.07), wart, Vector3(wx, maxf(h * 0.3, ys) + sin(a * 2.0) * 0.04, wz))
	_pt(body, _sph(w * 0.12), _pm(Color(0.38, 0.55, 0.22), 0.0), Vector3(w * 0.18, h * 0.36, l * 0.1), Vector3.ZERO, Vector3(1, 0.4, 1))
	_pt(body, _sph(w * 0.09), _pm(Color(0.45, 0.62, 0.25), 0.0), Vector3(-w * 0.2, h * 0.37, -l * 0.05), Vector3.ZERO, Vector3(1, 0.4, 1))
	# Wide mouth: a dark seam across the front, lower lip lighter.
	_pt(body, _bx(w * 0.7, h * 0.03, 0.03), _pm(Color(0.12, 0.1, 0.08), 0.0), Vector3(0, -h * 0.02, -l * 0.545), Vector3(0.15, 0, 0))
	_pt(body, _cap(w * 0.06, w * 0.6), ml, Vector3(0, -h * 0.08, -l * 0.52), Vector3(0, 0, PI / 2))
	# Bulging eyes on top of the head (centres just outside the body ellipsoid).
	var eyes := _nd(body, Vector3(0, h * 0.36, -l * 0.34))
	for side: float in [-1.0, 1.0]:
		_pt(eyes, _sph(w * 0.15), md, Vector3(side * w * 0.26, 0, 0))
	_eye_pair(eyes, Vector3(w * 0.26, h * 0.02, -w * 0.08), w * 0.11, Color(1.0, 0.8, 0.2), 0.9, true)
	# Legs: folded hind legs (big thighs) and short front legs, webbed feet.
	for sx: float in [-1.0, 1.0]:
		var hind := _nd(_rig, Vector3(sx * w * 0.42, h * 0.32, l * 0.3))
		_pt(hind, _sph(w * 0.22), m, Vector3(0, 0, 0), Vector3.ZERO, Vector3(0.8, 0.8, 1.2))
		_pt(hind, _cap(w * 0.09, h * 0.35), m, Vector3(sx * w * 0.08, -h * 0.12, -l * 0.08), Vector3(0.9, 0, sx * 0.3))
		_pt(hind, _bx(w * 0.26, h * 0.05, l * 0.22), md, Vector3(sx * w * 0.1, -h * 0.3, -l * 0.18))
		_limb(hind, 0.0 if sx > 0 else PI, 0.0, 0.5)
		var front := _nd(_rig, Vector3(sx * w * 0.3, h * 0.3, -l * 0.3))
		_pt(front, _cy(w * 0.07, w * 0.06, h * 0.3), m, Vector3(0, -h * 0.14, 0))
		_pt(front, _bx(w * 0.2, h * 0.05, l * 0.16), md, Vector3(0, -h * 0.29, -l * 0.04))
		_limb(front, PI if sx > 0 else 0.0, 0.0, 0.55)


# -- Thornback Stag (fast charger) ---------------------------------------------

func _build_stag() -> void:
	var w := size.x
	var h := size.y
	var l := size.z
	_visual_height = h * 1.45
	var m := _pm(color)
	var md := _pm(color.darkened(0.35))
	var ml := _pm(color.lightened(0.4))
	var horn := _pm(Color(0.3, 0.22, 0.16), 0.015)
	var tip := _pm(Color(0.85, 0.25, 0.2), 0.0, Color(0.9, 0.2, 0.1), 0.8)
	var hoof := _pm(Color(0.15, 0.12, 0.1), 0.0)
	var body := _nd(_rig, Vector3(0, h * 0.62, 0))
	_breath = body
	_pt(body, _cap(w * 0.26, l * 0.5), m, Vector3(0, 0, l * 0.05), Vector3(PI / 2, 0, 0))
	_pt(body, _sph(w * 0.3), m, Vector3(0, h * 0.02, -l * 0.22), Vector3.ZERO, Vector3(1, 1.1, 1))  # chest
	_pt(body, _sph(w * 0.27), m, Vector3(0, 0, l * 0.32), Vector3.ZERO, Vector3(1, 1, 1))  # haunch
	_pt(body, _cap(w * 0.2, l * 0.45), ml, Vector3(0, -h * 0.1, l * 0.02), Vector3(PI / 2, 0, 0))  # belly
	# Thorny spine: a row of dark barbs with red tips down the back.
	for i in 7:
		var z := -l * 0.2 + i * l * 0.09
		var hh := h * (0.16 if i % 2 == 0 else 0.11)
		_pt(body, _cy(0.0, w * 0.05, hh), horn, Vector3(0, w * 0.26 + hh * 0.4, z), Vector3(0.35, 0, 0))
		_pt(body, _sph(w * 0.025), tip, Vector3(0, w * 0.26 + hh * 0.85, z - hh * 0.3))
	# Neck up and forward, then the head.
	_pt(body, _cap(w * 0.14, l * 0.32), m, Vector3(0, h * 0.2, -l * 0.36), Vector3(-0.75, 0, 0))
	var head := _nd(body, Vector3(0, h * 0.42, -l * 0.5))
	_pt(head, _sph(w * 0.17), m, Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.95, 1.1))
	_pt(head, _cap(w * 0.1, l * 0.18), m, Vector3(0, -h * 0.05, -l * 0.14), Vector3(PI / 2 + 0.15, 0, 0))  # muzzle
	_pt(head, _sph(w * 0.05), _pm(Color(0.08, 0.06, 0.06), 0.0), Vector3(0, -h * 0.03, -l * 0.25))  # nose
	_pt(head, _cap(w * 0.07, l * 0.12), ml, Vector3(0, -h * 0.1, -l * 0.13), Vector3(PI / 2 + 0.15, 0, 0))  # jaw
	for side: float in [-1.0, 1.0]:
		_pt(head, _cy(0.0, w * 0.07, h * 0.18), m, Vector3(side * w * 0.15, h * 0.08, l * 0.02), Vector3(-0.3, 0, side * -0.9))  # ear
		_pt(head, _bx(w * 0.1, w * 0.025, w * 0.025), md, Vector3(side * w * 0.09, h * 0.06, -l * 0.1), Vector3(0, 0, side * 0.45))  # brow
		# Antlers: a main beam with three tines, thorn-red at the points.
		var ant := _nd(head, Vector3(side * w * 0.09, h * 0.12, 0.0), Vector3(-0.35, 0, side * -0.45))
		_pt(ant, _cy(w * 0.02, w * 0.035, h * 0.34), horn, Vector3(0, h * 0.17, 0))
		_pt(ant, _sph(w * 0.03), tip, Vector3(0, h * 0.35, 0))
		for t in 3:
			var ty := h * (0.1 + t * 0.09)
			var tn := _nd(ant, Vector3(0, ty, 0), Vector3(-0.2 + t * 0.15, 0, side * (0.9 - t * 0.2)))
			_pt(tn, _cy(0.0, w * 0.022, h * 0.16), horn, Vector3(0, h * 0.07, 0))
			_pt(tn, _sph(w * 0.022), tip, Vector3(0, h * 0.15, 0))
	_eye_pair(head, Vector3(w * 0.11, h * 0.02, -l * 0.12), w * 0.045, Color(1.0, 0.7, 0.2), 1.0)
	# Long legs: upper and lower segments with dark hooves.
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var leg := _nd(_rig, Vector3(sx * w * 0.18, h * 0.5, sz * l * 0.26))
			_pt(leg, _cy(w * 0.08, w * 0.06, h * 0.26), m, Vector3(0, -h * 0.13, 0))
			_pt(leg, _cy(w * 0.055, w * 0.045, h * 0.24), md, Vector3(0, -h * 0.37, 0))
			_pt(leg, _cy(w * 0.06, w * 0.065, h * 0.05), hoof, Vector3(0, -h * 0.5, 0))
			_limb(leg, 0.0 if sx * sz > 0 else PI, 0.0, 0.75)
	# Short tail with a pale underside.
	var tail := _nd(body, Vector3(0, h * 0.05, l * 0.46), Vector3(0.9, 0, 0))
	_pt(tail, _cap(w * 0.06, l * 0.14), m, Vector3(0, l * 0.07, 0))
	_pt(tail, _sph(w * 0.05), ml, Vector3(0, l * 0.13, 0.02))
	_limb(tail, PI / 2, 0.9, 0.3)


# -- Marsh Wisp (ranged bolt) --------------------------------------------------

func _build_wisp() -> void:
	var w := size.x
	var h := size.y
	_visual_height = h * 1.3
	var core_c := color
	var glow := _pm(core_c.lightened(0.5), 0.0, core_c, 3.0)
	var inner := _pm(Color(1, 1, 1), 0.0, Color(1, 1, 1), 2.5)
	var veil := _pm(core_c.darkened(0.45), 0.0, core_c, 0.5)
	var dark := _pm(Color(0.05, 0.08, 0.1), 0.0)
	var body := _nd(_rig, Vector3(0, h * 0.75, 0))
	_breath = body
	_pt(body, _sph(w * 0.36), glow, Vector3.ZERO)
	_pt(body, _sph(w * 0.2), inner, Vector3(0, w * 0.04, -w * 0.08))
	# Ragged veil of flame-shaped tendrils trailing below the core.
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		var r := w * 0.22
		var tn := _nd(body, Vector3(cos(a) * r, -w * 0.2, sin(a) * r), Vector3(PI + 0.25 * cos(a), 0, 0.25 * sin(a)))
		_pt(tn, _cy(0.0, w * 0.12, h * 0.45 + 0.1 * (i % 2)), veil, Vector3(0, h * 0.22, 0))
		_limb(tn, a, PI + 0.25 * cos(a), 0.35)
	# A sly little face: two dark slanted eyes and a faint grin.
	for side: float in [-1.0, 1.0]:
		_pt(body, _bx(w * 0.1, w * 0.03, 0.02), dark, Vector3(side * w * 0.12, w * 0.08, -w * 0.33), Vector3(0, 0, side * 0.5))
	_pt(body, _bx(w * 0.16, w * 0.02, 0.02), dark, Vector3(0, -w * 0.08, -w * 0.35))
	# Motes circling the core.
	_orbit = _nd(_rig, Vector3(0, h * 0.75, 0))
	_orbit.set_meta("base_y", h * 0.75)
	for i in 5:
		var a := TAU * i / 5.0
		_pt(_orbit, _sph(w * 0.06), inner, Vector3(cos(a) * w * 0.6, sin(a * 2.0) * w * 0.15, sin(a) * w * 0.6))
	if not WorldArt.headless():
		var l := OmniLight3D.new()
		l.light_color = core_c
		l.light_energy = 0.7
		l.omni_range = 5.0
		l.shadow_enabled = false
		l.position = Vector3(0, h * 0.75, 0)
		_rig.add_child(l)


# -- Mirelord, the Drowned Knight (Floor 2 Guardian) -----------------------------

func _build_drowned_knight() -> void:
	var w := size.x
	var h := size.y
	_visual_height = h * 1.1
	var plate := _pm(Color(0.33, 0.4, 0.44), 0.025)
	var plate_d := _pm(Color(0.2, 0.26, 0.3), 0.025)
	var rust := _pm(Color(0.46, 0.3, 0.22), 0.02)
	var weed := _pm(Color(0.16, 0.36, 0.24), 0.015)
	var weed_l := _pm(Color(0.25, 0.5, 0.3), 0.0)
	var glow := _pm(Color(0.55, 1.0, 0.9), 0.0, Color(0.35, 1.0, 0.85), 3.0)
	var bone := _pm(Color(0.85, 0.82, 0.7), 0.012)
	var coral := _pm(Color(0.8, 0.4, 0.45), 0.012)
	var hip_y := h * 0.42
	var torso := _nd(_rig, Vector3(0, hip_y, 0), Vector3(-0.1, 0, 0))
	_breath = torso
	# Layered cuirass: chest plate, belly plates, rusted belt.
	_pt(torso, _bx(w * 0.62, h * 0.26, w * 0.42), plate, Vector3(0, h * 0.17, 0))
	_pt(torso, _bx(w * 0.66, h * 0.08, w * 0.46), plate_d, Vector3(0, h * 0.3, 0))
	_pt(torso, _bx(w * 0.5, h * 0.1, w * 0.36), plate_d, Vector3(0, h * 0.04, 0))
	_pt(torso, _bx(w * 0.54, h * 0.05, w * 0.4), rust, Vector3(0, -h * 0.02, 0))
	_pt(torso, _bx(w * 0.14, h * 0.14, 0.03), glow, Vector3(0, h * 0.18, -w * 0.225))  # drowned sigil
	_pt(torso, _bx(w * 0.3, h * 0.04, 0.03), glow, Vector3(0, h * 0.18, -w * 0.225))
	# Seaweed drapes off the shoulders and belt, barnacle crust on one side.
	for i in 6:
		var x := -w * 0.3 + i * w * 0.12
		_pt(torso, _bx(w * 0.07, h * 0.3 + 0.05 * (i % 3), 0.03), weed if i % 2 == 0 else weed_l, Vector3(x, -h * 0.16, w * 0.2 + 0.02 * i), Vector3(0.12, 0, 0))
	_pt(torso, _sph(w * 0.12), coral, Vector3(w * 0.3, h * 0.24, -w * 0.16), Vector3.ZERO, Vector3(1, 0.5, 1))
	_pt(torso, _sph(w * 0.08), bone, Vector3(-w * 0.26, h * 0.1, -w * 0.2), Vector3.ZERO, Vector3(1, 0.5, 1))
	# Helm: a great helm with a glowing visor slit and a crown of coral spikes.
	var head := _nd(torso, Vector3(0, h * 0.42, 0), Vector3(0.1, 0, 0))
	_pt(head, _bx(w * 0.3, h * 0.17, w * 0.3), plate, Vector3(0, 0, 0))
	_pt(head, _bx(w * 0.34, h * 0.04, w * 0.34), plate_d, Vector3(0, h * 0.09, 0))
	_pt(head, _bx(w * 0.22, h * 0.025, 0.03), glow, Vector3(0, h * 0.01, -w * 0.16))  # visor glow
	_pt(head, _bx(w * 0.04, h * 0.1, 0.03), plate_d, Vector3(0, -h * 0.03, -w * 0.165))  # nasal bar
	for i in 5:
		var a := -PI * 0.4 + i * PI * 0.2
		_pt(head, _cy(0.0, w * 0.03, h * 0.12), coral, Vector3(sin(a) * w * 0.13, h * 0.16, -cos(a) * w * 0.1), Vector3(-0.3, 0, -a * 0.8))
	for side: float in [-1.0, 1.0]:
		_pt(head, _cy(0.0, w * 0.05, h * 0.2), bone, Vector3(side * w * 0.18, h * 0.1, 0), Vector3(0, 0, side * -0.8))  # horns
	# Pauldrons and arms: left bears a barnacled kite shield, right the drowned blade.
	for side: float in [-1.0, 1.0]:
		_pt(torso, _sph(w * 0.17), plate, Vector3(side * w * 0.4, h * 0.3, 0), Vector3.ZERO, Vector3(1, 0.75, 1))
		_pt(torso, _bx(w * 0.18, h * 0.04, w * 0.3), rust, Vector3(side * w * 0.42, h * 0.34, 0))
		var arm := _nd(torso, Vector3(side * w * 0.42, h * 0.24, 0), Vector3(-0.3, 0, side * -0.2))
		_pt(arm, _cap(w * 0.08, h * 0.2), plate_d, Vector3(0, -h * 0.11, 0))
		_pt(arm, _bx(w * 0.18, h * 0.16, w * 0.18), plate, Vector3(0, -h * 0.3, 0))  # gauntlet
		var hand := _nd(arm, Vector3(0, -h * 0.38, 0))
		if side < 0:
			_pt(hand, _bx(w * 0.05, h * 0.42, w * 0.3), plate, Vector3(-w * 0.1, 0, -w * 0.05))
			_pt(hand, _bx(w * 0.03, h * 0.3, w * 0.2), glow, Vector3(-w * 0.13, 0, -w * 0.05))
			for k in 4:
				_pt(hand, _sph(w * 0.035), bone, Vector3(-w * 0.14, h * (0.15 - k * 0.09), -w * (0.12 - k * 0.05)), Vector3.ZERO, Vector3(1, 0.6, 1))
		else:
			# A huge notched greatsword, blade weeping teal light.
			_pt(hand, _cy(0.025, 0.03, h * 0.22), rust, Vector3(0, h * 0.0, 0))
			_pt(hand, _bx(w * 0.26, h * 0.03, w * 0.06), plate_d, Vector3(0, h * 0.12, 0))
			_pt(hand, _bx(w * 0.09, h * 0.75, w * 0.03), plate, Vector3(0, h * 0.5, 0))
			_pt(hand, _bx(w * 0.025, h * 0.6, w * 0.035), glow, Vector3(0, h * 0.48, 0))
			_pt(hand, _cy(0.0, w * 0.045, h * 0.12), plate, Vector3(0, h * 0.93, 0))
		_limb(arm, PI if side < 0 else 0.0, -0.3, 0.3)
	# Legs: plate greaves and heavy sabatons.
	for side: float in [-1.0, 1.0]:
		var leg := _nd(_rig, Vector3(side * w * 0.17, hip_y, 0))
		_pt(leg, _bx(w * 0.2, h * 0.2, w * 0.22), plate_d, Vector3(0, -h * 0.1, 0))
		_pt(leg, _bx(w * 0.22, h * 0.16, w * 0.24), plate, Vector3(0, -h * 0.28, 0))
		_pt(leg, _bx(w * 0.24, h * 0.07, w * 0.34), rust, Vector3(0, -h * 0.39, -w * 0.05))
		_limb(leg, 0.0 if side < 0 else PI, 0.0, 0.45)
	# Tattered cape of kelp hanging from the pauldrons.
	_pt(torso, _bx(w * 0.6, h * 0.5, 0.03), weed, Vector3(0, h * 0.02, w * 0.24), Vector3(0.08, 0, 0))
	# Drowned ring: drifting bubbles and a rune circle around the waist.
	_orbit = _nd(_rig, Vector3(0, h * 0.5, 0))
	_orbit.set_meta("base_y", h * 0.5)
	var ring := TorusMesh.new()
	ring.inner_radius = w * 0.55
	ring.outer_radius = w * 0.58
	_pt(_orbit, ring, glow, Vector3.ZERO)
	for i in 6:
		var a := TAU * i / 6.0
		_pt(_orbit, _sph(w * 0.05 + 0.02 * (i % 2)), _pm(Color(0.8, 0.95, 1.0), 0.0, Color(0.6, 0.9, 1.0), 1.2), Vector3(cos(a) * w * 0.6, sin(a * 3.0) * 0.2, sin(a) * w * 0.6))


# ======================================================== creature models =====
# Rigged models from assets/CREATURES.md replace the primitive rigs above
# when the file is present. "Mesh" -> "Rig" -> <model> keeps "Mesh:scale"
# replication, the squash tweens, the flash (materials under "Mesh") and the
# dissolve (VFX lifts "Rig") exactly as for the primitives.

## Per rig kind: pack + name as AssetLib.creature() takes them, `tint`
## multiplied into every material ("" = the mob's data colour, normalised so
## it never darkens the texture), `fit` = model height as a multiple of the
## hitbox height (size.y), `yaw` = extra turn in degrees so the model faces -Z
## like the mob, `lift` = metres above the ground (flyers). A mob's data may
## carry a "model" dictionary with the same keys that overrides these.
## Floor 1 kinds only for now; Floor 2 mobs (toads, stags, wisps, Mirelord)
## keep their primitive rigs until that floor gets its own pass.
const MODELS := {
	"boar": {"pack": "animals", "name": "Pig", "tint": "7a4f36", "fit": 1.15},
	"wolf": {"pack": "animals", "name": "Wolf", "tint": "9a9aae", "fit": 1.25, "yaw": 90},
	"kobold": {"pack": "skeletons", "name": "Skeleton_Minion", "tint": "cfd0a4", "fit": 1.5},
	"sergeant": {"pack": "skeletons", "name": "Skeleton_Warrior", "tint": "d8bf92", "fit": 1.35},
	"sentinel": {"pack": "adventurers", "name": "Knight", "tint": "9aa4b0", "fit": 1.2},
	"king": {"pack": "creatures", "name": "Dragon", "tint": "b4a6bc", "fit": 1.35, "yaw": 0},
	"slime": {"pack": "creatures", "name": "Slime", "tint": "", "fit": 1.0},
	"rat": {"pack": "creatures", "name": "Rat", "tint": "", "fit": 1.0},
	"bat": {"pack": "creatures", "name": "Bat", "tint": "", "fit": 1.0, "lift": 1.2, "yaw": 0},
}

## Clip roles -> name fragments tried in order (AssetLib.play_clip matches by
## substring; KayKit rigs get a library with these exact role names).
const CLIP_ALIASES := {
	"idle": ["idle", "flying", "swim", "static"],
	"walk": ["walk", "run", "flying", "swim", "jump"],
	"attack": ["attack", "bite", "jump"],
	"hit": ["hit"],
	"death": ["death"],
}

## KayKit humanoids carry no clips; these come from the Rig_Medium files next
## to them (same rig, default import): role -> [file, candidate names, loop].
const KAYKIT_CLIPS := {
	"idle": ["Rig_Medium_General.glb", ["Idle_A", "Idle_B", "Idle"], true],
	"walk": ["Rig_Medium_MovementBasic.glb", ["Walking_A", "Walking_B", "Running_A", "Walking"], true],
	"attack": ["Rig_Medium_General.glb", ["Melee_1H_Attack_Chop", "Spellcast_Shoot", "Throw", "Interact", "Hit_B"], false],
	"hit": ["Rig_Medium_General.glb", ["Hit_A", "Hit"], false],
	"death": ["Rig_Medium_General.glb", ["Death_A", "Death"], false],
}
## The walkers are authored facing +Z; Godot mobs face -Z. The flyers (Bat,
## Dragon) and the Wolf differ, hence the yaw overrides in MODELS.
const PACK_YAW := {"animals": 180.0, "creatures": 180.0, "adventurers": 180.0, "skeletons": 180.0}
## How far (m) a mob keeps animating on Low/Medium; beyond it the clip freezes.
const ANIM_FREEZE_DIST := 40.0
## Mobs stop being drawn past this (times RenderProfile.prop_cull; Ultra = never).
const MOB_LOD_RANGE := 90.0

## MOBS_PRIMITIVE=1 in the environment forces the primitive rigs (before/after
## comparisons on the screenshot harness).
static var use_models: bool = OS.get_environment("MOBS_PRIMITIVE") == ""
static var _bounds_cache := {}     # pack/name -> AABB of the mesh vertices (rest pose, model space)
static var _creature_mats := {}    # source material id | tint -> template ShaderMaterial
static var _creature_shader: Shader
static var _kaykit_libs := {}      # pack dir + skeleton path -> AnimationLibrary


func _model_spec() -> Dictionary:
	var spec: Dictionary = MODELS.get(_rig_kind(), {}).duplicate()
	for k in model:
		spec[k] = model[k]
	return spec


## Multiplier for the model's materials: the spec tint, else the data colour
## scaled so its brightest channel is 0.92 (hue only; textures keep detail).
func _model_tint(spec: Dictionary) -> Color:
	var t := str(spec.get("tint", ""))
	if t != "" and Color.html_is_valid(t):
		return Color(t)
	var m := maxf(color.r, maxf(color.g, color.b))
	if m <= 0.001:
		return Color.WHITE
	return Color(color.r / m * 0.92, color.g / m * 0.92, color.b / m * 0.92, 1.0)


func _build_model(spec: Dictionary) -> bool:
	var pack := str(spec["pack"])
	var mname := str(spec["name"])
	var rig := Node3D.new()
	rig.name = "Rig"
	var res := AssetLib.creature(rig, pack, mname, Vector3.ZERO, 0.0, float(spec.get("scale", 1.0)), false)
	var inst: Node3D = res[0]
	if inst == null:
		rig.free()
		return false
	_rig = rig
	_mesh.add_child(_rig)
	_anim = res[1]
	# The FBX scenes carry empty helper MeshInstance3Ds (mesh == null); they
	# draw nothing and only cost node and renderer bookkeeping.
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null and mi.get_child_count() == 0:
			mi.get_parent().remove_child(mi)
			mi.free()
	if _anim == null and pack in ["adventurers", "skeletons"]:
		_anim = _kaykit_player(inst, AssetLib.PACKS[pack])
	# Fit: height = fit * hitbox height, feet on the ground, centred, facing -Z.
	var box := _model_bounds(inst, pack, mname)
	var want := size.y * float(spec.get("fit", 1.0))
	if box.size.y > 0.01 and want > 0.0:
		inst.scale *= want / (box.size.y * inst.scale.y)
	inst.rotation.y = deg_to_rad(float(spec.get("yaw", PACK_YAW.get(pack, 0.0))))
	var c := box.get_center()
	inst.position = -(inst.transform.basis * Vector3(c.x, box.position.y, c.z)) + Vector3(0, float(spec.get("lift", 0.0)), 0)
	_visual_height = want + float(spec.get("lift", 0.0))
	# Cel materials (own copies, so the flash never leaks to another mob) and
	# distance culling through the prop preset hooks.
	var tint := _model_tint(spec)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src: Material = mi.get_active_material(s)
			mi.set_surface_override_material(s, _creature_material(src, tint).duplicate())
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		RenderProfile.register_lod(mi, MOB_LOD_RANGE)
	_set_anim("idle")
	return true


## Vertex AABB of a model in its root's space, in the rest pose. Skinned
## meshes are taken through their bind poses and the skeleton's rest (the FBX
## importer leaves unit conversions in the binds, so the raw mesh space is
## not what gets drawn). Cached per model.
func _model_bounds(inst: Node3D, pack: String, mname: String) -> AABB:
	var key := pack + "/" + mname
	if _bounds_cache.has(key):
		return _bounds_cache[key]
	var box := AABB()
	var first := true
	var inv := inst.global_transform.affine_inverse() if inst.is_inside_tree() else Transform3D.IDENTITY
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf: Transform3D = inv * mi.global_transform if inst.is_inside_tree() else AssetLib._relative_xf(inst, mi)
		# Bind matrices (root space) for a skinned part.
		var binds: Array = []
		var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		if mi.skin != null and sk != null:
			var sk_xf: Transform3D = inv * sk.global_transform if inst.is_inside_tree() else AssetLib._relative_xf(inst, sk)
			var skin: Skin = mi.skin
			for b in skin.get_bind_count():
				var bi := skin.get_bind_bone(b)
				if bi < 0:
					bi = sk.find_bone(skin.get_bind_name(b))
				var rest := sk.get_bone_global_rest(bi) if bi >= 0 else Transform3D.IDENTITY
				binds.append(sk_xf * rest * skin.get_bind_pose(b))
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			var per := 0
			if not binds.is_empty() and bones != null and weights != null and verts.size() > 0:
				per = int(bones.size() / verts.size())
			for i in verts.size():
				var pnt: Vector3
				if per > 0:
					pnt = Vector3.ZERO
					var total := 0.0
					for k in per:
						var w := float(weights[i * per + k])
						var bi := int(bones[i * per + k])
						if w <= 0.0 or bi < 0 or bi >= binds.size():
							continue
						pnt += (binds[bi] as Transform3D) * verts[i] * w
						total += w
					if total <= 0.0001:
						pnt = xf * verts[i]
					else:
						pnt /= total
				else:
					pnt = xf * verts[i]
				if first:
					box = AABB(pnt, Vector3.ZERO)
					first = false
				else:
					box = box.expand(pnt)
	_bounds_cache[key] = box
	return box


## Cel version of an imported material (toon_creature.gdshader), tinted.
## Templates are shared per source material + tint; callers duplicate.
static func _creature_material(src: Material, tint: Color) -> ShaderMaterial:
	var key := "%d|%s" % [src.get_instance_id() if src else 0, tint.to_html(false)]
	if _creature_mats.has(key):
		return _creature_mats[key]
	if _creature_shader == null:
		_creature_shader = load("res://shaders/toon_creature.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _creature_shader
	var base := Color.WHITE
	if src is BaseMaterial3D:
		var b: BaseMaterial3D = src
		base = b.albedo_color
		if b.albedo_texture != null:
			m.set_shader_parameter("albedo_tex", b.albedo_texture)
		m.set_shader_parameter("use_vertex_color", b.vertex_color_use_as_albedo)
		if b.emission_enabled:
			m.set_shader_parameter("emission_color", b.emission)
			m.set_shader_parameter("emission_strength", b.emission_energy_multiplier)
	elif src is ShaderMaterial:
		var a = src.get_shader_parameter("albedo")
		if a is Color:
			base = a
	m.set_shader_parameter("albedo", Color(base.r * tint.r, base.g * tint.g, base.b * tint.b, 1.0))
	_creature_mats[key] = m
	return m


## AnimationPlayer for a KayKit humanoid, fed from the Rig_Medium clip files
## of its pack with the track paths pointed at this model's skeleton.
func _kaykit_player(inst: Node3D, pack_dir: String) -> AnimationPlayer:
	var skels := inst.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return null
	var rel := str(inst.get_path_to(skels[0]))
	var key := pack_dir + "|" + rel
	if not _kaykit_libs.has(key):
		var lib := AnimationLibrary.new()
		for role in KAYKIT_CLIPS:
			var spec: Array = KAYKIT_CLIPS[role]
			var path: String = pack_dir + "animations/" + spec[0]
			if not ResourceLoader.exists(path):
				continue
			var ps = load(path)
			if not (ps is PackedScene):
				continue
			var src_root: Node = ps.instantiate()
			var aps := src_root.find_children("*", "AnimationPlayer", true, false)
			if aps.is_empty():
				src_root.free()
				continue
			var ap: AnimationPlayer = aps[0]
			for cand in spec[1]:
				if not ap.has_animation(cand):
					continue
				var anim: Animation = ap.get_animation(cand).duplicate()
				for t in range(anim.get_track_count() - 1, -1, -1):
					var bone := anim.track_get_path(t).get_concatenated_subnames()
					if bone == "":
						anim.remove_track(t)
					else:
						anim.track_set_path(t, NodePath(rel + ":" + bone))
				anim.loop_mode = Animation.LOOP_LINEAR if spec[2] else Animation.LOOP_NONE
				lib.add_animation(role, anim)
				break
			src_root.free()
		_kaykit_libs[key] = lib
	var player := AnimationPlayer.new()
	player.name = "Clips"
	inst.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("", _kaykit_libs[key])
	return player


## Plays the clip for a role (first alias found). Returns its length, 0 if
## the model has none. A looping role already playing is left alone.
func _set_anim(state: String, loop := true) -> float:
	if _anim == null:
		return 0.0
	if loop and state == _anim_state and _anim.is_playing():
		return _anim.current_animation_length
	for needle in CLIP_ALIASES.get(state, [state]):
		if AssetLib.play_clip(_anim, needle, loop):
			_anim_state = state
			return _anim.current_animation_length
	return 0.0


## Per-frame clip choice for rigged models: walk while moving, idle when
## still, one-shots (attack/hit/death) hold the body until they are done.
## On Low/Medium the clip freezes beyond ANIM_FREEZE_DIST from the camera.
func _process_model() -> void:
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and RenderProfile.current in ["Low", "Medium"] \
			and cam.global_position.distance_squared_to(global_position) > ANIM_FREEZE_DIST * ANIM_FREEZE_DIST
	if far != _anim_frozen:
		_anim_frozen = far
		_anim.active = not far
	if far or _dead:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _attack_until:
		return
	if _run_blend > 0.25:
		_set_anim("walk")
		_anim.speed_scale = 0.8 + 0.7 * _run_blend
	else:
		_set_anim("idle")
		_anim.speed_scale = 1.0
