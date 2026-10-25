class_name Floor2Art
extends RefCounted
## Procedural art for Floor 2 of the Spire, "Mirewood": a misty autumn floor
## of leaf litter and moss, a dark lake with boardwalks out to a shrine isle,
## the hunters' village of Thornwick, the Sunken Barrow (wisps), and the
## second Labyrinth tower. Builds on WorldArt / WorldProps helpers and the
## same CC0 packs; every builder falls back to primitives without the packs.
## world.gd owns the gameplay layout (NPCs, mobs, pads, colliders) and calls in.

# --- Layout (mirrored by shaders/ground_mire.gdshader) ------------------------
const WAYGATE := Vector3(0, 0, 30)        # arrival portal; plaza centre is (0, 34)
const PLAZA := Vector2(0, 34)
const PLAZA_RADIUS := 9.0
const VILLAGE := Vector3(-34, 0, 14)      # Thornwick, hunters' village
const LAKE := Vector3(38, 0, 6)           # the Mere
const LAKE_RADIUS := 20.0
const ISLE := Vector3(42, 0, 2)           # shrine isle inside the lake
const ISLE_RADIUS := 6.0
const BARROW := Vector3(-40, 0, -42)      # Sunken Barrow (wisps)
const BARROW_RADIUS := 13.0
const TOWER := Vector3(8, 0, -70)
const ROADS := [
	[Vector2(0, 28), Vector2(-22, 18)],
	[Vector2(6, 30), Vector2(19, 12)],
	[Vector2(0, 26), Vector2(6, -52)],
	[Vector2(-38, 0), Vector2(-40, -30)],
	[Vector2(-22, 18), Vector2(-38, 0)],
]

# Palette.
const RUNE := Color("5ee0b0")             # Floor 2 rune teal (gates, pads, shrine)
const RUNE_DIM := Color("3fae8c")
const LEAF_A := Color("c8641e")
const LEAF_B := Color("e8a432")
const LEAF_C := Color("8f3a22")
const MOSS := Color("5a7a3a")
const BOG_WATER := Color("457a68")
const BOG_DEEP := Color("16302e")
const PLANK := Color("6e5a3e")
const PLANK_DARK := Color("4f3f2b")
const MIST := Color(0.82, 0.8, 0.74, 0.22)

const TREES_FALL := ["tree_oak_fall", "tree_default_fall", "tree_detailed_fall", "tree_fat_fall", "tree_tall_fall", "tree_plateau_fall", "tree_thin_fall"]
const TREES_DARK := ["tree_pineTallA_detailed", "tree_pineDefaultB", "tree_pineTallB"]

## Boardwalk ends: shore (toward the waygate road) and the isle rim.
static func boardwalk_ends() -> Array:
	var dir := (Vector3(19, 0, 12) - LAKE).normalized()
	var shore := LAKE + dir * (LAKE_RADIUS + 1.5)
	var to_isle := (shore - ISLE).normalized()
	var isle_edge := ISLE + to_isle * (ISLE_RADIUS - 0.6)
	return [shore, isle_edge]


## Mirrors ground_mire.gdshader so vegetation keeps off tracks and water.
static func ground_kind(p: Vector2) -> int:
	if p.distance_to(PLAZA) < PLAZA_RADIUS + 0.5 or p.distance_to(Vector2(ISLE.x, ISLE.z)) < ISLE_RADIUS + 0.4:
		return WorldArt.Ground.COBBLE
	if p.length() > 84.0:
		return WorldArt.Ground.RIM
	if p.distance_to(Vector2(TOWER.x, TOWER.z)) < 16.5:
		return WorldArt.Ground.TOWER
	if p.distance_to(Vector2(LAKE.x, LAKE.z)) < LAKE_RADIUS + 2.5:
		return WorldArt.Ground.WATER_K
	for r in ROADS:
		if WorldArt._seg_dist(p, r[0], r[1]) < 3.4:
			return WorldArt.Ground.SAND
	if p.distance_to(Vector2(VILLAGE.x, VILLAGE.z)) < 16.0 or p.distance_to(Vector2(BARROW.x, BARROW.z)) < BARROW_RADIUS + 1.0:
		return WorldArt.Ground.DIRT
	return WorldArt.Ground.GRASS


# --- Terrain, sky, environment --------------------------------------------------

static func build_terrain(parent: Node3D, rng: RandomNumberGenerator, radius: float) -> void:
	WorldArt.build_terrain(parent, rng, radius, {
		"shader": "ground_mire",
		"sets": [["grass", "forest_floor"], ["path", "brown_mud_leaves_01"], ["cobble", "cobblestone_floor_08"]],
		"cliff_a": Color("6e6a5a"), "cliff_b": Color("45443a"),
		"rock_a": Color("8f8a7a"), "rock_b": Color("5f5c50"), "crag_a": Color("7a7566"), "crag_b": Color("4a473e"),
		"lip_a": Color("9a957f"), "lip_b": Color("6e6a58")})
	var ground := parent.get_node_or_null("Ground") as MeshInstance3D
	if ground:
		var gm := ground.get_active_material(0) as ShaderMaterial
		if gm:
			gm.set_shader_parameter("grass_tiling", 0.22)
			gm.set_shader_parameter("path_tiling", 0.3)
			gm.set_shader_parameter("detail_tint", 0.35)
			gm.set_shader_parameter("grass_b", Color("9c7a3e"))
			gm.set_shader_parameter("grass_a", Color("6e5f36"))
	WorldArt.build_sky(parent, rng, radius, {"islet_a": Color("8a6a3a"), "islet_b": Color("5a6a3a"), "tree_a": Color("c8641e"), "tree_b": Color("e8a432"),
		"hills": [Color("8a9aa8"), Color("a4b0b8"), Color("c0c6c8")]})


## Thicker, warmer haze than Floor 1 so the woods fade into mist. DayNight
## owns the colours over the day; this sets the densities once.
static func tune_environment(parent: Node3D) -> void:
	var we := parent.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null:
		return
	var e := we.environment
	e.fog_density = 0.0032
	e.fog_aerial_perspective = 0.85
	e.fog_sky_affect = 0.12
	e.fog_height = -20.0
	e.fog_height_density = 0.06
	e.adjustment_saturation = 1.08
	e.adjustment_contrast = 1.04
	if e.volumetric_fog_enabled:
		e.volumetric_fog_density = 0.028
		e.volumetric_fog_albedo = Color("e8dcc4")
		e.volumetric_fog_emission = Color("3a2e1e")
		e.volumetric_fog_emission_energy = 0.06
	var sun := parent.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.rotation.y = deg_to_rad(-52)
		sun.light_color = Color("ffe9c8")
	var fill := parent.get_node_or_null("SkyFill") as DirectionalLight3D
	if fill:
		fill.light_color = Color("c9d4c0")


# --- Arrival waygate ------------------------------------------------------------

static func build_waygate(parent: Node3D) -> void:
	var curb := TorusMesh.new()
	curb.inner_radius = PLAZA_RADIUS - 0.4
	curb.outer_radius = PLAZA_RADIUS + 0.4
	curb.rings = 48
	WorldArt.mesh_node(parent, curb, Vector3(PLAZA.x, 0.0, PLAZA.y), WorldArt.mat(Color("5c6058"), 0.0), Vector3.ZERO, Vector3(1, 0.35, 1))
	WorldProps.portal_pillars(parent, WAYGATE, 3.0, 6.5)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.4
	tm.outer_radius = 2.8
	tm.rings = 48
	tm.material = WorldArt.rune_mat(RUNE, 2.4)
	ring.mesh = tm
	ring.rotation.x = PI / 2
	ring.position = WAYGATE + Vector3(0, 4, 0)
	parent.add_child(ring)
	var tw := ring.create_tween().set_loops()
	tw.tween_property(ring, "rotation:z", TAU, 14.0).from(0.0)
	WorldArt.rune_ring(parent, WAYGATE + Vector3(0, 0.07, 0), 4.2, RUNE, 0.22)
	# Lanterns around the circle, two benches, a signpost, hunters' clutter.
	for i in 6:
		var a := TAU * i / 6.0 + PI / 6
		WorldProps.lantern(parent, Vector3(PLAZA.x + cos(a) * 7.6, 0, PLAZA.y + sin(a) * 7.6), -a)
	for sx in [-1, 1]:
		if not AssetLib.prop(parent, "graveyard", "bench", Vector3(PLAZA.x + sx * 5.5, 0, PLAZA.y + 4.5), sx * PI / 2 + PI / 2, WorldProps.GRAVE, "box"):
			WorldArt.box(parent, Vector3(0.5, 0.45, 1.8), Vector3(PLAZA.x + sx * 5.5, 0.45, PLAZA.y + 4.5), WorldArt.WOOD)
	if not WorldProps.signpost(parent, Vector3(PLAZA.x + 4.0, 0, PLAZA.y - 6.5), -0.8):
		WorldArt.cyl(parent, 0.08, 0.1, 2.6, Vector3(PLAZA.x + 4.0, 1.3, PLAZA.y - 6.5), WorldArt.WOOD, 6)
	WorldProps.crate(parent, Vector3(PLAZA.x - 6.5, 0, PLAZA.y - 3.5), 0.9, 0.4)
	WorldProps.barrel(parent, Vector3(PLAZA.x - 7.2, 0, PLAZA.y - 2.2))
	WorldProps.prop(parent, "town", "cart", Vector3(PLAZA.x + 7.5, 0, PLAZA.y + 1.5), 1.9, WorldProps.TOWN, "box")
	# Banners on the pillars.
	if AssetLib.has_prop("dungeon", "banner_patternC_green"):
		for sx in [-1, 1]:
			AssetLib.prop(parent, "dungeon", "banner_patternC_green", WAYGATE + Vector3(sx * 3.0, 4.6, 0.75), 0.0, WorldProps.DUNGEON * 1.4, "none")


# --- Thornwick, the hunters' village -----------------------------------------

## Returns positions world.gd needs: {"smith": anvil pos, "fire": campfire pos}.
static func build_village(parent: Node3D) -> Dictionary:
	var c := VILLAGE
	var kinds := ["blacksmith", "tavern", "home_A", "home_B", "home_A"]
	var colors := ["red", "green", "yellow", "green", "red"]
	var ring := 12.0 if WorldProps.ready() else 10.0
	var hedge := []
	for i in 5:
		var a := TAU * i / 5.0 + 0.95
		var pos := c + Vector3(cos(a) * ring, 0, sin(a) * ring)
		var face := atan2(-cos(a), -sin(a))
		if WorldProps.ready():
			WorldProps.house(parent, pos, kinds[i], colors[i], face, WorldProps.HOUSE * (0.95 if kinds[i] == "tavern" else 0.9))
		else:
			WorldArt.house(parent, pos, 5.5, 4.5, 3.6, face, [0, 2, 1, 3, 0][i])
		if kinds[i].begins_with("home"):
			var fp := WorldProps.footprint(kinds[i], colors[i], WorldProps.HOUSE * 0.9)
			var fwd := Vector3(sin(face), 0, cos(face))
			var side := Vector3(cos(face), 0, -sin(face))
			var front := pos + fwd * (fp.y * 0.5 + 1.3)
			hedge.append([front - side * fp.x * 0.5, front - side * 1.2])
			hedge.append([front + side * 1.2, front + side * fp.x * 0.5])
	WorldProps.hedges(parent, hedge)
	# Central fire pit with log seats, where the hunters gather.
	campfire(parent, c)
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		WorldProps.prop(parent, "nature", "log", c + Vector3(cos(a) * 3.2, 0, sin(a) * 3.2), -a + PI / 2, WorldProps.NATURE * 1.1, "box")
	# Smithy by the blacksmith (i = 0): anvil and forge outside its door.
	var sa := TAU * 0 / 5.0 + 0.95
	var smith_house := c + Vector3(cos(sa) * ring, 0, sin(sa) * ring)
	var inward := (c - smith_house).normalized()
	var anvil := smith_house + inward * 6.0 + Vector3(0, 0, 2.2)
	var forge := smith_house + inward * 5.0 + Vector3(0, 0, -0.6)
	if not WorldProps.smithy(parent, anvil, forge):
		WorldArt.box(parent, Vector3(1.2, 0.5, 0.5), anvil + Vector3(0, 0.75, 0), Color("3b3b44"))
		WorldArt.box(parent, Vector3(2.2, 1.2, 1.6), forge + Vector3(0, 0.6, 0), Color("7a6a66"))
	WorldArt.mesh_node(parent, SphereMesh.new(), forge + Vector3(0.4, 0.5, 0.3), WorldArt.mat(Color("ff9a3c"), 0.0, Color("ff5a1a"), 3.0), Vector3.ZERO, Vector3(0.3, 0.2, 0.3))
	if not WorldArt.headless():
		var fl := OmniLight3D.new()
		fl.light_color = Color("ff8a3c")
		fl.light_energy = 0.6
		fl.omni_range = 3.5
		fl.position = forge + Vector3(0.4, 1.5, 0.3)
		parent.add_child(fl)
	# Hunters' gear: drying racks with hides, an antler trophy post, tents,
	# hay, crates, barrels, log stacks, a cart and a stall.
	drying_rack(parent, c + Vector3(6.5, 0, -6.0), 0.5)
	drying_rack(parent, c + Vector3(-7.5, 0, 5.5), -1.1)
	trophy_post(parent, c + Vector3(0, 0, -5.5))
	WorldProps.tent(parent, c + Vector3(-5.0, 0, -8.5), 2.6)
	WorldProps.tent(parent, c + Vector3(8.5, 0, 3.5), -1.4)
	var bales := []
	for k in 3:
		bales.append(c + Vector3(5.5 + k * 1.7, 0, 7.5 + (k % 2) * 1.1))
	if not WorldProps.hay(parent, bales):
		for b in bales:
			WorldArt.cyl(parent, 0.8, 0.8, 1.4, b + Vector3(0, 0.8, 0), Color("c9a85a"), 12, Vector3(0, 0, PI / 2))
	WorldProps.crate(parent, c + Vector3(-8.5, 0, -2.0), 0.9, 0.3)
	WorldProps.crate(parent, c + Vector3(-9.3, 0, -1.0), 0.7, 0.9)
	WorldProps.barrel(parent, c + Vector3(9.0, 0, -1.5))
	WorldProps.barrel(parent, c + Vector3(9.8, 0, -0.5), 0.9)
	WorldProps.prop(parent, "nature", "log_stackLarge", c + Vector3(-3.5, 0, 9.5), 0.4, WorldProps.NATURE, "box")
	WorldProps.prop(parent, "town", "cart-high", c + Vector3(3.5, 0, -9.5), 2.2, WorldProps.TOWN, "box")
	WorldProps.stall(parent, c + Vector3(-9.0, 0, 8.5), 1.6, 1)
	# Lanterns on the lanes between the fire pit and the houses; the 1.6 rad
	# offset keeps them off the smithy (anvil at ~0.95 rad) and the crates.
	for k in 4:
		var a := TAU * k / 4.0 + 1.6
		WorldProps.lantern(parent, c + Vector3(cos(a) * 7.5, 0, sin(a) * 7.5), -a)
	WorldProps.fences(parent, [
		[c + Vector3(-16, 0, -6), c + Vector3(-10, 0, -12)], [c + Vector3(12, 0, 10), c + Vector3(17, 0, 3)],
		[c + Vector3(10, 0, -13), c + Vector3(16, 0, -8)]])
	if not WorldProps.signpost(parent, c + Vector3(13.5, 0, 0.5), 0.3):
		WorldArt.cyl(parent, 0.08, 0.1, 2.6, c + Vector3(13.5, 1.3, 0.5), WorldArt.WOOD, 6)
	return {"smith": anvil, "fire": c}


## Campfire with the Talven-style flame mesh and a flickering light.
static func campfire(parent: Node3D, pos: Vector3) -> void:
	if not WorldProps.campfire(parent, pos):
		for k in 8:
			var a := TAU * k / 8.0
			WorldArt.sphere(parent, 0.3, pos + Vector3(cos(a) * 1.0, 0.15, sin(a) * 1.0), WorldArt.STONE_DARK, Vector3(1, 0.7, 1))
		for k in 3:
			WorldArt.cyl(parent, 0.12, 0.12, 1.3, pos + Vector3(0, 0.25, 0), WorldArt.WOOD, 6, Vector3(0, TAU * k / 3.0, PI / 2.3))
	var fire := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.0
	fm.bottom_radius = 0.55
	fm.height = 1.2
	fm.radial_segments = 8
	fm.material = WorldArt.mat(Color("ffb347"), 0.0, Color("ff6a1a"), 3.5)
	fire.mesh = fm
	fire.position = pos + Vector3(0, 0.75, 0)
	parent.add_child(fire)
	var ftw := fire.create_tween().set_loops()
	ftw.tween_property(fire, "scale", Vector3(0.85, 1.2, 0.85), 0.35).set_trans(Tween.TRANS_SINE)
	ftw.tween_property(fire, "scale", Vector3(1.1, 0.9, 1.1), 0.4).set_trans(Tween.TRANS_SINE)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.omni_range = 7
	light.light_energy = 0.9
	light.position = pos + Vector3(0, 1.5, 0)
	parent.add_child(light)
	if not WorldArt.headless():
		var smoke := WorldArt._particles(pos + Vector3(0, 1.4, 0), 24, 3.0, Vector3(0.2, 0.1, 0.2), Color(0.5, 0.5, 0.55, 0.45), 0.5, 0.0)
		smoke.process_material.initial_velocity_min = 1.0
		smoke.process_material.initial_velocity_max = 1.6
		smoke.process_material.spread = 12.0
		smoke.process_material.scale_max = 2.5
		parent.add_child(smoke)


## Two posts, a crossbar and hides pegged out to cure.
static func drying_rack(parent: Node3D, pos: Vector3, rot_y: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot_y
	parent.add_child(n)
	for sx in [-1.6, 1.6]:
		WorldArt.cyl(n, 0.07, 0.09, 2.4, Vector3(sx, 1.2, 0), WorldArt.WOOD, 6)
	WorldArt.cyl(n, 0.05, 0.05, 3.6, Vector3(0, 2.3, 0), WorldArt.WOOD_LIGHT, 6, Vector3(0, 0, PI / 2))
	var hides := [Color("8a6242"), Color("6f4a32"), Color("a3795a")]
	for i in 3:
		var x := -1.0 + i * 1.0
		WorldArt.box(n, Vector3(0.8, 1.3, 0.04), Vector3(x, 1.6, 0.03), hides[i], Vector3(0.05, 0, 0.08 * (i - 1)), 0.015)
	WorldArt.box_collider(parent, Vector3(3.6, 2.4, 0.4), pos + Vector3(0, 1.2, 0), Vector3(0, rot_y, 0))


## Totem post hung with stag antlers: the hunters' mark.
static func trophy_post(parent: Node3D, pos: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	WorldArt.cyl(n, 0.14, 0.2, 3.4, Vector3(0, 1.7, 0), WorldArt.WOOD, 8)
	WorldArt.cyl(n, 0.45, 0.5, 0.3, Vector3(0, 0.15, 0), WorldArt.STONE_DARK, 10)
	var horn := Color("4a3a2c")
	for side in [-1.0, 1.0]:
		for lvl in 2:
			var y := 2.2 + lvl * 0.8
			var a := Node3D.new()
			a.position = Vector3(side * 0.16, y, 0)
			a.rotation = Vector3(0.1, 0, side * -0.9)
			n.add_child(a)
			WorldArt.cyl(a, 0.03, 0.05, 0.9, Vector3(0, 0.45, 0), horn, 6)
			for t in 2:
				WorldArt.cyl(a, 0.0, 0.03, 0.35, Vector3(side * 0.12 * (t + 1), 0.35 + t * 0.3, 0), horn, 5, Vector3(0, 0, side * -0.8))
	WorldArt.box(n, Vector3(0.9, 1.1, 0.05), Vector3(0, 1.3, 0.2), Color("7a2e2a"), Vector3.ZERO, 0.0)  # hunters' banner
	WorldArt.box(n, Vector3(0.5, 0.08, 0.06), Vector3(0, 1.55, 0.23), Color("e8c472"), Vector3.ZERO, 0.0)
	WorldArt.box_collider(parent, Vector3(0.6, 3.4, 0.6), pos + Vector3(0, 1.7, 0))


# --- The Mere: lake, boardwalk, shrine isle ----------------------------------------

static func build_lake(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var c := LAKE
	var lake := CylinderMesh.new()
	lake.top_radius = LAKE_RADIUS + 0.8
	lake.bottom_radius = LAKE_RADIUS + 0.8
	lake.height = 0.08
	lake.radial_segments = 48
	var wm := WorldArt.water_mat(Vector2(0.4, 1.0), 0.08, BOG_WATER, BOG_DEEP)
	wm.set_shader_parameter("alpha", 0.9)
	wm.set_shader_parameter("wave_height", 0.02)
	var lm := WorldArt.mesh_node(parent, lake, c + Vector3(0, 0.05, 0), wm)
	lm.name = "Lake"
	# Muddy shore lip and shore rocks.
	var lip := TorusMesh.new()
	lip.inner_radius = LAKE_RADIUS + 0.4
	lip.outer_radius = LAKE_RADIUS + 2.4
	lip.rings = 64
	lip.ring_segments = 6
	WorldArt.mesh_node(parent, lip, c + Vector3(0, 0.02, 0), WorldArt.mat(Color("4a4030"), 0.0), Vector3.ZERO, Vector3(1, 0.12, 1))
	WorldProps.shore_rocks(parent, c, LAKE_RADIUS + 1.1)
	# Reeds: a thick ring, thinner where the boardwalk leaves the shore.
	var ends := boardwalk_ends()
	var shore: Vector3 = ends[0]
	var reeds := []
	var rc := []
	for i in 220:
		var ang := rng.randf() * TAU
		var r := LAKE_RADIUS + rng.randf_range(-1.2, 2.6)
		var p := c + Vector3(cos(ang) * r, 0, sin(ang) * r)
		if p.distance_to(shore) < 4.0:
			continue
		var s := rng.randf_range(1.8, 3.0)
		reeds.append(WorldArt.xf(p, rng.randf() * TAU, Vector3(s, s, s)))
		rc.append(Color("6a7a3a").lerp(Color("b59a4a"), rng.randf()))
	var gmat := ShaderMaterial.new()
	gmat.shader = WorldArt.shader("grass")
	gmat.set_shader_parameter("wind_strength", 0.3)
	gmat.set_shader_parameter("base_color", Color("3f3a1c"))
	gmat.set_shader_parameter("tip_color", Color("a88a44"))
	var mm := WorldArt.multimesh(parent, WorldArt.grass_mesh(), reeds, rc, "Reeds")
	mm.material_override = gmat
	# Lily pads (nature kit when present) and a few drifting logs.
	var pads := {"lily_large": [], "lily_small": []}
	for i in 26:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(2.0, LAKE_RADIUS - 2.0)
		var p := c + Vector3(cos(ang) * r, 0.08, sin(ang) * r)
		if p.distance_to(ISLE) < ISLE_RADIUS + 1.5 or _near_boardwalk(p):
			continue
		var k: String = "lily_large" if i % 3 == 0 else "lily_small"
		if AssetLib.has_prop("nature", k):
			pads[k].append(WorldArt.xf(p, rng.randf() * TAU, Vector3.ONE * WorldProps.NATURE * rng.randf_range(0.9, 1.3)))
		else:
			WorldArt.cyl(parent, 0.5, 0.5, 0.04, p + Vector3(0, 0.04, 0), Color("4f7b3a"), 10)
	for k in pads:
		if not pads[k].is_empty():
			AssetLib.multi(parent, "nature", k, pads[k], true, false)
	for i in 3:
		var ang := 0.9 + i * 1.9
		var p := c + Vector3(cos(ang) * (LAKE_RADIUS - 5.0), 0.0, sin(ang) * (LAKE_RADIUS - 5.0))
		if not AssetLib.prop(parent, "nature", "log_large", p, ang, WorldProps.NATURE, "none"):
			WorldArt.cyl(parent, 0.3, 0.3, 3.0, p + Vector3(0, 0.1, 0), WorldArt.WOOD, 8, Vector3(0, ang, PI / 2))
	# A beached canoe and a fishing stand on the shore near the boardwalk.
	var out := (shore - c).normalized()
	var side := out.cross(Vector3.UP)
	AssetLib.prop(parent, "nature", "canoe", shore + side * 6.0 + out * 0.5, atan2(side.x, side.z), WorldProps.NATURE, "box")
	AssetLib.prop(parent, "survival", "campfire-fishing-stand", shore - side * 6.5 + out * 1.0, 0.0, WorldProps.SURVIVAL, "box")
	build_boardwalk(parent, ends[0], ends[1])
	build_isle(parent)
	# Fog banks drifting over the water.
	if not WorldArt.headless():
		var mist := WorldArt._particles(c + Vector3(0, 0.8, 0), 70, 9.0, Vector3(LAKE_RADIUS, 0.4, LAKE_RADIUS), MIST, 5.0, 0.0)
		mist.name = "LakeMist"
		soften(mist, 0.3)
		mist.process_material.initial_velocity_min = 0.2
		mist.process_material.initial_velocity_max = 0.5
		mist.process_material.direction = Vector3(1, 0, 0.3)
		mist.process_material.spread = 30.0
		mist.process_material.scale_max = 2.0
		parent.add_child(mist)


static func _near_boardwalk(p: Vector3) -> bool:
	var ends := boardwalk_ends()
	var a: Vector3 = ends[0]
	var b: Vector3 = ends[1]
	return WorldArt._seg_dist(Vector2(p.x, p.z), Vector2(a.x, a.z), Vector2(b.x, b.z)) < 2.6


## Plank deck on pilings from a to b, rope rails on both sides. The deck is
## a thin slab at y 0.15 so the capsule steps on without a collider snag.
static func build_boardwalk(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var dir := (b - a)
	var len := dir.length()
	dir /= len
	var side := dir.cross(Vector3.UP)
	var rot_y := -atan2(dir.z, dir.x)
	var n := Node3D.new()
	n.name = "Boardwalk"
	parent.add_child(n)
	var plank_mat := WorldArt.stone_mat(PLANK, PLANK_DARK, "weathered_planks", 0.6, {"detail_strength": 0.6, "detail_tint": 0.3})
	var plank := BoxMesh.new()
	plank.size = Vector3(0.62, 0.14, 3.0)
	var xs := []
	var count := int(len / 0.7)
	for i in count:
		var t := (i + 0.5) / count
		var p := a.lerp(b, t) + Vector3(0, 0.1 + 0.015 * sin(i * 1.7), 0)
		xs.append(WorldArt.xf(p, rot_y + 0.02 * sin(i * 2.3), Vector3(1, 1, 1 + 0.03 * sin(i))))
	var deck := WorldArt.multimesh(n, plank, xs, [], "Planks")
	deck.material_override = plank_mat
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Stringers under the planks.
	for sx in [-1.1, 1.1]:
		WorldArt.box(n, Vector3(len, 0.18, 0.22), (a + b) * 0.5 + side * sx + Vector3(0, -0.02, 0), PLANK_DARK, Vector3(0, rot_y, 0), 0.0)
	# Pilings and rope rails every ~3.5 m.
	var posts := maxi(2, int(len / 3.5) + 1)
	var prev := []
	for i in posts:
		var t := float(i) / (posts - 1)
		var p := a.lerp(b, t)
		var pair := []
		for sx in [-1.35, 1.35]:
			var pp: Vector3 = p + side * sx
			WorldArt.cyl(n, 0.09, 0.12, 2.2, pp + Vector3(0, 0.4, 0), WorldArt.WOOD, 7)
			WorldArt.sphere(n, 0.12, pp + Vector3(0, 1.52, 0), Color("2e2418"))
			pair.append(pp + Vector3(0, 1.3, 0))
		if not prev.is_empty():
			for k in 2:
				var m: Vector3 = (prev[k] + pair[k]) * 0.5 + Vector3(0, -0.12, 0)
				var seg: float = prev[k].distance_to(pair[k])
				WorldArt.cyl(n, 0.025, 0.025, seg, m, Color("b59a6a"), 5, Vector3(0, rot_y, PI / 2))
		prev = pair
	# Teal lanterns hung on every other post pair.
	for i in range(0, posts, 2):
		var t := float(i) / (posts - 1)
		var p := a.lerp(b, t) + side * 1.35 + Vector3(0, 1.75, 0)
		var cage := BoxMesh.new()
		cage.size = Vector3(0.28, 0.36, 0.28)
		WorldArt.mesh_node(n, cage, p, WorldArt.mat(Color("d8fff0"), 0.0, RUNE, 1.6))
		if not WorldArt.headless():
			var l := OmniLight3D.new()
			l.light_color = RUNE
			l.light_energy = 0.5
			l.omni_range = 5.0
			l.shadow_enabled = false
			l.position = p
			n.add_child(l)


## Flagstone isle with the Shrine of Still Water: a ring of mossy columns, an
## altar under a floating rune crystal, candles and two braziers. The keeper
## NPC and the rite are world.gd's.
static func build_isle(parent: Node3D) -> void:
	var c := ISLE
	var disc := WorldArt.cyl(parent, ISLE_RADIUS + 0.3, ISLE_RADIUS + 0.8, 0.14, c + Vector3(0, 0.07, 0), Color("7d8279"), 40)
	disc.material_override = WorldArt.platform_floor_mat(Vector2(c.x, c.z), RUNE, c.y - 0.5)
	disc.material_override.set_shader_parameter("albedo", Color("7f8a78"))
	disc.material_override.set_shader_parameter("albedo_b", Color("606a5b"))
	WorldArt.rune_floor(parent, c + Vector3(0, 0.16, 0), 2.4, RUNE, 2.4)
	WorldArt.rune_ring(parent, c + Vector3(0, 0.17, 0), ISLE_RADIUS - 1.0, RUNE_DIM, 0.14)
	var moss_tint := Color("c4d6bc")
	var entry: Vector3 = (boardwalk_ends()[1] - c).normalized()
	for i in 6:
		var a := TAU * i / 6.0 + PI / 6
		var d := Vector3(cos(a), 0, sin(a))
		if d.dot(entry) > 0.8:
			continue
		var p := c + d * (ISLE_RADIUS - 1.3)
		if AssetLib.has_prop("dungeon", "pillar"):
			WorldProps.tinted_prop(parent, "dungeon", "pillar_decorated" if i % 2 == 0 else "pillar", p, -a, WorldProps.DUNGEON * 0.9, "box", moss_tint)
		else:
			WorldArt.ornate_pillar(parent, p, 3.6)
		# Ivy and moss caps.
		WorldArt.sphere(parent, 0.5, p + Vector3(0, 3.6, 0), MOSS, Vector3(1.2, 0.35, 1.2))
	# Back wall of the shrine opposite the boardwalk.
	var back: Vector3 = c - entry * (ISLE_RADIUS - 1.6)
	if AssetLib.has_prop("dungeon", "wall_arched"):
		WorldProps.tinted_prop(parent, "dungeon", "wall_arched", back, atan2(entry.x, entry.z), 1.4, "box", moss_tint)
	else:
		WorldArt.box(parent, Vector3(5.6, 5.0, 1.0), back + Vector3(0, 2.5, 0), WorldArt.STONE)
	# Altar, crystal and candles.
	var altar: Vector3 = c - entry * 1.2
	if not AssetLib.prop(parent, "graveyard", "altar-stone", altar, atan2(entry.x, entry.z), WorldProps.GRAVE, "box"):
		WorldArt.box(parent, Vector3(1.6, 1.0, 0.9), altar + Vector3(0, 0.5, 0), WorldArt.STONE_DARK)
	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.0
	crystal.bottom_radius = 0.45
	crystal.height = 1.5
	crystal.radial_segments = 4
	var cm := WorldArt.mat(RUNE.lightened(0.35), 0.0, RUNE, 3.0)
	var ks := WorldArt.mesh_node(parent, crystal, altar + Vector3(0, 2.6, 0), cm, Vector3(PI, 0, 0))
	var bob := ks.create_tween().set_loops()
	bob.tween_property(ks, "position:y", altar.y + 3.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(ks, "position:y", altar.y + 2.4, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var spin := ks.create_tween().set_loops()
	spin.tween_property(ks, "rotation:y", TAU, 6.0).from(0.0)
	if not WorldArt.headless():
		var l := OmniLight3D.new()
		l.light_color = RUNE
		l.light_energy = 1.2
		l.omni_range = 9.0
		l.position = altar + Vector3(0, 2.6, 0)
		parent.add_child(l)
	if AssetLib.has_prop("dungeon", "candle_triple"):
		for k in 4:
			var a := TAU * k / 4.0 + 0.5
			AssetLib.prop(parent, "dungeon", "candle_triple", c + Vector3(cos(a) * 2.9, 0.15, sin(a) * 2.9), a, WorldProps.DUNGEON, "none")
	var bside: Vector3 = entry.cross(Vector3.UP)
	for sx in [-1, 1]:
		var bp: Vector3 = c + entry * 2.8 + bside * sx * 3.0
		WorldArt.brazier(parent, bp)
		WorldArt.box_collider(parent, Vector3(1.4, 2.2, 1.4), bp + Vector3(0, 1.1, 0))
	# Offerings and reeds at the isle edge.
	if AssetLib.has_prop("graveyard", "urn-round"):
		AssetLib.prop(parent, "graveyard", "urn-round", back + bside * 2.4 + entry * 1.2, 0.3, WorldProps.GRAVE, "box")
		AssetLib.prop(parent, "graveyard", "urn-square", back - bside * 2.6 + entry * 1.4, -0.4, WorldProps.GRAVE, "box")


# --- The Sunken Barrow --------------------------------------------------------------

static func build_barrow(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var c := BARROW
	var to_village := Vector2(VILLAGE.x - c.x, VILLAGE.z - c.z).angle()
	WorldProps.iron_fence_ring(parent, c, BARROW_RADIUS, to_village, 0.5)
	# Gate pillars at the gap.
	for sx in [-1, 1]:
		var a: float = to_village + sx * 0.55
		var p := c + Vector3(cos(a), 0, sin(a)) * BARROW_RADIUS
		if not AssetLib.prop(parent, "graveyard", "pillar-obelisk", p, -a, WorldProps.GRAVE * 1.2, "box"):
			WorldArt.ornate_pillar(parent, p, 4.0)
	# Sunken rune circle where the wisps gather, broken columns around it.
	var dais := WorldArt.cyl(parent, 5.2, 5.6, 0.12, c + Vector3(0, 0.06, 0), Color("5c6158"), 32)
	dais.material_override = WorldArt.ruin_mat("ledge")
	WorldArt.rune_floor(parent, c + Vector3(0, 0.14, 0), 4.6, RUNE_DIM, 1.6)
	for k in 5:
		var a := TAU * k / 5.0 + 0.9
		if absf(wrapf(a - to_village, -PI, PI)) < 0.5:
			continue
		var p := c + Vector3(cos(a), 0, sin(a)) * 7.0
		WorldArt.broken_column(parent, p, 3.5 + 1.2 * (k % 2), RUNE_DIM, k % 2 == 1, 0.8)
		WorldArt.box_collider(parent, Vector3(1.2, 4.0, 1.2), p + Vector3(0, 2.0, 0))
	# Crypts and graves.
	var crypt_dir := Vector3(cos(to_village + PI), 0, sin(to_village + PI))
	var crypt := c + crypt_dir * 9.5
	if not AssetLib.prop(parent, "graveyard", "crypt", crypt, to_village + PI / 2, WorldProps.GRAVE * 1.5, "box"):
		WorldArt.box(parent, Vector3(5, 4, 4), crypt + Vector3(0, 2, 0), WorldArt.STONE_DARK)
	for sx in [-1, 1]:
		var a: float = to_village + PI + sx * 1.3
		AssetLib.prop(parent, "graveyard", "crypt-small", c + Vector3(cos(a), 0, sin(a)) * 9.0, -a + PI / 2, WorldProps.GRAVE * 1.3, "box")
	var kinds := {"gravestone-round": [], "gravestone-cross": [], "gravestone-bevel": [], "gravestone-broken": [], "gravestone-wide": [], "cross-wood": []}
	var keys := kinds.keys()
	var fallback := []
	for i in 44:
		var a := rng.randf() * TAU
		if absf(wrapf(a - to_village, -PI, PI)) < 0.55:
			continue
		var r := rng.randf_range(6.3, BARROW_RADIUS - 1.5)
		var p := c + Vector3(cos(a), 0, sin(a)) * r
		if p.distance_to(crypt) < 3.5:
			continue
		var k: String = keys[i % keys.size()]
		if AssetLib.has_prop("graveyard", k):
			kinds[k].append(WorldArt.xf(p, -a + PI / 2 + rng.randf_range(-0.4, 0.4), Vector3.ONE * WorldProps.GRAVE * rng.randf_range(1.1, 1.4), Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.15, 0.15))))
		else:
			fallback.append(WorldArt.xf(p + Vector3(0, 0.5, 0), -a, Vector3(0.7, 1.0, 0.25)))
	for k in keys:
		if not kinds[k].is_empty():
			AssetLib.multi(parent, "graveyard", k, kinds[k])
	if not fallback.is_empty():
		var mm := WorldArt.multimesh(parent, BoxMesh.new(), fallback, [], "Graves")
		mm.material_override = WorldArt.ruin_mat("trim")
	# Fire baskets with cold teal flames, debris and candles.
	for k in 4:
		var a := TAU * k / 4.0 + to_village + PI / 4
		var p := c + Vector3(cos(a), 0, sin(a)) * 5.9
		if not AssetLib.prop(parent, "graveyard", "fire-basket", p, 0.0, WorldProps.GRAVE, "box"):
			WorldArt.cyl(parent, 0.3, 0.2, 1.0, p + Vector3(0, 0.5, 0), Color("3a3440"), 8)
		var flame := CylinderMesh.new()
		flame.top_radius = 0.0
		flame.bottom_radius = 0.3
		flame.height = 0.8
		flame.radial_segments = 6
		var f := WorldArt.mesh_node(parent, flame, p + Vector3(0, 1.4, 0), WorldArt.mat(RUNE.lightened(0.3), 0.0, RUNE, 3.0))
		var ftw := f.create_tween().set_loops()
		ftw.tween_property(f, "scale", Vector3(0.8, 1.25, 0.8), 0.4).set_trans(Tween.TRANS_SINE)
		ftw.tween_property(f, "scale", Vector3(1.1, 0.9, 1.1), 0.45).set_trans(Tween.TRANS_SINE)
		if not WorldArt.headless():
			var l := OmniLight3D.new()
			l.light_color = RUNE
			l.light_energy = 0.8
			l.omni_range = 7.0
			l.shadow_enabled = false
			l.position = p + Vector3(0, 1.6, 0)
			parent.add_child(l)
	if AssetLib.has_prop("graveyard", "debris"):
		for k in 5:
			var a := rng.randf() * TAU
			var r := rng.randf_range(3.0, 11.0)
			AssetLib.prop(parent, "graveyard", "debris" if k % 2 == 0 else "debris-wood", c + Vector3(cos(a) * r, 0, sin(a) * r), rng.randf() * TAU, WorldProps.GRAVE, "none")
	# Crooked dead pines around the fence, mushrooms inside.
	var pines := []
	for i in 14:
		var a := rng.randf() * TAU
		if absf(wrapf(a - to_village, -PI, PI)) < 0.5:
			continue
		var r := rng.randf_range(BARROW_RADIUS + 1.5, BARROW_RADIUS + 7.0)
		pines.append(WorldArt.xf(c + Vector3(cos(a), 0, sin(a)) * r, rng.randf() * TAU, Vector3.ONE * WorldProps.GRAVE * rng.randf_range(1.4, 2.0)))
	if AssetLib.has_prop("graveyard", "pine-fall-crooked"):
		AssetLib.multi(parent, "graveyard", "pine-fall-crooked", pines)
	else:
		var mm := WorldArt.multimesh(parent, WorldArt.tree_mesh(1), pines, [], "BarrowPines")
		mm.material_override = WorldArt.foliage_mat(Color("5a3a22"), 0.2, 0.03)
	var shrooms := {"mushroom_redGroup": [], "mushroom_tanTall": [], "mushroom_redTall": []}
	for i in 30:
		var a := rng.randf() * TAU
		var r := rng.randf_range(5.5, BARROW_RADIUS - 1.0)
		var k: String = shrooms.keys()[i % 3]
		shrooms[k].append(WorldArt.xf(c + Vector3(cos(a) * r, 0, sin(a) * r), rng.randf() * TAU, Vector3.ONE * WorldProps.NATURE * rng.randf_range(0.8, 1.4)))
	for k in shrooms:
		if AssetLib.has_prop("nature", k):
			AssetLib.multi(parent, "nature", k, shrooms[k])
	# Ground fog pooling in the barrow.
	if not WorldArt.headless():
		var mist := WorldArt._particles(c + Vector3(0, 0.6, 0), 50, 8.0, Vector3(BARROW_RADIUS, 0.3, BARROW_RADIUS), Color(0.7, 0.8, 0.78, 0.25), 4.5, 0.0)
		mist.name = "BarrowMist"
		soften(mist, 0.3)
		mist.process_material.initial_velocity_min = 0.1
		mist.process_material.initial_velocity_max = 0.3
		mist.process_material.scale_max = 2.2
		parent.add_child(mist)


# --- Vegetation and ambience --------------------------------------------------------

## Autumn woods: fall-colour Nature Kit trees (procedural autumn puffballs
## without the pack), dark pines near the tower and barrow, mushrooms, bushes,
## logs, leaf-litter grass and a few pale flowers. Trunk colliders skip the
## mob grounds (tower apron, barrow) so mobs never get stuck.
static func build_vegetation(parent: Node3D, rng: RandomNumberGenerator, radius: float, keep_clear: Array) -> void:
	var clear := func(p: Vector2, extra := 0.0) -> bool:
		for k in keep_clear:
			if p.distance_to(Vector2(k[0].x, k[0].z)) < k[1] + extra:
				return true
		return false
	var use_pack := AssetLib.has_prop("nature", "tree_oak_fall")
	var trees := [[], [], []]
	var tree_cols := [[], [], []]
	var pack_trees := {}
	var trunk_shapes := []
	var tries := 0
	var placed := 0
	var tower2 := Vector2(TOWER.x, TOWER.z)
	var barrow2 := Vector2(BARROW.x, BARROW.z)
	while placed < 330 and tries < 8000:
		tries += 1
		var a := rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * (radius - 6)
		if p.length() < 14.0 or ground_kind(p) != WorldArt.Ground.GRASS or clear.call(p, 3.0):
			continue
		if p.distance_to(tower2) < 22.0:
			continue
		var too_close := false
		for v in 3:
			for t in trees[v]:
				if Vector2(t.origin.x, t.origin.z).distance_to(p) < 4.2:
					too_close = true
					break
			if too_close:
				break
		if too_close:
			continue
		var dark := (p.distance_to(tower2) < 40.0 or p.distance_to(barrow2) < 24.0) and rng.randf() < 0.6
		var variant := 1 if dark else (2 if rng.randf() < 0.35 else 0)
		var s := rng.randf_range(0.95, 1.6)
		var rot := rng.randf() * TAU
		if use_pack:
			var pool: Array = TREES_DARK if dark else TREES_FALL
			var kind: String = pool[rng.randi() % pool.size()]
			var ps := s * WorldProps.NATURE * 1.0
			if not pack_trees.has(kind):
				pack_trees[kind] = []
			pack_trees[kind].append(WorldArt.xf(Vector3(p.x, 0, p.y), rot, Vector3(ps, ps * rng.randf_range(0.95, 1.2), ps)))
		else:
			trees[variant].append(WorldArt.xf(Vector3(p.x, 0, p.y), rot, Vector3(s, s * rng.randf_range(0.9, 1.2), s)))
			var g := LEAF_A.lerp(LEAF_B, rng.randf()).lerp(LEAF_C, rng.randf() * 0.4)
			if dark:
				g = Color("2f4a3a").lerp(Color("4a6a4a"), rng.randf())
			tree_cols[variant].append(g)
		placed += 1
		if p.distance_to(tower2) > 34 and p.distance_to(barrow2) > 20:
			trunk_shapes.append(Vector3(p.x, 0, p.y))
	for v in 3:
		if trees[v].is_empty():
			continue
		var mmi := WorldArt.multimesh(parent, WorldArt.tree_mesh(v), trees[v], tree_cols[v], "Trees%d" % v)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Fall kinds get their own tint so the woods read as a mix of rust, amber and gold.
	var tints := {"tree_oak_fall": Color("ff8a5a"), "tree_default_fall": Color("ffd08a"), "tree_detailed_fall": Color("ff6a4a"),
		"tree_fat_fall": Color("ffb060"), "tree_tall_fall": Color("e8c070"), "tree_plateau_fall": Color("ff9a4a"), "tree_thin_fall": Color("d86a3a")}
	for kind in pack_trees:
		WorldProps.tinted_multi(parent, "nature", kind, pack_trees[kind], tints.get(kind, Color.WHITE))
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

	# Boulders, mossy.
	var rocks := []
	var rock_cols := []
	var pack_rocks := {"rock_largeA": [], "rock_largeB": [], "rock_largeC": [], "rock_tallA": []}
	var pack_keys := pack_rocks.keys()
	for i in 120:
		var a := rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * rng.randf_range(24, 82)
		if ground_kind(p) != WorldArt.Ground.GRASS or clear.call(p, 2.0):
			continue
		var s := rng.randf_range(0.5, 2.0)
		if AssetLib.has_prop("nature", "rock_largeA"):
			var k: String = pack_keys[(i * 7) % 4]
			var ps := s * 2.2
			pack_rocks[k].append(WorldArt.xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, Vector3(ps, ps * rng.randf_range(0.7, 1.0), ps)))
			continue
		rocks.append(WorldArt.xf(Vector3(p.x, -s * 0.2, p.y), rng.randf() * TAU, Vector3(s, s * rng.randf_range(0.6, 1.0), s * rng.randf_range(0.7, 1.3))))
		rock_cols.append(Color("6a6e62").lerp(Color("4a4e44"), rng.randf()))
	if not rocks.is_empty():
		var rm := WorldArt.multimesh(parent, WorldArt.rock_mesh(), rocks, rock_cols, "Rocks")
		rm.material_override = WorldArt.foliage_mat(Color.WHITE, 0.0, 0.03)
	for k in pack_rocks:
		if not pack_rocks[k].is_empty():
			WorldProps.tinted_multi(parent, "nature", k, pack_rocks[k], Color("c9d4bc"))

	if WorldArt.headless():
		return
	# Undergrowth: mushrooms everywhere, bushes, ferns, logs and stumps.
	var ok := func(p: Vector2) -> bool:
		return ground_kind(p) == WorldArt.Ground.GRASS and not clear.call(p, 1.5)
	if AssetLib.has_prop("nature", "plant_bush"):
		var sets := {"mushroom_redGroup": [70, 0.8, 1.3], "mushroom_tanGroup": [70, 0.8, 1.3], "mushroom_redTall": [30, 0.8, 1.2],
			"mushroom_tanTall": [30, 0.8, 1.2], "plant_bushDetailed": [60, 0.8, 1.3], "plant_bush": [50, 0.8, 1.2], "plant_flatTall": [60, 0.9, 1.4],
			"stump_old": [16, 0.9, 1.3], "stump_oldTall": [8, 0.9, 1.3], "log": [20, 0.8, 1.3], "log_large": [8, 0.9, 1.2]}
		for name in sets:
			if not AssetLib.has_prop("nature", name):
				continue
			var cfg: Array = sets[name]
			var xs := []
			var t2 := 0
			while xs.size() < cfg[0] and t2 < cfg[0] * 6:
				t2 += 1
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * (radius - 6)
				var p := Vector2(cos(a), sin(a)) * r
				if not ok.call(p):
					continue
				var s: float = WorldProps.NATURE * rng.randf_range(cfg[1], cfg[2])
				xs.append(WorldArt.xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, Vector3.ONE * s))
			if not xs.is_empty():
				var tint := Color("d8c8a0") if name.begins_with("plant") else Color.WHITE
				WorldProps.tinted_multi(parent, "nature", name, xs, tint, name.begins_with("plant") or name.begins_with("stump") or name.begins_with("log"))

	# Leaf-litter grass: sparser tufts in dry gold and rust.
	var gx := []
	var gc := []
	for i in 16000:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (radius - 4)
		var p := Vector2(cos(a), sin(a)) * r
		if ground_kind(p) != WorldArt.Ground.GRASS or clear.call(p, 0.5):
			continue
		var s := rng.randf_range(0.55, 1.0)
		gx.append(WorldArt.xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, Vector3(s, s * rng.randf_range(0.7, 1.1), s)))
		gc.append(Color(1, 1, 1).lerp(Color(1.0, 0.8, 0.5), rng.randf()).lerp(Color(0.9, 0.55, 0.35), rng.randf() * 0.35))
	var gmat := ShaderMaterial.new()
	gmat.shader = WorldArt.shader("grass")
	gmat.set_shader_parameter("base_color", Color("4a3f1e"))
	gmat.set_shader_parameter("tip_color", Color("9a7a3a"))
	gmat.set_shader_parameter("wind_strength", 0.18)
	var gmm := WorldArt.multimesh(parent, WorldArt.grass_mesh(), gx, gc, "Grass")
	gmm.material_override = gmat
	gmm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Pale flowers in a few patches.
	var fx := []
	var fc := []
	var palette := [Color("f4efe0"), Color("c9a7e8"), Color("e8c87a")]
	for patch in 28:
		var a := rng.randf() * TAU
		var cc := Vector2(cos(a), sin(a)) * rng.randf_range(20, 80)
		var col: Color = palette[rng.randi() % palette.size()]
		for i in 30:
			var p := cc + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
			if ground_kind(p) != WorldArt.Ground.GRASS or clear.call(p, 0.5):
				continue
			var s := rng.randf_range(0.8, 1.2)
			fx.append(WorldArt.xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, Vector3(s, s, s)))
			fc.append(col.lerp(Color.WHITE, rng.randf() * 0.3))
	if not fx.is_empty():
		var fmm := WorldArt.multimesh(parent, WorldArt.flower_mesh(), fx, fc, "Flowers")
		fmm.material_override = WorldArt.foliage_mat(Color.WHITE, 0.8)
		fmm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Turns a WorldArt._particles emitter into soft fog: a radial-gradient quad
## instead of the hard square, dim emission, slow drift.
static func soften(p: GPUParticles3D, alpha := 0.2) -> GPUParticles3D:
	var q := p.draw_pass_1 as QuadMesh
	var m := q.material as StandardMaterial3D
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	m.albedo_texture = tex
	m.emission_energy_multiplier = 0.4
	var pm := p.process_material as ParticleProcessMaterial
	pm.color = Color(pm.color.r, pm.color.g, pm.color.b, alpha)
	return p


## Falling leaves over the woods, ground mist, teal fireflies by the shrine.
static func build_ambience(parent: Node3D) -> void:
	if WorldArt.headless():
		return
	for spot in [Vector3(0, 9, 20), Vector3(-30, 9, -10), Vector3(40, 9, -40)]:
		var leaves := WorldArt._particles(spot, 170, 10.0, Vector3(45, 2, 45), Color(0.95, 0.5, 0.18, 0.95), 0.24, -0.45)
		leaves.name = "Leaves"
		leaves.process_material.color = Color(0.95, 0.55, 0.2, 0.95)
		leaves.process_material.angular_velocity_min = -220
		leaves.process_material.angular_velocity_max = 220
		leaves.process_material.initial_velocity_min = 0.5
		leaves.process_material.initial_velocity_max = 1.4
		leaves.process_material.direction = Vector3(1, -0.3, 0.4)
		leaves.process_material.spread = 45.0
		leaves.process_material.turbulence_enabled = true
		leaves.process_material.turbulence_noise_strength = 1.6
		parent.add_child(leaves)
	var mist := WorldArt._particles(Vector3(0, 0.7, -10), 160, 12.0, Vector3(80, 0.3, 80), Color(0.85, 0.84, 0.78, 0.14), 6.0, 0.0)
	mist.name = "GroundMist"
	soften(mist, 0.16)
	mist.process_material.initial_velocity_min = 0.15
	mist.process_material.initial_velocity_max = 0.4
	mist.process_material.direction = Vector3(1, 0, 0.2)
	mist.process_material.spread = 40.0
	mist.process_material.scale_max = 2.4
	parent.add_child(mist)
	var fire := WorldArt._particles(ISLE + Vector3(0, 1.5, 0), 90, 7.0, Vector3(14, 1.2, 14), Color(0.55, 1.0, 0.85, 0.9), 0.14, 0.0)
	fire.name = "Fireflies"
	fire.process_material.turbulence_enabled = true
	fire.process_material.turbulence_noise_strength = 1.2
	fire.process_material.turbulence_noise_scale = 4.0
	fire.process_material.initial_velocity_min = 0.1
	fire.process_material.initial_velocity_max = 0.4
	parent.add_child(fire)
