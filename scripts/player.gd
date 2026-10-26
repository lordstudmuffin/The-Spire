class_name Player
extends CharacterBody3D
## Third-person controller: WASD relative to camera, mouse look, sprint,
## jump, dash, a melee swing and Sword Arts.
## Online, each player node is owned by its peer: only the owner reads input
## and has a camera; position and look are replicated to everyone else.

signal interact_pressed

const JUMP_VELOCITY := 6.0
const DASH_SPEED := 18.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 0.8
## A dash is invulnerable to mob, boss and duel strikes for this long from
## its start (the server stamps its own copy in net_dash, rate-limited by
## DASH_COOLDOWN, and a strike already in flight waits for it: srv_strike).
const DASH_IFRAMES := 0.22
const ATTACK_RANGE := 2.2
## Light attack cadence: the gap between two light swings of the combo, and
## the server's per-kind cooldown for kind -1 (net_hit refuses < 90% of it).
const ATTACK_COOLDOWN := 0.36
## Basic attack combo: light, light, finisher. Each press advances the chain
## if it comes within COMBO_CHAIN of the last swing; otherwise it restarts.
## "kind" is what the server sees (-1 light, KIND_FINISHER the heavy third
## blow); "anim" picks the VRM clip (0 slice, 2 diagonal, 1 overhead chop);
## "gap" is how long until the next swing may start; "delay" is when the blade
## connects after the press (matched to the clip's contact frame); "knock" is
## the shove the mob takes (Enemy.take_hit reads the kind).
const KIND_FINISHER := -2
const COMBO := [
	{"kind": -1, "anim": 0, "mult": 1.0, "range": 2.2, "arc": 1.3, "gap": 0.36, "delay": 0.07},
	{"kind": -1, "anim": 2, "mult": 1.0, "range": 2.2, "arc": 1.3, "gap": 0.36, "delay": 0.07},
	{"kind": -2, "anim": 1, "mult": 1.5, "range": 2.5, "arc": 1.7, "gap": 0.62, "delay": 0.12},
]
const COMBO_CHAIN := 0.9
## Recovery after the finisher before a new chain (server: light swings are
## refused this soon after a finisher), and the finisher's own cooldown
## (one full chain: two light gaps plus this recovery).
const FINISHER_RECOVERY := 0.62
const FINISHER_COOLDOWN := 0.36 + 0.36 + 0.62
## An attack pressed this long before the swing is allowed fires as soon as
## it is (input buffer), so mashing in rhythm never eats a press.
const ATTACK_BUFFER := 0.16
## Light magnetism: a swing snaps to face the nearest foe within this range in
## a forward cone and steps in if it is just out of reach.
const MAGNET_RANGE := 3.8
const MAGNET_CONE := 0.35   # cos of the half-angle (~70 degrees)
const MAGNET_STEP := 7.0    # m/s for MAGNET_STEP_TIME
const MAGNET_STEP_TIME := 0.09
const MOUSE_SENS := 0.003
## Right-stick orbit speed at full deflection, radians per second (x stick_sens).
const STICK_SENS := 2.4
## Lock-on assist ("target"): the camera swings to the nearest mob this close.
const TARGET_RANGE := 16.0

## Sword Arts: preset moves with a cooldown and a short recovery ("post-motion").
## Damage is a multiplier of normal attack damage; arc is the hit cone in radians.
const SKILLS := [
	# "prof": One-Handed Sword proficiency needed (GameState.sword_prof).
	{"name": "Sweeping Edge", "mult": 1.6, "range": 2.6, "arc": PI, "cooldown": 4.0, "recovery": 0.5, "lunge": 0.0, "prof": 0},
	{"name": "Twin Crescent", "mult": 2.6, "range": 2.4, "arc": 0.9, "cooldown": 8.0, "recovery": 0.8, "lunge": 0.0, "prof": 40},
	{"name": "Falcon Rush", "mult": 2.0, "range": 2.4, "arc": 1.2, "cooldown": 10.0, "recovery": 0.6, "lunge": 14.0, "prof": 120},
]

signal skill_used(index: int, cooldown: float)

## EXP the last death cost (shown after the respawn).
var last_xp_lost := 0
## Display name of the last monster that hit this player (Enemy._damage_player);
## a permadeath fall records it as the cause.
var last_attacker := ""
## Server: a permadeath body whose owner disconnected mid-fight (Net.srv_lingering).
var lingering := false
## Off in the smoke test: a fall stays in the world instead of leaving for the title.
static var menu_after_fall := true
## Peer that owns this player (1 offline or for the host).
var peer_id := 1
## Replicated look so other players see your character.
var appearance := {}
var display_name := ""
var is_local := true
## Level and attack used for damage. Offline/host: mirrors GameState. On the
## server for a remote player: the server's own record (Net.srv_records),
## never the client's claim.
var level := 1
var srv_attack := 17.0
## Server-side movement sanity for remote players: token buckets for
## horizontal distance and vertical rise, the last accepted position, and a
## violation log that gets the peer kicked when it fills (see
## _server_movement_check). Legal teleports are Net.SAFE_DESTINATIONS.
const SRV_MAX_SPEED := 26.0       # dash 18, lunge 14, sprint ~15 m/s + slack
const SRV_BUDGET_CAP := 13.0      # ~0.5 s of max speed absorbs bursty syncs
const SRV_RISE_SPEED := 9.0       # jump launches at 6 m/s
const SRV_RISE_CAP := 5.0
const SRV_VIOLATION_WINDOW_MS := 10000
const SRV_MAX_VIOLATIONS := 6
const SRV_GRACE_MS := 400         # one violation per correction round-trip
var _srv_last_pos := Vector3.ZERO
var _srv_pos_init := false
var _srv_budget := SRV_BUDGET_CAP
var _srv_rise := SRV_RISE_CAP
var _srv_violations: Array = []
var _srv_grace_until := 0
var _srv_claimed_level := 0
var _last_report_ms := 0
var _report_queued := false
var _swing_serial := 0

var skill_cd := [0.0, 0.0, 0.0]
## Cooldowns of the held unique skill's Sword Arts (keys 4-6).
var unique_cd := [0.0, 0.0, 0.0]
## Cooldowns of the hidden class's arts (HiddenClasses.arts_of; keys R / C,
## pad LT+X / LT+B).
var class_cd := [0.0, 0.0]
## When this player's last parry was judged (this machine's clock: the
## server's for a remote player, so Still Water's "right after a parry" rule
## is checked against server time in Enemy.net_hit).
var last_parry_ms := -100000
var _recovery := 0.0

# --- Parry and guard ------------------------------------------------------
## Tap Parry as a mob's strike is about to land: the blow is deflected, the
## mob staggers (posture break) and the next hits on it land as ripostes.
## Holding Parry after the window guards: blocked hits do a fraction of
## their damage and wear the guard bar down; an empty bar is a guard break
## (stunned). A whiffed parry (no strike landed in the window) puts parry
## on a short cooldown so it can't be mashed. Judged where the mob's strike
## resolves (the server online, using the times it received our presses).
##
## Timing (all judged on the server for remote players):
## - PARRY_WINDOW: a strike that lands within this long after the press is
##   parried; within PERFECT_WINDOW it is a PERFECT parry (double posture,
##   longer stagger, guard refund, no blade wear).
## - A press made up to PARRY_BUFFER before the whiff cooldown ends opens
##   its window the moment the cooldown does (buffered input).
## - Online the press travels to the server after the player saw the blow
##   coming, so a strike that finds no parry on a remote player waits up to
##   one round trip + LATE_GRACE_PAD_MS (clamped LATE_GRACE_MIN/MAX_MS) for a
##   press or dash already in flight (srv_strike). The early side gets no
##   extra allowance, so the total window never grows past PARRY_WINDOW +
##   the measured round trip, capped at LATE_GRACE_MAX_MS.
const PARRY_WINDOW := 0.25
const PERFECT_WINDOW := 0.09
const PARRY_BUFFER := 0.1
const PARRY_WHIFF_CD := 0.6
const LATE_GRACE_PAD_MS := 40
const LATE_GRACE_MIN_MS := 60
const LATE_GRACE_MAX_MS := 260
const PERFECT_GUARD := 25.0      # guard refunded by a perfect parry
const BLOCK_REDUCTION := 0.7     # blocked hits do 30% damage
const GUARD_MAX := 100.0
const GUARD_PER_BLOCK := 34.0    # three blocked hits break guard
const GUARD_REGEN := 30.0        # per second while not blocking
const GUARD_BREAK_STUN := 1.3
var guard := GUARD_MAX
var blocking := false
var _parry_open_ms := -100000   # when the current parry window opened (this machine's clock)
var _parry_ready_ms := 0
var _parry_buffer_at := 0       # a buffered press opens its window at this time
var _parry_used := true         # local: the open window parried (else it whiffs)
var _stun := 0.0
var parries := 0                # successful parries (stats / tests)
var perfect_parries := 0        # of which perfect
var whiffs := 0                 # local whiffed windows (stats / tests)
## Was the last parry judged by defend() a perfect one (callers read it).
var last_parry_perfect := false
## Dash invulnerability on this machine's clock (server: stamped by net_dash).
var _iframe_until := 0
var _dash_srv_ms := -100000
## Server, remote player: strikes waiting for an in-flight parry/dash press,
## [{"at": ms, "from": Vector3, "cb": Callable, "parryable": bool}].
var _pending_strikes: Array = []
## Tests: let srv_strike hold strikes for this node as if it were remote.
var defer_test := false
# Basic attack combo state (owner only).
var _combo_step := 0
var _combo_t := 99.0
var _attack_buf := 0.0
var _magnet_t := 0.0
var _magnet_dir := Vector3.ZERO
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Either a VRMCharacter (real anime model) or the built-in CharacterModel.
var model: Node3D
var _vrm: VRMCharacter
var cam_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var _dash_timer := 0.0
var _dash_cd := 0.0
var _attack_cd := 0.0
var _swing_t := 0.0
var _weapon: MeshInstance3D
var _blade_mat: StandardMaterial3D
var _name_label: Label3D
## "PARTY" tag above members of the local player's party (Net.party_ids).
var _party_tag: Label3D
var _party_check_t := 0.0
var _applied_appearance := {}
var input_enabled := true
## Test hook (--bot): hunt mobs instead of reading input. --cheat makes the
## bot teleport, run at 10x speed and claim level 99, to exercise the server.
var bot := false
var cheat := false
## Duel opponent a bot fights instead of mobs (scripts/duels.gd sets it).
var bot_duel_target: Node3D = null
var _bot_t := 0.0
## Bot defence against a telegraphed strike: press / release times (ms, 0 = none).
var _bot_parry_at := 0
var _bot_release_at := 0
var _bot_target: Node3D
var _bot_last_pos := Vector3.ZERO
var _bot_stuck := 0
var _bot_avoid := {}  # enemy instance id -> ms until we may chase it again
var _bot_strafe := Vector3.ZERO
var _bot_strafe_t := 0.0
## Town wall (world.gd: centre (0,0,15), radius 36) and its north/south/east
## gates, so a walking bot leaves town through a gate instead of a wall.
const BOT_WALL_CENTER := Vector3(0, 0, 15)
const BOT_WALL_RADIUS := 36.0
const BOT_GATES: Array[Vector3] = [Vector3(0, 0, -21), Vector3(0, 0, 51), Vector3(36, 0, 12)]
## Footstep bookkeeping: metres until the next step, last grounded state.
var _step_dist := 0.0
var _was_grounded := true
## Cosmetic state (see scripts/vfx.gd): camera shake amplitude, swing combo
## side, last cosmetic swing time (rate limit for net_swing).
var _shake := 0.0
var _swing_flip := false
var _last_swing_fx_ms := 0


func _enter_tree() -> void:
	# Normally the spawner calls build() first; this covers direct instancing.
	if model == null:
		build()


## Creates the replicated children. Must run BEFORE the node enters the tree
## so the synchronizer carries the owner's authority from its first frame.
func build() -> void:
	if Net.online:
		set_multiplayer_authority(peer_id)
	_build()
	if Net.online:
		set_multiplayer_authority(peer_id, true)


func _ready() -> void:
	is_local = not Net.online or peer_id == multiplayer.get_unique_id()
	add_to_group("players")
	if is_local:
		add_to_group("player")
		cheat = "--cheat" in OS.get_cmdline_user_args()
		if Net.online and not multiplayer.is_server():
			_report_stats()
			GameState.leveled_up.connect(func(_l): _report_stats())
			GameState.stats_changed.connect(_report_stats)
			GameState.inventory_changed.connect(_report_stats)
		if appearance.is_empty():
			appearance = GameState.character.duplicate()
			model.apply(appearance)
		display_name = GameState.character["name"]
		cam_pivot = Node3D.new()
		cam_pivot.position.y = 1.5
		add_child(cam_pivot)
		cam_pivot.top_level = true
		spring = SpringArm3D.new()
		spring.spring_length = 4.5
		spring.rotation.x = -0.35
		spring.add_excluded_object(get_rid())
		cam_pivot.add_child(spring)
		camera = Camera3D.new()
		camera.fov = float(Settings.data["fov"])
		Settings.changed.connect(func(): camera.fov = float(Settings.data["fov"]))
		# The world's Environment exists now; apply the graphics preset to it.
		Settings.apply_graphics.call_deferred()
		spring.add_child(camera)
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_name_label.visible = not is_local


func _build() -> void:
	# Layer 2 = players. Players collide with the world (1) and mobs (4) but
	# never with each other, so a crowd can't shove or launch anyone.
	collision_layer = 2
	collision_mask = 1 | 4
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)

	# A dedicated/headless server never renders, so it skips the ~10 MB VRM
	# scenes and uses the cheap primitive model for collision/facing only.
	var headless := Net.dedicated or DisplayServer.get_name() == "headless"
	if not headless and VRMCharacter.BODIES.has(str(appearance.get("body", ""))):
		_vrm = VRMCharacter.new()
		model = _vrm
	else:
		model = CharacterModel.new()
	model.name = "Model"
	add_child(model)
	model.apply(appearance)
	_applied_appearance = appearance.duplicate()

	_build_sword()

	_name_label = Label3D.new()
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.position.y = 2.3
	_name_label.font_size = 40
	_name_label.outline_size = 8
	_name_label.modulate = Color(0.75, 0.9, 1.0)
	add_child(_name_label)
	_party_tag = Label3D.new()
	_party_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_party_tag.position.y = 2.62
	_party_tag.text = "PARTY"
	_party_tag.font_size = 22
	_party_tag.outline_size = 6
	_party_tag.modulate = Color(0.48, 0.86, 0.54)
	_party_tag.visible = false
	add_child(_party_tag)

	if Net.online:
		var sync := MultiplayerSynchronizer.new()
		sync.name = "Sync"
		var cfg := SceneReplicationConfig.new()
		# Only movement is client-owned. Looks and name come from the server's
		# sanitized spawn data; level/attack go through net_report_stats.
		for prop in [".:position", ".:velocity", "Model:rotation"]:
			cfg.add_property(NodePath(prop))
		sync.replication_config = cfg
		add_child(sync)


## Longsword held in the right hand: blade with a fuller, crossguard, wrapped
## grip and pommel. `_weapon` is the grip-rooted MeshInstance3D the swing code
## rotates; the blade keeps a StandardMaterial3D (`_blade_mat`) for the flash.
func _build_sword() -> void:
	var hand: Node3D
	if _vrm != null:
		# Hang the sword off the humanoid right hand bone.
		var att := BoneAttachment3D.new()
		att.name = "SwordAttach"
		att.bone_name = "RightHand"
		_vrm.skeleton.add_child(att)
		var grip_pivot := Node3D.new()
		# VRM hands point fingers along +X-ish in bind pose; aim the blade
		# forward out of the fist and tilt it like a held sword.
		grip_pivot.rotation_degrees = Vector3(0, -90, -20)
		att.add_child(grip_pivot)
		hand = grip_pivot
	else:
		hand = model.hand_r()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.86, 0.9, 0.98)
	steel.metallic = 0.85
	steel.roughness = 0.25
	steel.next_pass = ToonMaterial.outline(0.012)
	_blade_mat = steel
	var leather := ToonMaterial.part(Color(0.3, 0.18, 0.1), 0.012)
	var gold := ToonMaterial.part(Color(0.85, 0.68, 0.25), 0.012)
	var dark_steel := ToonMaterial.part(Color(0.45, 0.5, 0.6), 0.0)

	# Root = grip (so the swing pivots around the hand), blade points -Z.
	var grip := CylinderMesh.new()
	grip.top_radius = 0.02
	grip.bottom_radius = 0.022
	grip.height = 0.2
	grip.radial_segments = 12
	grip.material = leather
	_weapon = MeshInstance3D.new()
	_weapon.name = "Sword"
	_weapon.mesh = grip
	_weapon.rotation.x = PI / 2  # cylinder axis -> Z
	# Re-parent trick: the grip mesh is rotated, so put the rest under a
	# child that undoes the rotation and keeps blade-space simple.
	var sw := Node3D.new()
	sw.rotation.x = -PI / 2
	_weapon.add_child(sw)
	hand.add_child(_weapon)
	_weapon.position = Vector3(0, -0.01, 0.0)

	var add := func(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = pos
		mi.rotation = rot
		mi.scale = scl
		sw.add_child(mi)
		return mi
	# Grip wraps.
	for i in 3:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.019
		ring.outer_radius = 0.027
		add.call(ring, gold if i == 1 else leather, Vector3(0, 0, -0.06 + i * 0.05), Vector3(PI / 2, 0, 0))
	# Pommel.
	add.call(_sphere(0.032), gold, Vector3(0, 0, 0.12), Vector3.ZERO, Vector3(1, 1, 1.2))
	# Crossguard with knobs.
	add.call(_box(0.24, 0.028, 0.045), gold, Vector3(0, 0, -0.115))
	for side: float in [-1.0, 1.0]:
		add.call(_sphere(0.024), gold, Vector3(side * 0.125, 0, -0.115))
	# Blade + fuller + tip.
	var blade := BoxMesh.new()
	blade.size = Vector3(0.065, 0.012, 0.74)
	blade.material = steel
	add.call(blade, steel, Vector3(0, 0, -0.5))
	add.call(_box(0.014, 0.015, 0.6), dark_steel, Vector3(0, 0, -0.46))
	var tip := PrismMesh.new()
	tip.size = Vector3(0.065, 0.14, 0.012)
	add.call(tip, steel, Vector3(0, 0, -0.94), Vector3(-PI / 2, 0, 0))


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m


func _box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or not input_enabled or _dying:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var inv := -1.0 if Settings.data.get("invert_y", false) else 1.0
		cam_pivot.rotation.y -= event.relative.x * MOUSE_SENS * Settings.data["mouse_sens"]
		spring.rotation.x = clamp(spring.rotation.x - event.relative.y * inv * MOUSE_SENS * Settings.data["mouse_sens"], -1.2, 0.4)
	elif event.is_action_pressed("quick_heal") or (event.is_action_pressed("interact") and event is InputEventJoypadButton and Input.is_action_pressed("target")):
		quick_heal()
	elif event.is_action_pressed("interact"):
		interact_pressed.emit()
	elif event.is_action_pressed("target"):
		snap_to_target()


## Right stick: orbit the camera. Deadzone comes from the actions
## (Settings "stick_deadzone"); a squared response curve keeps small
## deflections precise while a full push turns at STICK_SENS * stick_sens.
func _stick_look(delta: float) -> void:
	var look := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if look == Vector2.ZERO:
		return
	look *= look.length()
	var rate: float = STICK_SENS * float(Settings.data["stick_sens"]) * delta
	var inv := -1.0 if Settings.data.get("invert_y", false) else 1.0
	cam_pivot.rotation.y -= look.x * rate
	spring.rotation.x = clamp(spring.rotation.x - look.y * inv * rate, -1.2, 0.4)


## Swing the camera (and the character) to face the nearest living mob.
func snap_to_target() -> bool:
	var best: Node3D = null
	var best_d := TARGET_RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D) or ("hp" in e and float(e.hp) <= 0.0):
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return false
	var to: Vector3 = best.global_position - global_position
	var yaw := atan2(-to.x, -to.z)
	var target_yaw: float = cam_pivot.rotation.y + angle_difference(cam_pivot.rotation.y, yaw)
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(cam_pivot, "rotation:y", target_yaw, 0.22)
	model.rotation.y = yaw
	Audio.play("ui_tick")
	return true


func _physics_process(delta: float) -> void:
	var grounded := is_on_floor() if is_local else absf(velocity.y) < 1.0
	if _vrm != null:
		_vrm.animate(delta, Vector2(velocity.x, velocity.z).length(), grounded)
	else:
		model.animate(delta, Vector2(velocity.x, velocity.z).length(), grounded, _swing_t / ATTACK_COOLDOWN if _swing_t > 0.0 else 0.0)
	_footsteps(delta, grounded)
	if not is_local:
		# Remote player: position arrives from the network; only refresh looks.
		if appearance != _applied_appearance:
			model.apply(appearance)
			_applied_appearance = appearance.duplicate()
		var shown_name: String = Net.guild_label(display_name)  # "Name  [TAG]" for guild members (P8)
		if _name_label.text != shown_name:
			_name_label.text = shown_name
		_party_check_t -= delta
		if _party_check_t <= 0.0:
			_party_check_t = 0.5
			var in_party: bool = Net.party_ids.has(peer_id)
			_party_tag.visible = in_party
			_name_label.modulate = Color(0.6, 0.95, 0.65) if in_party else Color(0.75, 0.9, 1.0)
		if multiplayer.is_server():
			_server_movement_check(delta)
			# Guard and stun of remote players are judged here (defend()).
			if _stun > 0.0:
				_stun = maxf(_stun - delta, 0.0)
			elif not blocking:
				guard = minf(guard + _guard_regen() * delta, GUARD_MAX)
			_tick_parry_buffer()
			_flush_pending(false)
		return
	level = GameState.level
	srv_attack = GameState.attack_damage()

	cam_pivot.global_position = global_position + Vector3(0, 1.5, 0)
	if input_enabled and not _dying and not bot:
		_stick_look(delta)
	_dash_cd = max(_dash_cd - delta, 0.0)
	_attack_cd = max(_attack_cd - delta, 0.0)
	_recovery = max(_recovery - delta, 0.0)
	for i in skill_cd.size():
		skill_cd[i] = max(skill_cd[i] - delta, 0.0)
	for i in unique_cd.size():
		unique_cd[i] = max(unique_cd[i] - delta, 0.0)
	for i in class_cd.size():
		class_cd[i] = max(class_cd[i] - delta, 0.0)

	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir := Vector2.ZERO
	if bot:
		_bot_defend_tick()
		input_dir = _bot_think(delta)
	elif input_enabled and not _dying and _recovery == 0.0:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Stick deflection = walk..run (get_vector already applies the deadzone);
	# keys and the bot always move at full speed.
	var input_mag := 1.0 if bot else clampf(input_dir.length(), 0.0, 1.0)
	var basis_y := Basis(Vector3.UP, cam_pivot.rotation.y)
	var dir := (basis_y * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var speed := GameState.move_speed()
	if input_enabled and not _dying and Input.is_action_pressed("sprint"):
		speed *= 1.7
	if bot and cheat:
		speed *= 10.0

	if input_enabled and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		Audio.play("jump", null, 0.1, -4.0)
		var fx := VFX.get_for(self)
		if fx:
			fx.puff(global_position, 0.9)
	# Hidden-class arts on a pad: hold Target (LT) and press Attack (X) for
	# class art 1 or Dash (B) for class art 2; keyboard also has R / C.
	var class_arts: Array = HiddenClasses.arts_of(GameState.hidden_class) if GameState.hidden_class != "" else []
	var class_chord := not class_arts.is_empty() and Input.is_action_pressed("target")
	var can_act := input_enabled and not _dying and _stun == 0.0 and not blocking and _recovery == 0.0
	if class_chord and class_arts.size() > 1 and can_act and Input.is_action_just_pressed("dash"):
		use_class_art(1)
	elif input_enabled and not _dying and _stun == 0.0 and Input.is_action_just_pressed("dash") and _dash_cd == 0.0:
		start_dash(dir)
	if input_enabled and not _dying and _stun == 0.0:
		if Input.is_action_just_pressed("parry"):
			press_parry()
		elif blocking and not Input.is_action_pressed("parry"):
			release_parry()
	if _stun > 0.0:
		_stun = maxf(_stun - delta, 0.0)
	elif not blocking:
		guard = minf(guard + _guard_regen() * delta, GUARD_MAX)
	_tick_parry_buffer()
	_check_whiff()
	_combo_t += delta
	_attack_buf = maxf(_attack_buf - delta, 0.0)
	if class_chord and can_act and Input.is_action_just_pressed("attack"):
		use_class_art(0)
	elif input_enabled and not _dying and not bot and Input.is_action_just_pressed("attack"):
		_attack_buf = ATTACK_BUFFER  # fires below now, or as soon as the swing is allowed
	if _attack_buf > 0.0 and input_enabled and not _dying and _stun == 0.0 and not blocking and _attack_cd == 0.0 and _recovery == 0.0:
		_attack_buf = 0.0
		_attack()
	if can_act and not class_arts.is_empty():
		for i in mini(class_arts.size(), class_cd.size()):
			if Input.is_action_just_pressed("class_%d" % (i + 1)):
				use_class_art(i)
	if input_enabled and not _dying and _stun == 0.0 and not blocking and _recovery == 0.0:
		# Gamepad: hold the target trigger (LT) and press a Sword Art button
		# for the matching unique art (keys 4-6 on keyboard).
		var chord := GameState.unique_skill != "" and Input.is_action_pressed("target")
		for i in SKILLS.size():
			if Input.is_action_just_pressed("skill_%d" % (i + 1)):
				if chord and i < unique_cd.size():
					if unique_cd[i] == 0.0:
						use_unique(i)
				elif not art_unlocked(i, GameState.sword_prof):
					_art_locked_toast(i)
				elif skill_cd[i] == 0.0:
					_use_skill(i)
		if GameState.unique_skill != "":
			for i in unique_cd.size():
				if Input.is_action_just_pressed("skill_%d" % (i + 4)) and unique_cd[i] == 0.0:
					use_unique(i)

	if _dash_timer > 0.0:
		_dash_timer -= delta
		var fwd := dir if dir != Vector3.ZERO else -model.global_transform.basis.z
		velocity.x = fwd.x * DASH_SPEED
		velocity.z = fwd.z * DASH_SPEED
	elif _magnet_t > 0.0:
		# Attack magnetism: a short step in toward the swing's target.
		_magnet_t -= delta
		velocity.x = _magnet_dir.x * MAGNET_STEP
		velocity.z = _magnet_dir.z * MAGNET_STEP
	elif dir != Vector3.ZERO:
		velocity.x = dir.x * speed * input_mag
		velocity.z = dir.z * speed * input_mag
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.z), 12.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, speed * 8 * delta)
		velocity.z = move_toward(velocity.z, 0, speed * 8 * delta)

	move_and_slide()
	_apply_shake(delta)

	if _swing_t > 0.0:
		_swing_t -= delta
		if _vrm == null:
			_weapon.rotation.y = lerp(1.4, -1.4, 1.0 - _swing_t / ATTACK_COOLDOWN)
	elif _vrm == null:
		_weapon.rotation.y = 0.0

	if global_position.y < -30:
		respawn()


## Distance-based footsteps (one every ~1.7 m walking, ~2 m sprinting) plus
## the landing thud. Own steps play flat; other players' steps are positional.
func _footsteps(delta: float, grounded: bool) -> void:
	if not Audio.enabled:
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if grounded and not _was_grounded:
		if is_local:
			Audio.play("land", null, 0.1, -6.0)
		var fx := VFX.get_for(self)
		if fx:
			fx.puff(global_position, 1.3)
	_was_grounded = grounded
	if not grounded or hspeed < 0.5:
		_step_dist = minf(_step_dist, 0.8)
		return
	_step_dist -= hspeed * delta
	if _step_dist <= 0.0:
		_step_dist = 2.0 if hspeed > 5.5 else 1.7
		Audio.footstep(Audio.surface_at(global_position), null if is_local else global_position)
		var fx := VFX.get_for(self)
		if fx:
			fx.puff(global_position, 0.55 if hspeed > 5.5 else 0.4)


## Basic attack: the next blow of the light-light-finisher chain. Faces (and
## steps toward) the nearest foe in front, plays the swing at once and lands
## the blade on the clip's contact frame ("delay"). The server re-checks
## kind, cadence, range and facing in Enemy.net_hit / Duels.srv_hit.
func _attack() -> void:
	if _combo_t > COMBO_CHAIN:
		_combo_step = 0
	var step: Dictionary = COMBO[_combo_step]
	var kind := int(step["kind"])
	_combo_t = 0.0
	_combo_step = (_combo_step + 1) % COMBO.size()
	_attack_cd = float(step["gap"])
	_magnetize(float(step["range"]))
	_play_swing_fx(kind, int(step["anim"]))
	if Net.online:
		net_swing.rpc(kind, int(step["anim"]))
	var dmg := GameState.attack_damage() * float(step["mult"])
	get_tree().create_timer(float(step["delay"]), false).timeout.connect(func():
		if is_inside_tree() and not _dying and _stun == 0.0:
			_hit_cone(dmg, float(step["range"]), float(step["arc"]), kind))


## The foe a swing should go to: the nearest living mob (or duel opponent)
## within MAGNET_RANGE inside a forward cone around where the player is
## steering (stick/keys) or facing. Turns the body to it at once and, if it
## stands just out of reach, steps in for MAGNET_STEP_TIME.
func _magnetize(reach: float) -> Node3D:
	var want := -model.global_transform.basis.z
	if is_local and not bot and input_enabled:
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if input_dir != Vector2.ZERO:
			want = Basis(Vector3.UP, cam_pivot.rotation.y) * Vector3(input_dir.x, 0, input_dir.y)
	want.y = 0.0
	want = want.normalized() if want.length_squared() > 0.001 else Vector3.FORWARD
	var best = null
	var best_score := INF
	var cands: Array = get_tree().get_nodes_in_group("enemies")
	var duels := get_tree().get_first_node_in_group("duels")
	if duels != null and duels.opponent_peer() != 0:
		for p in get_tree().get_nodes_in_group("players"):
			if p != self and duels.is_opponent(int(p.get("peer_id"))):
				cands.append(p)
	for e in cands:
		if not (e is Node3D) or not e.visible or ("hp" in e and float(e.hp) <= 0.0):
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > MAGNET_RANGE + (e.size.z * 0.5 if "size" in e else 0.0) or absf(e.global_position.y - global_position.y) > 2.5:
			continue
		var c := want.dot(to.normalized()) if d > 0.05 else 1.0
		if c < MAGNET_CONE:
			continue
		var score := d * (2.0 - c)  # prefer close and centred
		if score < best_score:
			best_score = score
			best = e
	if best == null:
		return null
	var to_b: Vector3 = best.global_position - global_position
	to_b.y = 0.0
	if to_b.length() > 0.05:
		model.rotation.y = atan2(-to_b.x, -to_b.z)
		var edge: float = to_b.length() - (best.size.z * 0.5 if "size" in best else 0.4)
		if edge > reach * 0.6 and _dash_timer <= 0.0:
			_magnet_dir = to_b.normalized()
			_magnet_t = clampf((edge - reach * 0.6) / MAGNET_STEP, 0.0, MAGNET_STEP_TIME)
	return best


## Everything a swing looks and sounds like, on every peer: the animation,
## the swing sound, the slash arc and (Sword Arts) the ground ring and blade
## glow. Cosmetic only; damage goes through _hit_cone / net_hit as before.
## `anim` overrides the clip (combo steps); -1 picks it from the kind.
func _play_swing_fx(kind: int, anim := -1) -> void:
	_swing_t = ATTACK_COOLDOWN
	if _vrm != null:
		_vrm.play_attack(anim if anim >= 0 else (0 if kind < 0 else 1 + kind))
	var pos = null if is_local else global_position
	if kind == KIND_FINISHER:
		Audio.play("swing", pos, 0.06, 2.0, 0.82)
		Audio.play("swing_heavy", pos, 0.08)
	elif kind < 0:
		Audio.play("swing", pos, 0.1)
	else:
		Audio.play("swing", pos, 0.05, 2.0, 0.9)
		Audio.play("skill", pos, 0.1)
		# Flash the blade so the skill reads even with placeholder art.
		var mat := _blade_mat
		var col := VFX.kind_color(kind)
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 3.0
		get_tree().create_timer(0.25, false).timeout.connect(func(): mat.emission_enabled = false)
	var fx := VFX.get_for(self)
	if fx == null:
		return
	_swing_flip = not _swing_flip
	var fwd := -model.global_transform.basis.z
	fx.slash(global_position, fwd, kind, _swing_flip)
	if kind >= 0 and _weapon != null and fx.has_method("blade_glow"):
		fx.call("blade_glow", _weapon, VFX.kind_color(kind), 0.5)
	if kind >= 0:
		fx.ring(global_position, VFX.kind_color(kind), 2.6 if kind != 2 else 3.2, 0.4)
		fx.flash_light(global_position + Vector3(0, 1.0, 0), VFX.kind_color(kind), 3.0)
	elif kind == KIND_FINISHER:
		fx.puff(global_position + fwd * 0.6, 0.8)
		fx.flash_light(global_position + Vector3(0, 1.0, 0) + fwd * 0.8, VFX.BASIC_COLOR, 2.0)


## Owner -> everyone: "I swung this move", so other players see the animation
## and slash arc. Purely cosmetic and unreliable; the server never acts on it
## (hits go through Enemy.net_hit). Accepted only from this node's own peer.
@rpc("any_peer", "call_remote", "unreliable")
func net_swing(kind: int, anim: int) -> void:
	if is_local or multiplayer.get_remote_sender_id() != peer_id:
		return
	var now := Time.get_ticks_msec()
	if now - _last_swing_fx_ms < 120:
		return  # Rate limit: a flood of swings cannot spam effects.
	_last_swing_fx_ms = now
	_play_swing_fx(clampi(kind, KIND_FINISHER, SKILLS.size() - 1), clampi(anim, -1, 3))


## Decaying camera shake (local player only; settings-free, small).
func shake(amount: float) -> void:
	_shake = minf(_shake + amount, 0.6)


func _apply_shake(delta: float) -> void:
	if camera == null:
		return
	if _shake <= 0.001:
		if camera.h_offset != 0.0 or camera.v_offset != 0.0:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
		return
	camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.12
	camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.12
	_shake *= exp(-delta * 11.0)


## Server, remote players only: accept or reject the position the owner
## synced since last tick. Distance is paid from a token bucket refilled at
## SRV_MAX_SPEED, so lag bursts pass but sustained speed or a teleport does
## not; vertical rise has its own small bucket and falls are always fine.
## Positions near a known teleport destination (pads, gate, respawn) are
## accepted outright. A rejected move snaps the player back to the last
## accepted position here and on the owner (net_correct_position); too many
## rejections inside a window get the peer kicked.
func _server_movement_check(delta: float) -> void:
	level = Net.srv_level(peer_id)
	srv_attack = Net.srv_attack_for(peer_id)
	var pos := global_position
	if not _srv_pos_init:
		_srv_pos_init = true
		_srv_last_pos = pos
		return
	_srv_budget = minf(_srv_budget + SRV_MAX_SPEED * delta, SRV_BUDGET_CAP)
	_srv_rise = minf(_srv_rise + SRV_RISE_SPEED * delta, SRV_RISE_CAP)
	var d := pos - _srv_last_pos
	var dh := Vector2(d.x, d.z).length()
	var reason := ""
	if Net.is_safe_destination(pos):
		_srv_budget = SRV_BUDGET_CAP
		_srv_rise = SRV_RISE_CAP
	elif not Net.in_world_bounds(pos):
		reason = "out of bounds at (%.0f, %.0f, %.0f)" % [pos.x, pos.y, pos.z]
	elif dh > _srv_budget + 0.01:
		reason = "moved %.1f m (budget %.1f)" % [dh, _srv_budget]
	elif d.y > _srv_rise + 0.01:
		reason = "rose %.1f m" % d.y
	if reason == "":
		_srv_budget -= dh
		_srv_rise -= maxf(d.y, 0.0)
		_srv_last_pos = pos
		return
	global_position = _srv_last_pos
	velocity = Vector3.ZERO
	var now := Time.get_ticks_msec()
	if now < _srv_grace_until:
		return
	_srv_grace_until = now + SRV_GRACE_MS
	net_correct_position.rpc_id(peer_id, _srv_last_pos)
	_srv_violations.append(now)
	while _srv_violations.size() > 0 and now - int(_srv_violations[0]) > SRV_VIOLATION_WINDOW_MS:
		_srv_violations.pop_front()
	print("[anticheat] peer %d (%s) %s: snapped back (%d/%d)" % [peer_id, display_name, reason, _srv_violations.size(), SRV_MAX_VIOLATIONS])
	if _srv_violations.size() >= SRV_MAX_VIOLATIONS:
		Net.kick(peer_id, "Impossible movement (%d corrections in %d s)" % [_srv_violations.size(), SRV_VIOLATION_WINDOW_MS / 1000])


## Where the server believes this player is: the last accepted position for
## a remote player (a rejected sync may sit in global_position until the next
## tick snaps it), otherwise the real one. Range checks use this.
func srv_position() -> Vector3:
	if Net.online and not is_local and multiplayer.is_server() and _srv_pos_init:
		return _srv_last_pos
	return global_position


## Server -> owner: your last move was rejected, you are here.
@rpc("any_peer", "call_remote", "reliable")
func net_correct_position(pos: Vector3) -> void:
	if not is_local or multiplayer.get_remote_sender_id() != 1:
		return
	global_position = pos
	velocity = Vector3.ZERO
	_dash_timer = 0.0


## Test bot: walk to the nearest live mob and swing at it. Returns the move
## input. Honest bots obey physics (so they also exercise the server's
## movement check as a legitimate player); --cheat bots teleport instead.
## A mob near this bot started a wind-up of `windup` seconds: mostly time a
## parry just before the blow, sometimes hold guard, sometimes do nothing, so
## soaks exercise all three server paths.
func bot_incoming(windup: float) -> void:
	if not bot or _dying or _bot_parry_at > 0 or blocking:
		return
	var now := Time.get_ticks_msec()
	var r := randf()
	if r < 0.55:
		# Half aim at the flare (perfect), half a little early (plain parry).
		_bot_parry_at = now + int(maxf(windup - (0.05 if randf() < 0.5 else 0.16), 0.0) * 1000.0)
		_bot_release_at = _bot_parry_at + 120
	elif r < 0.75:
		_bot_parry_at = now
		_bot_release_at = now + int((windup + 0.3) * 1000.0)


func _bot_defend_tick() -> void:
	var now := Time.get_ticks_msec()
	if _bot_parry_at > 0 and now >= _bot_parry_at:
		_bot_parry_at = 0
		press_parry()
	elif _bot_release_at > 0 and now >= _bot_release_at and _bot_parry_at == 0:
		_bot_release_at = 0
		if blocking:
			release_parry()


func _bot_think(delta: float) -> Vector2:
	_bot_t += delta
	var now := Time.get_ticks_msec()
	if bot_duel_target != null and is_instance_valid(bot_duel_target) and bot_duel_target.is_inside_tree():
		# Duelling (--duel soak): close on the opponent and swing; parries come
		# from bot_incoming on the server's telegraph.
		var dto: Vector3 = (bot_duel_target.global_position - global_position) * Vector3(1, 0, 1)
		if dto.length() > 1.8:
			return Vector2(dto.x, dto.z).normalized()
		model.look_at(Vector3(bot_duel_target.global_position.x, model.global_position.y, bot_duel_target.global_position.z))
		if _attack_cd == 0.0 and _recovery == 0.0 and _stun == 0.0 and not blocking:
			_attack()
		return Vector2.ZERO
	if _bot_target == null or not is_instance_valid(_bot_target) or not _bot_target.visible or fmod(_bot_t, 2.0) < delta:
		var best := INF
		var pick: Node3D = null
		# In a party, favour mobs close to a party member too, so --party
		# bots stay inside the reward-sharing range of each other.
		var mate: Node3D = null
		if not Net.party_ids.is_empty():
			var md := INF
			for p in get_tree().get_nodes_in_group("players"):
				if p != self and Net.party_ids.has(int(p.get("peer_id"))) and p.global_position.distance_to(global_position) < md:
					md = p.global_position.distance_to(global_position)
					mate = p
		for e in get_tree().get_nodes_in_group("enemies"):
			if not e.visible or int(_bot_avoid.get(e.get_instance_id(), 0)) > now:
				continue
			# Stay on this level (summit vs. ground): never chase off a ledge.
			if absf(e.global_position.y - global_position.y) > 20.0:
				continue
			var dist: float = e.global_position.distance_to(global_position)
			if mate != null:
				dist += 0.8 * e.global_position.distance_to(mate.global_position)
			if dist < best:
				best = dist
				pick = e
		if pick != _bot_target:
			_bot_stuck = 0
		_bot_target = pick
	if _bot_target == null:
		return Vector2.ZERO
	var goal: Vector3 = _bot_target.global_position
	# Inside the wall with the mob outside (or the reverse): go via a gate.
	var me_in := Vector2(global_position.x - BOT_WALL_CENTER.x, global_position.z - BOT_WALL_CENTER.z).length() < BOT_WALL_RADIUS - 1.0
	var mob_in := Vector2(goal.x - BOT_WALL_CENTER.x, goal.z - BOT_WALL_CENTER.z).length() < BOT_WALL_RADIUS - 1.0
	if me_in != mob_in:
		var gate := BOT_GATES[0]
		var best_gate := INF
		for g in BOT_GATES:
			var via: float = global_position.distance_to(g) + g.distance_to(goal)
			if via < best_gate:
				best_gate = via
				gate = g
		# Line up on the gate's radial so we pass between the gate towers
		# instead of wedging against one: near side first, then far side.
		var radial := (gate - BOT_WALL_CENTER) * Vector3(1, 0, 1)
		radial = radial.normalized()
		var inner := gate - radial * 7.0
		var outer := gate + radial * 7.0
		var near_pt := inner if me_in else outer
		var far_pt := outer if me_in else inner
		var flat_me := global_position * Vector3(1, 0, 1)
		if flat_me.distance_to(near_pt) > 2.0 and flat_me.distance_to(gate) > 7.5:
			goal = near_pt
		else:
			goal = far_pt
	var to: Vector3 = goal - global_position
	to.y = 0.0
	if cheat and to.length() > 2.0 and fmod(_bot_t, 0.5) < delta:
		var ang := randf() * TAU
		global_position = _bot_target.global_position + Vector3(cos(ang) * 1.4, 0.5, sin(ang) * 1.4)
		to = Vector3.ZERO
	# Stuck against a house or a wall: hop, sidestep, and after a few tries
	# give up on this mob for a while.
	if fmod(_bot_t, 1.0) < delta:
		if to.length() > 1.8 and global_position.distance_to(_bot_last_pos) < 0.6:
			_bot_stuck += 1
			if is_on_floor():
				velocity.y = JUMP_VELOCITY
			_bot_strafe = to.normalized().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
			_bot_strafe_t = 1.2
			if _bot_stuck >= 4:
				_bot_avoid[_bot_target.get_instance_id()] = now + 30000
				_bot_target = null
				_bot_stuck = 0
		else:
			_bot_stuck = 0
		_bot_last_pos = global_position
	if _bot_strafe_t > 0.0:
		_bot_strafe_t -= delta
		return Vector2(_bot_strafe.x, _bot_strafe.z)
	if to.length() > 1.6:
		return Vector2(to.x, to.z).normalized()
	model.look_at(Vector3(_bot_target.global_position.x, model.global_position.y, _bot_target.global_position.z))
	if _attack_cd == 0.0 and _recovery == 0.0:
		_attack()
	return Vector2.ZERO


## Damages every enemy within `range` and inside a cone of half-angle `arc/2`.
## Online the client sends the move kind (-1 basic, else skill index) and the
## server computes the damage itself from the player's level and cooldowns.
func _hit_cone(damage: float, range_: float, arc: float, kind := -1) -> int:
	var facing := -model.global_transform.basis.z
	var hits := 0
	_swing_serial += 1
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.visible:
			continue  # Dead on the server, not yet respawned.
		var to: Vector3 = e.global_position - global_position
		to.y = 0
		var reach: float = range_ + (e.size.z * 0.5 if "size" in e else 0.0)
		if to.length() <= reach and (to.length() < 0.6 or facing.dot(to.normalized()) > cos(arc / 2.0)):
			if not Net.online or multiplayer.is_server():
				e.take_hit(damage, to.normalized(), peer_id, kind)
			else:
				e.net_hit.rpc_id(1, kind, to.normalized(), _swing_serial)
			hits += 1
	if hits > 0 and is_local:
		GameState.wear_gear("weapon", Durability.WEAR_SWING)
		var learned := GameState.add_sword_prof(1)
		if learned != "":
			var hud := get_tree().get_first_node_in_group("hud")
			Audio.play("quest_complete")
			if hud and hud.has_method("toast"):
				hud.toast("New Sword Art: %s" % learned, "One-Handed Sword proficiency %d" % GameState.sword_prof, "Skill", UITheme.CYAN)
	# Duel opponent (scripts/duels.gd): the same cone, judged by the server
	# with the same kind / cooldown / range rules, then telegraphed so the
	# other player can parry. Nobody else is ever hit by a player.
	var duels := get_tree().get_first_node_in_group("duels")
	if duels != null and duels.opponent_peer() != 0:
		for p in get_tree().get_nodes_in_group("players"):
			if p == self or not duels.is_opponent(int(p.get("peer_id"))):
				continue
			var to: Vector3 = p.global_position - global_position
			to.y = 0
			if to.length() <= range_ + 0.4 and (to.length() < 0.6 or facing.dot(to.normalized()) > cos(arc / 2.0)):
				duels.client_hit(self, int(p.get("peer_id")), kind, to.normalized(), _swing_serial)
				hits += 1
	if hits > 0 and is_local:
		# Juice on a landed blow: a tiny camera kick and a 60 ms hit-stop on
		# our own animation (never Engine.time_scale: that would be global).
		shake(0.12 if kind == -1 else 0.24)
		InputSetup.rumble(0.15 if kind == -1 else 0.35, 0.35 if kind == -1 else 0.8, 0.08 if kind == -1 else 0.14)
		if _vrm != null:
			_vrm.hit_stop(0.06 if kind == -1 else 0.1)
	return hits


## Parry press: opens the window at once (no wind-up of its own) and starts
## guarding while held. Inside the whiff cooldown it only guards, unless the
## cooldown ends within PARRY_BUFFER, in which case the press is buffered.
func press_parry() -> void:
	_parry_press_at(Time.get_ticks_msec())
	if _vrm != null and _vrm.has_method("play_guard"):
		_vrm.play_guard(true)
	if Net.online and not multiplayer.is_server():
		net_parry.rpc_id(1, true)


func release_parry() -> void:
	blocking = false
	if _vrm != null and _vrm.has_method("play_guard"):
		_vrm.play_guard(false)
	if Net.online and not multiplayer.is_server():
		net_parry.rpc_id(1, false)


## The press itself, on whichever machine judges it (same rules everywhere).
func _parry_press_at(now: int) -> void:
	blocking = true
	if now >= _parry_ready_ms:
		_open_parry(now)
	elif _parry_ready_ms - now <= int(PARRY_BUFFER * 1000.0):
		_parry_buffer_at = _parry_ready_ms


func _open_parry(now: int) -> void:
	_parry_open_ms = now
	_parry_ready_ms = now + int(PARRY_WHIFF_CD * 1000.0)
	_parry_buffer_at = 0
	_parry_used = false
	_flush_pending(false)  # server: a strike held for a press in flight


## A buffered press opens its window when the whiff cooldown runs out (even
## if the tap was already released: the window parries on its own).
func _tick_parry_buffer() -> void:
	if _parry_buffer_at > 0 and Time.get_ticks_msec() >= _parry_buffer_at:
		_open_parry(Time.get_ticks_msec())


## Owner only: an open window that parried nothing is a whiff. Online the
## server's verdict needs a round trip, so the owner waits a little longer.
func _check_whiff() -> void:
	if _parry_used or not is_local:
		return
	var wait := int(PARRY_WINDOW * 1000.0) + (300 if Net.online and not multiplayer.is_server() else 0)
	if Time.get_ticks_msec() - _parry_open_ms > wait:
		_parry_used = true
		whiffs += 1
		defend_fx("whiff", global_position - model.global_transform.basis.z)


## Owner -> server: parry pressed / released. The server stamps its own time
## and applies the same whiff cooldown and buffer, so a client can't keep a
## window open by spamming.
@rpc("any_peer", "call_remote", "reliable")
func net_parry(on: bool) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id:
		return
	if on:
		_parry_press_at(Time.get_ticks_msec())
	else:
		blocking = false


## Dash: the burst of speed plus DASH_IFRAMES of invulnerability.
func start_dash(dir := Vector3.ZERO) -> void:
	_dash_timer = DASH_TIME
	_dash_cd = DASH_COOLDOWN
	_magnet_t = 0.0
	_start_iframes(Time.get_ticks_msec())
	if Net.online and not multiplayer.is_server():
		net_dash.rpc_id(1)
	Audio.play("dash")
	var fx := VFX.get_for(self)
	if fx:
		fx.dash(global_position, dir if dir != Vector3.ZERO else -model.global_transform.basis.z)


## Owner -> server: I dashed. The server grants its own i-frames at most once
## per DASH_COOLDOWN (90%), never while stunned.
@rpc("any_peer", "call_remote", "reliable")
func net_dash() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id:
		return
	_start_iframes(Time.get_ticks_msec())


func _start_iframes(now: int) -> bool:
	if _stun > 0.0 or now - _dash_srv_ms < int(DASH_COOLDOWN * 900.0):
		return false
	_dash_srv_ms = now
	_iframe_until = now + int(DASH_IFRAMES * 1000.0)
	_flush_pending(false)
	return true


func is_dodging() -> bool:
	return Time.get_ticks_msec() < _iframe_until


## Server-side late grace for this remote player's presses (ms).
func late_grace_ms() -> int:
	return clampi(Net.srv_rtt(peer_id) + LATE_GRACE_PAD_MS, LATE_GRACE_MIN_MS, LATE_GRACE_MAX_MS)


func _can_defer() -> bool:
	if defer_test:
		return true
	return Net.online and multiplayer.is_server() and not is_local and multiplayer.get_peers().has(peer_id)


## The one way a mob, boss or duel blow reaches this player: judged now
## (defend) and handed to `on_outcome(outcome)`. On the server, for a remote
## player who has no parry/dash running yet, the blow waits up to
## late_grace_ms() for a press already on its way; it then resolves as a
## (perfect) parry or dodge if one arrives, or as it would have anyway.
## `parryable` false: a heavy blow only i-frames or a raised guard soften.
## Returns the outcome, or "pending" while the blow is held.
func srv_strike(from_pos: Vector3, on_outcome: Callable, parryable := true) -> String:
	if _can_defer():
		var peek := defend(from_pos, parryable, false)
		if peek == "" or peek == "block":
			_pending_strikes.append({"at": Time.get_ticks_msec() + late_grace_ms(), "from": from_pos, "cb": on_outcome, "parryable": parryable})
			return "pending"
	var out := defend(from_pos, parryable)
	on_outcome.call(out)
	return out


## Resolve held strikes: now when a press or dash makes them parry/dodge,
## else when their grace runs out (or all of them when `force`).
func _flush_pending(force: bool) -> void:
	if _pending_strikes.is_empty():
		return
	var now := Time.get_ticks_msec()
	var due: Array = []
	var keep: Array = []
	for s in _pending_strikes:
		var o := defend(s["from"], bool(s["parryable"]), false)
		if force or now >= int(s["at"]) or o == "parry" or o == "dodge" or o == "dazed":
			due.append(s)
		else:
			keep.append(s)
	_pending_strikes = keep
	for s in due:
		var out := defend(s["from"], bool(s["parryable"]))
		var cb: Callable = s["cb"]
		if cb.is_valid():
			cb.call(out)


func pending_strikes() -> int:
	return _pending_strikes.size()


## Where a blow resolves (offline/host: here; server: the remote player's
## node). Returns "dodge" (dash i-frames), "parry" (last_parry_perfect tells
## the tier), "block", "stunned" (this blow broke the guard), "dazed" (already
## stunned: full damage) or "" (no defence). A parry consumes the
## window and refunds the whiff cooldown. `commit` false only looks.
## Unparryable blows (`parryable` false) are softened by any raised guard
## without wearing it, as before.
func defend(from_pos: Vector3, parryable := true, commit := true) -> String:
	if _stun > 0.0:
		return "dazed"  # already reeling: the blow lands in full
	var now := Time.get_ticks_msec()
	if now < _iframe_until:
		return "dodge"
	if not parryable:
		return "block" if blocking else ""
	# Must face the attacker roughly (no parrying blows from behind).
	var to := from_pos - global_position
	to.y = 0.0
	var facing := -model.global_transform.basis.z if model else Vector3.FORWARD
	var front := to.length() < 0.5 or facing.dot(to.normalized()) > -0.1
	var since := now - _parry_open_ms
	if front and since <= int(PARRY_WINDOW * 1000.0):
		if not commit:
			return "parry"
		_parry_open_ms = -100000
		_parry_ready_ms = now  # a clean parry can chain into the next one
		_parry_used = true
		last_parry_perfect = since <= perfect_ms()
		parries += 1
		last_parry_ms = now
		if last_parry_perfect:
			perfect_parries += 1
			guard = minf(guard + PERFECT_GUARD, GUARD_MAX)
		elif is_local:
			GameState.wear_gear("weapon", Durability.WEAR_PARRY)
		elif Net.online and multiplayer.is_server():
			Net.srv_wear(peer_id, "weapon", Durability.WEAR_PARRY)
		return "parry"
	if front and blocking:
		if not commit:
			return "block"
		guard -= GUARD_PER_BLOCK
		if guard <= 0.0:
			guard = 0.0
			blocking = false
			_stun = GUARD_BREAK_STUN
			_parry_buffer_at = 0
			if _vrm != null and _vrm.has_method("play_guard"):
				_vrm.play_guard(false)
			return "stunned"
		return "block"
	return ""


## How soon after the press a parried blow counts as perfect (ms). For a
## remote player the press reached the server one round trip after it was
## made, so the server takes that off; a press that arrives during the late
## grace (since <= 0) is always perfect.
func perfect_ms() -> int:
	var ms := int(PERFECT_WINDOW * 1000.0)
	if Net.online and multiplayer.is_server() and not is_local:
		ms = maxi(ms - Net.srv_rtt(peer_id), 0)
	return ms


func is_stunned() -> bool:
	return _stun > 0.0


## A duel opponent parried this player's blow (judged on the server): a
## short stagger and a shove backwards. Runs on the server's copy (so its
## next hits are refused while stunned) and on the owner (Duels "parried").
func pvp_staggered(secs: float, push: Vector3) -> void:
	_stun = maxf(_stun, clampf(secs, 0.0, GUARD_BREAK_STUN))
	_recovery = maxf(_recovery, 0.2)
	_combo_step = 0
	if is_local:
		velocity.x = push.x
		velocity.z = push.z
		shake(0.2)
		InputSetup.rumble(0.4, 0.8, 0.2)
		Audio.play("block", null, 0.05)
		_callout("PARRIED", Color(1.0, 0.45, 0.35), false)
		var fx := VFX.get_for(self)
		if fx and fx.has_method("stagger"):
			fx.call("stagger", self, secs)


## Big centred combat word on the owner's HUD (PARRY / PERFECT / ...).
func _callout(text: String, color: Color, big: bool) -> void:
	if not is_local or bot:
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("combat_callout"):
		hud.combat_callout(text, color, big)


## Local feedback for a defence outcome (on the defender's own machine):
## "parry", "perfect", "block", "stunned" (guard break), "dodge", "whiff".
func defend_fx(outcome: String, from_pos: Vector3) -> void:
	var fx := VFX.get_for(self)
	var at := global_position + Vector3(0, 1.2, 0) + (from_pos - global_position).normalized() * 0.6
	var spot = null if is_local else at
	match outcome:
		"parry", "perfect":
			var perfect := outcome == "perfect"
			Audio.play("parry_perfect" if perfect else "parry", spot, 0.04)
			shake(0.3 if perfect else 0.18)
			InputSetup.rumble(0.4 if perfect else 0.3, 1.0 if perfect else 0.9, 0.18 if perfect else 0.12)
			if fx and perfect and fx.has_method("perfect_parry_flash"):
				fx.call("perfect_parry_flash", at)
			elif fx and fx.has_method("parry_flash"):
				fx.call("parry_flash", at, false)
			elif fx:
				fx.flash(at, Color(1.0, 0.95, 0.7), 1.3)
				fx.ring(at, Color(1.0, 0.85, 0.4), 1.8, 0.25)
			if _vrm != null:
				_vrm.play_attack(3 if perfect else 0)  # the deflecting cut
				_vrm.hit_stop(0.14 if perfect else 0.09)
			_callout("PERFECT" if perfect else "PARRY", Color(1.0, 0.95, 0.75) if perfect else VFX.PARRY_COLOR, perfect)
			if perfect and is_local:
				_time_stop(0.11)
		"block":
			Audio.play("block", spot, 0.06)
			shake(0.1)
			if fx:
				fx.hit(at, (global_position - from_pos).normalized(), Color(0.7, 0.85, 1.0))
		"stunned":
			Audio.play("guard_break", spot, 0.04)
			shake(0.3)
			InputSetup.rumble(0.5, 1.0, 0.3)
			if fx and fx.has_method("parry_flash"):
				fx.call("parry_flash", at, true)
			if fx and fx.has_method("stagger"):
				fx.call("stagger", self, GUARD_BREAK_STUN)
			_callout("GUARD BREAK", Color(1.0, 0.4, 0.3), true)
		"dodge":
			Audio.play("dodge", spot, 0.08)
			if fx and fx.has_method("dodge_flash"):
				fx.call("dodge_flash", self)
			_callout("EVADE", Color(0.6, 0.9, 1.0), false)
		"whiff":
			Audio.play("parry_whiff", spot, 0.06)
			if fx and fx.has_method("parry_whiff"):
				fx.call("parry_whiff", self)
			_callout("WHIFF", Color(0.62, 0.66, 0.72), false)


## Offline only: a perfect parry freezes the world for a beat (online the
## world can't stop; the shake and the rig's hit-stop carry it instead).
func _time_stop(secs: float) -> void:
	if Net.online or not Audio.enabled or Engine.time_scale < 1.0:
		return
	Engine.time_scale = 0.08
	get_tree().create_timer(secs, true, false, true).timeout.connect(func():
		if Engine.time_scale == 0.08:
			Engine.time_scale = 1.0)


## Server -> owner: the outcome of a defence judged on the server (and the
## guard / stun it left), so the owner sees and feels it.
@rpc("authority", "call_remote", "reliable")
func net_defended(outcome: String, from_pos: Vector3, guard_left: float, stun: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	guard = clampf(guard_left, 0.0, GUARD_MAX)
	_stun = clampf(stun, 0.0, GUARD_BREAK_STUN)
	if outcome == "stunned":
		blocking = false
		if _vrm != null and _vrm.has_method("play_guard"):
			_vrm.play_guard(false)
	if outcome == "parry" or outcome == "perfect":
		parries += 1
		last_parry_ms = Time.get_ticks_msec()
		last_parry_perfect = outcome == "perfect"
		_parry_used = true
		_parry_open_ms = -100000
		_parry_ready_ms = 0
		if outcome == "perfect":
			perfect_parries += 1
		else:
			GameState.wear_gear("weapon", Durability.WEAR_PARRY)  # mirror of the server's wear
	defend_fx(outcome, from_pos)


## H (or LT + Y on a pad): crush a Healing Crystal from the pack.
func quick_heal() -> void:
	var err := LifeData.use_crystal("heal_crystal")
	if err == "pending":
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if err != "":
		Audio.play("ui_error")
		if hud and hud.has_method("toast"):
			hud.toast(err, "", "", UITheme.ROSE)
		return
	var w := get_tree().current_scene
	if w and w.has_method("crystal_effect"):
		w.crystal_effect("heal_crystal")


## A unique Sword Art (UniqueSkills arts of GameState.unique_skill): a rapid
## multi-slash combo. Offline the realm holder check runs here; online the
## server re-checks every hit (Enemy.net_hit). Returns false if refused.
func use_unique(i: int) -> bool:
	var id := GameState.unique_skill
	var arts := UniqueSkills.arts(id)
	if i < 0 or i >= arts.size() or unique_cd[i] > 0.0:
		return false
	if not Net.online and not Net.srv_holds_unique(1, id):
		return false
	var art: Dictionary = arts[i]
	unique_cd[i] = float(art["cooldown"])
	var hits := int(art.get("hits", 1))
	_recovery = float(art["recovery"]) + hits * 0.07
	Audio.play("skill_charge", null if is_local else global_position, 0.05)
	InputSetup.rumble(0.4, 0.9, 0.3)
	if float(art["lunge"]) > 0.0:
		var fwd := -model.global_transform.basis.z
		velocity.x = fwd.x * float(art["lunge"])
		velocity.z = fwd.z * float(art["lunge"])
	# Alternating slashes, one per hit, fast; damage lands once at the end
	# (the server validates one hit per swing).
	for h in hits:
		get_tree().create_timer(0.05 + h * 0.08, false).timeout.connect(func():
			if is_inside_tree():
				_play_swing_fx(h % SKILLS.size())
				if Net.online:
					net_swing.rpc(h % SKILLS.size(), -1))
	get_tree().create_timer(0.12 + hits * 0.08, false).timeout.connect(func():
		if is_inside_tree():
			_hit_cone(GameState.attack_damage() * GameState.art_power() * float(art["mult"]), float(art["range"]), float(art["arc"]), UniqueSkills.KIND_BASE + i))
	return true


## Guard regeneration per second: Stillblades recover faster. The class comes
## from the server's view of this peer (the record for remote players).
func _guard_regen() -> float:
	return GUARD_REGEN * HiddenClasses.guard_regen_mult(Net.srv_hidden_class(peer_id))


## Still Water may be cast this long after the last parry (client side).
func counter_open() -> bool:
	return Time.get_ticks_msec() - last_parry_ms <= int(HiddenClasses.COUNTER_WINDOW * 1000.0)


## A hidden-class Sword Art (HiddenClasses.arts_of(GameState.hidden_class),
## slot `i`). Offline the class check is GameState's; online the server
## re-checks class, cooldown and the after-parry rule on every hit
## (Enemy.net_hit). Returns false if refused. VFX hook: class_art_cast(player,
## class, art_id) behind has_method.
func use_class_art(i: int) -> bool:
	var cls := GameState.hidden_class
	var arts := HiddenClasses.arts_of(cls)
	if i < 0 or i >= arts.size() or i >= class_cd.size() or class_cd[i] > 0.0:
		return false
	var art: Dictionary = arts[i]
	if bool(art.get("after_parry", false)) and not counter_open():
		if is_local:
			Audio.play("ui_error", null, 0.0, -6.0)
		return false
	class_cd[i] = float(art["cooldown"])
	_recovery = float(art["recovery"])
	Audio.play("skill_charge", null if is_local else global_position, 0.05)
	InputSetup.rumble(0.35, 0.8, 0.22)
	var fx := VFX.get_for(self)
	if fx and fx.has_method("class_art_cast"):
		fx.call("class_art_cast", self, cls, str(art["id"]))
	if float(art["lunge"]) > 0.0:
		var fwd := -model.global_transform.basis.z
		velocity.x = fwd.x * float(art["lunge"])
		velocity.z = fwd.z * float(art["lunge"])
	_play_swing_fx(i % SKILLS.size())
	if Net.online:
		net_swing.rpc(i % SKILLS.size(), -1)
	var kind := HiddenClasses.kind_of(cls, i)
	get_tree().create_timer(0.12, false).timeout.connect(func():
		if not is_inside_tree():
			return
		var hits := _hit_cone(GameState.attack_damage() * GameState.art_power() * float(art["mult"]), float(art["range"]), float(art["arc"]), kind)
		# Offline / host the hits landed here (take_hit), so the art's
		# self-buff is granted here too; a remote client's comes from the
		# server with the validated hit (Enemy.net_hit).
		if hits > 0 and art.has("buff") and (not Net.online or multiplayer.is_server()):
			Net.srv_class_buff(peer_id, str(art["buff"]), HiddenClasses.HEARTH_GLOW)
			var fx2 := VFX.get_for(self)
			if fx2 and fx2.has_method("hearth_glow"):
				fx2.call("hearth_glow", self))
	return true


static func art_unlocked(i: int, prof: int) -> bool:
	return i >= 0 and i < SKILLS.size() and prof >= int(SKILLS[i].get("prof", 0))


func _art_locked_toast(i: int) -> void:
	Audio.play("ui_error")
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast("%s is not learned yet" % SKILLS[i]["name"], "One-Handed Sword proficiency %d / %d" % [GameState.sword_prof, int(SKILLS[i]["prof"])], "Skill", UITheme.MUTED)


func _use_skill(i: int) -> void:
	var sk: Dictionary = SKILLS[i]
	skill_cd[i] = sk["cooldown"]
	_recovery = sk["recovery"]
	_combo_step = 0
	_play_swing_fx(i)
	if Net.online:
		net_swing.rpc(i, -1)
	skill_used.emit(i, sk["cooldown"])
	# Heavy Sword Arts (2x damage and up) thump the pad; light ones tap it.
	if float(sk["mult"]) >= 2.0:
		InputSetup.rumble(0.35, 0.8, 0.22)
	else:
		InputSetup.rumble(0.2, 0.3, 0.1)
	if sk["lunge"] > 0.0:
		var fwd := -model.global_transform.basis.z
		velocity.x = fwd.x * sk["lunge"]
		velocity.z = fwd.z * sk["lunge"]
	# Short delay so a lunge connects at the end of the move.
	get_tree().create_timer(0.12, false).timeout.connect(func():
		if is_inside_tree():
			_hit_cone(GameState.attack_damage() * GameState.art_power() * sk["mult"], sk["range"], sk["arc"], i))


## Offline / host: damages the local GameState. On the server for a remote
## player: the record owns HP (Net.srv_damage soaks, kills and respawns, and
## tells the owner through net_hp / net_apply "respawn"); nothing is trusted
## from the client. The buffed attack the server uses comes from
## Net.srv_attack_for (see _server_movement_check).
func take_damage(amount: float) -> void:
	if Net.online and multiplayer.is_server() and not is_local:
		Net.srv_damage(peer_id, amount)
		return
	if not is_local or _dying:
		return
	GameState.take_damage(amount)
	Net.note_hidden(peer_id, "hurt")  # a hit ends a clean parry streak (HiddenClasses)
	Audio.play("player_hit", null, 0.1)
	shake(clampf(0.15 + amount / 60.0, 0.15, 0.4))
	InputSetup.rumble(0.5, clampf(0.3 + amount / 40.0, 0.3, 1.0), 0.25)
	var fx := VFX.get_for(self)
	if fx:
		fx.hit(global_position + Vector3(0, 1.1, 0), -model.global_transform.basis.z, Color(1.0, 0.35, 0.3))
	if GameState.hp <= 0.0:
		die()


@rpc("any_peer", "call_remote", "reliable")
func net_take_damage(amount: float) -> void:
	if multiplayer.get_remote_sender_id() == 1 and is_local:
		take_damage(clampf(amount, 0.0, 1000.0))


## Generous upper bound on what a legit player of this level can hit for
## (base + maxed strength + a Myth-rated weapon). Kept as a sanity ceiling.
static func attack_cap(lvl: int) -> float:
	return 8.0 + 3.0 * (6 + 3 * lvl) + lvl + 12.0 * 4.0


func _report_stats() -> void:
	if not Net.online or multiplayer.is_server():
		return
	var now := Time.get_ticks_msec()
	if now - _last_report_ms < 250:
		# Coalesce bursts (equip fires several signals) into one later report.
		if not _report_queued:
			_report_queued = true
			get_tree().create_timer(0.3, false).timeout.connect(func():
				_report_queued = false
				if is_inside_tree():
					_report_stats())
		return
	_last_report_ms = now
	var weapon = GameState.equipped.get("weapon")
	var w_atk: float = float(weapon["atk"]) if weapon is Dictionary else 0.0
	var w_rank: int = int(weapon.get("rank", 0)) if weapon is Dictionary else 0
	var lvl := 99 if (bot and cheat) else GameState.level
	var strength := 99 if (bot and cheat) else int(GameState.stats.get("strength", 0))
	if bot and cheat:
		w_atk = 999.0
		w_rank = 5
	net_report_stats.rpc_id(1, lvl, strength, w_atk, w_rank)


## The owner tells the server its strength and equipped weapon. Level and
## XP are the server's own (Net.srv_records); strength is clamped to what
## that level allows and the weapon to the best roll of its rank. The level
## claim is only compared against the record, and a mismatch logged.
@rpc("any_peer", "call_remote", "reliable")
func net_report_stats(lvl: int, strength: int, weapon_atk: float, weapon_rank: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id:
		return
	var now := Time.get_ticks_msec()
	if now - _last_report_ms < 100:
		return  # Rate limit: a flood of reports cannot busy the server.
	_last_report_ms = now
	Net.srv_set_reported(peer_id, strength, weapon_atk, weapon_rank)
	level = Net.srv_level(peer_id)
	srv_attack = Net.srv_attack_for(peer_id)
	if lvl != level and lvl != _srv_claimed_level:
		_srv_claimed_level = lvl
		print("[anticheat] peer %d (%s) claims Lv %d, server record says Lv %d; claim ignored" % [peer_id, display_name, lvl, level])


## Seconds the shattered body lingers before the move to the respawn point,
## then how long the "You are dead" screen counts down there.
const DEATH_SHATTER := 1.4
const DEATH_TIME := 3.0
var _dying := false


## Death: the body bursts into crystal shards where it fell (VFX.shatter when
## the visuals provide it), the screen greys out with a countdown, then the
## player respawns at the floor's arrival point. The server already healed
## and moved the record; this is the local presentation.
## `xp_lost`: the death penalty the server already applied (online); offline
## and on the host it is applied here (Net.death_penalty).
func die(xp_lost := -1) -> void:
	if _dying:
		return
	if is_local and Permadeath.is_on(GameState):
		if Net.remote_client():
			return  # the server decides; its "fallen" event calls fall()
		var info := Permadeath.make_fall(GameState, last_attacker, str(GameState.FLOOR_NAMES.get(GameState.floor, "Aincrad")))
		fall(info)
		return
	_dying = true
	if xp_lost < 0 and is_local and not Net.remote_client():
		xp_lost = Net.death_penalty(GameState)
	last_xp_lost = maxi(xp_lost, 0)
	input_enabled = false
	velocity = Vector3.ZERO
	var fx := VFX.get_for(self)
	var tint := Color(0.55, 0.85, 1.0)
	if fx and fx.has_method("shatter"):
		fx.call("shatter", null, model, [], tint, false, 0.0)
	elif fx:
		fx.flash(global_position + Vector3(0, 1.0, 0), tint, 1.6)
		fx.sparkle(global_position + Vector3(0, 1.0, 0), tint)
	Audio.play("player_death")
	InputSetup.rumble(0.8, 1.0, 0.5)
	shake(0.4)
	var hud := get_tree().get_first_node_in_group("hud")
	var where: String = GameState.FLOOR_NAMES.get(GameState.floor, "town")
	if hud and hud.has_method("show_death"):
		hud.show_death(DEATH_SHATTER + DEATH_TIME, where)
	input_enabled = false  # after show_death: closing screens re-enables input
	await get_tree().create_timer(DEATH_SHATTER, true, false, true).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	model.visible = false
	respawn()
	await get_tree().create_timer(DEATH_TIME, true, false, true).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	model.visible = true
	_dying = false
	input_enabled = true
	if hud and is_instance_valid(hud) and hud.has_method("hide_death"):
		hud.hide_death()
	Audio.play("respawn")
	if last_xp_lost > 0 and hud and is_instance_valid(hud) and hud.has_method("toast"):
		hud.toast("Lost %d EXP" % last_xp_lost, "Your gear took a beating too  ·  repair at an anvil", "Death", UITheme.ROSE)
	if fx and is_instance_valid(fx):
		fx.sparkle(global_position + Vector3(0, 1.0, 0), Color(0.7, 0.95, 1.0))


## Permadeath: the last death. The fall is written first (offline: into the
## slot, and the realm lets go of the character), then the shatter and the
## "journey has ended" screen, then back to the title. Online the server
## already wrote it and sends "fallen"; it drops the connection after.
func fall(info: Dictionary) -> void:
	if _dying and not GameState.fallen.is_empty():
		return
	_dying = true
	input_enabled = false
	velocity = Vector3.ZERO
	GameState.fallen = info.duplicate()
	GameState.hp = 0.0
	if not Net.remote_client():
		Permadeath.release(Net.get_realm(), Net.local_holder())
		GameState.unique_skill = ""
		Net.srv_announce("%s has fallen. Their name is struck on the Monument of Climbers." % str(GameState.character.get("name", "Someone")))
	SaveSystem.mark_fallen(info)
	var fx := VFX.get_for(self)
	var tint := Color(1.0, 0.45, 0.4)
	if fx and fx.has_method("shatter"):
		fx.call("shatter", null, model, [], tint, false, 0.0)
	elif fx:
		fx.flash(global_position + Vector3(0, 1.0, 0), tint, 1.6)
	Audio.play("player_death")
	InputSetup.rumble(1.0, 1.0, 0.8)
	shake(0.5)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_fallen"):
		hud.show_fallen(info, Permadeath.FALL_SCREEN)
	elif hud and hud.has_method("show_death"):
		hud.show_death(Permadeath.FALL_SCREEN, Permadeath.fall_text(info))
	input_enabled = false
	await get_tree().create_timer(DEATH_SHATTER, true, false, true).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	model.visible = false
	await get_tree().create_timer(maxf(Permadeath.FALL_SCREEN - DEATH_SHATTER, 1.0), true, false, true).timeout
	if not is_instance_valid(self) or not is_inside_tree() or not menu_after_fall:
		return
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func is_dying() -> bool:
	return _dying


func respawn() -> void:
	# Respawn at the floor's arrival point (town plaza on Floor 1), like being sent back to a safe zone.
	global_position = GameState.spawn_point()
	velocity = Vector3.ZERO
	GameState.heal_full()
