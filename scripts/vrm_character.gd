class_name VRMCharacter
extends Node3D
## Anime character built from a real VRM body (godot-vrm addon, MToon shading)
## driven by KayKit humanoid clips retargeted at import time onto Godot's
## SkeletonProfileHumanoid (see assets/animations/kaykit_bonemap.tres).
##
## Same contract as CharacterModel: feet at y = 0, faces -Z, apply(config) is
## cheap on repeated calls (re-tints only when a colour changes, reloads only
## when "body" changes). Call animate() every tick for locomotion blending.

const BODIES := {
	"alicia": "res://assets/characters/AliciaSolid_vrm-0.51.vrm",
	"godette": "res://assets/characters/Godette_vrm_v4.vrm",
	"seed": "res://assets/characters/extra/Seed-san.vrm",
}
const DEFAULT_BODY := "alicia"
## Per-body tint rules checked against the material name before the generic
## heuristics in _classify: substring -> role ("" = never tint). Seed-san (VRM 1.0,
## VirtualCast) names its clothes "huku" and has robot-arm / backpack parts that
## must keep their own colours.
const TINT_RULES := {
	"seed": [["hair", "hair"], ["huku", "outfit"], ["body", "skin"], ["eye_trans", ""], ["eye", "eye"],
		["wear_metal", ""], ["armgear", ""], ["arm", ""], ["robo", ""], ["glass", ""], ["green", ""], ["logo", ""], ["backpack", ""]],
}

## Clip sources: role -> [glb path, clip name, loop]. Words follow assets/animations/roles.json.
const CLIP_DIR := "res://assets/animations/"
const CLIPS := {
	"idle": ["Rig_Medium_General.glb", "Idle_A", true],
	"walk": ["Rig_Medium_MovementBasic.glb", "Walking_A", true],
	"run": ["Rig_Medium_MovementBasic.glb", "Running_A", true],
	"jump": ["Rig_Medium_MovementBasic.glb", "Jump_Idle", true],
	"hit": ["Rig_Medium_General.glb", "Hit_A", false],
	"attack0": ["Rig_Medium_CombatMelee.glb", "Melee_1H_Attack_Slice_Horizontal", false],
	"attack1": ["Rig_Medium_CombatMelee.glb", "Melee_1H_Attack_Chop", false],
	"attack2": ["Rig_Medium_CombatMelee.glb", "Melee_1H_Attack_Slice_Diagonal", false],
	"attack3": ["Rig_Medium_CombatMelee.glb", "Melee_1H_Attack_Stab", false],
	"guard": ["Rig_Medium_CombatMelee.glb", "Melee_Blocking", true],
}
const WALK_SPEED := 1.8   # m/s at which the walk clip plays unscaled
const RUN_SPEED := 5.0    # m/s at which the run clip plays unscaled
const HEAD_LABEL_OFFSET := 0.32

## Humanoid bone names (SkeletonProfileHumanoid) exposed for IK / attachments.
const HUMANOID_BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]

static var _scene_cache := {}        # body key -> PackedScene
static var _clip_cache := {}         # glb file -> {scene, skeleton, player} kept alive
static var _library_cache := {}      # skeleton path + layout -> AnimationLibrary

var skeleton: Skeleton3D
var body_key := ""
var instance: Node3D            # the instantiated VRM scene (scaled, rotated)
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var bones := {}                 # humanoid bone name -> index in `skeleton`

var _mats := {}                 # role -> Array[ShaderMaterial or StandardMaterial3D]
var _applied := {}              # last colours applied, per role
var _speed_blend := 0.0
var _air_blend := 0.0
var _facing_forward := true
var _height := 1.0


func _ready() -> void:
	if instance == null:
		apply({})


# ------------------------------------------------------------------ apply --

func apply(c: Dictionary) -> void:
	var key := str(c.get("body", DEFAULT_BODY))
	if not BODIES.has(key):
		key = DEFAULT_BODY
	if key != body_key or instance == null:
		_load_body(key)
	if instance == null:
		return  # VRM file missing or failed to load; already reported.
	var h: float = clampf(float(c.get("height", 1.0)), 0.85, 1.15)
	if not is_equal_approx(h, _height):
		_height = h
		instance.scale = Vector3(h, h, h)
	for role in ["hair", "skin", "eye", "outfit"]:
		var ck: String = role + "_color"
		if c.has(ck):
			var col := Color(str(c[ck]))
			if not _applied.has(role) or _applied[role] != col:
				_applied[role] = col
				_tint(role, col)


func _load_body(key: String) -> void:
	if instance:
		instance.queue_free()
		instance = null
	skeleton = null
	anim_player = null
	anim_tree = null
	_mats.clear()
	_applied.clear()
	bones.clear()
	body_key = key
	if not _scene_cache.has(key):
		_scene_cache[key] = load(BODIES[key]) if ResourceLoader.exists(BODIES[key]) else null
	var ps: PackedScene = _scene_cache[key]
	if ps == null:
		push_error("VRMCharacter: could not load body " + key)
		return
	instance = ps.instantiate()
	instance.name = "VRM"
	add_child(instance)
	skeleton = instance.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if skeleton == null:
		skeleton = instance.find_child("*", true, false) as Skeleton3D
	if skeleton:
		for b in HUMANOID_BONES:
			var i := skeleton.find_bone(b)
			if i >= 0:
				bones[b] = i
	_collect_materials()
	_setup_animation()
	instance.scale = Vector3(_height, _height, _height)
	if _facing_forward:
		set_facing_forward()


## VRM bodies face +Z; the game treats -Z as forward.
func set_facing_forward() -> void:
	_facing_forward = true
	if instance:
		instance.rotation.y = PI


## Global position just above the head bone (for name labels / health bars).
func head_position() -> Vector3:
	if skeleton and bones.has("Head"):
		var p: Vector3 = skeleton.get_bone_global_pose(bones["Head"]).origin
		return skeleton.global_transform * p + Vector3.UP * HEAD_LABEL_OFFSET * _height
	return global_position + Vector3.UP * 1.75 * _height


## Global transform of a humanoid bone (e.g. "RightHand" for a held weapon).
func bone_global_transform(bone_name: String) -> Transform3D:
	if skeleton and bones.has(bone_name):
		return skeleton.global_transform * skeleton.get_bone_global_pose(bones[bone_name])
	return global_transform


# -------------------------------------------------------------- materials --

func _collect_materials() -> void:
	if skeleton == null:
		return
	for mi in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_name := String(mi.name).to_lower()
		for s in mi.get_surface_override_material_count():
			var m: Material = mi.get_active_material(s)
			if m == null:
				continue
			var role := _classify_body(String(m.resource_name).to_lower(), mesh_name)
			if role == "":
				continue
			var dup: Material = m.duplicate()
			dup.set_meta("vrm_base", _get_color(dup))
			dup.set_meta("vrm_base_shade", _get_shade(dup))
			mi.set_surface_override_material(s, dup)
			if not _mats.has(role):
				_mats[role] = []
			_mats[role].append(dup)


func _classify_body(mat: String, mesh: String) -> String:
	if TINT_RULES.has(body_key):
		for rule in TINT_RULES[body_key]:
			if rule[0] in mat:
				return rule[1]
	return _classify(mat, mesh)


func _classify(mat: String, mesh: String) -> String:
	var n := mat + " " + mesh
	if "hair" in n:
		return "hair"
	for w in ["eyeline", "eyelash", "eyebrow", "eyewhite", "eye_white", "highlight", "brow", "lash", "mastuge", "mouth", "teeth", "tongue", "logo", "backpack"]:
		if w in n:
			return ""
	if "eye" in n or "iris" in n or "pupil" in n:
		return "eye"
	for w in ["wear", "cloth", "tops", "bottoms", "onepiece", "outfit", "shoes", "shoe", "boot", "dress", "skirt", "shirt", "jacket", "accessory", "ribbon", "sock", "glove", "costume", "uniform"]:
		if w in n:
			return "outfit"
	if "face" in n or "skin" in n or "body" in n or "leg" in n or "arm" in n:
		return "skin"
	return ""


func _get_color(m: Material) -> Color:
	if m is ShaderMaterial:
		var v = m.get_shader_parameter("_Color")
		if v == null:
			v = m.get_shader_parameter("_MainColor")
		if v == null:
			v = m.get_shader_parameter("albedo")
		return v if v is Color else Color.WHITE
	elif m is BaseMaterial3D:
		return m.albedo_color
	return Color.WHITE


func _get_shade(m: Material) -> Color:
	if m is ShaderMaterial:
		var v = m.get_shader_parameter("_ShadeColor")
		return v if v is Color else Color.WHITE
	return Color.WHITE


## Multiply the material's base colour by a tint so the texture keeps detail.
func _tint(role: String, col: Color) -> void:
	if not _mats.has(role):
		return
	var factor: Color
	match role:
		"skin":
			# Textures already carry a skin tone; normalise against the default skin so
			# the default config leaves the model untouched.
			var ref := Color("f2d0b5")
			factor = Color(col.r / ref.r, col.g / ref.g, col.b / ref.b, 1.0)
		"hair":
			factor = col.lightened(0.1)
		"eye":
			factor = col.lightened(0.2)
		_:
			factor = col.lightened(0.1)
	for m in _mats[role]:
		var base: Color = m.get_meta("vrm_base", Color.WHITE)
		var c := Color(base.r * factor.r, base.g * factor.g, base.b * factor.b, base.a)
		if m is ShaderMaterial:
			m.set_shader_parameter("_Color", c)
			var bs: Color = m.get_meta("vrm_base_shade", Color.WHITE)
			m.set_shader_parameter("_ShadeColor", Color(bs.r * factor.r, bs.g * factor.g, bs.b * factor.b, bs.a))
		elif m is BaseMaterial3D:
			m.albedo_color = c


# -------------------------------------------------------------- animation --

## Keep each clip scene alive so its (profile-aligned) source skeleton can be
## used to re-bake clips onto a target skeleton.
static func _clip_source(file: String) -> Dictionary:
	if _clip_cache.has(file):
		return _clip_cache[file]
	var out := {}
	var ps = load(CLIP_DIR + file)
	if ps is PackedScene:
		var inst: Node = ps.instantiate()
		for n in inst.find_children("*", "Skeleton3D", true, false):
			out["skeleton"] = n
			break
		for n in inst.find_children("*", "AnimationPlayer", true, false):
			out["player"] = n
			break
		out["scene"] = inst
	if not out.has("skeleton") or not out.has("player"):
		push_warning("VRMCharacter: clip file has no skeleton/AnimationPlayer: " + file)
		out = {}
	_clip_cache[file] = out
	return out


## Bone indices parents-first (a VRM skeleton may list a child before its parent).
static func _bone_order(sk: Skeleton3D) -> Array[int]:
	var n := sk.get_bone_count()
	var order: Array[int] = []
	var done := {}
	while order.size() < n:
		var progressed := false
		for i in n:
			if done.has(i):
				continue
			var p := sk.get_bone_parent(i)
			if p < 0 or done.has(p):
				done[i] = true
				order.append(i)
				progressed = true
		if not progressed:
			break
	return order


static func _skeleton_signature(sk: Skeleton3D) -> String:
	var parts := PackedStringArray()
	for b in HUMANOID_BONES:
		var i := sk.find_bone(b)
		if i < 0:
			continue
		var q := sk.get_bone_rest(i).basis.get_rotation_quaternion()
		parts.append("%s:%d:%.2f,%.2f,%.2f,%.2f" % [b, sk.get_bone_parent(i), q.x, q.y, q.z, q.w])
	return str(hash("|".join(parts)))


## Re-bake a clip so its local rotations are right for `dst`: the KayKit rig
## has no Shoulder/UpperChest/Neck bones and has extra wrist bones, so local
## keys cannot be copied 1:1. Both skeletons are profile-aligned (rest axes
## overwritten at import), so global rotations in profile space transfer directly.
static func _bake(src: Animation, src_skel: Skeleton3D, dst: Skeleton3D, skel_path: String, loop: bool) -> Animation:
	var anim := Animation.new()
	anim.length = src.length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var src_n := src_skel.get_bone_count()
	var dst_n := dst.get_bone_count()
	# Source track lookup by bone name.
	var rot_tracks := {}
	var pos_tracks := {}
	for t in src.get_track_count():
		var bone := src.track_get_path(t).get_concatenated_subnames()
		match src.track_get_type(t):
			Animation.TYPE_ROTATION_3D:
				rot_tracks[bone] = t
			Animation.TYPE_POSITION_3D:
				pos_tracks[bone] = t
	# Destination tracks for humanoid bones present in both skeletons.
	var dst_tracks := {}   # dst bone idx -> track idx
	var src_of := {}       # dst bone idx -> src bone idx
	for i in dst_n:
		var name := dst.get_bone_name(i)
		var si := src_skel.find_bone(name)
		if si >= 0 and name in HUMANOID_BONES:
			src_of[i] = si
			var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(tr, NodePath(skel_path + ":" + name))
			dst_tracks[i] = tr
	var hips_dst := dst.find_bone("Hips")
	var hips_pos_track := -1
	if hips_dst >= 0 and pos_tracks.has("Hips"):
		hips_pos_track = anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(hips_pos_track, NodePath(skel_path + ":Hips"))
	var src_rest_q: Array[Quaternion] = []
	var src_parent: Array[int] = []
	for i in src_n:
		src_rest_q.append(src_skel.get_bone_rest(i).basis.get_rotation_quaternion())
		src_parent.append(src_skel.get_bone_parent(i))
	var dst_rest_q: Array[Quaternion] = []
	var dst_parent: Array[int] = []
	for i in dst_n:
		dst_rest_q.append(dst.get_bone_rest(i).basis.get_rotation_quaternion())
		dst_parent.append(dst.get_bone_parent(i))
	var step := 1.0 / 30.0
	var samples := int(ceil(src.length / step)) + 1
	var src_global: Array[Quaternion] = []
	src_global.resize(src_n)
	var dst_global: Array[Quaternion] = []
	dst_global.resize(dst_n)
	var src_order := _bone_order(src_skel)
	var dst_order := _bone_order(dst)
	for s in samples:
		var t := minf(s * step, src.length)
		for i in src_order:
			var name := src_skel.get_bone_name(i)
			var q: Quaternion = src.rotation_track_interpolate(rot_tracks[name], t) if rot_tracks.has(name) else src_rest_q[i]
			var p := src_parent[i]
			src_global[i] = (src_global[p] * q) if p >= 0 else q
		for i in dst_order:
			var p := dst_parent[i]
			var parent_g: Quaternion = dst_global[p] if p >= 0 else Quaternion.IDENTITY
			var g: Quaternion
			if src_of.has(i):
				g = src_global[src_of[i]]
				anim.rotation_track_insert_key(dst_tracks[i], t, (parent_g.inverse() * g).normalized())
			else:
				g = parent_g * dst_rest_q[i]
			dst_global[i] = g
		if hips_pos_track >= 0:
			anim.position_track_insert_key(hips_pos_track, t, src.position_track_interpolate(pos_tracks["Hips"], t))
	return anim


## Build (once per skeleton layout) a library whose tracks point at the VRM skeleton.
static func _library_for(dst: Skeleton3D, skel_path: String) -> AnimationLibrary:
	var key := skel_path + "#" + _skeleton_signature(dst)
	if _library_cache.has(key):
		return _library_cache[key]
	var lib := AnimationLibrary.new()
	for role in CLIPS:
		var spec: Array = CLIPS[role]
		var srcd := _clip_source(spec[0])
		if srcd.is_empty():
			continue
		var ap: AnimationPlayer = srcd["player"]
		if not ap.has_animation(spec[1]):
			push_warning("VRMCharacter: missing clip %s in %s" % [spec[1], spec[0]])
			continue
		lib.add_animation(role, _bake(ap.get_animation(spec[1]), srcd["skeleton"], dst, skel_path, spec[2]))
	_library_cache[key] = lib
	return lib


func _setup_animation() -> void:
	if skeleton == null:
		return
	var skel_path := String(instance.get_path_to(skeleton))
	var lib := _library_for(skeleton, skel_path)
	anim_player = AnimationPlayer.new()
	anim_player.name = "LocoPlayer"
	instance.add_child(anim_player)
	anim_player.root_node = anim_player.get_path_to(instance)
	anim_player.add_animation_library("", lib)

	var root := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = 2.0
	loco.sync = true
	for pair in [["idle", 0.0], ["walk", 1.0], ["run", 2.0]]:
		if lib.has_animation(pair[0]):
			var n := AnimationNodeAnimation.new()
			n.animation = pair[0]
			loco.add_blend_point(n, pair[1])
	root.add_node("loco", loco, Vector2(0, 0))
	var jump := AnimationNodeAnimation.new()
	jump.animation = "jump" if lib.has_animation("jump") else "idle"
	root.add_node("jump", jump, Vector2(0, 200))
	var air := AnimationNodeBlend2.new()
	root.add_node("air", air, Vector2(250, 0))
	root.connect_node("air", 0, "loco")
	root.connect_node("air", 1, "jump")
	var hit_anim := AnimationNodeAnimation.new()
	hit_anim.animation = "hit" if lib.has_animation("hit") else "idle"
	root.add_node("hit_anim", hit_anim, Vector2(250, 200))
	var hit := AnimationNodeOneShot.new()
	hit.fadein_time = 0.08
	hit.fadeout_time = 0.15
	root.add_node("hit", hit, Vector2(500, 0))
	# Guard stance (play_guard): blended over locomotion, under hits/attacks.
	var guard_anim := AnimationNodeAnimation.new()
	guard_anim.animation = "guard" if lib.has_animation("guard") else "idle"
	root.add_node("guard_anim", guard_anim, Vector2(250, 400))
	var guard := AnimationNodeBlend2.new()
	guard.filter_enabled = false
	root.add_node("guard", guard, Vector2(400, 0))
	root.connect_node("guard", 0, "air")
	root.connect_node("guard", 1, "guard_anim")
	root.connect_node("hit", 0, "guard")
	root.connect_node("hit", 1, "hit_anim")
	var atk_anim := AnimationNodeAnimation.new()
	atk_anim.animation = "attack0" if lib.has_animation("attack0") else "idle"
	root.add_node("attack_anim", atk_anim, Vector2(500, 200))
	var atk := AnimationNodeOneShot.new()
	atk.fadein_time = 0.06
	atk.fadeout_time = 0.2
	root.add_node("attack", atk, Vector2(750, 0))
	root.connect_node("attack", 0, "hit")
	root.connect_node("attack", 1, "attack_anim")
	root.connect_node("output", 0, "attack")

	anim_tree = AnimationTree.new()
	anim_tree.name = "LocoTree"
	anim_tree.tree_root = root
	instance.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.root_node = anim_tree.get_path_to(instance)
	anim_tree.active = true
	anim_tree.set("parameters/loco/blend_position", 0.0)
	anim_tree.set("parameters/air/blend_amount", 0.0)
	anim_tree.set("parameters/guard/blend_amount", 0.0)


## Drive locomotion. speed is horizontal m/s: 0 idle, < 4 walk, else run.
## Blend space: 0 = idle, 1 = walk, 2 = run.
func animate(delta: float, speed: float, grounded: bool) -> void:
	if anim_tree == null:
		return
	var target := 0.0
	if speed >= 4.0:
		target = 1.0 + clampf((speed - 4.0) / (RUN_SPEED - 4.0), 0.0, 1.0)
	elif speed > 0.05:
		target = clampf(speed / WALK_SPEED, 0.0, 1.0)
	_speed_blend = lerpf(_speed_blend, target, minf(delta * 10.0, 1.0))
	_air_blend = lerpf(_air_blend, 0.0 if grounded else 1.0, minf(delta * 8.0, 1.0))
	anim_tree.set("parameters/loco/blend_position", _speed_blend)
	anim_tree.set("parameters/air/blend_amount", _air_blend)


## One-shot melee swing. kind 0..3 picks horizontal slice / chop / diagonal / stab.
func play_attack(kind: int) -> void:
	if anim_tree == null:
		return
	var role := "attack%d" % clampi(kind, 0, 3)
	var root := anim_tree.tree_root as AnimationNodeBlendTree
	var n := root.get_node("attack_anim") as AnimationNodeAnimation
	if n and anim_player.has_animation(role):
		n.animation = role
	anim_tree.set("parameters/attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Raise or lower the guard (sword held across the body). Eased over
## ~0.1 s; locomotion keeps playing underneath at reduced weight.
var _guard_tw: Tween
func play_guard(on: bool) -> void:
	if anim_tree == null or not is_inside_tree():
		return
	if _guard_tw:
		_guard_tw.kill()
	_guard_tw = create_tween()
	_guard_tw.tween_property(anim_tree, "parameters/guard/blend_amount", 0.85 if on else 0.0, 0.1 if on else 0.18)


func play_hit() -> void:
	if anim_tree == null:
		return
	anim_tree.set("parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Hit-stop: freeze this character's animation for `seconds` (~60 ms) so a
## landed blow has weight. Local to this rig; never touches Engine.time_scale.
var _hit_stop_serial := 0
func hit_stop(seconds := 0.06) -> void:
	if anim_tree == null or not is_inside_tree():
		return
	_hit_stop_serial += 1
	var serial := _hit_stop_serial
	anim_tree.active = false
	get_tree().create_timer(seconds, false).timeout.connect(func():
		if serial == _hit_stop_serial and anim_tree != null and is_inside_tree():
			anim_tree.active = true)


## Length in seconds of an attack clip (for cooldown timing).
func attack_length(kind: int) -> float:
	var role := "attack%d" % clampi(kind, 0, 3)
	if anim_player and anim_player.has_animation(role):
		return anim_player.get_animation(role).length
	return 0.5


## Debug helper: list meshes and material names (for tuning the tint heuristics).
func describe() -> String:
	var out := "body=%s skeleton=%s bones=%d\n" % [body_key, instance.get_path_to(skeleton) if skeleton else "none", bones.size()]
	for mi in instance.find_children("*", "MeshInstance3D", true, false):
		for s in mi.get_surface_override_material_count():
			var m: Material = mi.get_active_material(s)
			var extra := ""
			if m is ShaderMaterial:
				var tex = m.get_shader_parameter("_MainTex")
				extra = " color=%s tex=%s mesh=%s" % [str(m.get_shader_parameter("_Color")), tex.resource_name if tex else "-", mi.mesh.resource_name if mi.mesh else "-"]
			out += "  %s[%d] %s (%s)%s\n" % [mi.name, s, m.resource_name if m else "null", m.get_class() if m else "", extra]
	for r in _mats:
		out += "  role %s: %d materials\n" % [r, _mats[r].size()]
	return out
