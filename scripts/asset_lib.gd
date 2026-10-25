class_name AssetLib
extends RefCounted
## Loader for the CC0 / permissive packs under res://assets/ (see
## assets/LICENSES.md): Poly Haven sky HDRIs and PBR textures, Kenney and
## KayKit glTF props, Kenney particle sprites. Everything is cached, so
## hundreds of props share one PackedScene, one material and one mesh.
##
##   AssetLib.apply_sky(env, "day")                      # HDRI panorama sky
##   var grass := AssetLib.pbr("aerial_grass_rock", 0.25) # tiling PBR material
##   AssetLib.prop(self, "nature", "tree_oak", Vector3(4, 0, 2), 0.3, 2.0)
##   AssetLib.multi(self, "nature", "grass_large", xforms)  # MultiMesh batch
##
## Props are converted to the game's anime look on load: toon diffuse and
## specular on their StandardMaterial3Ds plus an ink outline pass, so Kenney
## and KayKit models sit next to the cel-shaded characters without a clash.

const HDRI := {
	"day": "res://assets/hdri/kloofendal_48d_partly_cloudy_puresky_4k.hdr",
	"sunset": "res://assets/hdri/kloppenheim_06_puresky_2k.hdr",
	"dusk": "res://assets/hdri/qwantani_dusk_2_puresky_2k.hdr",
	"night": "res://assets/hdri/kloppenheim_02_puresky_2k.hdr",
}

## Poly Haven texture sets (2k, diffuse + GL normal + ARM) in assets/textures/.
const TEXTURES := [
	"aerial_grass_rock", "grass_path_2", "forest_floor", "brown_mud_leaves_01",
	"gravel_road", "cobblestone_floor_08", "castle_brick_07", "rock_wall_10",
	"beige_wall_001", "weathered_planks", "wood_planks_grey", "bark_willow", "roof_tiles_14",
]

## Prop packs: pack key -> path pattern. Names are the file names without extension.
const PACKS := {
	"town": "res://assets/props/fantasy_town/%s.glb",      # Kenney Fantasy Town Kit 2.0
	"nature": "res://assets/props/nature/%s.glb",          # Kenney Nature Kit 2.1
	"castle": "res://assets/props/castle/%s.glb",          # Kenney Castle Kit
	"survival": "res://assets/props/survival/%s.glb",      # Kenney Survival Kit
	"graveyard": "res://assets/props/graveyard/%s.glb",    # Kenney Graveyard Kit 5.0
	"mini_dungeon": "res://assets/props/mini_dungeon/%s.glb",  # Kenney Mini Dungeon
	"dungeon": "res://assets/props/dungeon/%s.gltf.glb",   # KayKit Dungeon Remastered
	"hex": "res://assets/props/hex_medieval/%s.gltf",      # KayKit Medieval Hexagon Pack
	# Creature packs: a directory, searched for name.glb / .gltf / .fbx (see assets/CREATURES.md).
	"animals": "res://assets/props/animals/",              # Quaternius animated animals (FBX) + Kenney Cube Pets (cube_pets/)
	"creatures": "res://assets/props/creatures/",          # Quaternius monsters/easy enemies (FBX) + Bestiary (bestiary/*.glb)
	"adventurers": "res://assets/characters/packs/adventurers/",  # KayKit rigged humanoids (Knight, Mage, Rogue, Barbarian, Ranger)
	"skeletons": "res://assets/characters/packs/skeletons/",      # KayKit rigged skeletons (Minion, Mage, Rogue, Warrior)
}
const MODEL_EXTS := ["glb", "gltf", "fbx"]

const VFX_DIR := "res://assets/vfx/"

## Kenney's Nature Kit palette is teal; these overrides (by glTF material
## name) pull foliage and grass toward the game's anime greens. Edit freely.
const PALETTE := {
	"leafsGreen": Color("6cc24a"), "leafsDark": Color("3f9a3a"), "grass": Color("7fd35a"),
	"stone": Color("b9c0c8"), "stoneDark": Color("8b929c"), "water": Color("8fe0f0"),
	"leafsFall": Color("e07a2a"), "woodBirch": Color("d8cdb8"),  # Floor 2 autumn trees (tinted per kind in Floor2Art)
}
const OUTLINE_WIDTH := 0.018

static var _scenes := {}
static var _meshes := {}
static var _materials := {}
static var _pbr := {}
static var _skies := {}
static var _toon_mats := {}


# --- Sky ---------------------------------------------------------------------

## HDRI panorama Sky resource (cached per name).
static func sky(name := "day") -> Sky:
	if _skies.has(name):
		return _skies[name]
	var path: String = HDRI.get(name, HDRI["day"])
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	var s := Sky.new()
	if tex == null:
		push_warning("AssetLib: HDRI %s missing, using procedural sky" % path)
		s.sky_material = ProceduralSkyMaterial.new()
	else:
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = tex
		pm.filter = true
		s.sky_material = pm
	s.radiance_size = Sky.RADIANCE_SIZE_256
	s.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	_skies[name] = s
	return s


## Switches an Environment to an HDRI sky with sky-driven ambient/reflections.
static func apply_sky(env: Environment, name := "day", energy := 1.0, rotation_deg := 0.0) -> void:
	env.background_mode = Environment.BG_SKY
	env.sky = sky(name)
	env.sky_rotation = Vector3(0, deg_to_rad(rotation_deg), 0)
	env.background_energy_multiplier = energy
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY


## Sun direction that roughly matches each HDRI (sun azimuth/elevation).
static func sun_rotation(name := "day") -> Vector3:
	match name:
		"sunset": return Vector3(deg_to_rad(-12), deg_to_rad(118), 0)
		"dusk": return Vector3(deg_to_rad(-8), deg_to_rad(-70), 0)
		"night": return Vector3(deg_to_rad(-55), deg_to_rad(40), 0)
	return Vector3(deg_to_rad(-52), deg_to_rad(32), 0)


# --- PBR materials -------------------------------------------------------------

## Tiling PBR material from a Poly Haven set. uv_scale = repeats per metre.
## triplanar = true projects without UVs (terrain, rocks, procedural meshes).
static func pbr(name: String, uv_scale := 0.5, triplanar := false, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "%s|%.3f|%s|%s" % [name, uv_scale, triplanar, tint.to_html()]
	if _pbr.has(key):
		return _pbr[key]
	var dir := "res://assets/textures/%s/" % name
	var m := StandardMaterial3D.new()
	var diff := _tex(dir + name + "_diffuse_2k.jpg")
	var nor := _tex(dir + name + "_nor_gl_2k.jpg")
	var arm := _tex(dir + name + "_arm_2k.jpg")
	if diff == null:
		push_warning("AssetLib: texture set %s missing" % name)
		m.albedo_color = Color(0.6, 0.6, 0.6)
	else:
		m.albedo_texture = diff
	m.albedo_color = tint
	if nor:
		m.normal_enabled = true
		m.normal_texture = nor
		m.normal_scale = 1.0
	if arm:
		# Poly Haven ARM = ambient occlusion (R), roughness (G), metallic (B).
		m.ao_enabled = true
		m.ao_texture = arm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness_texture = arm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = arm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.metallic = 1.0
	m.roughness = 1.0
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	m.uv1_triplanar = triplanar
	m.uv1_world_triplanar = triplanar
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_pbr[key] = m
	return m


static func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


## One raw map of a Poly Haven set for custom shaders: kind is "diffuse",
## "nor_gl" or "arm". Null when the set is missing.
static func texture_map(name: String, kind := "diffuse") -> Texture2D:
	return _tex("res://assets/textures/%s/%s_%s_2k.jpg" % [name, name, kind])


static var _lum_cache := {}

## Mean luminance (0..1) of a texture, sampled on a coarse grid. Lets a shader
## treat the map as a modulation around 1.0 instead of darkening everything.
static func texture_mean_luminance(tex: Texture2D, fallback := 0.5) -> float:
	if tex == null:
		return fallback
	var key := tex.get_instance_id()
	if _lum_cache.has(key):
		return _lum_cache[key]
	var img := tex.get_image()
	var out := fallback
	if img != null and img.get_width() > 0:
		if img.is_compressed():
			img.decompress()
		var sum := 0.0
		var n := 24
		for y in n:
			for x in n:
				var c := img.get_pixel(int((x + 0.5) * img.get_width() / n), int((y + 0.5) * img.get_height() / n))
				sum += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
		out = sum / float(n * n)
	_lum_cache[key] = out
	return out


# --- Props -------------------------------------------------------------------

static func prop_path(pack: String, name: String) -> String:
	var pat: String = PACKS[pack]
	if pat.contains("%s"):
		return pat % name
	# Directory pack: name may include a subfolder (e.g. "quaternius_fbx/Wolf").
	for ext in MODEL_EXTS:
		var candidate: String = pat + name + "." + ext
		if ResourceLoader.exists(candidate):
			return candidate
	for sub in ["quaternius_fbx/", "cube_pets/", "bestiary/"]:
		for ext in MODEL_EXTS:
			var candidate: String = pat + sub + name + "." + ext
			if ResourceLoader.exists(candidate):
				return candidate
	return pat + name + ".glb"


static func has_prop(pack: String, name: String) -> bool:
	return PACKS.has(pack) and ResourceLoader.exists(prop_path(pack, name))


## Cached PackedScene for a prop.
static func scene(pack: String, name: String) -> PackedScene:
	var path := prop_path(pack, name)
	if _scenes.has(path):
		return _scenes[path]
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if ps == null:
		push_warning("AssetLib: prop %s/%s not found (%s)" % [pack, name, path])
	_scenes[path] = ps
	return ps


## Instances a prop under parent. collide: "trimesh" (default, exact),
## "box" (AABB), "trunk" (thin cylinder for trees), or "none".
## Places one prop. With `batching` on (the default during a world build) the
## prop is not instanced: the returned Node3D is an empty placeholder named
## like the prop that carries its collision, and flush_batches() bakes its
## mesh, at whatever transform the placeholder ends up with, into a shared
## ArrayMesh at the end of the frame (see "Static prop batching" below).
## `tint` multiplies every surface's albedo (Kenney kits use one atlas, so this
## recolours the whole piece); `batch = false` forces a live instance (needed
## when the caller animates or inspects the prop's own nodes, e.g. houses).
static func prop(parent: Node, pack: String, name: String, pos: Vector3, rot_y := 0.0, scl := 1.0, collide := "trimesh", toon := true, tint := Color.WHITE, batch := true) -> Node3D:
	if batching and batch:
		return _batched_prop(parent, pack, name, pos, rot_y, scl, collide, toon, tint)
	var ps := scene(pack, name)
	if ps == null:
		return null
	var inst: Node3D = ps.instantiate()
	inst.name = name
	inst.position = pos
	inst.rotation.y = rot_y
	inst.scale = Vector3.ONE * scl
	parent.add_child(inst)
	if toon:
		toonify(inst)
	if tint != Color.WHITE:
		var parts: Array = []
		_collect_meshes(inst, parts)
		for mi in parts:
			for si in mi.mesh.get_surface_count():
				var src: Material = mi.get_active_material(si)
				if src:
					mi.set_surface_override_material(si, tinted_material(src, tint))
	if collide != "none":
		add_collision(inst, collide)
	return inst


## Instances a rigged/animated creature (no collision, never batched, toon
## look applied) and returns [instance, AnimationPlayer or null]. Animation
## names are listed in assets/CREATURES.md (Quaternius FBX clips look like
## "Armature|Slime_Idle"). Quaternius FBX models are authored ~3-4x life
## size; FBX_SCALE brings a wolf to ~1 m at scl = 1.0.
const FBX_SCALE := 0.3

static func creature(parent: Node, pack: String, name: String, pos: Vector3, rot_y := 0.0, scl := 1.0, toon := true) -> Array:
	var path := prop_path(pack, name)
	if path.ends_with(".fbx"):
		scl *= FBX_SCALE
	var inst := prop(parent, pack, name, pos, rot_y, scl, "none", toon, Color.WHITE, false)
	if inst == null:
		return [null, null]
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	return [inst, aps[0] if aps.size() > 0 else null]


## Plays the first animation whose name contains `needle` (case-insensitive).
static func play_clip(ap: AnimationPlayer, needle: String, loop := true, blend := 0.2) -> bool:
	if ap == null:
		return false
	for n in ap.get_animation_list():
		if n.to_lower().contains(needle.to_lower()):
			var anim := ap.get_animation(n)
			anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
			ap.play(n, blend)
			return true
	return false


# --- Static prop batching -----------------------------------------------------------
## A Kenney/KayKit prop scene is 1-6 MeshInstance3Ds, each a draw call (two
## with the outline pass). A floor places a few hundred one-offs, so instead
## every prop placed through prop() while `batching` is on becomes a
## placeholder and, once per frame, flush_batches() merges all pending props
## into one MeshInstance3D per parent, size class and BATCH_CELL-metre cell,
## one surface per distinct material. Collision shapes are built from the same
## cached mesh, so gameplay is unchanged. Size classes (longest world-space
## side): tiny (< TINY_SIZE m) drops the outline pass and shadows, tiny and
## small (< SMALL_SIZE m) batches cull by distance (RenderProfile.prop_cull).

static var batching := true
const BATCH_CELL := 48.0
const SMALL_CELL := 24.0
const TINY_SIZE := 1.0
const SMALL_SIZE := 2.6
const LOD_TINY := 70.0
const LOD_SMALL := 120.0
static var _pending: Array = []
static var _flush_queued := false
static var _no_outline := {}
static var _tint_mats := {}
## Counters for the --stats harness / report.
static var batched_props := 0
static var batch_meshes := 0


static func _batched_prop(parent: Node, pack: String, name: String, pos: Vector3, rot_y: float, scl: float, collide: String, toon: bool, tint: Color) -> Node3D:
	var m := mesh(pack, name, toon)
	if m == null:
		return null
	var ph := Node3D.new()
	ph.name = name
	ph.position = pos
	ph.rotation.y = rot_y
	ph.scale = Vector3.ONE * scl
	parent.add_child(ph)
	ph.set_meta("batch_mesh", m)
	ph.set_meta("batch_tint", tint)
	if collide != "none":
		_collision_for_mesh(ph, m, collide)
	_pending.append(ph)
	if not _flush_queued:
		_flush_queued = true
		(func(): AssetLib.flush_batches()).call_deferred()
	return ph


## Same shapes add_collision() would build from the live instance.
static func _collision_for_mesh(ph: Node3D, m: Mesh, mode: String) -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	ph.add_child(body)
	var cs := CollisionShape3D.new()
	var box := m.get_aabb()
	match mode:
		"trimesh":
			cs.shape = m.create_trimesh_shape()
		"trunk":
			var cyl := CylinderShape3D.new()
			cyl.radius = maxf(0.15, minf(box.size.x, box.size.z) * 0.12)
			cyl.height = box.size.y
			cs.shape = cyl
			cs.position = box.get_center()
		_:
			var bs := BoxShape3D.new()
			bs.size = box.size
			cs.shape = bs
			cs.position = box.get_center()
	body.add_child(cs)


static func _without_outline(m: Material) -> Material:
	if m == null or m.next_pass == null:
		return m
	var id := m.get_instance_id()
	if not _no_outline.has(id):
		var c: Material = m.duplicate()
		c.next_pass = null
		_no_outline[id] = c
	return _no_outline[id]


## Copy of a pack material with its albedo multiplied by tint. Cached.
static func tinted_material(src: Material, tint: Color) -> Material:
	if tint == Color.WHITE or not (src is BaseMaterial3D):
		return src
	var key := "%d|%s" % [src.get_instance_id(), tint.to_html()]
	if _tint_mats.has(key):
		return _tint_mats[key]
	var m: BaseMaterial3D = src.duplicate()
	m.albedo_color = src.albedo_color * tint
	m.next_pass = src.next_pass
	_tint_mats[key] = m
	return m


## Bakes every pending placeholder into per-cell ArrayMeshes. Runs deferred
## after the frame that placed them; safe to call directly too.
static func flush_batches() -> void:
	_flush_queued = false
	if _pending.is_empty():
		return
	var groups := {}
	for ph in _pending:
		if not is_instance_valid(ph) or not ph.is_inside_tree() or not ph.has_meta("batch_mesh"):
			continue
		var parent := ph.get_parent() as Node3D
		if parent == null:
			continue
		var m: Mesh = ph.get_meta("batch_mesh")
		var tint: Color = ph.get_meta("batch_tint")
		ph.remove_meta("batch_mesh")
		ph.set_meta("batched", true)
		var xf: Transform3D = parent.global_transform.affine_inverse() * ph.global_transform
		var aabb: AABB = xf * m.get_aabb()
		var longest: float = aabb.size[aabb.get_longest_axis_index()]
		var cls := 0 if longest < TINY_SIZE else (1 if longest < SMALL_SIZE else 2)
		var cell := BATCH_CELL if cls == 2 else SMALL_CELL
		var c := aabb.get_center()
		var key := "%d|%d|%d|%d" % [parent.get_instance_id(), cls, floori(c.x / cell), floori(c.z / cell)]
		if not groups.has(key):
			groups[key] = {"parent": parent, "cls": cls, "cell": Vector2i(floori(c.x / cell), floori(c.z / cell)), "mats": {}, "tools": {}, "count": 0}
		var g: Dictionary = groups[key]
		g["count"] += 1
		for si in m.get_surface_count():
			var mat: Material = tinted_material(m.surface_get_material(si), tint)
			if cls == 0:
				mat = _without_outline(mat)
			var mk := mat.get_instance_id() if mat else 0
			if not g["tools"].has(mk):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				g["tools"][mk] = st
				g["mats"][mk] = mat
			g["tools"][mk].append_from(m, si, xf)
	_pending.clear()
	for key in groups:
		var g: Dictionary = groups[key]
		var am := ArrayMesh.new()
		for mk in g["tools"]:
			var st: SurfaceTool = g["tools"][mk]
			st.set_material(g["mats"][mk])
			st.commit(am)
		var mi := MeshInstance3D.new()
		mi.name = "Batch_%s_%d_%d" % [["tiny", "small", "large"][g["cls"]], g["cell"].x, g["cell"].y]
		mi.mesh = am
		if g["cls"] == 0:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			RenderProfile.register_lod(mi, LOD_TINY)
		elif g["cls"] == 1:
			RenderProfile.register_lod(mi, LOD_SMALL)
		g["parent"].add_child(mi)
		batched_props += g["count"]
		batch_meshes += 1


## Places many copies of one prop as a MultiMesh (vegetation, rocks, fences).
static func multi(parent: Node, pack: String, name: String, xforms: Array, toon := true, shadows := true) -> MultiMeshInstance3D:
	var m := mesh(pack, name, toon)
	if m == null:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_" + name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	# Undergrowth honours the preset's foliage density (visible_instance_count).
	for prefix in ["flower_", "plant_", "mushroom_", "grass"]:
		if name.begins_with(prefix):
			RenderProfile.register_foliage(mmi)
			break
	return mmi


## First mesh of a prop, with the prop's node transform baked in and (if toon)
## the anime material treatment applied. Cached.
static func mesh(pack: String, name: String, toon := true) -> Mesh:
	var key := "%s/%s/%s" % [pack, name, toon]
	if _meshes.has(key):
		return _meshes[key]
	var ps := scene(pack, name)
	if ps == null:
		return null
	var inst: Node3D = ps.instantiate()
	var found: Mesh = null
	var parts: Array = []
	_collect_meshes(inst, parts)
	if parts.size() == 1:
		var mi: MeshInstance3D = parts[0]
		found = mi.mesh
		if toon:
			found = _toon_mesh(found, mi)
		var xf: Transform3D = _relative_xf(inst, mi)
		if not xf.is_equal_approx(Transform3D.IDENTITY):
			found = _baked(found, xf)
	elif parts.size() > 1:
		# Merge all parts into one ArrayMesh so a MultiMesh can draw them.
		var am := ArrayMesh.new()
		for mi in parts:
			var src: Mesh = _toon_mesh(mi.mesh, mi) if toon else mi.mesh
			var xf: Transform3D = _relative_xf(inst, mi)
			var baked := _baked(src, xf)
			for s in baked.get_surface_count():
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, baked.surface_get_arrays(s))
				am.surface_set_material(am.get_surface_count() - 1, baked.surface_get_material(s))
		found = am
	inst.free()
	if toon and found:
		found = with_outline_normals(found)
	_meshes[key] = found
	return found


## Local-space AABB of a prop (for layout code). Cached through mesh().
static func aabb(pack: String, name: String) -> AABB:
	var m := mesh(pack, name, false)
	return m.get_aabb() if m else AABB()


static func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and n.mesh:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


static func _relative_xf(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = cur.transform * xf
		cur = cur.get_parent()
	return xf


static func _baked(src: Mesh, xf: Transform3D) -> ArrayMesh:
	var am := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var nv := PackedVector3Array()
		nv.resize(verts.size())
		for i in verts.size():
			nv[i] = xf * verts[i]
		arrays[Mesh.ARRAY_VERTEX] = nv
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var nn := PackedVector3Array()
			nn.resize(norms.size())
			for i in norms.size():
				nn[i] = (xf.basis * norms[i]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = nn
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(s, src.surface_get_material(s))
	return am


# --- Anime look for imported props ---------------------------------------------

## Gives every StandardMaterial3D in a prop toon diffuse/specular and an ink
## outline pass. Materials are converted once and shared across all props.
static func toonify(root: Node) -> void:
	var parts: Array = []
	_collect_meshes(root, parts)
	for mi in parts:
		var m: Mesh = mi.mesh
		# The ink outline pass misbehaves on skinned meshes, so rigged
		# creatures get toon shading only.
		var skinned: bool = mi.skin != null or (mi.skeleton != NodePath("") and mi.get_node_or_null(mi.skeleton) is Skeleton3D)
		for s in m.get_surface_count():
			var src: Material = mi.get_active_material(s)
			if src:
				mi.set_surface_override_material(s, _toon_material(src, not skinned))
		if not skinned:
			var overrides: Array = []
			for s in m.get_surface_count():
				overrides.append(mi.get_surface_override_material(s))
			mi.mesh = with_outline_normals(m)
			for s in overrides.size():
				mi.set_surface_override_material(s, overrides[s])


## Copy of `m` whose vertices carry, in CUSTOM0, the normal averaged over
## every vertex at the same position: the ink outline (outline.gdshader)
## pushes along it so hard-edged low-poly meshes keep a closed silhouette.
## Cached per source mesh; meshes without normals come back unchanged.
static var _outline_meshes := {}
static func with_outline_normals(m: Mesh) -> Mesh:
	if m == null or not (m is ArrayMesh):
		return m
	var id := m.get_instance_id()
	if _outline_meshes.has(id):
		return _outline_meshes[id]
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var arrays: Array = m.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals = arrays[Mesh.ARRAY_NORMAL]
		if m.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES or normals == null or (normals as PackedVector3Array).size() != verts.size():
			_outline_meshes[id] = m
			return m
		var sums := {}
		for i in verts.size():
			var k := Vector3i(roundi(verts[i].x * 1000.0), roundi(verts[i].y * 1000.0), roundi(verts[i].z * 1000.0))
			sums[k] = sums.get(k, Vector3.ZERO) + (normals as PackedVector3Array)[i]
		var custom := PackedFloat32Array()
		custom.resize(verts.size() * 4)
		for i in verts.size():
			var k := Vector3i(roundi(verts[i].x * 1000.0), roundi(verts[i].y * 1000.0), roundi(verts[i].z * 1000.0))
			var n: Vector3 = sums[k]
			n = n.normalized() if n.length_squared() > 0.000001 else (normals as PackedVector3Array)[i]
			custom[i * 4] = n.x
			custom[i * 4 + 1] = n.y
			custom[i * 4 + 2] = n.z
			custom[i * 4 + 3] = 0.0
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		# Blend shapes and LODs are dropped: props and buildings carry none.
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		out.surface_set_material(s, m.surface_get_material(s))
		out.surface_set_name(s, m.surface_get_name(s))
	_outline_meshes[id] = out
	_outline_meshes[out.get_instance_id()] = out
	return out


static func _toon_mesh(m: Mesh, mi: MeshInstance3D) -> Mesh:
	var copy: Mesh = m.duplicate()
	for s in m.get_surface_count():
		var src: Material = mi.get_active_material(s)
		if src:
			copy.surface_set_material(s, _toon_material(src))
	return copy


static func _toon_material(src: Material, outline := true) -> Material:
	var id := src.get_instance_id() * 2 + (1 if outline else 0)
	if _toon_mats.has(id):
		return _toon_mats[id]
	var out: Material = src
	if src is BaseMaterial3D:
		var m: BaseMaterial3D = src.duplicate()
		if PALETTE.has(src.resource_name):
			m.albedo_color = PALETTE[src.resource_name]
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_TOON
		m.roughness = maxf(m.roughness, 0.85)
		m.metallic = minf(m.metallic, 0.1)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS if m.albedo_texture else m.texture_filter
		if outline and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			m.next_pass = ToonMaterial.outline(OUTLINE_WIDTH)
		out = m
	_toon_mats[id] = out
	return out


# --- Collision ----------------------------------------------------------------

static func add_collision(inst: Node3D, mode := "trimesh") -> StaticBody3D:
	var parts: Array = []
	_collect_meshes(inst, parts)
	if parts.is_empty():
		return null
	var body := StaticBody3D.new()
	body.name = "Collision"
	inst.add_child(body)
	match mode:
		"trimesh":
			for mi in parts:
				var cs := CollisionShape3D.new()
				cs.shape = mi.mesh.create_trimesh_shape()
				cs.transform = _relative_xf(inst, mi)
				body.add_child(cs)
		"box", "trunk":
			var box := AABB()
			var first := true
			for mi in parts:
				var a: AABB = _relative_xf(inst, mi) * mi.mesh.get_aabb()
				box = a if first else box.merge(a)
				first = false
			var cs := CollisionShape3D.new()
			if mode == "box":
				var bs := BoxShape3D.new()
				bs.size = box.size
				cs.shape = bs
				cs.position = box.get_center()
			else:
				var cyl := CylinderShape3D.new()
				cyl.radius = maxf(0.15, minf(box.size.x, box.size.z) * 0.12)
				cyl.height = box.size.y
				cs.shape = cyl
				cs.position = Vector3(box.get_center().x, box.get_center().y, box.get_center().z)
			body.add_child(cs)
	return body


# --- Particles ----------------------------------------------------------------

static func vfx_texture(name: String) -> Texture2D:
	return _tex(VFX_DIR + name + ".png")


# --- Complete buildings (KayKit Medieval Hexagon Pack) ---------------------------

## Building kinds in the hex pack; each exists in blue/green/red/yellow.
const HEX_BUILDINGS := ["home_A", "home_B", "tavern", "blacksmith", "church", "market",
	"windmill", "well", "tower_A", "tower_B", "tower_base", "lumbermill", "barracks",
	"castle", "mine", "watermill", "archeryrange", "tower_catapult"]
const HEX_COLORS := ["blue", "green", "red", "yellow"]
## The hex pack is tiny (a home is ~0.8 units); 6x makes a ~5 m cottage.
const HEX_SCALE := 6.0

## Places a finished textured building. kind from HEX_BUILDINGS, color from
## HEX_COLORS. Collision is a box over the footprint. Door faces +Z.
static func house(parent: Node, pos: Vector3, kind := "home_A", color := "blue", rot_y := 0.0, scl := HEX_SCALE) -> Node3D:
	var name := "buildings/%s/building_%s_%s" % [color, kind, color]
	# Live instance: WorldProps spins the windmill's fan, and a building is
	# big enough to be its own draw call.
	var n := prop(parent, "hex", name, pos, rot_y, scl, "box", true, Color.WHITE, false)
	WorldArt.light_hex_windows(n)  # glass glows after dusk
	return n


## Footprint (x, z) in metres of a hex building at the given scale.
static func house_footprint(kind := "home_A", color := "blue", scl := HEX_SCALE) -> Vector2:
	var a := aabb("hex", "buildings/%s/building_%s_%s" % [color, kind, color])
	return Vector2(a.size.x, a.size.z) * scl
