class_name NPC
extends StaticBody3D
## Talkable NPC. Gives one quest, then accepts its turn-in.
## Dialogue lines are data so writers can add NPCs without code.
##
## Look: every NPC stands on a real VRM body (VRMCharacter: alicia / godette /
## seed, tinted per role, KayKit idle clip) with a role prop in the right hand
## and a role tag under the name. A dedicated/headless server never renders,
## so there it keeps the cheap primitive CharacterModel, like the player does.

@export var npc_name := "Guide"
@export var appearance := {}
@export var quest_id := ""
@export var quest_goal := 5
@export var quest_xp := 150
@export var quest_money := 100
@export var lines := {
	"offer": "Hello, traveler.",
	"in_progress": "Keep at it.",
	"turn_in": "Thank you!",
	"done": "Good to see you again.",
}

const TALK_RANGE := 2.8
## Head turns toward a player closer than this (metres); eases back when alone.
const LOOK_RANGE := 7.0
const LOOK_YAW_MAX := 0.95
const LOOK_PITCH_MAX := 0.35

## Role table: VRM body, held prop, tag text and palette tweaks per NPC. The
## world's `appearance` dict (hair/outfit/eye colours, height) is kept and
## these entries overlay it, so a name missing here still gets a VRM body.
##   body: alicia | godette | seed      prop: hammer | rod | staff | spear | bow | lantern | ledger
const ROLES := {
	"Smith Haldor": {"body": "seed", "role": "Smith", "prop": "hammer", "outfit_color": "3a322c", "skin_color": "e3bc9a"},
	"Smith Orla": {"body": "seed", "role": "Smith", "prop": "hammer", "outfit_color": "2f2c2a"},
	"Guide Mira": {"body": "alicia", "role": "Guide", "prop": ""},
	"Captain Rhys": {"body": "godette", "role": "Captain", "prop": "spear"},
	"Huntmaster Sable": {"body": "alicia", "role": "Huntmaster", "prop": "bow", "outfit_color": "4a5a2e", "skin_color": "dcb08c"},
	"Keeper Ilsa": {"body": "alicia", "role": "Keeper", "prop": "staff", "outfit_color": "2e7a70", "hair_color": "eef0f6"},
	"Waykeeper Bran": {"body": "godette", "role": "Waykeeper", "prop": "lantern"},
	"Old Tam": {"body": "godette", "role": "Fisher", "prop": "rod"},
	"Fisher Maud": {"body": "alicia", "role": "Fisher", "prop": "rod"},
	"Trader Pell": {"body": "seed", "role": "Trader", "prop": "ledger"},
	"Elder Wren": {"body": "alicia", "role": "Elder", "prop": "staff", "hair_color": "d9d9dd", "skin_color": "e6c9b0"},
	"Quartermaster Dain": {"body": "seed", "role": "Quartermaster", "prop": "spear"},
	# Hollowbrook quest chain (Floor 1).
	"Trapper Vesna": {"body": "alicia", "role": "Trapper", "prop": "spear", "outfit_color": "5a4a32", "skin_color": "d9b08a"},
	"Herbalist Hesper": {"body": "alicia", "role": "Herbalist", "prop": "staff", "outfit_color": "4f6a3a", "hair_color": "b5651d"},
	"Innkeeper Rook": {"body": "seed", "role": "Innkeeper", "prop": "ledger", "outfit_color": "6a3a2a"},
	"Scout Fen": {"body": "godette", "role": "Scout", "prop": "lantern"},
}
## Godette is one palette-textured material (hair, clothes and skin share it),
## so it cannot be tinted per role: its NPCs keep the stock blue look.
const UNTINTABLE := ["godette"]
const ROLE_TAG_COLOR := Color(0.62, 0.86, 0.95)

## When set, called instead of the default quest talk. Returns the line to show.
var talk_override: Callable

var _model: Node3D
var _vrm: VRMCharacter
var _marker: Label3D
var _t := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _look_timer := 0.0
var _look_target: Node3D


func _ready() -> void:
	add_to_group("npcs")
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	var role: Dictionary = ROLES.get(npc_name, {})
	var look := appearance.duplicate()
	for k in role:
		if k.ends_with("_color") or k == "height":
			look[k] = role[k]
	look["body"] = role.get("body", VRMCharacter.BODIES.keys()[absi(hash(npc_name)) % VRMCharacter.BODIES.size()])
	if look["body"] in UNTINTABLE:
		for k in ["hair_color", "outfit_color", "skin_color", "eye_color"]:
			look.erase(k)
	# A dedicated/headless server never renders: skip the ~10 MB VRM scenes.
	var headless := Net.dedicated or DisplayServer.get_name() == "headless"
	if not headless and VRMCharacter.BODIES.has(str(look["body"])):
		_vrm = VRMCharacter.new()
		_model = _vrm
	else:
		_model = CharacterModel.new()
	_model.name = "Model"
	add_child(_model)
	_model.apply(look)
	if _vrm != null and _vrm.instance == null:
		# VRM failed to load (missing asset): fall back to the primitive body.
		_vrm.queue_free()
		_vrm = null
		_model = CharacterModel.new()
		_model.name = "Model"
		add_child(_model)
		_model.apply(look)
	if _vrm != null:
		# Seed-san carries a backpack-mounted robot arm that rests extended
		# sideways; it is an accessory (both real arms stay), so NPCs hide it.
		for mi in _vrm.instance.find_children("robo_arm", "MeshInstance3D", true, false):
			mi.visible = false
		_build_prop(str(role.get("prop", "")))
		# Runs after the AnimationTree wrote this frame's pose, so the look-at
		# yaw stacks on top of the idle clip instead of fighting it.
		process_priority = 5
	# Soft contact shadow so the figure sits on the ground.
	var disc := CylinderMesh.new()
	disc.top_radius = 0.45
	disc.bottom_radius = 0.45
	disc.height = 0.02
	disc.radial_segments = 20
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.05, 0.05, 0.1, 0.35)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material = dm
	var shadow := MeshInstance3D.new()
	shadow.mesh = disc
	shadow.position.y = 0.02
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	var h: float = clampf(float(look.get("height", 1.0)), 0.85, 1.15)
	var label := Label3D.new()
	label.text = npc_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.2 * h
	label.font_size = 40
	label.outline_size = 10
	label.modulate = Color(1, 0.93, 0.6)
	label.outline_modulate = Color(0.12, 0.08, 0.2, 0.9)
	add_child(label)
	var tag := str(role.get("role", ""))
	if tag != "":
		# Role tag under the name, styled like the player's PARTY tag.
		var rl := Label3D.new()
		rl.text = tag.to_upper()
		rl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		rl.position.y = 2.2 * h - 0.24
		rl.font_size = 22
		rl.outline_size = 6
		rl.modulate = ROLE_TAG_COLOR
		rl.outline_modulate = Color(0.12, 0.08, 0.2, 0.9)
		add_child(rl)
	if quest_id != "":
		# Golden quest marker bobbing over the head, JRPG style.
		_marker = Label3D.new()
		_marker.text = "!"
		_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_marker.position.y = 2.75
		_marker.font_size = 96
		_marker.outline_size = 14
		_marker.modulate = Color(1.0, 0.82, 0.2)
		_marker.outline_modulate = Color(0.35, 0.18, 0.0)
		add_child(_marker)
	if _vrm == null:
		# Gentle idle breathing so the primitive body does not read as a statue
		# (the VRM body plays the KayKit idle clip instead).
		var tw := create_tween().set_loops()
		tw.tween_property(_model, "scale:y", _model.scale.y * 1.03, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_model, "scale:y", _model.scale.y, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _process(delta: float) -> void:
	if _marker != null:
		_t += delta
		_marker.position.y = 2.75 + sin(_t * 2.4) * 0.12
	if _vrm != null:
		_look(delta)


## Head turn toward the nearest player in LOOK_RANGE, stacked on the idle pose.
func _look(delta: float) -> void:
	var sk := _vrm.skeleton
	if sk == null or not _vrm.bones.has("Head"):
		return
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = 0.25
		_look_target = null
		var best := LOOK_RANGE
		for p in get_tree().get_nodes_in_group("players"):
			if not (p is Node3D):
				continue
			var d: float = p.global_position.distance_to(global_position)
			if d < best:
				best = d
				_look_target = p
	var want_yaw := 0.0
	var want_pitch := 0.0
	if _look_target != null and is_instance_valid(_look_target):
		var head_i: int = _vrm.bones["Head"]
		var head_local: Vector3 = sk.get_bone_global_pose(head_i).origin
		var local: Vector3 = sk.global_transform.affine_inverse() * (_look_target.global_position + Vector3.UP * 1.45)
		var rel := local - head_local
		# Skeleton space faces +Z; yaw turns +Z toward +X, pitch > 0 looks down.
		var yaw := atan2(rel.x, rel.z)
		if absf(yaw) < 1.6:
			want_yaw = clampf(yaw, -LOOK_YAW_MAX, LOOK_YAW_MAX)
			want_pitch = clampf(-atan2(rel.y, Vector2(rel.x, rel.z).length()), -LOOK_PITCH_MAX, LOOK_PITCH_MAX)
	var k := minf(delta * 4.0, 1.0)
	_look_yaw = lerpf(_look_yaw, want_yaw, k)
	_look_pitch = lerpf(_look_pitch, want_pitch, k)
	if absf(_look_yaw) < 0.002 and absf(_look_pitch) < 0.002:
		return
	var hi: int = _vrm.bones["Head"]
	var q := sk.get_bone_pose_rotation(hi)
	sk.set_bone_pose_rotation(hi, (q * Quaternion(Vector3.UP, _look_yaw) * Quaternion(Vector3.RIGHT, _look_pitch)).normalized())


# ------------------------------------------------------------------ props --

## Role prop hung off the humanoid RightHand bone, like the player's sword:
## the grip pivot puts -Z out of the fist. Simple toon primitives.
func _build_prop(kind: String) -> void:
	if kind == "" or _vrm.skeleton == null or not _vrm.bones.has("RightHand"):
		return
	var att := BoneAttachment3D.new()
	att.name = "PropAttach"
	att.bone_name = "RightHand"
	_vrm.skeleton.add_child(att)
	var pivot := Node3D.new()
	pivot.rotation_degrees = Vector3(0, -90, -20)
	att.add_child(pivot)
	var prop := Node3D.new()
	prop.name = "Prop"
	pivot.add_child(prop)
	var wood := ToonMaterial.part(Color(0.45, 0.3, 0.16), 0.012)
	var dark_wood := ToonMaterial.part(Color(0.3, 0.2, 0.11), 0.012)
	var steel := ToonMaterial.part(Color(0.66, 0.7, 0.78), 0.012)
	var dark_steel := ToonMaterial.part(Color(0.3, 0.32, 0.38), 0.012)
	var leather := ToonMaterial.part(Color(0.3, 0.18, 0.1), 0.012)
	var brass := ToonMaterial.part(Color(0.85, 0.68, 0.25), 0.012)
	match kind:
		"hammer":
			# Smith's hammer: short haft, blocky head, held out of the fist.
			_pp(prop, _cyl(0.016, 0.02, 0.42), leather, Vector3(0, 0, -0.12), Vector3(PI / 2, 0, 0))
			_pp(prop, _bx(0.085, 0.085, 0.16), dark_steel, Vector3(0, 0, -0.34))
			_pp(prop, _cyl(0.045, 0.045, 0.03), steel, Vector3(0, 0, -0.34), Vector3(0, 0, PI / 2), Vector3(1, 1, 1))
			_pp(prop, _bx(0.03, 0.03, 0.17), brass, Vector3(0, 0, -0.34))
		"rod":
			# Fishing rod rested upright like a staff, a line down to a cork bobber.
			prop.rotation_degrees = Vector3(90, 0, 0)
			_pp(prop, _cyl(0.006, 0.014, 1.7), wood, Vector3(0, 0, -0.7), Vector3(PI / 2, 0, 0))
			_pp(prop, _cyl(0.016, 0.016, 0.22), leather, Vector3(0, 0, 0.05), Vector3(PI / 2, 0, 0))
			_pp(prop, _cyl(0.012, 0.012, 0.03), brass, Vector3(0, 0, -0.2), Vector3(PI / 2, 0, 0))
			var tipn := Node3D.new()
			tipn.position = Vector3(0, 0, -1.55)
			tipn.rotation_degrees = Vector3(-90, 0, 0)  # line hangs straight down
			prop.add_child(tipn)
			_pp(tipn, _cyl(0.003, 0.003, 0.9), ToonMaterial.part(Color(0.9, 0.9, 0.95), 0.0), Vector3(0, -0.45, 0))
			_pp(tipn, _sph(0.03), ToonMaterial.part(Color(0.9, 0.25, 0.2), 0.008), Vector3(0, -0.9, 0), Vector3.ZERO, Vector3(1, 1.4, 1))
			_pp(tipn, _sph(0.03), ToonMaterial.part(Color(0.95, 0.95, 0.9), 0.008), Vector3(0, -0.94, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
		"staff":
			# Keeper / elder staff planted at the side, orb at the top.
			prop.rotation_degrees = Vector3(90, 0, 0)
			_pp(prop, _cyl(0.018, 0.024, 1.75), dark_wood, Vector3(0, 0, -0.38), Vector3(PI / 2, 0, 0))
			for i in 3:
				_pp(prop, _cyl(0.026, 0.026, 0.02), brass, Vector3(0, 0, -1.08 - i * 0.05), Vector3(PI / 2, 0, 0))
			_pp(prop, _sph(0.06), ToonMaterial.part(Color(0.55, 0.95, 0.85), 0.0, Color(0.4, 0.95, 0.8), 1.6), Vector3(0, 0, -1.3))
			_pp(prop, _cyl(0.0, 0.05, 0.1), brass, Vector3(0, 0, -1.22), Vector3(PI / 2, 0, 0))
		"spear":
			# Guard spear held upright, leaf blade and a red tassel.
			prop.rotation_degrees = Vector3(90, 0, 0)
			_pp(prop, _cyl(0.012, 0.015, 2.0), wood, Vector3(0, 0, -0.5), Vector3(PI / 2, 0, 0))
			_pp(prop, _cyl(0.0, 0.035, 0.26), steel, Vector3(0, 0, -1.62), Vector3(PI / 2, 0, 0))
			_pp(prop, _cyl(0.03, 0.03, 0.04), brass, Vector3(0, 0, -1.48), Vector3(PI / 2, 0, 0))
			_pp(prop, _bx(0.07, 0.05, 0.015), ToonMaterial.part(Color(0.7, 0.15, 0.1), 0.0), Vector3(0, -0.03, -1.44))
		"bow":
			# Hunting bow held upright: two limbs meeting at the grip, string behind.
			prop.rotation_degrees = Vector3(90, 0, 0)
			_pp(prop, _cyl(0.014, 0.018, 0.22), leather, Vector3(0, 0, 0), Vector3(PI / 2, 0, 0))
			for s: float in [-1.0, 1.0]:
				var limb := Node3D.new()
				limb.position = Vector3(0, 0, s * 0.1)
				limb.rotation_degrees = Vector3(s * -14, 0, 0)
				prop.add_child(limb)
				_pp(limb, _cyl(0.008, 0.016, 0.62), dark_wood, Vector3(0, 0, s * 0.31), Vector3(PI / 2, 0, 0))
				_pp(limb, _cyl(0.0, 0.012, 0.08), brass, Vector3(0, 0, s * 0.64), Vector3(PI / 2 if s > 0 else -PI / 2, 0, 0))
			_pp(prop, _bx(0.004, 0.004, 1.3), ToonMaterial.part(Color(0.9, 0.88, 0.8), 0.0), Vector3(0, 0.17, 0))
		"lantern":
			# Waykeeper's lantern held out in front on a short hook.
			_pp(prop, _cyl(0.01, 0.01, 0.3), dark_steel, Vector3(0, 0, -0.15), Vector3(PI / 2, 0, 0))
			var hang := Node3D.new()
			hang.position = Vector3(0, 0, -0.3)
			prop.add_child(hang)
			_pp(hang, _cyl(0.012, 0.012, 0.12), dark_steel, Vector3(0, -0.06, 0))
			_pp(hang, _bx(0.11, 0.18, 0.11), ToonMaterial.part(Color(0.98, 0.82, 0.45), 0.0, Color(1.0, 0.7, 0.3), 2.2), Vector3(0, -0.2, 0))
			_pp(hang, _bx(0.14, 0.02, 0.14), dark_steel, Vector3(0, -0.1, 0))
			_pp(hang, _bx(0.14, 0.02, 0.14), dark_steel, Vector3(0, -0.3, 0))
			for k in 4:
				var a := TAU * k / 4.0 + PI / 4.0
				_pp(hang, _bx(0.012, 0.2, 0.012), dark_steel, Vector3(cos(a) * 0.075, -0.2, sin(a) * 0.075))
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.75, 0.4)
			l.light_energy = 0.7
			l.omni_range = 3.0
			l.shadow_enabled = false
			l.position = Vector3(0, -0.2, 0)
			hang.add_child(l)
		"ledger":
			# Trader's ledger held flat in the palm, a quill tucked in.
			_pp(prop, _bx(0.18, 0.035, 0.24), leather, Vector3(0, 0, -0.1), Vector3(0, 0, 0.35))
			_pp(prop, _bx(0.165, 0.028, 0.225), ToonMaterial.part(Color(0.95, 0.92, 0.82), 0.0), Vector3(0, 0.002, -0.1), Vector3(0, 0, 0.35))
			_pp(prop, _bx(0.03, 0.045, 0.24), brass, Vector3(-0.08, 0, -0.1), Vector3(0, 0, 0.35))
			_pp(prop, _cyl(0.004, 0.006, 0.22), ToonMaterial.part(Color(0.92, 0.92, 0.95), 0.0), Vector3(0.02, 0.04, -0.14), Vector3(0.9, 0, 0.5))
		_:
			pass


func _pp(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _sph(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	return m


func _bx(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 12
	return m


# ------------------------------------------------------------------- talk --

func in_range(p: Node3D) -> bool:
	return p.global_position.distance_to(global_position) < TALK_RANGE


## Returns the line to show and updates quest state.
func talk() -> String:
	if talk_override.is_valid():
		return talk_override.call()
	if quest_id == "":
		return lines["offer"]
	if not GameState.quests.has(quest_id):
		GameState.start_quest(quest_id, quest_goal)
		return lines["offer"]
	if GameState.quest_ready(quest_id):
		GameState.complete_quest(quest_id)
		GameState.add_xp(quest_xp)
		GameState.add_money(quest_money)
		return "%s\n(+%d XP, +%d Col)" % [lines["turn_in"], quest_xp, quest_money]
	if GameState.quests[quest_id]["done"]:
		return lines["done"]
	return lines["in_progress"]
