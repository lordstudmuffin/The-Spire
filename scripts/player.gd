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
const ATTACK_RANGE := 2.2
const ATTACK_COOLDOWN := 0.45
const MOUSE_SENS := 0.003
## Right-stick orbit speed at full deflection, radians per second (x stick_sens).
const STICK_SENS := 2.4
## Lock-on assist ("target"): the camera swings to the nearest mob this close.
const TARGET_RANGE := 16.0

## Sword Arts: preset moves with a cooldown and a short recovery ("post-motion").
## Damage is a multiplier of normal attack damage; arc is the hit cone in radians.
const SKILLS := [
	{"name": "Horizontal", "mult": 1.6, "range": 2.6, "arc": PI, "cooldown": 4.0, "recovery": 0.5, "lunge": 0.0},
	{"name": "Vertical Arc", "mult": 2.6, "range": 2.4, "arc": 0.9, "cooldown": 8.0, "recovery": 0.8, "lunge": 0.0},
	{"name": "Rage Spike", "mult": 2.0, "range": 2.4, "arc": 1.2, "cooldown": 10.0, "recovery": 0.6, "lunge": 14.0},
]

signal skill_used(index: int, cooldown: float)

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
var _recovery := 0.0
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
var _bot_t := 0.0
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
	if not is_local or not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var inv := -1.0 if Settings.data.get("invert_y", false) else 1.0
		cam_pivot.rotation.y -= event.relative.x * MOUSE_SENS * Settings.data["mouse_sens"]
		spring.rotation.x = clamp(spring.rotation.x - event.relative.y * inv * MOUSE_SENS * Settings.data["mouse_sens"], -1.2, 0.4)
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
		if _name_label.text != display_name:
			_name_label.text = display_name
		_party_check_t -= delta
		if _party_check_t <= 0.0:
			_party_check_t = 0.5
			var in_party: bool = Net.party_ids.has(peer_id)
			_party_tag.visible = in_party
			_name_label.modulate = Color(0.6, 0.95, 0.65) if in_party else Color(0.75, 0.9, 1.0)
		if multiplayer.is_server():
			_server_movement_check(delta)
		return
	level = GameState.level
	srv_attack = GameState.attack_damage()

	cam_pivot.global_position = global_position + Vector3(0, 1.5, 0)
	if input_enabled and not bot:
		_stick_look(delta)
	_dash_cd = max(_dash_cd - delta, 0.0)
	_attack_cd = max(_attack_cd - delta, 0.0)
	_recovery = max(_recovery - delta, 0.0)
	for i in skill_cd.size():
		skill_cd[i] = max(skill_cd[i] - delta, 0.0)

	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir := Vector2.ZERO
	if bot:
		input_dir = _bot_think(delta)
	elif input_enabled and _recovery == 0.0:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Stick deflection = walk..run (get_vector already applies the deadzone);
	# keys and the bot always move at full speed.
	var input_mag := 1.0 if bot else clampf(input_dir.length(), 0.0, 1.0)
	var basis_y := Basis(Vector3.UP, cam_pivot.rotation.y)
	var dir := (basis_y * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var speed := GameState.move_speed()
	if input_enabled and Input.is_action_pressed("sprint"):
		speed *= 1.7
	if bot and cheat:
		speed *= 10.0

	if input_enabled and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		Audio.play("jump", null, 0.1, -4.0)
		var fx := VFX.get_for(self)
		if fx:
			fx.puff(global_position, 0.9)
	if input_enabled and Input.is_action_just_pressed("dash") and _dash_cd == 0.0:
		_dash_timer = DASH_TIME
		_dash_cd = DASH_COOLDOWN
		Audio.play("dash")
		var fx := VFX.get_for(self)
		if fx:
			fx.dash(global_position, dir if dir != Vector3.ZERO else -model.global_transform.basis.z)
	if input_enabled and Input.is_action_just_pressed("attack") and _attack_cd == 0.0 and _recovery == 0.0:
		_attack()
	if input_enabled and _recovery == 0.0:
		for i in SKILLS.size():
			if Input.is_action_just_pressed("skill_%d" % (i + 1)) and skill_cd[i] == 0.0:
				_use_skill(i)

	if _dash_timer > 0.0:
		_dash_timer -= delta
		var fwd := dir if dir != Vector3.ZERO else -model.global_transform.basis.z
		velocity.x = fwd.x * DASH_SPEED
		velocity.z = fwd.z * DASH_SPEED
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


func _attack() -> void:
	_attack_cd = ATTACK_COOLDOWN
	_play_swing_fx(-1)
	if Net.online:
		net_swing.rpc(-1)
	_hit_cone(GameState.attack_damage(), ATTACK_RANGE, 1.3)


## Everything a swing looks and sounds like, on every peer: the animation,
## the swing sound, the slash arc and (Sword Arts) the ground ring and blade
## glow. Cosmetic only; damage goes through _hit_cone / net_hit as before.
func _play_swing_fx(kind: int) -> void:
	_swing_t = ATTACK_COOLDOWN
	if _vrm != null:
		_vrm.play_attack(0 if kind < 0 else 1 + kind)
	var pos = null if is_local else global_position
	if kind < 0:
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
	if kind >= 0:
		fx.ring(global_position, VFX.kind_color(kind), 2.6 if kind != 2 else 3.2, 0.4)
		fx.flash_light(global_position + Vector3(0, 1.0, 0), VFX.kind_color(kind), 3.0)


## Owner -> everyone: "I swung this move", so other players see the animation
## and slash arc. Purely cosmetic and unreliable; the server never acts on it
## (hits go through Enemy.net_hit). Accepted only from this node's own peer.
@rpc("any_peer", "call_remote", "unreliable")
func net_swing(kind: int) -> void:
	if is_local or multiplayer.get_remote_sender_id() != peer_id:
		return
	var now := Time.get_ticks_msec()
	if now - _last_swing_fx_ms < 120:
		return  # Rate limit: a flood of swings cannot spam effects.
	_last_swing_fx_ms = now
	_play_swing_fx(clampi(kind, -1, SKILLS.size() - 1))


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
func _bot_think(delta: float) -> Vector2:
	_bot_t += delta
	var now := Time.get_ticks_msec()
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
				e.take_hit(damage, to.normalized(), peer_id)
			else:
				e.net_hit.rpc_id(1, kind, to.normalized(), _swing_serial)
			hits += 1
	if hits > 0 and is_local:
		# Juice on a landed blow: a tiny camera kick and a 60 ms hit-stop on
		# our own animation (never Engine.time_scale: that would be global).
		shake(0.12 if kind < 0 else 0.22)
		if _vrm != null:
			_vrm.hit_stop(0.06 if kind < 0 else 0.09)
	return hits


func _use_skill(i: int) -> void:
	var sk: Dictionary = SKILLS[i]
	skill_cd[i] = sk["cooldown"]
	_recovery = sk["recovery"]
	_play_swing_fx(i)
	if Net.online:
		net_swing.rpc(i)
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
			_hit_cone(GameState.attack_damage() * sk["mult"], sk["range"], sk["arc"], i))


## Offline / host: damages the local GameState. On the server for a remote
## player: the record owns HP (Net.srv_damage soaks, kills and respawns, and
## tells the owner through net_hp / net_apply "respawn"); nothing is trusted
## from the client. The buffed attack the server uses comes from
## Net.srv_attack_for (see _server_movement_check).
func take_damage(amount: float) -> void:
	if Net.online and multiplayer.is_server() and not is_local:
		Net.srv_damage(peer_id, amount)
		return
	if not is_local:
		return
	GameState.take_damage(amount)
	Audio.play("player_hit", null, 0.1)
	shake(clampf(0.15 + amount / 60.0, 0.15, 0.4))
	InputSetup.rumble(0.5, clampf(0.3 + amount / 40.0, 0.3, 1.0), 0.25)
	var fx := VFX.get_for(self)
	if fx:
		fx.hit(global_position + Vector3(0, 1.1, 0), -model.global_transform.basis.z, Color(1.0, 0.35, 0.3))
	if GameState.hp <= 0.0:
		Audio.play("teleport")
		respawn()


@rpc("any_peer", "call_remote", "reliable")
func net_take_damage(amount: float) -> void:
	if multiplayer.get_remote_sender_id() == 1 and is_local:
		take_damage(clampf(amount, 0.0, 1000.0))


## Generous upper bound on what a legit player of this level can hit for
## (base + maxed strength + a Mythical weapon). Kept as a sanity ceiling.
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


func respawn() -> void:
	# Respawn at the floor's arrival point (town plaza on Floor 1), like being sent back to a safe zone.
	global_position = GameState.spawn_point()
	velocity = Vector3.ZERO
	GameState.heal_full()
