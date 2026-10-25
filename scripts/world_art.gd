class_name WorldArt
extends RefCounted
## Procedural art for Floor 1: terrain dressing, vegetation MultiMeshes,
## houses, walls, lanterns, the Labyrinth tower, clouds and distant islets.
## Everything is built from primitives and shaders in res://shaders/, so the
## world needs zero binary assets. world.gd owns gameplay layout and calls in.

const GRASS_A := Color("5fae4a")
const GRASS_B := Color("8fd36b")
const SAND := Color("d9c39a")
const STONE := Color("9a9aa6")
const STONE_DARK := Color("6e6e7c")
const WOOD := Color("6b4a2e")
const WOOD_LIGHT := Color("a9815a")
const TERRACOTTA := Color("c8603f")
const TEAL := Color("3f8f8c")
const SLATE := Color("5b6478")
const CREAM := Color("f3e7d3")
const PEACH := Color("f1d6bd")
const SAGE := Color("dfe5cf")
const WATER := Color("5fd3e6")
const LANTERN := Color("ffb35c")

const PLAZA := Vector2(0, 15)
const PLAZA_RADIUS := 22.0
const POND := Vector2(54, -14)
const POND_RADIUS := 8.0
const ROADS := [
	[Vector2(0, -7), Vector2(0, -57)],
	[Vector2(-20, 24), Vector2(-46, 36)],
	[Vector2(-5, -6), Vector2(-14, -41)],
	[Vector2(0, 37), Vector2(0, 62)],
	[Vector2(22, 13), Vector2(48, -10)],
]

enum Ground { GRASS, SAND, COBBLE, DIRT, WATER_K, RIM, TOWER }

static var _mats := {}
static var _shaders := {}


static func headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func shader(n: String) -> Shader:
	if not _shaders.has(n):
		_shaders[n] = load("res://shaders/%s.gdshader" % n)
	return _shaders[n]


## Cached cel material with outline; one per colour so hundreds of props share.
static func mat(c: Color, outline := 0.025, emission := Color.BLACK, strength := 0.0) -> ShaderMaterial:
	var key := "%s|%.3f|%s|%.2f" % [c.to_html(), outline, emission.to_html(), strength]
	if _mats.has(key):
		return _mats[key]
	var m := ToonMaterial.make(c, emission, strength)
	if outline > 0.0:
		m.next_pass = ToonMaterial.outline(outline)
	_mats[key] = m
	return m


static func foliage_mat(c: Color, wind := 0.0, outline := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("foliage")
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("wind", wind)
	if outline > 0.0:
		m.next_pass = ToonMaterial.outline(outline)
	return m


static func rune_mat(c: Color, strength := 2.2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("rune")
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("strength", strength)
	return m


static func water_mat(flow := Vector2(1, 0), speed := 0.25, shallow := WATER, deep := Color("1f7fb8")) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("water")
	m.set_shader_parameter("flow_dir", flow)
	m.set_shader_parameter("flow_speed", speed)
	m.set_shader_parameter("shallow_color", shallow)
	m.set_shader_parameter("deep_color", deep)
	return m


## Cel "ancient stonework" material (shaders/stone.gdshader): two painted
## tones, a world-space triplanar Poly Haven detail map when the set exists
## (castle_brick_07, rock_wall_10, ...), optional brick courses, rune bands
## and a height fade. Extra shader parameters go in `params`.
static func stone_mat(a: Color, b: Color, detail := "castle_brick_07", tiling := 0.2, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("stone")
	m.set_shader_parameter("albedo", a)
	m.set_shader_parameter("albedo_b", b)
	var diff: Texture2D = AssetLib.texture_map(detail, "diffuse") if detail != "" else null
	if diff:
		m.set_shader_parameter("detail_tex", diff)
		m.set_shader_parameter("detail_mean", AssetLib.texture_mean_luminance(diff))
		m.set_shader_parameter("detail_tiling", tiling)
		m.set_shader_parameter("detail_strength", 0.55)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


## Cel plank wood (stone.gdshader in plank mode) with a Poly Haven wood map:
## boards `width` wide, staggered ends, per-board shade and grain. axis 0
## lays floor boards along world x, 1 along z; walls always get vertical
## boards. Cached per look.
static func wood_mat(a: Color, b: Color, detail := "weathered_planks", width := 0.32, axis := 0, params := {}) -> ShaderMaterial:
	var key := "wood|%s|%s|%s|%.2f|%d|%s" % [a.to_html(), b.to_html(), detail, width, axis, str(params)]
	if _mats.has(key):
		return _mats[key]
	var m := stone_mat(a, b, detail, 0.45, {"detail_strength": 0.55, "detail_tint": 0.35, "plank_period": width, "plank_axis": float(axis),
		"brick_length": 2.6, "band_width": 0.028, "band_dark": 0.62, "shadow_level": 0.52, "mid_level": 0.8})
	for k in params:
		m.set_shader_parameter(k, params[k])
	_mats[key] = m
	return m


## Lime-washed plaster (beige_wall_001 under the cel look). Cached.
static func plaster_mat(a := Color("efe3cc"), b := Color("e4d4b6"), params := {}) -> ShaderMaterial:
	var key := "plaster|%s|%s|%s" % [a.to_html(), b.to_html(), str(params)]
	if _mats.has(key):
		return _mats[key]
	var m := stone_mat(a, b, "beige_wall_001", 0.7, {"detail_strength": 0.35, "detail_tint": 0.15, "shadow_level": 0.55, "mid_level": 0.82})
	for k in params:
		m.set_shader_parameter(k, params[k])
	_mats[key] = m
	return m


## Woven rug material (shaders/rug.gdshader). Fresh instance per call.
static func rug_mat(base := Color("a8332e"), accent := Color("d9a441"), dark := Color("3a1f2a"), pale := Color("f3e2bd")) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("rug")
	m.set_shader_parameter("base", base)
	m.set_shader_parameter("accent", accent)
	m.set_shader_parameter("dark", dark)
	m.set_shader_parameter("pale", pale)
	return m


## Sky seen through a window (shaders/window_sky.gdshader); registered so
## set_night_tint() darkens it after dusk.
static func window_sky_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("window_sky")
	window_materials.append(m)
	return m


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ba := b - a
	var h: float = clamp((p - a).dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (p - (a + ba * h)).length()


## Mirrors shaders/ground.gdshader so vegetation avoids roads and the plaza.
static func ground_kind(p: Vector2) -> int:
	if p.distance_to(PLAZA) < PLAZA_RADIUS + 0.5:
		return Ground.COBBLE
	if p.length() > 84.0:
		return Ground.RIM
	if p.distance_to(Vector2(0, -70)) < 16.5:
		return Ground.TOWER
	if p.distance_to(POND) < POND_RADIUS + 2.5:
		return Ground.WATER_K
	for r in ROADS:
		if _seg_dist(p, r[0], r[1]) < 3.8:
			return Ground.SAND
	if p.distance_to(Vector2(-48, 38)) < 14.0 or p.distance_to(Vector2(-14, -44)) < 10.5:
		return Ground.DIRT
	return Ground.GRASS


# --- Small helpers ---------------------------------------------------------

static func mesh_node(parent: Node, mesh: Mesh, pos: Vector3, m: Material = null, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if m:
		mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func box(parent: Node, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO, outline := 0.025) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return mesh_node(parent, bm, pos, mat(c, outline), rot)


static func cyl(parent: Node, top: float, bottom: float, h: float, pos: Vector3, c: Color, segs := 16, rot := Vector3.ZERO) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	return mesh_node(parent, cm, pos, mat(c), rot)


static func sphere(parent: Node, r: float, pos: Vector3, c: Color, scl := Vector3.ONE) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	sm.radial_segments = 16
	sm.rings = 8
	return mesh_node(parent, sm, pos, mat(c), Vector3.ZERO, scl)


static func collider(parent: Node, shape: Shape3D, pos: Vector3, rot := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation = rot
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body


static func box_collider(parent: Node, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> StaticBody3D:
	var bs := BoxShape3D.new()
	bs.size = size
	return collider(parent, bs, pos, rot)


static func multimesh(parent: Node, mesh: Mesh, xforms: Array, colors: Array = [], n: String = "") -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if n != "":
		mmi.name = n
	parent.add_child(mmi)
	if foliage_chunking and FOLIAGE_LOD.has(n):
		# Split into distance-culled chunks at the end of the frame (after
		# the caller has set its material and shadow flags).
		_foliage_pending.append(mmi)
		if not _foliage_queued:
			_foliage_queued = true
			(func(): WorldArt.chunk_foliage()).call_deferred()
	return mmi


# --- Foliage chunks ------------------------------------------------------------------
## Grass, flowers and reeds are placed as one island-wide MultiMesh (tens of
## thousands of tufts, one draw, never culled). chunk_foliage() re-cuts each
## into FOLIAGE_CHUNK-metre cells: the renderer frustum-culls cells behind the
## camera, far cells stop drawing at the preset's range (RenderProfile.prop_cull
## x the base range below; 0 on Ultra), and every chunk honours the foliage
## density slider through visible_instance_count. Instances are shuffled
## inside a cell so a density cut thins evenly instead of erasing patches.

const FOLIAGE_CHUNK := 22.0
## Off = one island-wide MultiMesh per kind, as before (screenshot --no-batch).
static var foliage_chunking := true
const FOLIAGE_LOD := {"Grass": 95.0, "Flowers": 80.0, "Reeds": 80.0}
static var _foliage_pending: Array = []
static var _foliage_queued := false


static func chunk_foliage() -> void:
	_foliage_queued = false
	for mmi in _foliage_pending:
		if not is_instance_valid(mmi) or not mmi.is_inside_tree() or mmi.multimesh == null:
			continue
		var mm: MultiMesh = mmi.multimesh
		var n := mm.instance_count
		if n < 400:
			RenderProfile.register_foliage(mmi)
			RenderProfile.register_lod(mmi, FOLIAGE_LOD.get(mmi.name, 90.0))
			continue
		var cells := {}
		for i in n:
			var o := mm.get_instance_transform(i).origin
			var key := Vector2i(floori(o.x / FOLIAGE_CHUNK), floori(o.z / FOLIAGE_CHUNK))
			if not cells.has(key):
				cells[key] = []
			cells[key].append(i)
		var parent: Node = mmi.get_parent()
		var base_name: String = mmi.name
		var rng := RandomNumberGenerator.new()
		var lod_base: float = FOLIAGE_LOD.get(base_name, 90.0)
		for key in cells:
			var ids: Array = cells[key]
			# Seeded Fisher-Yates: the same tufts hide at Low on every run.
			rng.seed = key.x * 7919 + key.y * 104729 + n
			for j in range(ids.size() - 1, 0, -1):
				var k := rng.randi_range(0, j)
				var tmp = ids[j]
				ids[j] = ids[k]
				ids[k] = tmp
			var cm := MultiMesh.new()
			cm.transform_format = mm.transform_format
			cm.use_colors = mm.use_colors
			cm.use_custom_data = mm.use_custom_data
			cm.mesh = mm.mesh
			cm.instance_count = ids.size()
			for j in ids.size():
				cm.set_instance_transform(j, mm.get_instance_transform(ids[j]))
				if mm.use_colors:
					cm.set_instance_color(j, mm.get_instance_color(ids[j]))
			var c := MultiMeshInstance3D.new()
			c.name = "%s_%d_%d" % [base_name, key.x, key.y]
			c.multimesh = cm
			c.material_override = mmi.material_override
			c.cast_shadow = mmi.cast_shadow
			c.transform = mmi.transform
			parent.add_child(c)
			RenderProfile.register_foliage(c)
			RenderProfile.register_lod(c, lod_base)
		mmi.queue_free()
	_foliage_pending.clear()


static func xf(pos: Vector3, rot_y := 0.0, scl := Vector3.ONE, tilt := Vector3.ZERO) -> Transform3D:
	var b := Basis.from_euler(Vector3(tilt.x, rot_y, tilt.z)).scaled(scl)
	return Transform3D(b, pos)


# --- Terrain ---------------------------------------------------------------

## Flat walkable disc (collision stays a cylinder in world.gd) with the
## painterly ground shader, a rocky cliff skirt and the jagged underside.
## `look` overrides for other floors: "shader" (ground shader name), "sets"
## (detail map sets for bind_ground_detail), "cliff_a"/"cliff_b" (skirt
## rock tones), "rock_a"/"rock_b" (boulder tints), "lip_a"/"lip_b".
static func build_terrain(parent: Node3D, rng: RandomNumberGenerator, radius: float, look: Dictionary = {}) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 18
	var segs := 96
	var ring_r := []
	for r in rings + 1:
		ring_r.append(radius * pow(float(r) / rings, 1.25))
	for r in rings + 1:
		for s in segs:
			var a := TAU * s / segs
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(cos(a), sin(a)) * ring_r[r] / radius)
			st.add_vertex(Vector3(cos(a) * ring_r[r], 0, sin(a) * ring_r[r]))
	for r in rings:
		for s in segs:
			var s1 := (s + 1) % segs
			var i0 := r * segs + s
			var i1 := r * segs + s1
			var i2 := (r + 1) * segs + s
			var i3 := (r + 1) * segs + s1
			if r > 0:
				st.add_index(i0)
				st.add_index(i3)
				st.add_index(i1)
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i3)
	var top := st.commit()
	var gm := ShaderMaterial.new()
	gm.shader = shader(look.get("shader", "ground"))
	bind_ground_detail(gm, look.get("sets", []))
	var ground := mesh_node(parent, top, Vector3.ZERO, gm)
	ground.name = "Ground"

	# Underside: a jagged inverted cone of rock carved with noise.
	var ut := SurfaceTool.new()
	ut.begin(Mesh.PRIMITIVE_TRIANGLES)
	var levels := [[0.0, 1.0], [-3.0, 1.03], [-9.0, 0.96], [-18.0, 0.82], [-30.0, 0.6], [-42.0, 0.35], [-50.0, 0.12], [-54.0, 0.0]]
	var usegs := 64
	for l in levels.size():
		for s in usegs:
			var a := TAU * s / usegs
			var jag := 1.0 + (sin(a * 7.0 + l * 1.3) * 0.05 + sin(a * 13.0 + l * 2.1) * 0.035) * (1.0 if l > 0 else 0.0)
			var rr: float = radius * levels[l][1] * jag
			var y: float = levels[l][0] + (0.0 if l == 0 or l == levels.size() - 1 else sin(a * 9.0 + l) * 1.2)
			ut.set_color(Color.WHITE)
			ut.add_vertex(Vector3(cos(a) * rr, y, sin(a) * rr))
	for l in levels.size() - 1:
		for s in usegs:
			var s1 := (s + 1) % usegs
			var i0 := l * usegs + s
			var i1 := l * usegs + s1
			var i2 := (l + 1) * usegs + s
			var i3 := (l + 1) * usegs + s1
			ut.add_index(i0)
			ut.add_index(i1)
			ut.add_index(i3)
			ut.add_index(i0)
			ut.add_index(i3)
			ut.add_index(i2)
	ut.generate_normals()
	var cliff_mat := stone_mat(look.get("cliff_a", Color("857266")), look.get("cliff_b", Color("5e5049")), "rock_wall_10", 0.12, {"detail_strength": 0.7, "detail_tint": 0.35, "shadow_level": 0.45})
	var rock_a: Color = look.get("rock_a", Color("b5a69a"))
	var rock_b: Color = look.get("rock_b", Color("8a7d74"))
	var crag_a: Color = look.get("crag_a", Color("9c8c80"))
	var crag_b: Color = look.get("crag_b", Color("6e6058"))
	var lip_a: Color = look.get("lip_a", Color("c0b8ad"))
	var lip_b: Color = look.get("lip_b", Color("948a7e"))
	var under := mesh_node(parent, ut.commit(), Vector3.ZERO, cliff_mat)
	under.name = "Underside"

	# Cliff rocks: chunky boulders hugging the rim, tilted outward.
	var rock := rock_mesh()
	var xs := []
	var cs := []
	for i in 320:
		var a := rng.randf() * TAU
		var r := radius - 2.5 + rng.randf_range(-1.5, 3.5)
		var s := rng.randf_range(2.5, 6.5)
		var pos := Vector3(cos(a) * r, rng.randf_range(-3.5, -0.2) - s * 0.25, sin(a) * r)
		xs.append(xf(pos, rng.randf() * TAU, Vector3(s, s * rng.randf_range(0.7, 1.3), s * rng.randf_range(0.7, 1.2)), Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))))
		cs.append(rock_a.lerp(rock_b, rng.randf()) * (1.0 if rng.randf() > 0.3 else 1.12))
	# A second, lower band of larger crags so the skirt reads as layered rock.
	for i in 140:
		var a := rng.randf() * TAU
		var r := radius * 0.97 + rng.randf_range(-2.0, 1.0)
		var s := rng.randf_range(5.0, 9.5)
		var pos := Vector3(cos(a) * r, rng.randf_range(-12.0, -5.0), sin(a) * r)
		xs.append(xf(pos, rng.randf() * TAU, Vector3(s, s * rng.randf_range(0.9, 1.6), s * rng.randf_range(0.6, 1.0)), Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))))
		cs.append(crag_a.lerp(crag_b, rng.randf()))
	# Rim lip: a ring of smaller stones on top so the edge reads.
	for i in 160:
		var a := rng.randf() * TAU
		var r := radius - rng.randf_range(0.8, 3.0)
		var s := rng.randf_range(0.6, 1.6)
		xs.append(xf(Vector3(cos(a) * r, s * 0.15, sin(a) * r), rng.randf() * TAU, Vector3(s, s * 0.7, s)))
		cs.append(lip_a.lerp(lip_b, rng.randf()))
	var cliffs := multimesh(parent, rock, xs, cs, "Cliffs")
	cliffs.material_override = cliff_mat
	cliffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Feeds the Poly Haven grass / gravel / cobblestone maps into the ground
## shader as a detail layer under the painted palette (no-op without them).
static func bind_ground_detail(gm: ShaderMaterial, sets: Array = []) -> void:
	if sets.is_empty():
		sets = [["grass", "aerial_grass_rock"], ["path", "gravel_road"], ["cobble", "cobblestone_floor_08"]]
	var bound := 0
	for pair in sets:
		var diff := AssetLib.texture_map(pair[1], "diffuse")
		if diff == null:
			continue
		gm.set_shader_parameter(pair[0] + "_tex", diff)
		gm.set_shader_parameter(pair[0] + "_mean", AssetLib.texture_mean_luminance(diff))
		var nor := AssetLib.texture_map(pair[1], "nor_gl")
		if nor:
			gm.set_shader_parameter(pair[0] + "_nor", nor)
		bound += 1
	if bound > 0:
		gm.set_shader_parameter("detail_strength", 0.6)
		gm.set_shader_parameter("detail_tint", 0.08)


static func rock_mesh() -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 1.6
	sm.radial_segments = 7
	sm.rings = 4
	var st := SurfaceTool.new()
	st.create_from(sm, 0)
	var arr := st.commit_to_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var h := RandomNumberGenerator.new()
	h.seed = 7
	for i in verts.size():
		var v := verts[i]
		var k := 1.0 + (sin(v.x * 5.1 + v.z * 3.7) * 0.12 + cos(v.y * 6.3 + v.x * 2.0) * 0.1)
		verts[i] = Vector3(v.x * k, max(v.y, -0.5) * k, v.z * k)
	arr[Mesh.ARRAY_VERTEX] = verts
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st2 := SurfaceTool.new()
	st2.create_from(out, 0)
	st2.generate_normals()
	return st2.commit()


# --- Vegetation ------------------------------------------------------------

static func grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 3:
		var a := TAU * b / 3.0
		var dirv := Vector3(cos(a), 0, sin(a)) * 0.07
		var side := Vector3(-sin(a), 0, cos(a)) * 0.07
		var base := dirv * 0.6
		var pts := [base - side, base + side, base + Vector3(0, 0.45, 0) + side * 0.6 + dirv * 0.6, base + Vector3(0, 0.45, 0) - side * 0.6 + dirv * 0.6, base + Vector3(0, 0.85, 0) + dirv * 1.6]
		var uvs := [0.0, 0.0, 0.55, 0.55, 1.0]
		var tris := [[0, 2, 1], [0, 3, 2], [3, 4, 2]]
		for t in tris:
			for k in t:
				st.set_color(Color.WHITE)
				st.set_uv(Vector2(0, uvs[k]))
				st.set_normal(Vector3.UP)
				st.add_vertex(pts[k])
	return st.commit()


static func flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Stem (thin tri) + a five-petal head: a scalloped disc tilted toward the
	# viewer's usual side, double-sided, with a darker eye in the middle.
	var stem := [Vector3(-0.02, 0, 0), Vector3(0.02, 0, 0), Vector3(0, 0.5, 0)]
	for k in 3:
		st.set_color(Color(0.45, 0.75, 0.35))
		st.set_normal(Vector3.UP)
		st.add_vertex(stem[k])
	var c := Vector3(0, 0.52, 0)
	var tilt := Basis(Vector3.RIGHT, 0.45)
	var n := tilt * Vector3.UP
	var petals := 5
	var seg := 30
	var ring: Array[Vector3] = []
	for i in seg:
		var a := TAU * i / seg
		# Scalloped radius: five rounded lobes with notches between them.
		var lobe := absf(sin(a * petals * 0.5))
		var r := 0.05 + 0.13 * pow(lobe, 0.6)
		ring.append(c + tilt * Vector3(cos(a) * r, 0, sin(a) * r))
	var eye := c + n * 0.012
	for i in seg:
		var a := ring[i]
		var b := ring[(i + 1) % seg]
		for tri in [[eye, a, b], [eye, b, a]]:
			for k in 3:
				var v: Vector3 = tri[k]
				var d := v.distance_to(c)
				# Petals pale at the tips, deeper toward the eye.
				st.set_color(Color(1, 1, 1).lerp(Color(0.82, 0.78, 0.75), clampf(1.0 - d / 0.18, 0.0, 1.0) * 0.5))
				st.set_normal(n if tri[1] == a else -n)
				st.add_vertex(v)
	# Eye: small raised disc in warm yellow.
	var eye_r := 0.035
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		var p0 := c + n * 0.02 + tilt * Vector3(cos(a0) * eye_r, 0, sin(a0) * eye_r)
		var p1 := c + n * 0.02 + tilt * Vector3(cos(a1) * eye_r, 0, sin(a1) * eye_r)
		for tri in [[c + n * 0.03, p0, p1], [c + n * 0.03, p1, p0]]:
			for k in 3:
				st.set_color(Color(1.0, 0.78, 0.25))
				st.set_normal(n)
				st.add_vertex(tri[k])
	return st.commit()


static func tree_mesh(variant: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.38
	trunk.height = 2.6 if variant != 1 else 2.0
	trunk.radial_segments = 8
	trunk.rings = 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, trunk.height / 2, 0)))
	if variant == 2:
		st.append_from(trunk, 0, Transform3D(Basis.from_euler(Vector3(0, 0, 0.5)).scaled(Vector3(0.6, 0.7, 0.6)), Vector3(0.6, 2.2, 0)))
	mesh = st.commit(mesh)
	var ct := SurfaceTool.new()
	ct.begin(Mesh.PRIMITIVE_TRIANGLES)
	match variant:
		0:  # Round puffball: three stacked spheres.
			var s := SphereMesh.new()
			s.radius = 1.0
			s.height = 2.0
			s.radial_segments = 14
			s.rings = 7
			for b in [[Vector3(0, 3.0, 0), 1.9], [Vector3(0.7, 4.0, 0.4), 1.4], [Vector3(-0.6, 4.3, -0.3), 1.3], [Vector3(0.1, 5.0, 0.1), 1.0]]:
				ct.append_from(s, 0, Transform3D(Basis().scaled(Vector3(b[1], b[1] * 0.85, b[1])), b[0]))
		1:  # Pine: three stacked cones.
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 1.0
			c.height = 2.0
			c.radial_segments = 10
			c.rings = 1
			for b in [[1.6, 2.0, 2.6], [1.3, 1.8, 3.9], [0.9, 1.6, 5.0]]:
				ct.append_from(c, 0, Transform3D(Basis().scaled(Vector3(b[0], b[1], b[0])), Vector3(0, b[2], 0)))
		_:  # Broad oak: wide flattened canopy.
			var s := SphereMesh.new()
			s.radius = 1.0
			s.height = 2.0
			s.radial_segments = 14
			s.rings = 7
			for b in [[Vector3(0, 3.4, 0), Vector3(2.6, 1.7, 2.6)], [Vector3(1.4, 3.9, 0.6), Vector3(1.5, 1.2, 1.5)], [Vector3(-1.2, 4.1, -0.5), Vector3(1.6, 1.3, 1.6)], [Vector3(0.2, 4.7, 0.3), Vector3(1.4, 1.1, 1.4)]]:
				ct.append_from(s, 0, Transform3D(Basis().scaled(b[1]), b[0]))
	mesh = ct.commit(mesh)
	mesh.surface_set_material(0, foliage_mat(WOOD, 0.0, 0.03))
	mesh.surface_set_material(1, foliage_mat(Color.WHITE, 0.6, 0.045))
	return mesh


## Grass tufts, flowers, scattered rocks and trees. Trees get trunk colliders
## (grouped in one StaticBody) except near the tower so mobs never get stuck.
static func build_vegetation(parent: Node3D, rng: RandomNumberGenerator, radius: float, keep_clear: Array) -> void:
	var clear := func(p: Vector2, extra := 0.0) -> bool:
		for k in keep_clear:
			if p.distance_to(Vector2(k[0].x, k[0].z)) < k[1] + extra:
				return true
		return false
	# Trees.
	var use_pack := AssetLib.has_prop("nature", "tree_oak")
	var trees := [[], [], []]
	var tree_cols := [[], [], []]
	var pack_trees := {}
	var trunk_shapes := []
	var tries := 0
	var placed := 0
	while placed < 260 and tries < 6000:
		tries += 1
		var p: Vector2
		var woods := placed < 170
		if woods:
			p = Vector2(rng.randf_range(-82, 82), rng.randf_range(-86, -28))
		else:
			var a := rng.randf() * TAU
			p = Vector2(cos(a), sin(a)) * rng.randf_range(40, 82)
		if p.length() > radius - 5 or ground_kind(p) != Ground.GRASS or clear.call(p, 3.0):
			continue
		if p.distance_to(Vector2(0, -70)) < 24:
			continue
		var too_close := false
		for v in 3:
			for t in trees[v]:
				if Vector2(t.origin.x, t.origin.z).distance_to(p) < 4.5:
					too_close = true
					break
			if too_close:
				break
		if too_close:
			continue
		var variant := 1 if woods and rng.randf() < 0.45 else (2 if rng.randf() < 0.3 else 0)
		var s := rng.randf_range(0.9, 1.5)
		var rot := rng.randf() * TAU
		var pick := rng.randf()
		var sakura := rng.randf() < 0.08
		if use_pack:
			# Nature Kit trees: one MultiMesh per kind, pines in the woods.
			var pool: Array = WorldProps.TREES_WOODS if variant == 1 else WorldProps.TREES_MEADOW
			var kind: String = WorldProps.TREES_FALL[int(pick * WorldProps.TREES_FALL.size()) % WorldProps.TREES_FALL.size()] if sakura and variant != 1 else pool[int(pick * pool.size()) % pool.size()]
			var ps := s * WorldProps.NATURE * 1.15
			if not pack_trees.has(kind):
				pack_trees[kind] = []
			pack_trees[kind].append(xf(Vector3(p.x, 0, p.y), rot, Vector3(ps, ps * rng.randf_range(0.95, 1.15), ps)))
		else:
			trees[variant].append(xf(Vector3(p.x, 0, p.y), rot, Vector3(s, s * rng.randf_range(0.9, 1.2), s)))
			var g := Color("4e9a3c").lerp(Color("8fd36b"), rng.randf())
			if variant == 1:
				g = Color("2f7a4a").lerp(Color("5aa86a"), rng.randf())
			if sakura:
				g = Color("e58fb4").lerp(Color("f6c1d3"), rng.randf())  # Sakura.
			tree_cols[variant].append(g)
		placed += 1
		if p.distance_to(Vector2(0, -70)) > 34 and p.distance_to(Vector2(-14, -44)) > 16:
			trunk_shapes.append(Vector3(p.x, 0, p.y))
	for v in 3:
		if trees[v].is_empty():
			continue
		var mmi := multimesh(parent, tree_mesh(v), trees[v], tree_cols[v], "Trees%d" % v)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for kind in pack_trees:
		AssetLib.multi(parent, "nature", kind, pack_trees[kind])
	var body := StaticBody3D.new()
	body.name = "TreeTrunks"
	for p in trunk_shapes:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.4
		sh.height = 3.0
		cs.shape = sh
		cs.position = p + Vector3(0, 1.5, 0)
		body.add_child(cs)
	parent.add_child(body)

	# Scattered boulders.
	var rocks := []
	var rock_cols := []
	var pack_rocks := {"rock_largeA": [], "rock_largeB": [], "rock_largeC": [], "rock_tallA": [], "rock_smallA": [], "rock_smallC": []}
	var pack_keys := pack_rocks.keys()
	for i in 140:
		var a := rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * rng.randf_range(30, 82)
		if ground_kind(p) != Ground.GRASS or clear.call(p, 2.0):
			continue
		var s := rng.randf_range(0.5, 2.2)
		if use_pack:
			var k: String = pack_keys[(i * 7) % 4]
			var ps := s * 2.2
			pack_rocks[k].append(xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, Vector3(ps, ps * rng.randf_range(0.7, 1.0), ps)))
			continue
		rocks.append(xf(Vector3(p.x, -s * 0.2, p.y), rng.randf() * TAU, Vector3(s, s * rng.randf_range(0.6, 1.0), s * rng.randf_range(0.7, 1.3))))
		rock_cols.append(Color("7c7a84").lerp(Color("5a5762"), rng.randf()))
	# Pond rim stones.
	for i in 34:
		var a := TAU * i / 34.0 + rng.randf() * 0.1
		var r := POND_RADIUS + rng.randf_range(0.2, 1.2)
		var s := rng.randf_range(0.5, 1.1)
		if use_pack:
			var k: String = pack_keys[4 + i % 2]
			var ps := s * 2.4
			pack_rocks[k].append(xf(Vector3(POND.x + cos(a) * r, 0, POND.y + sin(a) * r), rng.randf() * TAU, Vector3(ps, ps * 0.8, ps)))
			continue
		rocks.append(xf(Vector3(POND.x + cos(a) * r, -s * 0.25, POND.y + sin(a) * r), rng.randf() * TAU, Vector3(s, s * 0.6, s)))
		rock_cols.append(Color("a8a39c").lerp(Color("7a7872"), rng.randf()))
	if not rocks.is_empty():
		var rm := multimesh(parent, rock_mesh(), rocks, rock_cols, "Rocks")
		rm.material_override = foliage_mat(Color.WHITE, 0.0, 0.03)
	for k in pack_rocks:
		if not pack_rocks[k].is_empty():
			AssetLib.multi(parent, "nature", k, pack_rocks[k])

	if headless():
		return
	# Bushes, mushrooms, stumps, logs and flower clumps from the Nature Kit.
	WorldProps.undergrowth(parent, rng, radius, func(p: Vector2) -> bool:
		return ground_kind(p) == Ground.GRASS and not clear.call(p, 1.5))

	if headless():
		return
	# Grass: dense tufts everywhere the ground is meadow.
	var gx := []
	var gc := []
	var n_grass := 26000
	for i in n_grass:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (radius - 4)
		var p := Vector2(cos(a), sin(a)) * r
		if ground_kind(p) != Ground.GRASS or clear.call(p, 0.5):
			continue
		var s := rng.randf_range(0.6, 1.1)
		gx.append(xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, Vector3(s, s * rng.randf_range(0.7, 1.1), s)))
		gc.append(Color(1, 1, 1).lerp(Color(0.78, 1.0, 0.8), rng.randf()).lerp(Color(0.95, 0.95, 0.7), rng.randf() * 0.25))
	var gmat := ShaderMaterial.new()
	gmat.shader = shader("grass")
	var gmm := multimesh(parent, grass_mesh(), gx, gc, "Grass")
	gmm.material_override = gmat
	gmm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Flowers in loose patches.
	var fx := []
	var fc := []
	var palette := [Color("fff4a8"), Color("ffffff"), Color("f7a1c4"), Color("8fb8ff"), Color("ff9c6b")]
	for patch in 70:
		var a := rng.randf() * TAU
		var c := Vector2(cos(a), sin(a)) * rng.randf_range(20, 80)
		var col: Color = palette[rng.randi() % palette.size()]
		for i in 40:
			var p := c + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
			if ground_kind(p) != Ground.GRASS or clear.call(p, 0.5):
				continue
			var s := rng.randf_range(0.8, 1.3)
			fx.append(xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, Vector3(s, s, s)))
			fc.append(col.lerp(Color.WHITE, rng.randf() * 0.3))
	var fmm := multimesh(parent, flower_mesh(), fx, fc, "Flowers")
	fmm.material_override = foliage_mat(Color.WHITE, 0.8)
	fmm.material_override.set_shader_parameter("emission_color", Color.WHITE)
	fmm.material_override.set_shader_parameter("emission_strength", 0.05)
	fmm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- Water -----------------------------------------------------------------

static func build_water(parent: Node3D, radius: float) -> void:
	var pond := CylinderMesh.new()
	pond.top_radius = POND_RADIUS + 0.6
	pond.bottom_radius = POND_RADIUS + 0.6
	pond.height = 0.08
	pond.radial_segments = 32
	var pm := mesh_node(parent, pond, Vector3(POND.x, 0.05, POND.y), water_mat(Vector2(1, 0.3), 0.18))
	pm.name = "Pond"
	# Sandy shore lip and a ring of shore boulders so the pond reads as dug in.
	var lip := TorusMesh.new()
	lip.inner_radius = POND_RADIUS + 0.3
	lip.outer_radius = POND_RADIUS + 1.9
	lip.rings = 48
	lip.ring_segments = 6
	mesh_node(parent, lip, Vector3(POND.x, 0.02, POND.y), mat(Color("d8c7a0"), 0.0), Vector3.ZERO, Vector3(1, 0.12, 1))
	WorldProps.shore_rocks(parent, Vector3(POND.x, 0, POND.y), POND_RADIUS + 0.9)
	# Stream from the pond to the rim and a waterfall off the edge.
	var a := Vector2(POND.x + 6, POND.y - 2)
	var b := Vector2(radius - 0.5, POND.y - 5)
	var dir := (b - a)
	var plane := PlaneMesh.new()
	plane.size = Vector2(dir.length() + 1.0, 3.2)
	plane.subdivide_width = 16
	var mid := (a + b) * 0.5
	var sm := mesh_node(parent, plane, Vector3(mid.x, 0.04, mid.y), water_mat(Vector2(1, 0), 0.6), Vector3(0, -atan2(dir.y, dir.x), 0))
	sm.name = "Stream"
	var fall := PlaneMesh.new()
	fall.size = Vector2(3.2, 34.0)
	var fm := water_mat(Vector2(0, 1), 1.6)
	fm.set_shader_parameter("wave_height", 0.0)
	var out := Vector2(cos(atan2(b.y, b.x)), sin(atan2(b.y, b.x)))
	var fpos := Vector3(b.x + out.x * 0.9, -17.0, b.y + out.y * 0.9)
	var fn := mesh_node(parent, fall, fpos, fm, Vector3(PI / 2, -atan2(out.y, out.x) + PI / 2, 0))
	fn.name = "Waterfall"
	# Mist at the foot of the fall.
	if not headless():
		var mist := _particles(fpos + Vector3(0, -17, 0), 40, 3.0, Vector3(3, 1, 3), Color(1, 1, 1, 0.5), 1.2, 0.0)
		mist.process_material.initial_velocity_min = 0.5
		mist.process_material.initial_velocity_max = 1.5
		mist.process_material.direction = Vector3(0, 1, 0)
		mist.process_material.spread = 60.0
		parent.add_child(mist)
	# Reeds around the pond.
	var reeds := []
	var rc := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 90:
		var ang := rng.randf() * TAU
		var r := POND_RADIUS + rng.randf_range(0.6, 2.4)
		var s := rng.randf_range(1.6, 2.6)
		reeds.append(xf(Vector3(POND.x + cos(ang) * r, 0, POND.y + sin(ang) * r), rng.randf() * TAU, Vector3(s, s, s)))
		rc.append(Color("5c9a3a").lerp(Color("9ccf62"), rng.randf()))
	var gmat := ShaderMaterial.new()
	gmat.shader = shader("grass")
	gmat.set_shader_parameter("wind_strength", 0.35)
	var mm := multimesh(parent, grass_mesh(), reeds, rc, "Reeds")
	mm.material_override = gmat
	# Lily pads.
	for i in 7:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(1, POND_RADIUS - 1.5)
		cyl(parent, 0.5, 0.5, 0.04, Vector3(POND.x + cos(ang) * r, 0.1, POND.y + sin(ang) * r), Color("4f9b4a"), 10)


# --- Architecture ----------------------------------------------------------

## Cottage with pitched roof, chimney, door, framed glowing windows and a
## stone footing. Returns the StaticBody3D holding the collision box.
static func house(parent: Node3D, pos: Vector3, w: float, d: float, h: float, rot_y: float, variant: int = 0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	parent.add_child(body)
	var wall_colors := [CREAM, PEACH, SAGE, Color("efe0c8")]
	var roof_colors := [TERRACOTTA, TEAL, SLATE, Color("b8503a")]
	var wall_c: Color = wall_colors[variant % wall_colors.size()]
	var roof_c: Color = roof_colors[variant % roof_colors.size()]
	var two_story := variant % 3 == 2
	var hh := h * (1.35 if two_story else 1.0)
	# Footing + walls.
	box(body, Vector3(w + 0.3, 0.5, d + 0.3), Vector3(0, 0.25, 0), STONE_DARK)
	box(body, Vector3(w, hh, d), Vector3(0, hh / 2 + 0.2, 0), wall_c)
	if two_story:
		box(body, Vector3(w + 0.6, hh * 0.45, d + 0.6), Vector3(0, hh * 0.775 + 0.2, 0), wall_c.darkened(0.05))
	# Timber frame beams.
	if variant % 2 == 1 or two_story:
		var bw := 0.14
		var fy := hh / 2 + 0.2
		var ext := 0.6 if two_story else 0.0
		for sx in [-1, 1]:
			box(body, Vector3(bw, hh, bw), Vector3(sx * (w / 2 + 0.02), fy, d / 2 + 0.02 + ext / 2), WOOD)
			box(body, Vector3(bw, hh, bw), Vector3(sx * (w / 2 + 0.02), fy, -d / 2 - 0.02 - ext / 2), WOOD)
		box(body, Vector3(w + 0.1, bw, bw), Vector3(0, hh * 0.55 + 0.2, d / 2 + 0.03 + ext / 2), WOOD)
		box(body, Vector3(w + 0.1, bw, bw), Vector3(0, hh * 0.55 + 0.2, -d / 2 - 0.03 - ext / 2), WOOD)
	# Roof: prism, overhanging, plus ridge beam.
	var roof := PrismMesh.new()
	roof.size = Vector3(w + 1.6 + (0.6 if two_story else 0.0), h * 0.62, d + 1.2 + (0.6 if two_story else 0.0))
	mesh_node(body, roof, Vector3(0, hh + 0.2 + roof.size.y / 2, 0), mat(roof_c, 0.03))
	box(body, Vector3(roof.size.x * 0.98, 0.25, 0.25), Vector3(0, hh + 0.2 + roof.size.y, 0), roof_c.darkened(0.3))
	# Eave board under the roof front/back.
	box(body, Vector3(roof.size.x, 0.22, 0.2), Vector3(0, hh + 0.25, roof.size.z / 2 - 0.1), roof_c.darkened(0.35))
	box(body, Vector3(roof.size.x, 0.22, 0.2), Vector3(0, hh + 0.25, -roof.size.z / 2 + 0.1), roof_c.darkened(0.35))
	# Chimney.
	box(body, Vector3(0.7, h * 0.7, 0.7), Vector3(w * 0.3, hh + 0.2 + h * 0.5, -d * 0.2), STONE_DARK)
	box(body, Vector3(0.9, 0.2, 0.9), Vector3(w * 0.3, hh + 0.2 + h * 0.85, -d * 0.2), STONE)
	# Door (front = +z) with frame and step.
	var front := d / 2 + 0.01
	box(body, Vector3(1.3, 2.3, 0.14), Vector3(0, 1.35, front + 0.04), WOOD.darkened(0.1))
	box(body, Vector3(1.0, 2.1, 0.1), Vector3(0, 1.25, front + 0.12), WOOD_LIGHT)
	box(body, Vector3(1.6, 0.18, 0.7), Vector3(0, 0.29, front + 0.3), STONE)
	sphere(body, 0.07, Vector3(0.32, 1.2, front + 0.2), Color("e8c060"))
	# Windows: frames + warm glowing panes.
	var glow := mat(Color("f7d98f"), 0.0, Color("ffb85c"), 0.35)
	var wins := [Vector3(-w * 0.3, 1.7, front), Vector3(w * 0.3, 1.7, front)]
	if two_story:
		wins.append(Vector3(-w * 0.25, hh * 0.78 + 0.3, front + 0.3))
		wins.append(Vector3(w * 0.25, hh * 0.78 + 0.3, front + 0.3))
	for sx in [-1, 1]:
		wins.append(Vector3(sx * (w / 2 + 0.01), 1.8, -d * 0.15))
	for wp in wins:
		var side := absf(wp.x) >= w / 2 - 0.05
		var fsz := Vector3(0.2, 1.1, 1.0) if side else Vector3(1.0, 1.1, 0.2)
		var psz := Vector3(0.12, 0.85, 0.75) if side else Vector3(0.75, 0.85, 0.12)
		box(body, fsz, wp + (Vector3(sign(wp.x) * 0.06, 0, 0) if side else Vector3(0, 0, 0.06)), WOOD)
		var pane := BoxMesh.new()
		pane.size = psz
		mesh_node(body, pane, wp + (Vector3(sign(wp.x) * 0.1, 0, 0) if side else Vector3(0, 0, 0.1)), glow)
		if not side:
			box(body, Vector3(1.1, 0.12, 0.35), wp + Vector3(0, -0.62, 0.15), WOOD_LIGHT)  # Flower box.
	# Collision for the whole footprint.
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w + 0.4, hh + 1.0, d + 0.4)
	cs.shape = bs
	cs.position.y = (hh + 1.0) / 2
	body.add_child(cs)
	return body


## Lantern cage material and lights, dimmed by day and lit at night (DayNight).
static var lantern_material: ShaderMaterial
## Unlit sky dressing (cloud puffs, far hills) that DayNight darkens at night.
static var cloud_material: ShaderMaterial
static var hill_materials: Array = []  # [[StandardMaterial3D, day Color], ...]
static var window_materials: Array = []  # shaders/window_sky.gdshader panes (cottage windows)
## One shared material for every exterior window pane that glows at night
## (the player's cottage): cool glass by day, warm lamplight after dusk.
static var window_glow_material: ShaderMaterial
## Ambient firefly sprites: faded in only after dusk by set_lantern_glow().
static var firefly_material: StandardMaterial3D
## Hex-kit building materials whose window glass glows after dusk (see
## light_hex_windows); keyed by instance id so each is set up once.
static var hex_window_materials := {}
static var _hex_window_mask: ImageTexture
## The KayKit hex atlas (1024², 8x4 cells of 128x256) keeps window glass in
## the grey cell at column 6, row 1; every colour variant shares the layout.
const HEX_GLASS_CELL := Rect2i(768, 256, 128, 256)
static var _petal_tex: ImageTexture
const WINDOW_DAY := Color("c3d2dc")
const WINDOW_NIGHT := Color("ffd98a")
const WINDOW_GLOW := Color("ffb347")

const CLOUD_TOP_DAY := Color(1.0, 0.99, 0.97)
const CLOUD_BOTTOM_DAY := Color(0.72, 0.76, 0.92)
const CLOUD_TOP_NIGHT := Color("3a4270")
const CLOUD_BOTTOM_NIGHT := Color("161b36")
const HILL_NIGHT := Color("131a38")


## night 0..1: dims the unshaded clouds and distant hills so they do not glow
## against the night sky (they ignore scene lights by design).
static func set_night_tint(night: float) -> void:
	if cloud_material:
		cloud_material.set_shader_parameter("top_color", CLOUD_TOP_DAY.lerp(CLOUD_TOP_NIGHT, night))
		cloud_material.set_shader_parameter("bottom_color", CLOUD_BOTTOM_DAY.lerp(CLOUD_BOTTOM_NIGHT, night))
	for pair in hill_materials:
		var m: StandardMaterial3D = pair[0]
		if is_instance_valid(m):
			m.albedo_color = (pair[1] as Color).lerp(HILL_NIGHT, night)
	for wm in window_materials:
		if is_instance_valid(wm):
			wm.set_shader_parameter("night", night)


static func set_lantern_glow(night: float) -> void:
	if lantern_material:
		lantern_material.set_shader_parameter("emission_strength", 0.25 + 2.75 * night)
	if window_glow_material:
		var k := smoothstep(0.15, 0.85, night)
		window_glow_material.set_shader_parameter("albedo", WINDOW_DAY.lerp(WINDOW_NIGHT, k))
		window_glow_material.set_shader_parameter("emission_strength", 2.6 * k)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var wk := smoothstep(0.15, 0.85, night)
		for id in hex_window_materials:
			var hm: StandardMaterial3D = hex_window_materials[id]
			if is_instance_valid(hm):
				hm.emission_energy_multiplier = 2.0 * wk
		var ff := smoothstep(0.35, 0.8, night)
		if firefly_material:
			firefly_material.albedo_color = Color(1, 1, 1, ff)
		for f in tree.get_nodes_in_group("fireflies"):
			f.visible = ff > 0.01
		for l in tree.get_nodes_in_group("lantern_lights"):
			l.light_energy = 1.4 * night
			l.visible = night > 0.02


## Emission mask for the hex atlas: warm lamplight in the glass cell (a touch
## brighter low in the pane, like a lit room seen from outside), black
## elsewhere. 64x32: only the cell boundaries matter.
static func _hex_glass_mask() -> ImageTexture:
	if _hex_window_mask:
		return _hex_window_mask
	var w := 64
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	var x0 := HEX_GLASS_CELL.position.x * w / 1024
	var x1 := HEX_GLASS_CELL.end.x * w / 1024
	var y0 := HEX_GLASS_CELL.position.y * h / 1024
	var y1 := HEX_GLASS_CELL.end.y * h / 1024
	for y in range(y0, y1):
		var t := float(y - y0) / maxf(1.0, y1 - y0 - 1)
		for x in range(x0, x1):
			img.set_pixel(x, y, Color(1.0, 0.78, 0.48).lerp(Color(1.0, 0.62, 0.3), t))
	_hex_window_mask = ImageTexture.create_from_image(img)
	return _hex_window_mask


## Makes the window glass of a KayKit hex building glow after dusk: the
## building's (shared, toon) atlas materials get an emission mask over the
## glass cell, and DayNight drives their energy via set_lantern_glow. Every
## house of a colour shares one material, so this costs nothing per house.
static func light_hex_windows(root: Node) -> void:
	if headless() or root == null:
		return
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_active_material(si) as StandardMaterial3D
			if m == null or m.albedo_texture == null or hex_window_materials.has(m.get_instance_id()):
				continue
			if not "hex_medieval/buildings" in m.albedo_texture.resource_path:
				continue
			m.emission_enabled = true
			m.emission = Color(1, 1, 1)
			m.emission_texture = _hex_glass_mask()
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			m.emission_energy_multiplier = 0.0
			hex_window_materials[m.get_instance_id()] = m


## A thin exterior window pane that glows warm at night (DayNight ->
## set_lantern_glow). `size` is the pane's (width, height) in the parent's
## units; the pane lies in the parent's XY plane facing +Z.
static func window_glow_pane(parent: Node3D, pos: Vector3, size: Vector2, rot := Vector3.ZERO) -> MeshInstance3D:
	if window_glow_material == null:
		window_glow_material = ToonMaterial.make(WINDOW_DAY, WINDOW_GLOW, 0.0)
	var pane := BoxMesh.new()
	pane.size = Vector3(size.x, size.y, 0.004)
	var mi := mesh_node(parent, pane, pos, window_glow_material, rot)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func lantern(parent: Node3D, pos: Vector3, with_light := true, height := 3.2) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	cyl(n, 0.2, 0.3, 0.3, Vector3(0, 0.15, 0), STONE_DARK, 8)
	cyl(n, 0.07, 0.1, height, Vector3(0, height / 2, 0), Color("3a3440"), 8)
	box(n, Vector3(0.9, 0.08, 0.08), Vector3(0.35, height - 0.1, 0), Color("3a3440"))
	var cage := BoxMesh.new()
	cage.size = Vector3(0.42, 0.55, 0.42)
	if lantern_material == null:
		lantern_material = ToonMaterial.make(Color("fff0c0"), LANTERN, 0.25)
	mesh_node(n, cage, Vector3(0.75, height - 0.5, 0), lantern_material)
	var cap := PrismMesh.new()
	cap.size = Vector3(0.6, 0.3, 0.6)
	mesh_node(n, cap, Vector3(0.75, height - 0.08, 0), mat(Color("3a3440")))
	lantern_light(n, Vector3(0.75, height - 0.5, 0))
	return n


## The lantern OmniLight (group "lantern_lights"): off by day, DayNight
## switches it on after dusk. Skipped headless.
static func lantern_light(parent: Node3D, pos: Vector3) -> OmniLight3D:
	if headless():
		return null
	var l := OmniLight3D.new()
	l.light_color = LANTERN
	l.light_energy = 0.0
	l.visible = false
	l.omni_range = 9.0
	l.omni_attenuation = 1.4
	l.position = pos
	l.shadow_enabled = false
	l.add_to_group("lantern_lights")
	parent.add_child(l)
	return l


static func fountain(parent: Node3D, pos: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	cyl(n, 3.2, 3.4, 0.9, Vector3(0, 0.45, 0), STONE, 24)
	cyl(n, 2.8, 2.8, 0.95, Vector3(0, 0.48, 0), STONE_DARK, 24)
	var w := CylinderMesh.new()
	w.top_radius = 2.75
	w.bottom_radius = 2.75
	w.height = 0.05
	w.radial_segments = 24
	mesh_node(n, w, Vector3(0, 0.82, 0), water_mat(Vector2(0.3, 1), 0.3))
	cyl(n, 0.35, 0.5, 1.8, Vector3(0, 1.4, 0), STONE, 12)
	cyl(n, 1.2, 1.0, 0.3, Vector3(0, 2.3, 0), STONE, 16)
	var w2 := CylinderMesh.new()
	w2.top_radius = 1.0
	w2.bottom_radius = 1.0
	w2.height = 0.05
	mesh_node(n, w2, Vector3(0, 2.48, 0), water_mat(Vector2(1, 1), 0.4))
	cyl(n, 0.12, 0.2, 1.0, Vector3(0, 2.9, 0), STONE, 8)
	sphere(n, 0.35, Vector3(0, 3.5, 0), Color("9fe3f0"))
	collider(n, _cyl_shape(3.4, 1.0), Vector3(0, 0.5, 0))
	if not headless():
		var spray := _particles(Vector3(0, 3.6, 0), 90, 1.6, Vector3(0.15, 0.1, 0.15), Color(0.85, 0.97, 1.0, 0.8), 0.12, -9.0)
		spray.process_material.direction = Vector3(0, 1, 0)
		spray.process_material.spread = 25.0
		spray.process_material.initial_velocity_min = 3.5
		spray.process_material.initial_velocity_max = 5.0
		n.add_child(spray)


static func _cyl_shape(r: float, h: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return s


static func windmill(parent: Node3D, pos: Vector3, rot_y := 0.0) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot_y
	parent.add_child(n)
	cyl(n, 2.4, 3.2, 9.0, Vector3(0, 4.5, 0), CREAM, 12)
	cyl(n, 2.6, 3.4, 0.6, Vector3(0, 0.3, 0), STONE_DARK, 12)
	var cap := CylinderMesh.new()
	cap.top_radius = 0.2
	cap.bottom_radius = 2.9
	cap.height = 2.4
	cap.radial_segments = 12
	mesh_node(n, cap, Vector3(0, 10.2, 0), mat(TERRACOTTA, 0.03))
	box(n, Vector3(1.0, 2.0, 0.12), Vector3(0, 1.2, 3.1), WOOD)
	var hub := Node3D.new()
	hub.position = Vector3(0, 8.6, 3.3)
	n.add_child(hub)
	cyl(n, 0.3, 0.3, 1.2, Vector3(0, 8.6, 2.8), WOOD, 8, Vector3(PI / 2, 0, 0))
	for i in 4:
		var blade := Node3D.new()
		blade.rotation.z = TAU * i / 4.0
		hub.add_child(blade)
		box(blade, Vector3(0.18, 5.5, 0.18), Vector3(0, 2.75, 0), WOOD)
		box(blade, Vector3(1.4, 4.6, 0.06), Vector3(0.75, 3.0, 0.1), Color("f7efe0"), Vector3.ZERO, 0.02)
	var tw := n.create_tween().set_loops()
	tw.tween_property(hub, "rotation:z", TAU, 9.0).from(0.0)
	collider(n, _cyl_shape(3.2, 9.0), Vector3(0, 4.5, 0))


## Crenellated stone wall arc around the town, with gaps for the gates and
## gate towers flanking them. Visuals come from the Kenney castle kit through
## WorldProps.castle_wall when it is installed (one MultiMesh per piece type),
## otherwise from banded-stone blocks. Collision is one StaticBody either way.
static func town_wall(parent: Node3D, center: Vector3, radius: float, gaps: Array) -> void:
	var seg_len := 4.0
	var count := int(TAU * radius / seg_len)
	var use_pack := WorldProps.has_castle_walls()
	var depth := 3.0 if use_pack else 1.4
	var height := 5.0 if use_pack else 3.6
	var body := StaticBody3D.new()
	body.name = "TownWall"
	parent.add_child(body)
	var angles := []
	var gate_angles := []
	for i in count:
		var a := TAU * i / count
		var in_gap := false
		for g in gaps:
			var dlt := absf(wrapf(a - g[0], -PI, PI))
			if dlt < g[1]:
				in_gap = true
				if dlt > g[1] - TAU / count * 1.01:
					gate_angles.append(a)
		if in_gap:
			continue
		angles.append(a)
		var p := center + Vector3(cos(a), 0, sin(a)) * radius
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(seg_len + 0.15, height, depth)
		cs.shape = bs
		cs.position = p + Vector3(0, height / 2, 0)
		cs.rotation.y = -a - PI / 2
		body.add_child(cs)
	for a in gate_angles:
		var p := center + Vector3(cos(a), 0, sin(a)) * radius
		collider(parent, _cyl_shape(2.2 if use_pack else 1.8, 12.0 if use_pack else 5.5), p + Vector3(0, 6.0 if use_pack else 2.75, 0))
	if use_pack and WorldProps.castle_wall(parent, center, radius, angles, gate_angles, seg_len):
		return
	# Procedural fallback: banded stone blocks with merlons and gate turrets.
	var block := BoxMesh.new()
	block.size = Vector3(seg_len + 0.15, height, depth)
	var merlon := BoxMesh.new()
	merlon.size = Vector3(1.0, 0.8, depth + 0.1)
	var xs := []
	var mx := []
	var cols := []
	for i in angles.size():
		var a: float = angles[i]
		var p := center + Vector3(cos(a), 0, sin(a)) * radius
		xs.append(xf(p + Vector3(0, height / 2, 0), -a - PI / 2))
		cols.append(Color.WHITE.lerp(Color("d8d4dd"), fmod(i * 0.37, 1.0)))
		for k: float in [-1.3, 0.0, 1.3]:
			var mp: Vector3 = p + Vector3(-sin(a), 0, cos(a)) * k
			mx.append(xf(mp + Vector3(0, height + 0.4, 0), -a - PI / 2))
	var wall_stone := stone_mat(Color("b3aeb9"), Color("968f9e"), "castle_brick_07", 0.3, {"band_period": 0.9, "band_width": 0.08, "brick_length": 1.8})
	wall_stone.next_pass = ToonMaterial.outline(0.03)
	var wm := multimesh(parent, block, xs, cols, "WallBlocks")
	wm.material_override = wall_stone
	var mm := multimesh(parent, merlon, mx, [], "WallMerlons")
	mm.material_override = mat(STONE_DARK, 0.02)
	for a in gate_angles:
		var p := center + Vector3(cos(a), 0, sin(a)) * radius
		var tc := cyl(parent, 1.6, 1.8, 5.5, p + Vector3(0, 2.75, 0), STONE, 12)
		tc.material_override = wall_stone
		var cone := CylinderMesh.new()
		cone.top_radius = 0.1
		cone.bottom_radius = 2.1
		cone.height = 2.2
		cone.radial_segments = 12
		mesh_node(parent, cone, p + Vector3(0, 6.6, 0), mat(TEAL, 0.03))
		# Banner.
		box(parent, Vector3(0.06, 2.4, 0.8), p + Vector3(cos(a) * 1.9, 3.8, sin(a) * 1.9), Color("c93d5a"), Vector3(0, -a, 0), 0.0)


static func fence_line(parent: Node3D, a: Vector3, b: Vector3, xs: Array) -> void:
	var dir := b - a
	var n := int(dir.length() / 2.2)
	for i in n + 1:
		var p := a + dir * (float(i) / n)
		xs.append(xf(p, -atan2(dir.z, dir.x), Vector3.ONE))


static func fence_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var post := BoxMesh.new()
	post.size = Vector3(0.16, 1.2, 0.16)
	st.append_from(post, 0, Transform3D(Basis(), Vector3(0, 0.6, 0)))
	var rail := BoxMesh.new()
	rail.size = Vector3(2.2, 0.1, 0.08)
	st.append_from(rail, 0, Transform3D(Basis(), Vector3(1.1, 0.95, 0)))
	st.append_from(rail, 0, Transform3D(Basis(), Vector3(1.1, 0.5, 0)))
	return st.commit()


static func fences(parent: Node3D, lines: Array) -> void:
	var xs := []
	for l in lines:
		fence_line(parent, l[0], l[1], xs)
	var mm := multimesh(parent, fence_mesh(), xs, [], "Fences")
	mm.material_override = mat(WOOD_LIGHT, 0.02)


static func crate(parent: Node3D, pos: Vector3, s := 1.0, rot := 0.0) -> void:
	box(parent, Vector3(s, s, s), pos + Vector3(0, s / 2, 0), WOOD_LIGHT, Vector3(0, rot, 0))
	box(parent, Vector3(s * 1.02, 0.08, s * 1.02), pos + Vector3(0, s * 0.5, 0), WOOD, Vector3(0, rot, 0))


static func barrel(parent: Node3D, pos: Vector3) -> void:
	cyl(parent, 0.45, 0.45, 1.0, pos + Vector3(0, 0.5, 0), WOOD, 10)
	cyl(parent, 0.5, 0.5, 0.12, pos + Vector3(0, 0.25, 0), STONE_DARK, 10)
	cyl(parent, 0.5, 0.5, 0.12, pos + Vector3(0, 0.78, 0), STONE_DARK, 10)


static func market_stall(parent: Node3D, pos: Vector3, rot_y: float, cloth: Color) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot_y
	parent.add_child(n)
	box(n, Vector3(3.0, 0.9, 1.2), Vector3(0, 0.45, 0), WOOD_LIGHT)
	for sx in [-1, 1]:
		cyl(n, 0.07, 0.07, 2.6, Vector3(sx * 1.4, 1.3, -0.5), WOOD, 6)
		cyl(n, 0.07, 0.07, 2.3, Vector3(sx * 1.4, 1.15, 0.6), WOOD, 6)
	var awn := PrismMesh.new()
	awn.size = Vector3(3.4, 0.5, 1.8)
	mesh_node(n, awn, Vector3(0, 2.65, 0.05), mat(cloth, 0.02), Vector3(0, 0, 0))
	box(n, Vector3(3.4, 0.08, 1.8), Vector3(0, 2.42, 0.05), cloth.darkened(0.2), Vector3.ZERO, 0.0)
	for i in 3:
		sphere(n, 0.22, Vector3(-0.8 + i * 0.8, 1.1, 0.1), [Color("e94f37"), Color("f6c445"), Color("8ac926")][i])
	box_collider(parent, Vector3(3.0, 1.2, 1.2), pos + Vector3(0, 0.6, 0), Vector3(0, rot_y, 0))


## Procedural carved pillar (fallback for WorldProps.portal_pillars): fluted
## shaft with eight ribs and a moulded neck. Plinth, cap and runes are added
## by the caller.
static func ornate_pillar(parent: Node3D, pos: Vector3, height: float, c := Color("e9e6f2")) -> void:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	cyl(n, 0.5, 0.56, height, Vector3(0, height / 2, 0), c, 12)
	var rib := BoxMesh.new()
	rib.size = Vector3(0.14, height - 1.4, 0.2)
	var xs := []
	for k in 8:
		var a := TAU * k / 8.0
		xs.append(xf(Vector3(cos(a) * 0.52, height / 2, sin(a) * 0.52), -a, Vector3.ONE))
	var mm := multimesh(n, rib, xs, [], "Ribs")
	mm.material_override = mat(c.darkened(0.12), 0.0)
	cyl(n, 0.7, 0.6, 0.3, Vector3(0, height - 0.5, 0), STONE, 12)
	cyl(n, 0.6, 0.7, 0.3, Vector3(0, 0.8, 0), STONE, 12)


static func rune_ring(parent: Node3D, pos: Vector3, r: float, c: Color, width := 0.25) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r - width
	t.outer_radius = r
	t.rings = 48
	t.ring_segments = 6
	return mesh_node(parent, t, pos, rune_mat(c), Vector3.ZERO, Vector3(1, 0.25, 1))


# --- The Labyrinth tower -----------------------------------------------------

## Monumental ancient stone tower: banded brick courses laid around the axis
## (shaders/stone.gdshader with the castle_brick_07 map), ribs, ring ledges,
## buttresses, glowing rune bands, ivy at the foot, castle-kit turrets around
## the base (WorldProps.tower_base) and a crown that fades into a wreath of
## clouds. Collision stays the cylinder in world.gd.
static func tower(parent: Node3D, pos: Vector3) -> void:
	var n := Node3D.new()
	n.name = "TowerArt"
	n.position = pos
	parent.add_child(n)
	var tiers := [[12.0, 11.0, 0.0, 62.0], [10.6, 9.8, 62.0, 78.0], [9.4, 8.6, 140.0, 80.0]]
	var fade := {"fade_start": 150.0, "fade_end": 214.0, "fade_color": Color("dfe4f3")}
	var stone := stone_mat(Color("a7a1b8"), Color("8b839f"), "castle_brick_07", 0.22, fade)
	stone.set_shader_parameter("band_period", 2.6)
	stone.set_shader_parameter("band_width", 0.16)
	stone.set_shader_parameter("brick_length", 3.6)
	stone.set_shader_parameter("polar", 1.0)
	stone.set_shader_parameter("center", Vector2(pos.x, pos.z))
	stone.set_shader_parameter("polar_radius", 11.0)
	stone.set_shader_parameter("rune_heights", Vector3(31.0, 105.0, 178.0))
	stone.set_shader_parameter("rune_width", 1.8)
	stone.set_shader_parameter("rune_color", Color("a66bff"))
	stone.set_shader_parameter("rune_strength", 2.8)
	var trim := stone_mat(Color("6f6886"), Color("5a536f"), "rock_wall_10", 0.3, fade)
	trim.set_shader_parameter("detail_strength", 0.45)
	var ledge_mat := stone_mat(Color("7d7694"), Color("645d7a"), "castle_brick_07", 0.3, fade)
	var rib := BoxMesh.new()
	rib.size = Vector3.ONE
	var ribs := []
	var ring := CylinderMesh.new()
	ring.top_radius = 1.0
	ring.bottom_radius = 1.0
	ring.height = 1.0
	ring.radial_segments = 32
	ring.rings = 1
	var rings := []
	for i in tiers.size():
		var t: Array = tiers[i]
		var shaft := CylinderMesh.new()
		shaft.top_radius = t[1]
		shaft.bottom_radius = t[0]
		shaft.height = t[3]
		shaft.radial_segments = 36
		shaft.rings = 6
		mesh_node(n, shaft, Vector3(0, t[2] + t[3] / 2, 0), stone)
		# Corbelled ledge and parapet rail at the top of each tier.
		var ledge := CylinderMesh.new()
		ledge.top_radius = t[1] + 1.8
		ledge.bottom_radius = t[1] + 0.3
		ledge.height = 1.8
		ledge.radial_segments = 36
		mesh_node(n, ledge, Vector3(0, t[2] + t[3] - 0.9, 0), ledge_mat)
		var rail := TorusMesh.new()
		rail.inner_radius = t[1] + 1.2
		rail.outer_radius = t[1] + 1.8
		rail.rings = 36
		mesh_node(n, rail, Vector3(0, t[2] + t[3] + 0.5, 0), ledge_mat, Vector3.ZERO, Vector3(1, 2.0, 1))
		rune_ring(n, Vector3(0, t[2] + t[3] + 1.25, 0), t[1] + 1.55, Color("a66bff"), 0.22)
		# Twelve ribs per tier (one MultiMesh for all of them).
		for k in 12:
			var a := TAU * k / 12.0
			var r_mid: float = (t[0] + t[1]) * 0.5 - 0.1
			ribs.append(xf(Vector3(cos(a) * r_mid, t[2] + t[3] / 2, sin(a) * r_mid), -a, Vector3(1.4, t[3], 1.4)))
		# Thin ring ledges every ~25 m so the height reads from the ground.
		var y: float = t[2] + 22.0
		while y < t[2] + t[3] - 8.0:
			var rr: float = lerpf(t[0], t[1], (y - t[2]) / t[3])
			rings.append(xf(Vector3(0, y, 0), 0.0, Vector3(rr + 0.7, 0.8, rr + 0.7)))
			y += 25.0
	var rm := multimesh(n, rib, ribs, [], "TowerRibs")
	rm.material_override = trim
	var lm := multimesh(n, ring, rings, [], "TowerLedges")
	lm.material_override = ledge_mat
	# Crown: a ring of spikes and a floating crystal above the summit arena.
	var spikes := CylinderMesh.new()
	spikes.top_radius = 0.0
	spikes.bottom_radius = 0.8
	spikes.height = 6.0
	spikes.radial_segments = 6
	for k in 12:
		var a := TAU * k / 12.0
		mesh_node(n, spikes, Vector3(cos(a) * 18.5, 222 + 3.0, sin(a) * 18.5), mat(Color("6b5a86"), 0.03))
	# Buttresses at the foot: tall stone fins with a stepped shoulder.
	for k in 6:
		var a := TAU * k / 6.0 + PI / 6
		var bm := PrismMesh.new()
		bm.size = Vector3(3.0, 18.0, 8.0)
		mesh_node(n, bm, Vector3(cos(a) * 14.6, 9.0, sin(a) * 14.6), trim, Vector3(0, -a - PI / 2, 0))
		var shoulder := BoxMesh.new()
		shoulder.size = Vector3(3.6, 1.2, 8.6)
		mesh_node(n, shoulder, Vector3(cos(a) * 14.6, 0.6, sin(a) * 14.6), ledge_mat, Vector3(0, -a - PI / 2, 0))
	# Glowing windows spiralling up.
	var win := BoxMesh.new()
	win.size = Vector3(1.2, 2.4, 0.5)
	var wx := []
	for k in 70:
		var y := 8.0 + k * 3.0
		var a := k * 0.55
		var r := 12.0 - (y / 220.0) * 3.6
		wx.append(xf(Vector3(cos(a) * r, y, sin(a) * r), -a + PI / 2))
	var wm := multimesh(n, win, wx, [], "TowerWindows")
	wm.material_override = mat(Color("8fd0ff"), 0.0, Color("6fc2ff"), 2.0)
	# Ivy clinging to the lower shaft and buttresses (one MultiMesh).
	var ivy := SphereMesh.new()
	ivy.radius = 1.0
	ivy.height = 1.6
	ivy.radial_segments = 8
	ivy.rings = 4
	var ivy_xs := []
	var ivy_cs := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in 260:
		var a := rng.randf() * TAU
		if absf(wrapf(a - PI / 2, -PI, PI)) < 0.5:
			continue
		var y := rng.randf_range(0.3, 30.0) * rng.randf_range(0.25, 1.0)
		var r := 12.0 - y / 62.0 - 0.1
		var s := rng.randf_range(0.5, 1.4) * (1.0 - y / 60.0)
		ivy_xs.append(xf(Vector3(cos(a) * r, y, sin(a) * r), -a + PI / 2, Vector3(s, s * 1.8, s * 0.3)))
		ivy_cs.append(Color("2f6e2e").lerp(Color("5fa84a"), rng.randf()))
	var im := multimesh(n, ivy, ivy_xs, ivy_cs, "TowerIvy")
	im.material_override = foliage_mat(Color.WHITE, 0.25)
	# Castle-kit turrets around the base (procedural towers without the pack).
	if not WorldProps.tower_base(parent, pos):
		for k in 4:
			var a := deg_to_rad(40.0 + 90.0 * k) + PI / 2
			var p := Vector3(cos(a) * 15.5, 0, sin(a) * 15.5)
			var tc := cyl(n, 2.0, 2.2, 14.0, p + Vector3(0, 7, 0), STONE, 12)
			tc.material_override = stone
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 2.6
			cone.height = 4.0
			cone.radial_segments = 12
			mesh_node(n, cone, p + Vector3(0, 16, 0), mat(Color("4b4470"), 0.03))
			collider(n, _cyl_shape(2.2, 14.0), p + Vector3(0, 7, 0))
	# Cloud wreath where the shaft fades out, so the top is lost in the sky.
	if cloud_material == null:
		cloud_material = ShaderMaterial.new()
		cloud_material.shader = shader("cloud")
	var cx := []
	var cc := []
	for i in 30:
		var a := rng.randf() * TAU
		var r := rng.randf_range(7.0, 15.0)
		var y := rng.randf_range(184.0, 214.0)
		var s := rng.randf_range(3.5, 7.5)
		cx.append(xf(Vector3(cos(a) * r, y, sin(a) * r), rng.randf() * TAU, Vector3(s, s * 0.45, s * 0.8)))
		cc.append(Color.WHITE.lerp(Color("e8e4f6"), rng.randf() * 0.6))
	var cm := multimesh(n, cloud_mesh(), cx, cc, "TowerClouds")
	cm.material_override = cloud_material
	cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Gate: arch, carved jambs, inner glow and rune steps. The door body
	# itself stays in world.gd.
	var arch := TorusMesh.new()
	arch.inner_radius = 3.6
	arch.outer_radius = 4.8
	arch.rings = 32
	mesh_node(n, arch, Vector3(0, 4.0, 12.3), trim, Vector3(0, 0, 0), Vector3(1, 1, 0.6))
	var jamb := BoxMesh.new()
	jamb.size = Vector3(1.6, 9.0, 1.6)
	for sx in [-1, 1]:
		mesh_node(n, jamb, Vector3(sx * 5.2, 4.5, 12.4), ledge_mat)
		box(n, Vector3(2.1, 0.5, 2.1), Vector3(sx * 5.2, 9.2, 12.4), STONE_DARK, Vector3.ZERO, 0.03)
		sphere(n, 0.55, Vector3(sx * 5.2, 9.9, 12.4), Color("c89bff"))
		mesh_node(n, SphereMesh.new(), Vector3(sx * 5.2, 9.9, 12.4), mat(Color("d9c2ff"), 0.0, Color("9a5cff"), 3.0), Vector3.ZERO, Vector3(0.5, 0.5, 0.5))
	rune_ring(n, Vector3(0, 0.08, 15.5), 3.2, Color("a66bff"))
	cyl(n, 4.5, 4.5, 0.3, Vector3(0, 0.15, 16.0), STONE, 24)
	cyl(n, 5.5, 5.5, 0.3, Vector3(0, 0.0, 17.5), STONE_DARK, 24)


# --- Labyrinth terraces and summit (carved ruins) -------------------------------

static var _ruin_mats := {}


## Shared ruin stone materials: "wall" (brick courses, castle_brick_07),
## "trim" (rough rock_wall_10), "ledge" (lighter courses).
static func ruin_mat(kind: String) -> ShaderMaterial:
	if _ruin_mats.has(kind):
		return _ruin_mats[kind]
	var m: ShaderMaterial
	match kind:
		"trim":
			m = stone_mat(Color("6f6886"), Color("5a536f"), "rock_wall_10", 0.3)
			m.set_shader_parameter("detail_strength", 0.45)
		"ledge":
			m = stone_mat(Color("8d86a6"), Color("746d8c"), "castle_brick_07", 0.3)
			m.set_shader_parameter("band_period", 0.6)
			m.set_shader_parameter("band_width", 0.08)
			m.set_shader_parameter("brick_length", 1.8)
		_:
			m = stone_mat(Color("a7a1b8"), Color("8b839f"), "castle_brick_07", 0.22)
			m.set_shader_parameter("band_period", 1.0)
			m.set_shader_parameter("band_width", 0.1)
			m.set_shader_parameter("brick_length", 2.2)
	_ruin_mats[kind] = m
	return m


## Flagstone floor laid in rings around `center` (for the slab discs).
static func platform_floor_mat(center: Vector2, rune := Color.BLACK, rune_y := -10000.0) -> ShaderMaterial:
	var m := stone_mat(Color("a49eb6"), Color("867e9b"), "cobblestone_floor_08", 0.35, {
		"floor_period": 1.7, "polar": 1.0, "center": center, "polar_radius": 10.0,
		"band_period": 0.5, "band_width": 0.1, "brick_length": 1.7, "band_dark": 0.66})
	if rune != Color.BLACK:
		m.set_shader_parameter("rune_heights", Vector3(rune_y, -10000.0, -10000.0))
		m.set_shader_parameter("rune_width", 0.5)
		m.set_shader_parameter("rune_color", rune)
		m.set_shader_parameter("rune_strength", 2.2)
	return m


## Dresses a floating ruin terrace: inverted-ziggurat underside with glowing
## rune courses, ribbed buttresses, a root spire, hanging crags (nature kit
## or procedural), a corbelled lip, floor rune rings, moss and ivy. Parapets
## and pillars come from WorldProps (world.gd keeps their colliders).
static func platform_dress(parent: Node3D, base: Vector3, radius: float, rune: Color, gap_dir: Vector3 = Vector3.ZERO, gap_cos := 2.0) -> void:
	var n := Node3D.new()
	n.name = "PlatformDress"
	n.position = base
	parent.add_child(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base.y) * 7 + 3
	var c2 := Vector2(base.x, base.z)
	# Underside courses: bricks laid around the axis, two rune bands.
	var wall := stone_mat(Color("9d96b2"), Color("7f7794"), "castle_brick_07", 0.22, {
		"band_period": 0.9, "band_width": 0.1, "brick_length": 2.4, "polar": 1.0, "center": c2,
		"polar_radius": radius * 0.7, "rune_heights": Vector3(base.y - 2.6, base.y - 6.6, -10000.0),
		"rune_width": 0.7, "rune_color": rune, "rune_strength": 2.4})
	var tiers := [[radius + 0.5, 1.6], [radius * 0.84, 1.9], [radius * 0.66, 2.1], [radius * 0.48, 2.3]]
	var y := -0.5
	var tier := CylinderMesh.new()
	tier.top_radius = 1.0
	tier.bottom_radius = 1.0
	tier.height = 1.0
	tier.radial_segments = 32
	tier.rings = 1
	var tier_xs := []
	var corbel := TorusMesh.new()
	corbel.inner_radius = 0.86
	corbel.outer_radius = 1.0
	corbel.rings = 32
	corbel.ring_segments = 6
	var corbel_xs := []
	for t in tiers:
		var r: float = t[0]
		var h: float = t[1]
		tier_xs.append(xf(Vector3(0, y - h / 2, 0), 0.0, Vector3(r, h, r)))
		corbel_xs.append(xf(Vector3(0, y - h, 0), 0.0, Vector3(r + 0.25, 0.9, r + 0.25)))
		y -= h
	var tm := multimesh(n, tier, tier_xs, [], "UnderTiers")
	tm.material_override = wall
	var cm := multimesh(n, corbel, corbel_xs, [], "UnderCorbels")
	cm.material_override = ruin_mat("ledge")
	# Root spire and a glowing keystone at its tip.
	var spire := CylinderMesh.new()
	spire.top_radius = radius * 0.36
	spire.bottom_radius = 0.0
	spire.height = radius * 0.8
	spire.radial_segments = 10
	mesh_node(n, spire, Vector3(0, y - spire.height / 2 + 0.2, 0), ruin_mat("trim"))
	var key := CylinderMesh.new()
	key.top_radius = 0.0
	key.bottom_radius = 0.7
	key.height = 2.2
	key.radial_segments = 4
	mesh_node(n, key, Vector3(0, y - spire.height - 0.6, 0), mat(rune.lightened(0.3), 0.0, rune, 3.0), Vector3(PI, 0, 0))
	# Eight ribbed buttresses from the lip down to the spire.
	var rib := BoxMesh.new()
	rib.size = Vector3.ONE
	var rib_xs := []
	var top := Vector3(0, -0.8, 0)
	var bot_y := y - spire.height * 0.45
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8
		var d := Vector3(cos(a), 0, sin(a))
		var from := d * (radius + 0.2) + top
		var to := d * (radius * 0.2) + Vector3(0, bot_y, 0)
		var dir := to - from
		var b := Basis.looking_at(dir.normalized(), d.cross(Vector3.UP)).scaled(Vector3(1.3, 1.1, dir.length()))
		rib_xs.append(Transform3D(b, (from + to) * 0.5))
	var rm := multimesh(n, rib, rib_xs, [], "UnderRibs")
	rm.material_override = ruin_mat("trim")
	# Corbelled lip under the rim.
	var lip := TorusMesh.new()
	lip.inner_radius = radius - 0.3
	lip.outer_radius = radius + 0.7
	lip.rings = 48
	mesh_node(n, lip, Vector3(0, -0.35, 0), ruin_mat("ledge"), Vector3.ZERO, Vector3(1, 0.6, 1))
	# Hanging crags under the tiers.
	if not WorldProps.hanging_crags(n, Vector3.ZERO, radius, rng, int(radius * 2.4)):
		var xs := []
		var cs := []
		for i in 22:
			var a := rng.randf() * TAU
			var r := rng.randf_range(radius * 0.35, radius * 0.95)
			var s := rng.randf_range(0.8, 2.0)
			xs.append(xf(Vector3(cos(a) * r, -1.5 - (radius - r) * 0.45 - s * 0.5, sin(a) * r), a, Vector3(s, s * 1.8, s * 0.9), Vector3(PI + rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.3, 0.3))))
			cs.append(Color("7d7592").lerp(Color("625a7a"), rng.randf()))
		var crag := multimesh(n, rock_mesh(), xs, cs, "Crags")
		crag.material_override = mat(Color.WHITE, 0.03)
	# Floor rune rings.
	rune_ring(n, Vector3(0, 0.06, 0), radius * 0.55, rune, 0.2)
	rune_ring(n, Vector3(0, 0.06, 0), radius * 0.3, rune, 0.12)
	# Ivy spilling over the rim and moss on the flags (one MultiMesh each).
	var ivy := SphereMesh.new()
	ivy.radius = 1.0
	ivy.height = 1.6
	ivy.radial_segments = 8
	ivy.rings = 4
	var ivy_xs := []
	var ivy_cs := []
	for i in int(radius * 7.0):
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a))
		if gap_dir != Vector3.ZERO and d.dot(gap_dir) > gap_cos - 0.1:
			continue
		var s := rng.randf_range(0.22, 0.55)
		var drop := rng.randf_range(0.1, 1.8)
		ivy_xs.append(xf(d * (radius + 0.55) + Vector3(0, -drop * 0.6, 0), -a + PI / 2, Vector3(s, s * 1.3 + drop * 0.35, s * 0.3)))
		ivy_cs.append(Color("2f6e2e").lerp(Color("5fa84a"), rng.randf()))
	var moss_xs := []
	var moss_cs := []
	for i in int(radius * 1.4):
		var a := rng.randf() * TAU
		var r := rng.randf_range(3.5, radius - 1.6)
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		if absf(p.x) < 3.0 and absf(absf(p.z) - 9.0) < 3.0:
			continue  # Keep the teleport pads clear.
		var s := rng.randf_range(0.45, 1.2)
		moss_xs.append(xf(p, a, Vector3(s, 0.07, s * rng.randf_range(0.5, 1.0))))
		moss_cs.append(Color("3e7a35").lerp(Color("79b85a"), rng.randf()))
	var im := multimesh(n, ivy, ivy_xs + moss_xs, ivy_cs + moss_cs, "IvyMoss")
	im.material_override = foliage_mat(Color.WHITE, 0.25)
	im.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Summoning circle (shaders/rune_floor.gdshader) laid over the flagstones.
static func rune_floor(parent: Node3D, pos: Vector3, radius: float, c: Color, strength := 3.2) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2, radius * 2)
	var m := ShaderMaterial.new()
	m.shader = shader("rune_floor")
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("strength", strength)
	var mi := mesh_node(parent, pm, pos + Vector3(0, 0.05, 0), m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Ruined column: plinth, graveyard-kit carved shaft (fluted procedural one
## without the pack), rune collar, and either a carved cap with a crystal
## finial or a snapped top with a fallen drum beside it. Visual only.
static func broken_column(parent: Node3D, pos: Vector3, height: float, rune: Color, broken := false, width := 1.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	var h := height * (0.55 if broken else 1.0)
	mesh_node(n, BoxMesh.new(), Vector3(0, 0.25, 0), ruin_mat("ledge"), Vector3.ZERO, Vector3(width * 2.0, 0.5, width * 2.0))
	mesh_node(n, BoxMesh.new(), Vector3(0, 0.65, 0), ruin_mat("trim"), Vector3.ZERO, Vector3(width * 1.6, 0.3, width * 1.6))
	if WorldProps.has("graveyard", "column-large"):
		var a := AssetLib.aabb("graveyard", "column-large")
		var col := WorldProps.tinted_prop(n, "graveyard", "column-large", Vector3(0, 0.8, 0), 0.0, 1.0, "none", Color("d9d3ea"))
		var sy := (h - 0.8) / maxf(a.size.y, 0.1)
		col.scale = Vector3(sy * 0.5 * width, sy, sy * 0.5 * width)
	else:
		ornate_pillar(n, Vector3(0, 0.8, 0), h - 0.8, Color("c9c3da"))
	var ring := rune_ring(n, Vector3(0, h * 0.42, 0), width * 0.95, rune, 0.18)
	ring.scale = Vector3(1, 1.4, 1)
	if broken:
		# Snapped shaft: a jagged crown and a fallen drum.
		var crown := CylinderMesh.new()
		crown.top_radius = width * 0.55
		crown.bottom_radius = width * 0.72
		crown.height = 0.6
		crown.radial_segments = 7
		mesh_node(n, crown, Vector3(0, h + 0.2, 0), ruin_mat("trim"), Vector3(0.12, 0.3, -0.1))
		var drum := CylinderMesh.new()
		drum.top_radius = width * 0.6
		drum.bottom_radius = width * 0.6
		drum.height = 1.6
		drum.radial_segments = 10
		mesh_node(n, drum, Vector3(width * 1.9, 0.6, width * 0.6), ruin_mat("trim"), Vector3(PI / 2, 0.6, 0.2))
	else:
		mesh_node(n, BoxMesh.new(), Vector3(0, h + 0.2, 0), ruin_mat("ledge"), Vector3.ZERO, Vector3(width * 1.7, 0.4, width * 1.7))
		var crystal := CylinderMesh.new()
		crystal.top_radius = 0.0
		crystal.bottom_radius = 0.42
		crystal.height = 1.3
		crystal.radial_segments = 4
		var cmat := mat(rune.lightened(0.35), 0.0, rune, 2.5)
		mesh_node(n, crystal, Vector3(0, h + 1.05, 0), cmat)
		mesh_node(n, crystal, Vector3(0, h + 0.4, 0), cmat, Vector3(PI, 0, 0), Vector3(0.7, 0.35, 0.7))
	return n


## Stone brazier with a cel flame, embers and (unless headless or
## with_light is false) an OmniLight in the "arena_lights" group that
## world.gd switches on only while someone is on the summit.
static func brazier(parent: Node3D, pos: Vector3, with_light := true) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	mesh_node(n, BoxMesh.new(), Vector3(0, 0.3, 0), ruin_mat("ledge"), Vector3.ZERO, Vector3(1.4, 0.6, 1.4))
	cyl(n, 0.22, 0.3, 0.9, Vector3(0, 1.05, 0), Color("3a3440"), 8)
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.85
	bowl.bottom_radius = 0.45
	bowl.height = 0.6
	bowl.radial_segments = 12
	mesh_node(n, bowl, Vector3(0, 1.8, 0), mat(Color("4a4252"), 0.03))
	var coals := CylinderMesh.new()
	coals.top_radius = 0.7
	coals.bottom_radius = 0.7
	coals.height = 0.1
	coals.radial_segments = 12
	mesh_node(n, coals, Vector3(0, 2.1, 0), mat(Color("ff7a2a"), 0.0, Color("ff5a1a"), 2.5))
	var flame := CylinderMesh.new()
	flame.top_radius = 0.0
	flame.bottom_radius = 0.55
	flame.height = 1.5
	flame.radial_segments = 5
	var f_outer := mesh_node(n, flame, Vector3(0, 2.8, 0), mat(Color("ff9a3c"), 0.0, Color("ff6a1c"), 3.0))
	var f_inner := mesh_node(n, flame, Vector3(0, 2.7, 0), mat(Color("fff1b0"), 0.0, Color("ffd36a"), 3.5), Vector3(0, 0.6, 0), Vector3(0.55, 0.7, 0.55))
	f_outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f_inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := f_outer.create_tween().set_loops()
	tw.tween_property(f_outer, "scale", Vector3(0.85, 1.25, 0.85), 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(f_outer, "scale", Vector3(1.1, 0.9, 1.1), 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(f_outer, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_SINE)
	var spin := f_inner.create_tween().set_loops()
	spin.tween_property(f_inner, "rotation:y", TAU, 1.3).from(0.0)
	if not headless():
		var embers := _particles(Vector3(0, 2.6, 0), 10, 1.6, Vector3(0.3, 0.1, 0.3), Color("ffb060"), 0.12, 1.4)
		n.add_child(embers)
		if with_light:
			var l := OmniLight3D.new()
			l.light_color = Color("ffa050")
			l.light_energy = 1.5
			l.omni_range = 13.0
			l.omni_attenuation = 1.3
			l.shadow_enabled = false
			l.visible = false
			l.position = Vector3(0, 3.0, 0)
			l.add_to_group("arena_lights")
			n.add_child(l)
	return n


## Open fire in the brazier style: coals, a flickering outer tongue, a
## spinning pale core, rising embers and (optionally) a warm OmniLight with
## a gentle flicker. `s` scales the whole flame (1.0 = a ~1.5 m tongue).
static func flame(parent: Node3D, pos: Vector3, s := 1.0, with_light := true, light_energy := 1.6, light_range := 9.0) -> Node3D:
	var n := Node3D.new()
	n.name = "Flame"
	n.position = pos
	n.scale = Vector3.ONE * s
	parent.add_child(n)
	var coals := CylinderMesh.new()
	coals.top_radius = 0.5
	coals.bottom_radius = 0.42
	coals.height = 0.16
	coals.radial_segments = 10
	mesh_node(n, coals, Vector3(0, 0.08, 0), mat(Color("ff7a2a"), 0.0, Color("ff4a12"), 2.6))
	var fl := CylinderMesh.new()
	fl.top_radius = 0.0
	fl.bottom_radius = 0.5
	fl.height = 1.5
	fl.radial_segments = 5
	var f_outer := mesh_node(n, fl, Vector3(0, 0.85, 0), mat(Color("ff9a3c"), 0.0, Color("ff6a1c"), 3.0))
	var f_inner := mesh_node(n, fl, Vector3(0, 0.72, 0), mat(Color("fff1b0"), 0.0, Color("ffd36a"), 3.6), Vector3(0, 0.6, 0), Vector3(0.55, 0.7, 0.55))
	f_outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f_inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := f_outer.create_tween().set_loops()
	tw.tween_property(f_outer, "scale", Vector3(0.85, 1.25, 0.85), 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(f_outer, "scale", Vector3(1.1, 0.9, 1.1), 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(f_outer, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_SINE)
	var spin := f_inner.create_tween().set_loops()
	spin.tween_property(f_inner, "rotation:y", TAU, 1.3).from(0.0)
	if not headless():
		var embers := _particles(Vector3(0, 0.9, 0), 10, 1.6, Vector3(0.25, 0.1, 0.25), Color("ffb060"), 0.1, 1.2)
		n.add_child(embers)
	if with_light and not headless():
		# Added beside the (scaled) flame node so the range stays in metres.
		var l := OmniLight3D.new()
		l.name = "FireLight"
		l.light_color = Color("ffa050")
		l.light_energy = light_energy
		l.omni_range = light_range
		l.omni_attenuation = 1.6
		l.shadow_enabled = false
		l.position = pos + Vector3(0, 1.1 * s, 0)
		parent.add_child(l)
		var lt := l.create_tween().set_loops()
		lt.tween_property(l, "light_energy", light_energy * 0.86, 0.23).set_trans(Tween.TRANS_SINE)
		lt.tween_property(l, "light_energy", light_energy * 1.08, 0.31).set_trans(Tween.TRANS_SINE)
		lt.tween_property(l, "light_energy", light_energy, 0.27).set_trans(Tween.TRANS_SINE)
	return n


## A lit candle: wax column, wick and a glowing teardrop flame. Visual only.
static func candle(parent: Node3D, pos: Vector3, h := 0.18, r := 0.035, wax := Color("f3e9d2")) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	cyl(n, r, r * 1.05, h, Vector3(0, h * 0.5, 0), wax, 8)
	cyl(n, 0.004, 0.004, 0.03, Vector3(0, h + 0.01, 0), Color("2a2020"), 4)
	var fm := SphereMesh.new()
	fm.radius = r * 0.75
	fm.height = r * 2.6
	fm.radial_segments = 8
	fm.rings = 5
	var f := mesh_node(n, fm, Vector3(0, h + r * 1.3, 0), mat(Color("fff0b8"), 0.0, Color("ffc24a"), 3.4))
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := f.create_tween().set_loops()
	tw.tween_property(f, "scale", Vector3(0.8, 1.25, 0.8), 0.3 + 0.1 * fmod(pos.x * 3.1 + pos.z * 1.7, 1.0)).set_trans(Tween.TRANS_SINE)
	tw.tween_property(f, "scale", Vector3(1.05, 0.9, 1.05), 0.35).set_trans(Tween.TRANS_SINE)
	return n


## Sealed gate at the back of the summit: carved wall with a pointed arch,
## a dark rune-sealed door, flanking columns, chains of glowing sigils and
## a keystone crystal. `facing` is the direction the door looks (into the
## arena). Visual only; the caller adds the collider.
static func sealed_gate(parent: Node3D, pos: Vector3, facing: Vector3, rune: Color) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = atan2(facing.x, facing.z)
	parent.add_child(n)
	# Wall block (local +z faces the arena).
	if not WorldProps.gate_frame(n, Vector3.ZERO, rune):
		mesh_node(n, BoxMesh.new(), Vector3(0, 4.5, -0.6), ruin_mat("wall"), Vector3.ZERO, Vector3(11.0, 9.0, 2.4))
	# Door slab, seal and glyph bands.
	var door := BoxMesh.new()
	door.size = Vector3(4.6, 6.6, 0.6)
	mesh_node(n, door, Vector3(0, 3.3, 0.0), mat(Color("3b2a66").lerp(rune.darkened(0.72), 0.55), 0.03, rune.darkened(0.1), 1.2)).name = "Door"
	var arch := TorusMesh.new()
	arch.inner_radius = 2.5
	arch.outer_radius = 3.3
	arch.rings = 32
	mesh_node(n, arch, Vector3(0, 3.9, 0.45), ruin_mat("trim"), Vector3.ZERO, Vector3(1, 1.15, 0.5))
	var seal := TorusMesh.new()
	seal.inner_radius = 1.1
	seal.outer_radius = 1.4
	seal.rings = 40
	var seal_mi := mesh_node(n, seal, Vector3(0, 3.6, 0.42), rune_mat(rune, 2.6), Vector3(PI / 2, 0, 0))
	seal_mi.name = "Seal"
	var seal2 := TorusMesh.new()
	seal2.inner_radius = 0.55
	seal2.outer_radius = 0.72
	seal2.rings = 32
	var seal2_mi := mesh_node(n, seal2, Vector3(0, 3.6, 0.44), rune_mat(rune.lightened(0.3), 2.6), Vector3(PI / 2, 0, 0))
	seal2_mi.name = "Seal2"
	var tw := seal_mi.create_tween().set_loops()
	tw.tween_property(seal_mi, "rotation:y", TAU, 14.0).from(0.0)
	var tw2 := seal2_mi.create_tween().set_loops()
	tw2.tween_property(seal2_mi, "rotation:y", -TAU, 9.0).from(0.0)
	var bar := BoxMesh.new()
	bar.size = Vector3(4.2, 0.22, 0.12)
	for yy in [1.2, 5.6]:
		mesh_node(n, bar, Vector3(0, yy, 0.36), mat(rune.lightened(0.45), 0.0, rune, 2.2)).name = "Bar%d" % int(yy)
	# Keystone crystal above the arch and two sigil lamps on the jambs.
	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.0
	crystal.bottom_radius = 0.5
	crystal.height = 1.6
	crystal.radial_segments = 4
	var cmat := mat(rune.lightened(0.35), 0.0, rune, 3.0)
	var ks := mesh_node(n, crystal, Vector3(0, 8.6, 0.6), cmat, Vector3(PI, 0, 0))
	ks.name = "Keystone"
	var bob := ks.create_tween().set_loops()
	bob.tween_property(ks, "position:y", 9.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(ks, "position:y", 8.4, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for sx in [-1, 1]:
		broken_column(n, Vector3(sx * 6.4, 0, 0.6), 8.0, rune, false, 0.9)
		sphere(n, 0.4, Vector3(sx * 3.2, 6.9, 0.7), rune.lightened(0.4)).material_override = cmat
	return n


## Rings of floating rubble drifting around a summit: two counter-rotating
## MultiMeshes (nature-kit rocks tinted to the stone, procedural without).
static func floating_debris(parent: Node3D, center: Vector3, radius: float, rune: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for ringi in 2:
		var hub := Node3D.new()
		hub.name = "Debris%d" % ringi
		hub.position = center
		parent.add_child(hub)
		var xs := []
		var cs := []
		var count := 26 if ringi == 0 else 18
		for i in count:
			var a := rng.randf() * TAU
			var r := radius + rng.randf_range(2.5, 9.0) + ringi * 3.0
			var y := rng.randf_range(-6.0, 7.0)
			var s := rng.randf_range(0.6, 1.9)
			xs.append(xf(Vector3(cos(a) * r, y, sin(a) * r), rng.randf() * TAU, Vector3(s, s * rng.randf_range(0.7, 1.3), s), Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))))
			cs.append(Color("8a82a0").lerp(Color("6a6282"), rng.randf()))
		if not WorldProps.debris_cloud(hub, xs):
			var mm := multimesh(hub, rock_mesh(), xs, cs, "Chunks")
			mm.material_override = mat(Color.WHITE, 0.03)
		# A few glowing shards among the rubble.
		var shard := CylinderMesh.new()
		shard.top_radius = 0.0
		shard.bottom_radius = 0.35
		shard.height = 1.4
		shard.radial_segments = 4
		var sx := []
		for i in 6:
			var a := rng.randf() * TAU
			var r := radius + rng.randf_range(3.0, 8.0)
			sx.append(xf(Vector3(cos(a) * r, rng.randf_range(-3.0, 6.0), sin(a) * r), rng.randf() * TAU, Vector3.ONE, Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))))
		var sm := multimesh(hub, shard, sx, [], "Shards")
		sm.material_override = mat(rune.lightened(0.3), 0.0, rune, 2.5)
		sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tw := hub.create_tween().set_loops()
		tw.tween_property(hub, "rotation:y", TAU if ringi == 0 else -TAU, 110.0 + ringi * 50.0).from(0.0)


# --- Sky dressing ----------------------------------------------------------

static func cloud_mesh() -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


## Cloud puffs below the island plus a few far away, and distant islets.
## `look` overrides for other floors: "islet_a"/"islet_b" (islet hill tones),
## "tree_a"/"tree_b" (islet tree tones), "hills" (three horizon tints).
static func build_sky(parent: Node3D, rng: RandomNumberGenerator, radius: float, look: Dictionary = {}) -> void:
	var islet_a: Color = look.get("islet_a", GRASS_A)
	var islet_b: Color = look.get("islet_b", Color("3f8a4a"))
	var tree_a: Color = look.get("tree_a", Color("4e9a3c"))
	var tree_b: Color = look.get("tree_b", Color("8fd36b"))
	var hills: Array = look.get("hills", [Color("8fb7d9"), Color("a9c7e3"), Color("c3d8ec")])
	var xs := []
	var cs := []
	var cm: ShaderMaterial = cloud_material
	if cm == null:
		cm = ShaderMaterial.new()
		cm.shader = shader("cloud")
		cloud_material = cm
	for cluster in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(radius * 0.55, radius * 2.1)
		var y := rng.randf_range(-34, -9)
		var c := Vector3(cos(a) * r, y, sin(a) * r)
		var base_s := rng.randf_range(7, 16)
		var tint := Color.WHITE.lerp(Color("ffe6d6"), rng.randf() * 0.5)
		for puff in 5:
			var off := Vector3(rng.randf_range(-1.2, 1.2) * base_s, rng.randf_range(-0.15, 0.25) * base_s, rng.randf_range(-0.9, 0.9) * base_s)
			var s := base_s * rng.randf_range(0.5, 1.0)
			xs.append(xf(c + off, rng.randf() * TAU, Vector3(s, s * 0.45, s * 0.8)))
			cs.append(tint)
	for far in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(260, 620)
		var y := rng.randf_range(10, 90)
		var c := Vector3(cos(a) * r, y, sin(a) * r)
		var base_s := rng.randf_range(16, 34)
		for puff in 4:
			var off := Vector3(rng.randf_range(-1.2, 1.2) * base_s, rng.randf_range(-0.1, 0.2) * base_s, rng.randf_range(-0.6, 0.6) * base_s)
			var s := base_s * rng.randf_range(0.6, 1.0)
			xs.append(xf(c + off, rng.randf() * TAU, Vector3(s, s * 0.42, s * 0.8)))
			cs.append(Color.WHITE)
	var mm := multimesh(parent, cloud_mesh(), xs, cs, "Clouds")
	mm.material_override = cm
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Distant floating islets with hills and trees, for depth.
	var islets := [[Vector3(230, -20, 140), 38.0], [Vector3(-260, 15, 90), 46.0], [Vector3(180, 35, -260), 30.0], [Vector3(-170, -40, -230), 26.0],
		[Vector3(330, 10, -60), 54.0], [Vector3(-90, 50, 330), 34.0], [Vector3(110, -70, 300), 24.0], [Vector3(-380, -10, -140), 60.0]]
	var tree_xs := [[], [], []]
	var tree_cs := [[], [], []]
	for isl in islets:
		var c: Vector3 = isl[0]
		var r: float = isl[1]
		var n := Node3D.new()
		n.position = c
		parent.add_child(n)
		var top := CylinderMesh.new()
		top.top_radius = r
		top.bottom_radius = r * 1.03
		top.height = 2.0
		top.radial_segments = 24
		mesh_node(n, top, Vector3(0, -1, 0), mat(GRASS_A.lerp(GRASS_B, 0.4), 0.0))
		var under := CylinderMesh.new()
		under.top_radius = r * 1.02
		under.bottom_radius = r * 0.1
		under.height = r * 0.9
		under.radial_segments = 16
		mesh_node(n, under, Vector3(0, -2 - r * 0.45, 0), mat(Color("6f5a4c"), 0.0))
		for h in 3:
			var hp := Vector3(rng.randf_range(-0.5, 0.5) * r, 0, rng.randf_range(-0.5, 0.5) * r)
			var hs := r * rng.randf_range(0.25, 0.5)
			sphere(n, 1.0, hp, islet_a.lerp(islet_b, rng.randf() * 0.5), Vector3(hs, hs * 0.5, hs))
		for t in 10:
			var a := rng.randf() * TAU
			var rr := rng.randf() * r * 0.8
			var s := rng.randf_range(1.2, 2.2)
			var v := rng.randi() % 3
			tree_xs[v].append(xf(c + Vector3(cos(a) * rr, 0, sin(a) * rr), rng.randf() * TAU, Vector3(s, s, s)))
			tree_cs[v].append(tree_a.lerp(tree_b, rng.randf()))
	for v in 3:
		if not tree_xs[v].is_empty():
			multimesh(parent, tree_mesh(v), tree_xs[v], tree_cs[v], "IsletTrees%d" % v)

	# Layered hill silhouettes on the horizon (unlit tints fading into the fog).
	var hill_layers := [[700.0, hills[0], 0.9], [900.0, hills[1], 1.2], [1150.0, hills[2], 1.5]]
	hill_materials.clear()  # fresh per world build; old ones die with their scene
	for li in hill_layers.size():
		var layer: Array = hill_layers[li]
		var hm := StandardMaterial3D.new()
		hm.albedo_color = layer[1]
		hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var hx := []
		var hr := RandomNumberGenerator.new()
		hr.seed = 100 + li
		var count := 18 + li * 6
		for k in count:
			var a := TAU * k / count + hr.randf_range(-0.1, 0.1)
			var w: float = hr.randf_range(90, 180) * layer[2]
			var h: float = hr.randf_range(50, 120) * layer[2]
			hx.append(xf(Vector3(cos(a) * layer[0], -70.0 + li * 10.0, sin(a) * layer[0]), -a, Vector3(w, h, w * 0.6)))
		var hmm := multimesh(parent, cloud_mesh(), hx, [], "Hills%d" % li)
		hmm.material_override = hm
		hill_materials.append([hm, layer[1]])
		hmm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- Ambient particles -----------------------------------------------------

static func _particles(pos: Vector3, amount: int, lifetime: float, extents: Vector3, color: Color, size: float, gravity_y: float, tex: Texture2D = null, additive := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.visibility_aabb = AABB(-extents * 2 - Vector3(2, 2, 2), extents * 4 + Vector3(4, 12, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.gravity = Vector3(0, gravity_y, 0)
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.color = color
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	m.emission_enabled = true
	m.emission = Color(color.r, color.g, color.b)
	m.emission_energy_multiplier = 1.5
	m.no_depth_test = false
	# Never a bare quad: small motes get a soft disc, big ones a smoke puff.
	if tex == null and not headless():
		tex = AssetLib.vfx_texture("smoke_04" if size >= 0.4 else "circle_05")
	if tex:
		m.albedo_texture = tex
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.draw_pass_1 = q
	return p


## Soft white petal sprite (tinted per particle): a pointed oval with a
## faint centre crease, so drifting petals never read as flat squares.
static func petal_texture() -> ImageTexture:
	if _petal_tex:
		return _petal_tex
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			# Width tapers toward the tip (v = -1) for a teardrop petal.
			var w := 0.62 * sqrt(maxf(0.0, 1.0 - v * v)) * (0.75 + 0.25 * v)
			var d := absf(u) / maxf(w, 0.001)
			var a := clampf((1.0 - d) * 6.0, 0.0, 1.0) * clampf((1.0 - absf(v)) * 8.0, 0.0, 1.0)
			var shade := 1.0 - 0.18 * exp(-u * u * 90.0) - 0.12 * (v + 1.0) * 0.5
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	_petal_tex = ImageTexture.create_from_image(img)
	return _petal_tex


static func build_ambience(parent: Node3D) -> void:
	if headless():
		return
	var fire := _particles(Vector3(0, 1.5, 15), 140, 7.0, Vector3(30, 1.2, 30), Color(1.0, 0.92, 0.5, 0.9), 0.3, 0.0,
		AssetLib.vfx_texture("circle_05"), true)
	fire.name = "Fireflies"
	firefly_material = (fire.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	firefly_material.albedo_color = Color(1, 1, 1, 0)
	firefly_material.emission_enabled = false
	fire.set_meta("firefly", true)
	fire.add_to_group("fireflies")
	fire.visible = false
	fire.process_material.turbulence_enabled = true
	fire.process_material.turbulence_noise_strength = 1.2
	fire.process_material.turbulence_noise_scale = 4.0
	fire.process_material.initial_velocity_min = 0.1
	fire.process_material.initial_velocity_max = 0.4
	parent.add_child(fire)
	var petals := _particles(Vector3(0, 9, -10), 160, 9.0, Vector3(55, 2, 55), Color(1.0, 0.72, 0.84, 0.95), 0.26, -0.35,
		petal_texture())
	(petals.draw_pass_1.material as StandardMaterial3D).emission_energy_multiplier = 0.35
	petals.name = "Petals"
	petals.process_material.angular_velocity_min = -200
	petals.process_material.angular_velocity_max = 200
	petals.process_material.initial_velocity_min = 0.6
	petals.process_material.initial_velocity_max = 1.6
	petals.process_material.direction = Vector3(1, -0.2, 0.3)
	petals.process_material.spread = 40.0
	petals.process_material.turbulence_enabled = true
	petals.process_material.turbulence_noise_strength = 1.5
	parent.add_child(petals)


# --- Environment -----------------------------------------------------------

static func is_forward_plus() -> bool:
	# A RenderingDevice only exists on the Vulkan/D3D12 paths; Compatibility
	# and headless return null, so the cheap path is used there.
	if RenderingServer.get_rendering_device() == null:
		return false
	var method := str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"))
	return method == "forward_plus"


## Daytime painterly sky and light rig. In Forward+ the high-end stack is
## switched on (SDFGI, SSAO, SSIL, SSR, volumetric fog, DOF); Compatibility
## keeps the same scene with the cheap path.
static func build_environment(parent: Node3D) -> void:
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	var sky := Sky.new()
	# Painterly gradient + sun + stars/moon + the floor above (sky_spire);
	# DayNight drives its colours. The underside of the next floor roofs
	# every floor of the Spire except Floor 2's frozen build.
	var sm := ShaderMaterial.new()
	sm.shader = shader("sky_spire")
	sm.set_shader_parameter("lid", 1.0 if GameState.floor == 1 else 0.0)
	sm.set_shader_parameter("lid_start", 0.5)
	sky.sky_material = sm
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Mostly a fixed warm-neutral fill, only a little sky: on Forward+ the
	# full sky radiance (blue above, lavender below) tinted the meadow mint.
	e.ambient_light_color = Color(0.78, 0.8, 0.72)
	e.ambient_light_sky_contribution = 0.3
	e.ambient_light_energy = 0.45
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.72
	e.tonemap_white = 4.0
	e.fog_enabled = true
	e.fog_light_color = Color("d9e6ff")
	e.fog_light_energy = 1.0
	e.fog_density = 0.0010
	e.fog_sky_affect = 0.0
	e.fog_aerial_perspective = 0.6
	e.fog_height = -40.0
	e.fog_height_density = 0.02
	e.glow_enabled = true
	e.glow_intensity = 0.25
	e.glow_strength = 0.8
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.4
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.06
	e.adjustment_saturation = 1.12
	e.adjustment_brightness = 1.0
	if is_forward_plus():
		e.sdfgi_enabled = true
		e.sdfgi_cascades = 4
		e.sdfgi_min_cell_size = 0.3
		e.sdfgi_use_occlusion = true
		# GI kept gentle: full-strength sky bounce greys out the meadow and
		# kills the saturated cel look (compare Low vs High shots).
		e.sdfgi_bounce_feedback = 0.3
		e.sdfgi_energy = 0.6
		e.ssao_enabled = true
		e.ssao_radius = 1.5
		e.ssao_intensity = 1.6
		e.ssao_power = 1.6
		e.ssil_enabled = true
		e.ssil_radius = 4.0
		e.ssil_intensity = 0.6
		e.ssr_enabled = true
		e.ssr_max_steps = 96
		e.ssr_fade_in = 0.2
		e.ssr_fade_out = 2.0
		e.volumetric_fog_enabled = true
		# Thin: a clear, bright anime sky with light shafts, not a grey haze.
		e.volumetric_fog_density = 0.0045
		e.volumetric_fog_albedo = Color("fff1e0")
		e.volumetric_fog_emission = Color("3a3020")
		e.volumetric_fog_emission_energy = 0.08
		e.volumetric_fog_anisotropy = 0.7
		e.volumetric_fog_length = 160.0
		e.volumetric_fog_detail_spread = 2.2
		e.volumetric_fog_ambient_inject = 0.12
		e.volumetric_fog_sky_affect = 0.0
		e.glow_intensity = 0.45
		e.glow_bloom = 0.0
		e.adjustment_saturation = 1.18
		# Filmic flattens the painted mid-tones toward grey-mint; a linear
		# curve keeps the saturated cel palette the art is painted in.
		e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		e.tonemap_exposure = 0.86
		# Runtime quality upgrades that would only cost or error elsewhere.
		var vp := parent.get_viewport()
		if vp:
			vp.use_taa = true
			vp.positional_shadow_atlas_size = 8192
		RenderingServer.directional_shadow_atlas_set_size(8192, true)
		var attrs := CameraAttributesPractical.new()
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = 180.0
		attrs.dof_blur_far_transition = 140.0
		attrs.dof_blur_amount = 0.05
		attrs.auto_exposure_enabled = false
		env.camera_attributes = attrs
	env.environment = e
	parent.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(38), 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.0
	sun.light_color = Color("fff1dc")
	sun.light_indirect_energy = 1.4
	sun.light_volumetric_fog_energy = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.2
	sun.directional_shadow_split_3 = 0.5
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	sun.shadow_opacity = 1.0
	parent.add_child(sun)
	# Soft cool fill from the sky side so shadows are never pure black.
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY  # no second disc in the sky
	fill.rotation = Vector3(deg_to_rad(-35), deg_to_rad(-140), 0)
	fill.light_energy = 0.18
	fill.light_color = Color("a9c6ff")
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	parent.add_child(fill)
