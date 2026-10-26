class_name WorldProps
extends RefCounted
## Dresses Floor 1 with the CC0 packs under res://assets/ (see
## assets/HANDOFF.md) through AssetLib: KayKit hex buildings, Kenney town,
## nature, survival, graveyard, castle and dungeon props. Every builder falls
## back to the procedural WorldArt primitives when a pack is missing, so the
## world still builds (and collides identically) before the assets import.
## Anything repeated more than a handful of times goes through AssetLib.multi.

const TOWN := 2.4        # Kenney Fantasy Town: 1 unit ~ 2.4 m
const NATURE := 3.2      # Kenney Nature Kit: props are ~1 unit
const SURVIVAL := 5.5    # Kenney Survival Kit: tiny 0.5 unit props
const GRAVE := 2.4       # Kenney Graveyard Kit
const CASTLE := 4.0      # Kenney Castle Kit
const DUNGEON := 0.8     # KayKit Dungeon: metre scale (pillar 4 m)
const HOUSE := 7.0       # KayKit hex buildings: ~0.8 unit -> 5.6 m cottage

## Nature Kit tree kinds: [meadow kinds, woodland kinds, autumn accents].
const TREES_MEADOW := ["tree_oak", "tree_default", "tree_detailed", "tree_fat"]
const TREES_WOODS := ["tree_pineTallA_detailed", "tree_pineDefaultA", "tree_pineRoundC", "tree_pineTallB"]
const TREES_FALL := ["tree_oak_fall", "tree_default_fall"]

static var _lantern_xf: Array = []
static var _glass_xf: Array = []


static func has(pack: String, name: String) -> bool:
	return AssetLib.has_prop(pack, name)


static func ready() -> bool:
	return has("town", "lantern") and has("hex", "buildings/blue/building_home_A_blue")


# --- Buildings ---------------------------------------------------------------

## A finished hex-pack building; door faces local +Z. Falls back to the
## procedural cottage with a similar footprint.
static func house(parent: Node3D, pos: Vector3, kind: String, color: String, rot_y: float, scl := HOUSE) -> Node3D:
	var n := AssetLib.house(parent, pos, kind, color, rot_y, scl)
	if n == null:
		return WorldArt.house(parent, pos, 6.0, 5.0, 4.0, rot_y, 0)
	n.name = "Bld_%s_%s" % [kind, color]
	if kind == "windmill":
		_spin_fan(n)
	return n


static func _spin_fan(n: Node3D) -> void:
	for c in _descendants(n):
		if c is Node3D and c.name.to_lower().contains("fan"):
			var tw: Tween = c.create_tween().set_loops()
			tw.tween_property(c, "rotation:z", TAU, 11.0).from(0.0)
			return


static func _descendants(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		out.append(c)
		_descendants(c, out)
	return out


## Footprint (x, z) in metres so layouts can space buildings.
static func footprint(kind: String, color := "blue", scl := HOUSE) -> Vector2:
	if not ready():
		return Vector2(6.4, 5.4)
	return AssetLib.house_footprint(kind, color, scl)


# --- Lanterns ----------------------------------------------------------------

## Lamp post (one MultiMesh for all posts) with the game's lantern glow cube
## and OmniLight, so DayNight's set_lantern_glow keeps working unchanged.
static func lantern(parent: Node3D, pos: Vector3, rot_y := 0.0) -> void:
	if not has("town", "lantern"):
		WorldArt.lantern(parent, pos, false)
		return
	_lantern_xf.append(WorldArt.xf(pos, rot_y, Vector3.ONE * TOWN))
	var head := pos + Vector3(0, 1.36 * TOWN, 0)
	_glass_xf.append(WorldArt.xf(head, rot_y, Vector3(0.46, 0.5, 0.46)))
	WorldArt.lantern_light(parent, head)


## Emits the batched lantern posts and glass. Call once after placing them.
static func flush(parent: Node3D) -> void:
	if _lantern_xf.is_empty():
		return
	AssetLib.multi(parent, "town", "lantern", _lantern_xf)
	if WorldArt.lantern_material == null:
		WorldArt.lantern_material = ToonMaterial.make(Color("fff0c0"), WorldArt.LANTERN, 0.25)
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var mm := WorldArt.multimesh(parent, bm, _glass_xf, [], "LanternGlass")
	mm.material_override = WorldArt.lantern_material
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lantern_xf.clear()
	_glass_xf.clear()


# --- Lines of things (fences, hedges, walls) ---------------------------------

## Lays `name` end to end from a to b. The piece spans local z -0.5..0.5 and
## sits `side_off` units off its origin in local x (Kenney town pieces do).
static func _line_xforms(a: Vector3, b: Vector3, scl: float, side_off: float, out: Array) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var seg := scl
	var n := maxi(1, int(round(len / seg)))
	var dir := d / len
	var rot := atan2(dir.x, dir.z)
	var side := Vector3(cos(rot), 0, -sin(rot))
	var step := len / n
	for i in n:
		var p := a + dir * (step * (i + 0.5)) - side * side_off * scl
		out.append(WorldArt.xf(p, rot, Vector3(scl, scl, step)))


static func fences(parent: Node3D, lines: Array) -> void:
	if not has("town", "fence"):
		WorldArt.fences(parent, lines)
		return
	var xs := []
	for l in lines:
		_line_xforms(l[0], l[1], TOWN, 0.46, xs)
	AssetLib.multi(parent, "town", "fence", xs)


static func hedges(parent: Node3D, lines: Array) -> void:
	if not has("town", "hedge-large"):
		return
	var xs := []
	for l in lines:
		_line_xforms(l[0], l[1], TOWN, 0.3, xs)
	AssetLib.multi(parent, "town", "hedge-large", xs)


## Ring of graveyard iron fence around a centre, with a gap (radians, centred
## on gap_dir) left open.
static func iron_fence_ring(parent: Node3D, center: Vector3, radius: float, gap_dir: float, gap_half: float) -> void:
	if not has("graveyard", "iron-fence"):
		return
	var xs := []
	var count := int(TAU * radius / GRAVE)
	for i in count:
		var a := TAU * i / count
		if absf(wrapf(a - gap_dir, -PI, PI)) < gap_half:
			continue
		# iron-fence spans local x -0.5..0.5 at local z ~ -0.33. rot -a - PI/2
		# turns local x into the tangent and local +z inward, so the bars sit
		# 0.33 units outside the origin: pull the origin in by that much.
		var p := center + Vector3(cos(a), 0, sin(a)) * (radius - 0.33 * GRAVE)
		xs.append(WorldArt.xf(p, -a - PI / 2, Vector3.ONE * GRAVE))
	AssetLib.multi(parent, "graveyard", "iron-fence", xs)


# --- Plaza & town props -----------------------------------------------------------

static func fountain(parent: Node3D, pos: Vector3) -> void:
	if not has("town", "fountain-round-detail"):
		WorldArt.fountain(parent, pos)
		return
	var f := AssetLib.prop(parent, "town", "fountain-round-detail", pos, 0.0, 3.0, "trimesh", true, Color.WHITE, false)
	f.name = "Fountain"
	if not WorldArt.headless():
		# Carved pale stone and live water instead of the kit's flat white.
		var stone := WorldArt.stone_mat(Color("d9d6cf"), Color("b3aea4"), "castle_brick_07", 0.6, {
			"band_period": 0.45, "brick_length": 0.8, "band_width": 0.06, "band_dark": 0.78, "detail_strength": 0.35,
			"polar": 1.0, "center": Vector2(pos.x, pos.z), "polar_radius": 2.0})
		var water := WorldArt.water_mat(Vector2(1, 0.4), 0.18)
		for mi in f.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			for si in m3.mesh.get_surface_count():
				var src := m3.get_active_material(si)
				var c := Color.WHITE
				if src is BaseMaterial3D:
					c = (src as BaseMaterial3D).albedo_color
				var watery := c.b > c.r + 0.12
				m3.set_surface_override_material(si, water if watery else stone)
		var spray := WorldArt._particles(Vector3(0, 0.5, 0), 90, 1.6, Vector3(0.15, 0.1, 0.15), Color(0.85, 0.97, 1.0, 0.8), 0.12, -9.0)
		spray.process_material.direction = Vector3(0, 1, 0)
		spray.process_material.spread = 25.0
		spray.process_material.initial_velocity_min = 3.5
		spray.process_material.initial_velocity_max = 5.0
		spray.scale = Vector3.ONE / 3.0
		f.add_child(spray)


static func stall(parent: Node3D, pos: Vector3, rot_y: float, variant: int) -> void:
	var names := ["stall-red", "stall-green", "stall"]
	var nm: String = names[variant % names.size()]
	if not has("town", nm):
		WorldArt.market_stall(parent, pos, rot_y, [Color("d9534f"), Color("3f8f8c"), Color("e8b84a")][variant % 3])
		return
	AssetLib.prop(parent, "town", nm, pos, rot_y, TOWN, "box")
	if has("town", "stall-bench"):
		var side := Vector3(cos(rot_y), 0, -sin(rot_y))
		AssetLib.prop(parent, "town", "stall-bench", pos + side * 1.9, rot_y, TOWN, "box")


static func crate(parent: Node3D, pos: Vector3, s := 1.0, rot_y := 0.0) -> void:
	if not has("survival", "box"):
		WorldArt.crate(parent, pos, s, rot_y)
		return
	AssetLib.prop(parent, "survival", "box-large" if s > 0.85 else "box", pos, rot_y, SURVIVAL * s, "box")


static func barrel(parent: Node3D, pos: Vector3, rot_y := 0.0) -> void:
	if not has("survival", "barrel"):
		WorldArt.barrel(parent, pos)
		return
	AssetLib.prop(parent, "survival", "barrel", pos, rot_y, SURVIVAL, "box")


static func prop(parent: Node3D, pack: String, name: String, pos: Vector3, rot_y := 0.0, scl := 1.0, collide := "box") -> Node3D:
	if not has(pack, name):
		return null
	return AssetLib.prop(parent, pack, name, pos, rot_y, scl, collide)


## A prop that stays its own instance (never baked into a batch): for
## furniture that is placed and removed at runtime, such as cottage decor.
static func live_prop(parent: Node, pack: String, name: String, pos: Vector3, rot_y := 0.0, scl := 1.0, collide := "box", tint := Color.WHITE) -> Node3D:
	if not has(pack, name):
		return null
	return AssetLib.prop(parent, pack, name, pos, rot_y, scl, collide, true, tint, false)


## Blacksmith's workplace: the survival-kit anvil and grindstone, a brick
## furnace with a live fire, hood and chimney (WorldArt.flame; the caller
## adds its own OmniLight), bellows, a tool rack of hanging hammers and
## axes, hex-pack weapon racks, a quench barrel, water bucket and a crate of
## stock. The furnace mouth faces the anvil. False without the survival kit.
static func smithy(parent: Node3D, anvil_pos: Vector3, forge_pos: Vector3) -> bool:
	if not has("survival", "workbench-anvil"):
		return false
	var d := anvil_pos - forge_pos
	d.y = 0.0
	var dir := d.normalized() if d.length() > 0.01 else Vector3(0, 0, 1)
	var rot := atan2(dir.x, dir.z)
	var side := Vector3(cos(rot), 0, -sin(rot))
	AssetLib.prop(parent, "survival", "workbench-anvil", anvil_pos, rot + PI - 0.6, SURVIVAL, "box")
	AssetLib.prop(parent, "survival", "workbench-grind", forge_pos - side * 2.6 + dir * 0.6, rot + 0.4, SURVIVAL, "box")
	# Furnace: brick body, dark firebox mouth, fire, iron hood and stack.
	var f := Node3D.new()
	f.name = "Furnace"
	f.position = forge_pos
	f.rotation.y = rot
	parent.add_child(f)
	var brick := WorldArt.stone_mat(Color("8a7468"), Color("6f5a52"), "castle_brick_07", 0.5, {"band_period": 0.26, "band_width": 0.035, "brick_length": 0.55, "band_dark": 0.6, "detail_strength": 0.45})
	# Body built around a recessed firebox mouth (1.0 wide, 0.3..0.9 high,
	# 0.5 deep) so the fire inside shows from the front.
	for part in [[Vector3(0, 0.6, -0.25), Vector3(2.0, 1.2, 1.0)], [Vector3(-0.75, 0.6, 0.5), Vector3(0.5, 1.2, 0.5)],
			[Vector3(0.75, 0.6, 0.5), Vector3(0.5, 1.2, 0.5)], [Vector3(0, 0.15, 0.5), Vector3(1.0, 0.3, 0.5)], [Vector3(0, 1.05, 0.5), Vector3(1.0, 0.3, 0.5)]]:
		WorldArt.mesh_node(f, BoxMesh.new(), part[0], brick, Vector3.ZERO, part[1])
	WorldArt.box_collider(f, Vector3(2.0, 1.2, 1.5), Vector3(0, 0.6, 0))
	WorldArt.mesh_node(f, BoxMesh.new(), Vector3(0, 1.26, 0), WorldArt.ruin_mat("ledge"), Vector3.ZERO, Vector3(2.2, 0.14, 1.7))
	WorldArt.box(f, Vector3(1.0, 0.6, 0.04), Vector3(0, 0.6, 0.27), Color("1a1216"), Vector3.ZERO, 0.0)
	WorldArt.box(f, Vector3(1.0, 0.04, 0.5), Vector3(0, 0.31, 0.5), Color("2a2328"), Vector3.ZERO, 0.0)
	WorldArt.flame(f, Vector3(0, 0.32, 0.52), 0.34, false)
	var hood := CylinderMesh.new()
	hood.top_radius = 0.3
	hood.bottom_radius = 1.0
	hood.height = 0.7
	hood.radial_segments = 4
	WorldArt.mesh_node(f, hood, Vector3(0, 1.68, -0.1), WorldArt.mat(Color("3a3440"), 0.03), Vector3(0, PI / 4, 0))
	WorldArt.cyl(f, 0.2, 0.22, 2.2, Vector3(0, 3.1, -0.1), Color("3a3440"), 8)
	WorldArt.cyl(f, 0.3, 0.24, 0.16, Vector3(0, 4.25, -0.1), Color("2a2530"), 8)
	if not WorldArt.headless():
		var smoke := WorldArt._particles(Vector3(0, 4.4, -0.1), 16, 3.2, Vector3(0.12, 0.05, 0.12), Color(0.45, 0.45, 0.5, 0.4), 0.45, 0.0)
		smoke.process_material.initial_velocity_min = 0.8
		smoke.process_material.initial_velocity_max = 1.3
		smoke.process_material.spread = 14.0
		smoke.process_material.scale_max = 2.6
		f.add_child(smoke)
	# Coal heap and a poker by the mouth.
	for k in 5:
		var a := TAU * k / 5.0
		WorldArt.sphere(f, 0.17, Vector3(1.25 + cos(a) * 0.16, 0.12, 0.3 + sin(a) * 0.16), Color("26222a"), Vector3(1.0, 0.7, 1.0))
	WorldArt.cyl(f, 0.015, 0.015, 1.1, Vector3(-0.85, 0.55, 0.95), Color("3b3b44"), 5, Vector3(0.5, 0, 0.2))
	# Bellows at the furnace side: two boards, a leather wedge and a nozzle.
	var b := Node3D.new()
	b.position = Vector3(-1.55, 0.0, 0.1)
	b.rotation.y = PI / 2
	f.add_child(b)
	WorldArt.box(b, Vector3(0.14, 0.5, 0.14), Vector3(0.0, 0.25, 0.3), WorldArt.WOOD)
	WorldArt.box(b, Vector3(0.14, 0.5, 0.14), Vector3(0.0, 0.25, -0.3), WorldArt.WOOD)
	WorldArt.box(b, Vector3(0.95, 0.05, 0.55), Vector3(0, 0.55, 0), WorldArt.WOOD_LIGHT)
	var wedge := PrismMesh.new()
	wedge.size = Vector3(0.9, 0.3, 0.5)
	WorldArt.mesh_node(b, wedge, Vector3(0, 0.72, 0), WorldArt.mat(Color("7a4a2e"), 0.025), Vector3(0, 0, 0))
	WorldArt.box(b, Vector3(0.95, 0.05, 0.55), Vector3(0.1, 0.9, 0), WorldArt.WOOD_LIGHT, Vector3(0, 0, 0.22))
	WorldArt.cyl(b, 0.04, 0.06, 0.6, Vector3(0.65, 0.6, 0), Color("3b3b44"), 6, Vector3(0, 0, PI / 2))
	WorldArt.cyl(b, 0.03, 0.03, 0.7, Vector3(-0.55, 1.05, 0), WorldArt.WOOD, 6, Vector3(0, 0, PI / 2 + 0.4))
	# Behind the furnace: a tool rack (hammers, axes, pickaxe) and a weapon
	# rack of finished blades; stock, quench water and ore around the anvil.
	tool_rack(parent, forge_pos - dir * 1.7 + side * 2.0, rot)
	weapon_rack(parent, forge_pos - dir * 1.4 - side * 2.4, rot + 0.35)
	if has("survival", "barrel-open"):
		AssetLib.prop(parent, "survival", "barrel-open", anvil_pos - side * 1.5 - dir * 0.3, 0.0, SURVIVAL, "box")
	if has("hex", "decoration/props/bucket_water"):
		AssetLib.prop(parent, "hex", "decoration/props/bucket_water", anvil_pos - side * 1.0 + dir * 0.7, rot, HOUSE * 0.8, "none")
	if has("survival", "box-open"):
		AssetLib.prop(parent, "survival", "box-open", forge_pos + side * 1.9 - dir * 0.3, rot + 0.5, SURVIVAL * 0.8, "box")
	if has("survival", "resource-stone"):
		AssetLib.prop(parent, "survival", "resource-stone", forge_pos + side * 2.0 + dir * 1.1, rot + 1.1, SURVIVAL * 0.7, "none")
	return true


## Weapon rack: a slanted frame holding swords, a spear and a round shield
## (mini-dungeon kit; plain blades without it). Local +z faces the viewer.
static func weapon_rack(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var r := Node3D.new()
	r.name = "WeaponRack"
	r.position = pos
	r.rotation.y = rot_y
	parent.add_child(r)
	for sx in [-1, 1]:
		WorldArt.box(r, Vector3(0.12, 1.5, 0.12), Vector3(sx * 0.95, 0.75, -0.15), WorldArt.WOOD)
		WorldArt.box(r, Vector3(0.12, 0.12, 0.7), Vector3(sx * 0.95, 0.06, 0.05), WorldArt.WOOD)
	WorldArt.box(r, Vector3(2.0, 0.1, 0.12), Vector3(0, 1.3, -0.15), WorldArt.WOOD_LIGHT)
	WorldArt.box(r, Vector3(2.0, 0.14, 0.3), Vector3(0, 0.22, 0.2), WorldArt.WOOD_LIGHT)
	WorldArt.box_collider(r, Vector3(2.0, 1.5, 0.7), Vector3(0, 0.75, 0.05))
	var steel := Color("c9ced8")
	for k in 4:
		var x := -0.66 + k * 0.44
		if k == 2 and has("mini_dungeon", "weapon-spear"):
			var sp := AssetLib.prop(r, "mini_dungeon", "weapon-spear", Vector3(x, 0.3, 0.12), 0.0, 3.4, "none")
			if sp:
				sp.rotation.x = -0.2
		elif has("mini_dungeon", "weapon-sword"):
			var sw := AssetLib.prop(r, "mini_dungeon", "weapon-sword", Vector3(x, 0.55, 0.1), 0.0, 2.6, "none")
			if sw:
				sw.rotation.x = -0.22
		else:
			WorldArt.box(r, Vector3(0.08, 1.0, 0.03), Vector3(x, 0.8, 0.05), steel, Vector3(-0.2, 0, 0))
			WorldArt.box(r, Vector3(0.3, 0.05, 0.06), Vector3(x, 0.32, 0.12), Color("8a6420"), Vector3(-0.2, 0, 0))
	if has("mini_dungeon", "shield-round"):
		AssetLib.prop(r, "mini_dungeon", "shield-round", Vector3(0.0, 0.85, -0.05), 0.0, 2.4, "none")
	return r


## Wooden rack with survival-kit tools hanging from its rail. `rot_y` turns
## the rail; tools face local +z.
static func tool_rack(parent: Node3D, pos: Vector3, rot_y: float) -> Node3D:
	var r := Node3D.new()
	r.name = "ToolRack"
	r.position = pos
	r.rotation.y = rot_y
	parent.add_child(r)
	for sx in [-1, 1]:
		WorldArt.box(r, Vector3(0.14, 1.9, 0.14), Vector3(sx * 1.1, 0.95, 0), WorldArt.WOOD)
	WorldArt.box(r, Vector3(2.4, 0.12, 0.16), Vector3(0, 1.72, 0), WorldArt.WOOD_LIGHT)
	WorldArt.box(r, Vector3(2.4, 0.12, 0.16), Vector3(0, 0.9, 0), WorldArt.WOOD_LIGHT)
	WorldArt.box_collider(r, Vector3(2.4, 1.9, 0.3), Vector3(0, 0.95, 0))
	var tools := ["tool-hammer", "tool-axe", "tool-pickaxe", "tool-hammer-upgraded", "tool-axe-upgraded"]
	var x := -0.85
	for t in tools:
		if has("survival", t):
			AssetLib.prop(r, "survival", t, Vector3(x, 0.42, 0.12), 0.0, SURVIVAL * 0.85, "none")
		x += 0.43
	return r


## Crossroads signpost.
static func signpost(parent: Node3D, pos: Vector3, rot_y := 0.0) -> bool:
	if not has("survival", "signpost"):
		return false
	AssetLib.prop(parent, "survival", "signpost", pos, rot_y, SURVIVAL, "box")
	return true


## Hay bales (graveyard kit) scattered near a farm.
static func hay(parent: Node3D, spots: Array) -> bool:
	if not has("graveyard", "hay-bale"):
		return false
	var xs := []
	for i in spots.size():
		xs.append(WorldArt.xf(spots[i], 0.4 * i, Vector3.ONE * GRAVE))
	AssetLib.multi(parent, "graveyard", "hay-bale", xs)
	return true


## A vegetable patch: dirt rows with crops on them.
static func crops(parent: Node3D, origin: Vector3, rows: int, rot_y := 0.0) -> bool:
	if not has("nature", "crops_dirtDoubleRow") or not has("nature", "crop_pumpkin"):
		return false
	var s := 2.6
	var dirt := []
	var veg := [[], [], []]
	var kinds := ["crop_carrot", "crop_pumpkin", "crop_turnip"]
	var b := Basis.from_euler(Vector3(0, rot_y, 0))
	for r in rows:
		for k in 2:
			var local := Vector3(r * 1.1 * s, 0, k * s)
			dirt.append(WorldArt.xf(origin + b * local, rot_y, Vector3.ONE * s))
			for j in 2:
				var vl := local + Vector3((j - 0.5) * 0.5 * s, 0.02, 0)
				veg[r % 3].append(WorldArt.xf(origin + b * vl, rot_y + j * 1.3, Vector3.ONE * s * 0.9))
	AssetLib.multi(parent, "nature", "crops_dirtDoubleRow", dirt, true, false)
	for i in 3:
		if not veg[i].is_empty():
			AssetLib.multi(parent, "nature", kinds[i], veg[i], true, false)
	return true


# --- Camp (survival kit) ---------------------------------------------------------

static func tent(parent: Node3D, pos: Vector3, rot_y: float) -> bool:
	if not has("survival", "tent"):
		return false
	AssetLib.prop(parent, "survival", "tent", pos, rot_y, SURVIVAL * 1.15, "box")
	return true


static func campfire(parent: Node3D, pos: Vector3) -> bool:
	if not has("survival", "campfire-pit"):
		return false
	AssetLib.prop(parent, "survival", "campfire-pit", pos, 0.0, SURVIVAL, "none")
	cooking_pot(parent, pos)
	return true


## Iron stew pot hanging from a chain under a three-pole tripod over a
## fire at `pos`, steam rising. Visual only; the fire's flame is the caller's.
static func cooking_pot(parent: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var n := Node3D.new()
	n.name = "CookingPot"
	n.position = pos
	n.rotation.y = rot_y
	parent.add_child(n)
	var apex := Vector3(0, 2.05, 0)
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		var foot := Vector3(cos(a) * 1.15, 0, sin(a) * 1.15)
		var mid := (foot + apex) * 0.5
		var pole := CylinderMesh.new()
		pole.top_radius = 0.035
		pole.bottom_radius = 0.05
		pole.height = foot.distance_to(apex) + 0.3
		pole.radial_segments = 6
		var m := WorldArt.mesh_node(n, pole, mid, WorldArt.mat(WorldArt.WOOD))
		m.basis = Basis(Quaternion(Vector3.UP, (apex - foot).normalized()))
	WorldArt.cyl(n, 0.08, 0.08, 0.22, apex + Vector3(0, 0.02, 0), Color("4a3422"), 6, Vector3(0, 0, PI / 2))
	for k in 6:
		WorldArt.cyl(n, 0.018, 0.018, 0.1, Vector3(0, 1.92 - k * 0.1, 0), Color("3b3b44"), 5, Vector3(0, k * 0.8, 0.5 * (k % 2)))
	var iron := Color("34323b")
	WorldArt.cyl(n, 0.34, 0.26, 0.36, Vector3(0, 1.06, 0), iron, 12)
	WorldArt.cyl(n, 0.37, 0.37, 0.06, Vector3(0, 1.26, 0), Color("2a282f"), 12)
	WorldArt.cyl(n, 0.3, 0.3, 0.03, Vector3(0, 1.245, 0), Color("b8743a"), 12)
	var handle := TorusMesh.new()
	handle.inner_radius = 0.33
	handle.outer_radius = 0.36
	handle.rings = 24
	handle.ring_segments = 5
	WorldArt.mesh_node(n, handle, Vector3(0, 1.3, 0), WorldArt.mat(iron), Vector3(0, 0, PI / 2), Vector3(1, 1, 0.9))
	WorldArt.cyl(n, 0.012, 0.012, 0.55, Vector3(0.22, 1.42, 0.08), WorldArt.WOOD, 5, Vector3(0.3, 0, 0.6))
	for k in 3:
		WorldArt.box(n, Vector3(0.09, 0.09, 0.09), Vector3(sin(k * 2.1) * 0.12, 1.3, cos(k * 2.1) * 0.1), [Color("d9a441"), Color("c8603f"), Color("6fbf5a")][k], Vector3(0.3, k * 0.7, 0.4), 0.0)
	if not WorldArt.headless():
		var steam := WorldArt._particles(Vector3(0, 1.4, 0), 10, 1.8, Vector3(0.12, 0.02, 0.12), Color(0.95, 0.95, 1.0, 0.3), 0.25, 0.0)
		steam.process_material.initial_velocity_min = 0.3
		steam.process_material.initial_velocity_max = 0.6
		steam.process_material.spread = 10.0
		steam.process_material.scale_max = 2.0
		n.add_child(steam)
	return n


static func camp_gear(parent: Node3D, c: Vector3) -> bool:
	if not has("survival", "workbench"):
		return false
	AssetLib.prop(parent, "survival", "workbench", c + Vector3(-5.2, 0, 2.0), 1.4, SURVIVAL, "box")
	AssetLib.prop(parent, "survival", "chest", c + Vector3(4.6, 0, -3.2), 0.5, SURVIVAL, "box")
	AssetLib.prop(parent, "survival", "bedroll", c + Vector3(2.5, 0, 4.2), 0.3, SURVIVAL, "none")
	if has("survival", "resource-wood"):
		AssetLib.prop(parent, "survival", "resource-wood", c + Vector3(-3.6, 0, -3.8), 0.2, SURVIVAL, "box")
	if has("hex", "decoration/props/weaponrack"):
		AssetLib.prop(parent, "hex", "decoration/props/weaponrack", c + Vector3(-5.0, 0, -1.2), 1.57, HOUSE, "box")
	if has("hex", "decoration/props/flag_blue"):
		AssetLib.prop(parent, "hex", "decoration/props/flag_blue", c + Vector3(6, 0, 3), 0.0, HOUSE, "none")
	return true


# --- The Labyrinth exterior (graveyard + castle kits) -------------------------------

## Fenced burial ground and crooked pines around the tower foot; the gate
## side (toward +z) stays open.
static func labyrinth_grounds(parent: Node3D, tower: Vector3, rng: RandomNumberGenerator) -> bool:
	if not has("graveyard", "gravestone-round"):
		return false
	iron_fence_ring(parent, tower, 19.0, PI / 2, 0.55)
	var kinds := {"gravestone-round": [], "gravestone-cross": [], "gravestone-bevel": [], "cross": [], "gravestone-wide": []}
	var keys := kinds.keys()
	for i in 34:
		var a := rng.randf_range(0.0, TAU)
		if absf(wrapf(a - PI / 2, -PI, PI)) < 0.7:
			continue
		var r := rng.randf_range(17.0, 22.5)
		var p := tower + Vector3(cos(a), 0, sin(a)) * r
		kinds[keys[i % keys.size()]].append(WorldArt.xf(p, -a + PI / 2 + rng.randf_range(-0.3, 0.3), Vector3.ONE * GRAVE * 1.3))
	for k in keys:
		if not kinds[k].is_empty():
			AssetLib.multi(parent, "graveyard", k, kinds[k])
	# Crypts and obelisks as landmarks, pines for silhouette.
	for side in [-1, 1]:
		AssetLib.prop(parent, "graveyard", "crypt-small", tower + Vector3(side * 21.0, 0, -6.0), -side * 1.3, GRAVE * 1.4, "box")
		AssetLib.prop(parent, "graveyard", "pillar-obelisk", tower + Vector3(side * 8.5, 0, 19.5), 0.0, GRAVE * 1.3, "box")
		AssetLib.prop(parent, "graveyard", "lightpost-single", tower + Vector3(side * 4.5, 0, 22.0), 0.0, GRAVE, "box")
	if has("castle", "rocks-large"):
		for i in 5:
			var a := TAU * i / 5.0 + 0.9
			if absf(wrapf(a - PI / 2, -PI, PI)) < 0.8:
				continue
			AssetLib.prop(parent, "castle", "rocks-large", tower + Vector3(cos(a), 0, sin(a)) * 15.0, a, CASTLE * 0.8, "none")
	var pines := []
	for i in 14:
		var a := rng.randf_range(0.0, TAU)
		if absf(wrapf(a - PI / 2, -PI, PI)) < 0.6:
			continue
		var r := rng.randf_range(23.0, 30.0)
		pines.append(WorldArt.xf(tower + Vector3(cos(a), 0, sin(a)) * r, a, Vector3.ONE * NATURE * rng.randf_range(1.3, 1.9)))
	# Nature Kit pines (palette-remapped to the game's greens) rather than the
	# graveyard kit's teal ones.
	if has("nature", "tree_pineDefaultB"):
		AssetLib.multi(parent, "nature", "tree_pineDefaultB", pines)
	return true


# --- Labyrinth terraces (dungeon kit) ------------------------------------------------

const RUIN_TINT := Color("d8d2e8")   # Dungeon-kit stone pulled toward the tower's lavender.
const CRAG_TINT := Color("d2cae6")

## Dungeon pillars (with box collision), torches, banners, a stair, broken
## paving, clutter and standing torches by the pads. Returns false when the
## pack is missing so the caller keeps its primitive pillars.
static func terrace_dress(parent: Node3D, base: Vector3, idx: int) -> bool:
	if not has("dungeon", "pillar"):
		return false
	var banners := ["banner_patternA_blue", "banner_patternB_blue", "banner_patternC_blue", "banner_shield_blue"]
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		var p := base + Vector3(cos(a) * 7, 0, sin(a) * 7)
		var inward := -Vector3(cos(a), 0, sin(a))
		tinted_prop(parent, "dungeon", "pillar_decorated" if k % 2 == idx % 2 else "pillar", p, -a, DUNGEON, "box", RUIN_TINT)
		if has("dungeon", "torch_mounted"):
			AssetLib.prop(parent, "dungeon", "torch_mounted", p + Vector3(0, 2.0, 0) + inward * 0.62, atan2(inward.x, inward.z), DUNGEON, "none")
		var bn: String = banners[(k + idx) % banners.size()]
		if k % 2 == 1 and has("dungeon", bn):
			AssetLib.prop(parent, "dungeon", bn, p + Vector3(0, 0.7, 0) + inward * 0.2, atan2(inward.x, inward.z), DUNGEON * 1.1, "none")
	tinted_prop(parent, "dungeon", "crates_stacked", base + Vector3(-5.5, 0, 4.0 + idx), 0.4, DUNGEON, "box", Color.WHITE)
	AssetLib.prop(parent, "dungeon", "barrel_small_stack", base + Vector3(5.0, 0, 3.5 - idx), -0.7, DUNGEON, "box")
	tinted_prop(parent, "dungeon", "rubble_large", base + Vector3(2.0 + idx, 0, -6.0), 1.1 * idx, DUNGEON, "none", RUIN_TINT)
	tinted_prop(parent, "dungeon", "rubble_half", base + Vector3(-7.0, 0, -2.0), 0.3, DUNGEON, "none", RUIN_TINT)
	# A ruined stair that climbs to nowhere, and a broken wall stub.
	if has("dungeon", "stairs_narrow"):
		tinted_prop(parent, "dungeon", "stairs_narrow", base + Vector3(8.5 - idx * 17.0, 0, -5.5), PI / 2 if idx == 0 else -PI / 2, DUNGEON * 0.8, "none", RUIN_TINT)
	if has("dungeon", "wall_broken"):
		tinted_prop(parent, "dungeon", "wall_broken", base + Vector3(-9.0 + idx * 18.0, 0, 3.5), 1.2 - idx * 2.4, DUNGEON * 0.8, "box", RUIN_TINT)
	# Broken and weedy paving slabs scattered on the flags.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 + idx
	var tiles := {"floor_tile_small_broken_A": [], "floor_tile_small_broken_B": [], "floor_tile_small_weeds_A": [], "floor_tile_small_weeds_B": []}
	var keys := tiles.keys()
	for i in 18:
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.5, 11.5)
		var p := Vector3(cos(a) * r, 0.08, sin(a) * r)
		if absf(p.x) < 3.0 and absf(absf(p.z) - 9.0) < 3.0:
			continue
		if p.distance_to(Vector3(cos(a) * 7, 0, sin(a) * 7)) < 1.6:
			continue
		tiles[keys[i % keys.size()]].append(WorldArt.xf(base + p, rng.randf() * TAU, Vector3.ONE * DUNGEON))
	for k in keys:
		if has("dungeon", k) and not tiles[k].is_empty():
			tinted_multi(parent, "dungeon", k, tiles[k], RUIN_TINT)
	# Standing torches flanking each pad.
	if has("dungeon", "torch_lit"):
		var tx := []
		for z in [9.0, -9.0]:
			for x in [-2.4, 2.4]:
				tx.append(WorldArt.xf(base + Vector3(x, 0.395 * DUNGEON * 1.4, z), 0.0, Vector3.ONE * DUNGEON * 1.4))
		AssetLib.multi(parent, "dungeon", "torch_lit", tx)
	return true


## Balustrade pieces (dungeon barrier_column / barrier) standing in for the
## primitive parapet boxes at `angles` around center. seg is the box width;
## the piece is scaled to it. Returns false without the pack.
static func parapet(parent: Node3D, center: Vector3, radius: float, angles: Array, seg: float, height := 1.5, skip_cos := 2.0, skip_dir := Vector3.ZERO) -> bool:
	if not has("dungeon", "barrier_column") or not has("dungeon", "barrier"):
		return false
	var sx := seg / 4.0
	var sy := height / 1.4
	var cols := []
	var plain := []
	var i := 0
	for a in angles:
		var d := Vector3(cos(a), 0, sin(a))
		if skip_dir != Vector3.ZERO and d.dot(skip_dir) > skip_cos:
			continue
		var p: Vector3 = center + d * radius
		# barrier spans local x -2..2, z -0.25..0.25; rot turns local x along the tangent.
		var x := WorldArt.xf(p, -a - PI / 2, Vector3(sx, sy, sy))
		if i % 3 == 0:
			cols.append(x)
		else:
			plain.append(x)
		i += 1
	if not cols.is_empty():
		tinted_multi(parent, "dungeon", "barrier_column", cols, RUIN_TINT)
	if not plain.is_empty():
		tinted_multi(parent, "dungeon", "barrier", plain, RUIN_TINT)
	return true


## Balustrade pieces end to end from a to b (bridge rails). Returns false
## without the pack.
static func balustrade_line(parent: Node3D, a: Vector3, b: Vector3, height := 1.0) -> bool:
	if not has("dungeon", "barrier"):
		return false
	var len := a.distance_to(b)
	var count := maxi(1, int(round(len / 3.2)))
	var piece := len / count
	var dir := (b - a) / len
	var rot := -atan2(dir.z, dir.x)
	var xs := []
	for i in count:
		xs.append(WorldArt.xf(a + dir * (piece * (i + 0.5)), rot, Vector3(piece / 4.0, height / 1.1, 0.9)))
	tinted_multi(parent, "dungeon", "barrier", xs, RUIN_TINT)
	return true


## Terrace entrance where the bridge meets the rim: two dungeon pillars
## (box collision) with banners and torches facing in, framing `dir`.
static func entrance(parent: Node3D, base: Vector3, radius: float, dir: Vector3, rune_banner := "banner_patternB_blue") -> bool:
	var d := dir.normalized()
	var side := d.cross(Vector3.UP)
	if not has("dungeon", "pillar"):
		for sx in [-1, 1]:
			WorldArt.ornate_pillar(parent, base + d * (radius - 0.8) + side * sx * 3.2, 4.0)
		return false
	for sx in [-1, 1]:
		var p: Vector3 = base + d * (radius - 0.9) + side * sx * 3.2
		var rot := atan2(d.x, d.z)
		tinted_prop(parent, "dungeon", "pillar_decorated", p, rot, DUNGEON * 1.25, "box", RUIN_TINT)
		if has("dungeon", "torch_mounted"):
			AssetLib.prop(parent, "dungeon", "torch_mounted", p + Vector3(0, 2.6, 0) - side * sx * 0.78, atan2(-side.x * sx, -side.z * sx), DUNGEON, "none")
		if has("dungeon", rune_banner):
			AssetLib.prop(parent, "dungeon", rune_banner, p + Vector3(0, 1.2, 0) - d * 0.3, atan2(-d.x, -d.z), DUNGEON * 1.3, "none")
	return true


## Upside-down nature-kit crags hanging from a platform underside (local
## space of `parent`, centred on `at`). Returns false without the pack.
static func hanging_crags(parent: Node3D, at: Vector3, radius: float, rng: RandomNumberGenerator, count: int) -> bool:
	var kinds := ["stone_tallA", "stone_tallB", "stone_tallD", "stone_tallF", "stone_largeC", "stone_tallH"]
	var ok := true
	for k in kinds:
		if not has("nature", k):
			ok = false
	if not ok:
		return false
	var sets := {}
	for k in kinds:
		sets[k] = []
	for i in count:
		var a := rng.randf() * TAU
		var r := rng.randf_range(radius * 0.3, radius * 0.98)
		var s := NATURE * rng.randf_range(0.6, 1.4)
		var depth := 1.0 + (radius - r) * 0.42
		var pos := at + Vector3(cos(a) * r, -depth, sin(a) * r)
		sets[kinds[i % kinds.size()]].append(WorldArt.xf(pos, rng.randf() * TAU, Vector3(s, s * rng.randf_range(1.2, 1.8), s), Vector3(PI + rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.25, 0.25))))
	for k in kinds:
		if not sets[k].is_empty():
			tinted_multi(parent, "nature", k, sets[k], CRAG_TINT)
	return true


## Floating rubble chunks for WorldArt.floating_debris (nature rocks). False
## without the pack.
static func debris_cloud(parent: Node3D, xforms: Array) -> bool:
	var kinds := ["stone_tallC", "stone_largeA", "stone_tallE", "stone_tallB"]
	for k in kinds:
		if not has("nature", k):
			return false
	var sets := {}
	for k in kinds:
		sets[k] = []
	for i in xforms.size():
		var x: Transform3D = xforms[i]
		x.basis = x.basis.scaled(Vector3.ONE * NATURE * 0.8)
		sets[kinds[i % kinds.size()]].append(x)
	for k in kinds:
		if not sets[k].is_empty():
			tinted_multi(parent, "nature", k, sets[k], CRAG_TINT)
	return true


## Carved gate wall for WorldArt.sealed_gate: a scaled dungeon arched wall
## (local +z faces the arena), two shield banners and torches. False
## without the pack.
static func gate_frame(parent: Node3D, at: Vector3, _rune: Color) -> bool:
	if not has("dungeon", "wall_arched"):
		return false
	var s := 2.3
	var tint := Color("f2ecff")
	# wall spans local x -2..2, z -0.5..0.5, 4 high.
	tinted_prop(parent, "dungeon", "wall_arched", at + Vector3(0, 0, -0.6), 0.0, s, "none", tint)
	for sx in [-1, 1]:
		# wall_half spans local x 0..2; the -x copy is turned around.
		tinted_prop(parent, "dungeon", "wall_half", at + Vector3(sx * 4.6, 0, -0.6), 0.0 if sx > 0 else PI, s, "none", tint)
		if has("dungeon", "banner_shield_blue"):
			AssetLib.prop(parent, "dungeon", "banner_shield_blue", at + Vector3(sx * 3.5, 3.4, -0.1), 0.0, DUNGEON * 1.5, "none")
		if has("dungeon", "torch_mounted"):
			AssetLib.prop(parent, "dungeon", "torch_mounted", at + Vector3(sx * 3.5, 1.9, 0.52), 0.0, DUNGEON * 1.2, "none")
	return true


## Dungeon-kit pieces around the summit: twelve ruined columns on the
## parapet (box collision, intact and snapped), rubble, broken paving and a
## stair up to the gate side. `gate_dir` and `entry_dir` stay clear.
static func summit_props(parent: Node3D, center: Vector3, radius: float, rune: Color, gate_dir: Vector3, entry_dir: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 53
	for k in 12:
		var a := TAU * k / 12.0 + PI / 12.0
		var d := Vector3(cos(a), 0, sin(a))
		if d.dot(gate_dir) > 0.93 or d.dot(entry_dir) > 0.93:
			continue
		var p := center + d * (radius - 1.0)
		var broken := k % 3 != 0
		var h := 6.5 if not broken else rng.randf_range(3.0, 4.5)
		WorldArt.broken_column(parent, p, h, rune, broken, 0.8)
		WorldArt.box_collider(parent, Vector3(1.4, h, 1.4), p + Vector3(0, h / 2, 0))
	if not has("dungeon", "rubble_half"):
		return
	for k in 5:
		var a := TAU * k / 5.0 + 0.7
		var d := Vector3(cos(a), 0, sin(a))
		if d.dot(gate_dir) > 0.8 or d.dot(entry_dir) > 0.8:
			continue
		tinted_prop(parent, "dungeon", "rubble_half" if k % 2 == 0 else "rubble_large", center + d * (radius - 3.2), a + rng.randf_range(-0.5, 0.5), DUNGEON * 0.9, "none", RUIN_TINT)
	var tiles := {"floor_tile_small_broken_A": [], "floor_tile_small_broken_B": [], "floor_tile_small_weeds_B": []}
	var keys := tiles.keys()
	for i in 22:
		var a := rng.randf() * TAU
		var r := rng.randf_range(radius * 0.62, radius - 2.2)
		var d := Vector3(cos(a), 0, sin(a))
		if d.dot(entry_dir) > 0.9:
			continue
		tiles[keys[i % keys.size()]].append(WorldArt.xf(center + d * r + Vector3(0, 0.08, 0), rng.randf() * TAU, Vector3.ONE * DUNGEON))
	for k in keys:
		if has("dungeon", k) and not tiles[k].is_empty():
			tinted_multi(parent, "dungeon", k, tiles[k], RUIN_TINT)


## Torches and banners on the Labyrinth gate at the tower foot (dungeon kit).
static func tower_gate_dress(parent: Node3D, tower: Vector3) -> bool:
	if not has("dungeon", "torch_lit"):
		return false
	var tx := []
	for sx in [-1, 1]:
		tx.append(WorldArt.xf(tower + Vector3(sx * 3.6, 0.3 + 0.395 * DUNGEON * 1.6, 14.2), 0.0, Vector3.ONE * DUNGEON * 1.6))
		if has("dungeon", "torch_mounted"):
			AssetLib.prop(parent, "dungeon", "torch_mounted", tower + Vector3(sx * 4.35, 5.2, 12.4), -sx * PI / 2, DUNGEON * 1.2, "none")
		if has("dungeon", "banner_patternC_blue"):
			AssetLib.prop(parent, "dungeon", "banner_patternC_blue", tower + Vector3(sx * 5.2, 5.4, 12.7), 0.0, DUNGEON * 1.6, "none")
	AssetLib.multi(parent, "dungeon", "torch_lit", tx)
	return true


# --- Vegetation batches ---------------------------------------------------------------

## Bushes, mushrooms, stumps and logs scattered on meadow ground. `ok` is a
## Callable(Vector2) -> bool that says whether a spot is free.
static func undergrowth(parent: Node3D, rng: RandomNumberGenerator, radius: float, ok: Callable) -> bool:
	if not has("nature", "plant_bush"):
		return false
	var sets := {"plant_bush": [90, 0.9, 1.4], "plant_bushDetailed": [50, 0.8, 1.3], "mushroom_redGroup": [36, 0.7, 1.1],
		"mushroom_tanGroup": [30, 0.7, 1.1], "stump_round": [16, 0.8, 1.2], "log": [14, 0.8, 1.2], "flower_yellowA": [120, 0.8, 1.2], "flower_redA": [90, 0.8, 1.2]}
	for name in sets:
		var cfg: Array = sets[name]
		var xs := []
		var tries := 0
		while xs.size() < cfg[0] and tries < cfg[0] * 6:
			tries += 1
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * (radius - 6)
			var p := Vector2(cos(a), sin(a)) * r
			if not ok.call(p):
				continue
			var s: float = NATURE * rng.randf_range(cfg[1], cfg[2])
			xs.append(WorldArt.xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, Vector3.ONE * s))
		if not xs.is_empty():
			AssetLib.multi(parent, "nature", name, xs, true, name.begins_with("plant") or name.begins_with("stump") or name == "log")
	return true


# --- Tinted pack pieces --------------------------------------------------------------

static var _tint_meshes := {}

## Copy of a toon-converted pack material with its albedo multiplied by tint
## (Kenney kits use one "colormap" atlas, so this recolours the whole piece).
static func _tinted_material(src: Material, tint: Color) -> Material:
	return AssetLib.tinted_material(src, tint)


## AssetLib.multi with every surface material re-tinted. Cached per piece/tint.
static func tinted_multi(parent: Node, pack: String, name: String, xforms: Array, tint: Color, shadows := true) -> MultiMeshInstance3D:
	var mmi := AssetLib.multi(parent, pack, name, xforms, true, shadows)
	if mmi == null or tint == Color.WHITE:
		return mmi
	var key := "%s/%s|%s" % [pack, name, tint.to_html()]
	if not _tint_meshes.has(key):
		var m: Mesh = mmi.multimesh.mesh.duplicate()
		for s in m.get_surface_count():
			m.surface_set_material(s, _tinted_material(m.surface_get_material(s), tint))
		_tint_meshes[key] = m
	mmi.multimesh.mesh = _tint_meshes[key]
	return mmi


## AssetLib.prop with its materials re-tinted.
## AssetLib.prop with its materials re-tinted (batched like any other prop).
static func tinted_prop(parent: Node, pack: String, name: String, pos: Vector3, rot_y: float, scl: float, collide: String, tint: Color) -> Node3D:
	return AssetLib.prop(parent, pack, name, pos, rot_y, scl, collide, true, tint)


# --- Town wall (castle kit) ------------------------------------------------------------

static func has_castle_walls() -> bool:
	return has("castle", "wall") and has("castle", "tower-square-base") and has("castle", "tower-square-top-roof")


## Castle-kit curtain wall: one MultiMesh of `wall` pieces at the given
## angles around center, square gate towers (base + windowed mid + roof) at
## the gate angles, and banners on their outer faces. Colliders come from
## WorldArt.town_wall.
static func castle_wall(parent: Node3D, center: Vector3, radius: float, angles: Array, gate_angles: Array, seg_len: float) -> bool:
	if not has_castle_walls():
		return false
	var step := seg_len / radius
	var xs := []
	for a in angles:
		var p: Vector3 = center + Vector3(cos(a), 0, sin(a)) * radius
		# wall spans local x -0.5..0.5 (across) and z -0.5..0.5 (along);
		# rot -a turns local +z into the tangent. Length covers the outer chord.
		xs.append(WorldArt.xf(p, -a, Vector3(3.0, 3.8, (radius + 1.5) * step * 1.02)))
	var wall := tinted_multi(parent, "castle", "wall", xs, Color("f1e6d4"))
	# Grey dressed-stone courses running around the ring (the stretched kit
	# piece is flat-shaded, so it read as cardboard).
	var stone := WorldArt.stone_mat(Color("bdb6aa"), Color("9d978d"), "castle_brick_07", 0.3, {
		"band_period": 0.62, "brick_length": 1.5, "band_width": 0.07, "band_dark": 0.7,
		"polar": 1.0, "center": Vector2(center.x, center.z), "polar_radius": radius})
	if wall:
		wall.material_override = stone
	var base := []
	var mid := []
	var top := []
	var flags := []
	var s := CASTLE
	for a in gate_angles:
		var p: Vector3 = center + Vector3(cos(a), 0, sin(a)) * radius
		var rot: float = -a
		base.append(WorldArt.xf(p, rot, Vector3.ONE * s))
		mid.append(WorldArt.xf(p + Vector3(0, 1.01 * s, 0), rot, Vector3.ONE * s))
		top.append(WorldArt.xf(p + Vector3(0, 2.02 * s, 0), rot, Vector3.ONE * s))
		var out := Vector3(cos(a), 0, sin(a))
		flags.append(WorldArt.xf(p + out * (0.5 * s + 0.05) + Vector3(0, 4.3, 0), -a, Vector3.ONE * 2.4))
	var gate_stone := WorldArt.stone_mat(Color("c4bdb1"), Color("a29b90"), "castle_brick_07", 0.3, {
		"band_period": 0.55, "brick_length": 1.2, "band_width": 0.07, "band_dark": 0.7})
	for t in [tinted_multi(parent, "castle", "tower-square-base", base, Color("f1e6d4")),
			tinted_multi(parent, "castle", "tower-square-mid-windows" if has("castle", "tower-square-mid-windows") else "tower-square-mid", mid, Color("f1e6d4"))]:
		if t:
			t.material_override = gate_stone
	tinted_multi(parent, "castle", "tower-square-top-roof", top, Color("f1e6d4"))
	if has("castle", "flag-banner-long"):
		tinted_multi(parent, "castle", "flag-banner-long", flags, Color("ff8fa3"), false)
	return true


# --- Labyrinth tower base (castle kit) ----------------------------------------------------

## Four square turrets (base, windowed mid, plain mid, roof) around the tower
## foot, tinted to the shaft's lavender stone, with pennants. Box collision.
static func tower_base(parent: Node3D, tower: Vector3) -> bool:
	if not has_castle_walls() or not has("castle", "tower-square-mid"):
		return false
	var tint := Color("8a93c9")
	var s := CASTLE
	var base := []
	var mid_w := []
	var mid := []
	var top := []
	var flags := []
	for k in 4:
		var a := deg_to_rad(40.0 + 90.0 * k) + PI / 2
		var p := tower + Vector3(cos(a), 0, sin(a)) * 15.5
		var rot := -a
		base.append(WorldArt.xf(p, rot, Vector3.ONE * s))
		mid_w.append(WorldArt.xf(p + Vector3(0, 1.01 * s, 0), rot, Vector3.ONE * s))
		mid.append(WorldArt.xf(p + Vector3(0, 2.02 * s, 0), rot, Vector3.ONE * s))
		top.append(WorldArt.xf(p + Vector3(0, 3.03 * s, 0), rot, Vector3.ONE * s))
		flags.append(WorldArt.xf(p + Vector3(0, 4.0 * s, 0), rot, Vector3.ONE * 3.0))
		WorldArt.box_collider(parent, Vector3(s + 0.2, 4.1 * s, s + 0.2), p + Vector3(0, 2.05 * s, 0), Vector3(0, rot, 0))
	tinted_multi(parent, "castle", "tower-square-base", base, tint)
	tinted_multi(parent, "castle", "tower-square-mid-windows" if has("castle", "tower-square-mid-windows") else "tower-square-mid", mid_w, tint)
	tinted_multi(parent, "castle", "tower-square-mid", mid, tint)
	tinted_multi(parent, "castle", "tower-square-top-roof", top, Color("8c84b8"))
	if has("castle", "flag-pennant"):
		tinted_multi(parent, "castle", "flag-pennant", flags, Color("c08cff"), false)
	return true


# --- Plaza portal pillars -------------------------------------------------------------

## Two ornate columns flanking the plaza portal at center +- half_gap on x:
## graveyard-kit carved pillars (procedural fluted ones without the pack),
## a plinth, two glowing rune collars, a carved cap and a crystal finial.
## Each keeps the 1.1 x height x 1.1 collision box of the old plain pillar.
static func portal_pillars(parent: Node3D, center: Vector3, half_gap := 3.0, height := 6.5) -> void:
	var glow := Color("4fc3ff")
	for sx in [-1, 1]:
		var p := center + Vector3(sx * half_gap, 0, 0)
		var body := WorldArt.box_collider(parent, Vector3(1.1, height, 1.1), p + Vector3(0, height / 2, 0))
		body.name = "PortalPillar%s" % ("L" if sx < 0 else "R")
		if has("graveyard", "column-large"):
			# Grey carved column; squeezed a little so it stays slimmer than the ring.
			var a := AssetLib.aabb("graveyard", "column-large")
			# Live (unbatched) so the marble override below reaches its meshes.
			var col := AssetLib.prop(parent, "graveyard", "column-large", p + Vector3(0, 0.5, 0), PI / 2 * sx, 1.0, "none", true, Color.WHITE, false)
			var sy := (height - 0.5) / maxf(a.size.y, 0.1)
			col.scale = Vector3(sy * 0.56, sy, sy * 0.56)
			# Pale marble with fine courses: the kit's atlas gave it brown bands.
			var marble := WorldArt.stone_mat(Color("e4e6ee"), Color("c3c7d4"), "castle_brick_07", 0.5, {
				"band_period": 0.9, "brick_length": 0.9, "band_width": 0.04, "band_dark": 0.82, "detail_strength": 0.3})
			for mi in col.find_children("*", "GeometryInstance3D", true, false):
				(mi as GeometryInstance3D).material_override = marble
			if col is GeometryInstance3D:
				(col as GeometryInstance3D).material_override = marble
		else:
			WorldArt.ornate_pillar(parent, p + Vector3(0, 0.5, 0), height - 0.5)
		WorldArt.box(parent, Vector3(2.0, 0.4, 2.0), p + Vector3(0, 0.2, 0), WorldArt.STONE_DARK)
		WorldArt.box(parent, Vector3(1.6, 0.25, 1.6), p + Vector3(0, 0.52, 0), WorldArt.STONE)
		for y in [height * 0.36, height * 0.7]:
			# Thin floating rune halos (stretching the torus tall showed its
			# dark inner wall as striped bands on the column).
			WorldArt.rune_ring(parent, p + Vector3(0, y, 0), 1.0, glow, 0.08)
		WorldArt.box(parent, Vector3(1.7, 0.4, 1.7), p + Vector3(0, height + 0.15, 0), WorldArt.STONE_DARK)
		var crystal := CylinderMesh.new()
		crystal.top_radius = 0.0
		crystal.bottom_radius = 0.42
		crystal.height = 1.3
		crystal.radial_segments = 4
		var cm := WorldArt.mat(Color("bfe9ff"), 0.0, glow, 2.5)
		WorldArt.mesh_node(parent, crystal, p + Vector3(0, height + 1.0, 0), cm)
		WorldArt.mesh_node(parent, crystal, p + Vector3(0, height + 0.35, 0), cm, Vector3(PI, 0, 0), Vector3(0.7, 0.35, 0.7))


# --- Pond shore ----------------------------------------------------------------------

## Boulders around a pond (nature kit; procedural rocks without it).
static func shore_rocks(parent: Node3D, center: Vector3, radius: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var kinds := {"rock_largeA": [], "rock_largeB": [], "rock_smallA": []}
	var fallback := []
	for i in 22:
		var a := rng.randf_range(0.0, TAU)
		if absf(wrapf(a - 0.3, -PI, PI)) < 0.45:
			continue  # Leave the stream outlet open.
		var p := center + Vector3(cos(a), 0, sin(a)) * (radius + rng.randf_range(-0.3, 1.2))
		var s := rng.randf_range(0.7, 1.3)
		var kind: String = kinds.keys()[i % 3]
		if has("nature", kind):
			kinds[kind].append(WorldArt.xf(p, rng.randf() * TAU, Vector3.ONE * NATURE * s))
		else:
			fallback.append(WorldArt.xf(p + Vector3(0, 0.1, 0), rng.randf() * TAU, Vector3(s * 1.4, s * 0.8, s * 1.1)))
	for k in kinds:
		if not kinds[k].is_empty():
			AssetLib.multi(parent, "nature", k, kinds[k])
	if not fallback.is_empty():
		var mm := WorldArt.multimesh(parent, WorldArt.rock_mesh(), fallback, [], "ShoreRocks")
		mm.material_override = WorldArt.mat(Color("8d8578"), 0.03)


# --- Hall of Iron -------------------------------------------------------------

## The black-iron hall on the plaza's north side (after the Black Iron Palace
## of the Town of Beginnings): two dark stone wings with gabled roofs, iron
## buttresses and tall lit window slits, joined by a pointed iron arch over
## the north road (clear width 2 * `gap`). `center` is the middle of the arch
## at ground level; the hall faces +Z (the plaza). Original procedural art.
static func iron_hall(parent: Node3D, center: Vector3, gap := 5.3, wing_w := 4.2, depth := 7.0, height := 9.0) -> void:
	var wall := WorldArt.stone_mat(Color("3a3c47"), Color("2c2e38"), "castle_brick_07", 0.24, {
		"band_period": 1.2, "band_width": 0.07, "brick_length": 2.0})
	var iron := WorldArt.mat(Color("23252e"), 0.03)
	var trim := WorldArt.stone_mat(Color("51535f"), Color("434551"), "rock_wall_10", 0.3, {"detail_strength": 0.4})
	var slit := WorldArt.rune_mat(Color("6fb8ff"), 0.9)
	var rose_glass := WorldArt.rune_mat(Color("1d3a66"), 0.5)
	for sx in [-1.0, 1.0]:
		var cx: float = sx * (gap + wing_w * 0.5)
		var c := center + Vector3(cx, 0, 0)
		# Wing body on a plinth course.
		var body := BoxMesh.new()
		body.size = Vector3(wing_w, height, depth)
		WorldArt.mesh_node(parent, body, c + Vector3(0, height * 0.5, 0), wall)
		var plinth := BoxMesh.new()
		plinth.size = Vector3(wing_w + 0.5, 0.7, depth + 0.5)
		WorldArt.mesh_node(parent, plinth, c + Vector3(0, 0.35, 0), trim)
		var cornice := BoxMesh.new()
		cornice.size = Vector3(wing_w + 0.4, 0.35, depth + 0.4)
		WorldArt.mesh_node(parent, cornice, c + Vector3(0, height + 0.17, 0), trim)
		WorldArt.box_collider(parent, Vector3(wing_w + 0.5, height, depth + 0.5), c + Vector3(0, height * 0.5, 0))
		# Steep gable roof running front to back, with an iron ridge.
		var roof := PrismMesh.new()
		roof.size = Vector3(wing_w + 0.6, 4.2, depth + 0.6)
		WorldArt.mesh_node(parent, roof, c + Vector3(0, height + 0.35 + 2.1, 0), iron)
		# Buttresses at the front corners, stepping in toward the top.
		for bx in [-0.5, 0.5]:
			var bp := c + Vector3(bx * wing_w, 0, depth * 0.5)
			var b1 := BoxMesh.new()
			b1.size = Vector3(0.8, height * 0.62, 1.0)
			WorldArt.mesh_node(parent, b1, bp + Vector3(0, height * 0.31, 0.3), trim)
			var b2 := BoxMesh.new()
			b2.size = Vector3(0.6, height * 0.5, 0.6)
			WorldArt.mesh_node(parent, b2, bp + Vector3(0, height * 0.87, 0.15), trim)
			var fin := CylinderMesh.new()
			fin.top_radius = 0.0
			fin.bottom_radius = 0.34
			fin.height = 2.2
			fin.radial_segments = 4
			fin.rings = 1
			WorldArt.mesh_node(parent, fin, bp + Vector3(0, height * 1.12 + 1.1, 0.15), iron, Vector3(0, PI / 4, 0))
		# Two tall window slits on the front face and a round rose window.
		for wx in [-0.24, 0.24]:
			var w := BoxMesh.new()
			w.size = Vector3(0.42, 3.4, 0.08)
			WorldArt.mesh_node(parent, w, c + Vector3(wx * wing_w, 3.6, depth * 0.5 + 0.02), slit)
			var hood := PrismMesh.new()
			hood.size = Vector3(0.7, 0.45, 0.18)
			WorldArt.mesh_node(parent, hood, c + Vector3(wx * wing_w, 5.55, depth * 0.5 + 0.06), trim)
		var rose := CylinderMesh.new()
		rose.top_radius = 0.55
		rose.bottom_radius = 0.55
		rose.height = 0.08
		rose.radial_segments = 16
		rose.rings = 1
		WorldArt.mesh_node(parent, rose, c + Vector3(0, 7.2, depth * 0.5 + 0.02), rose_glass, Vector3(PI / 2, 0, 0))
		WorldArt.rune_ring(parent, c + Vector3(0, 7.2, depth * 0.5 + 0.07), 0.75, Color("6fb8ff"), 0.08).rotation.x = PI / 2
		# Side slits along the outer flank.
		for k in 3:
			var sw := BoxMesh.new()
			sw.size = Vector3(0.08, 3.0, 0.38)
			WorldArt.mesh_node(parent, sw, c + Vector3(sx * (wing_w * 0.5 + 0.02), 3.6, depth * (0.3 - 0.3 * k)), slit)
	# The arch: a heavy lintel across the road with a pointed gable and the
	# hall's emblem, carried on iron piers set against the wings.
	var span := gap * 2.0
	var lintel := BoxMesh.new()
	lintel.size = Vector3(span + 0.4, 1.2, 1.6)
	var ly := height - 0.6
	WorldArt.mesh_node(parent, lintel, center + Vector3(0, ly, depth * 0.5 - 0.8), wall)
	var band := BoxMesh.new()
	band.size = Vector3(span + 0.6, 0.3, 1.8)
	WorldArt.mesh_node(parent, band, center + Vector3(0, ly - 0.75, depth * 0.5 - 0.8), trim)
	var gable := PrismMesh.new()
	gable.size = Vector3(span * 0.62, 2.6, 1.4)
	WorldArt.mesh_node(parent, gable, center + Vector3(0, height + 1.3, depth * 0.5 - 0.8), wall)
	var gcap := PrismMesh.new()
	gcap.size = Vector3(span * 0.66, 2.75, 1.0)
	WorldArt.mesh_node(parent, gcap, center + Vector3(0, height + 1.42, depth * 0.5 - 1.05), iron)
	WorldArt.rune_ring(parent, center + Vector3(0, height + 0.9, depth * 0.5 - 0.02), 0.8, Color("6fb8ff"), 0.1).rotation.x = PI / 2
	for sx in [-1.0, 1.0]:
		var pier := BoxMesh.new()
		pier.size = Vector3(0.5, ly - 0.9, 0.8)
		WorldArt.mesh_node(parent, pier, center + Vector3(sx * (gap - 0.05), (ly - 0.9) * 0.5, depth * 0.5 - 0.4), iron)


## The Snaptrap Grove (world.GROVE): a ring of tall ferns, bushes and red
## toadstools round each vine's clearing (the clearing itself stays open so
## the plant reads and can be fought), fallen logs and stumps between them,
## and a mossy standing stone at the heart. Deterministic per seed.
static func grove_dress(parent: Node3D, center: Vector3, spots: Array, seed := 4817) -> void:
	if not has("nature", "plant_bush"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sets := {}
	for k in ["plant_flatTall", "plant_bushLarge", "plant_bushDetailed", "mushroom_redTall", "mushroom_redGroup", "grass_leafsLarge", "mushroom_tanGroup"]:
		sets[k] = []
	var near_spot := func(p: Vector3, r: float) -> bool:
		for s in spots:
			if Vector2(p.x - s.x, p.z - s.z).length() < r:
				return true
		return false
	for s in spots:
		var base := rng.randf() * TAU
		for i in 7:
			var a := base + TAU * i / 7.0 + rng.randf_range(-0.2, 0.2)
			var r := rng.randf_range(2.7, 3.6)
			var p: Vector3 = center + s + Vector3(cos(a) * r, 0, sin(a) * r)
			if near_spot.call(p - center, 2.5):
				continue
			var kind: String = ["plant_flatTall", "plant_bushLarge", "plant_flatTall", "grass_leafsLarge", "plant_bushDetailed", "mushroom_redTall", "grass_leafsLarge"][i]
			sets[kind].append(WorldArt.xf(p, rng.randf() * TAU, Vector3.ONE * NATURE * rng.randf_range(0.9, 1.4)))
	# Loose floor cover across the whole grove, never inside a clearing.
	for i in 70:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 14.0
		var off := Vector3(cos(a) * r, 0, sin(a) * r)
		if near_spot.call(off, 2.4):
			continue
		var kind: String = ["grass_leafsLarge", "mushroom_tanGroup", "mushroom_redGroup", "plant_bushDetailed"][i % 4]
		sets[kind].append(WorldArt.xf(center + off, rng.randf() * TAU, Vector3.ONE * NATURE * rng.randf_range(0.7, 1.1)))
	for k in sets:
		if not sets[k].is_empty():
			AssetLib.multi(parent, "nature", k, sets[k], true, k.begins_with("plant"))
	# Close-set dark oaks and pines round and between the clearings, so the
	# grove reads as woods (trunks are solid).
	var trees := {}
	var placed: Array = []
	var pool := ["tree_oak_dark", "tree_default_dark", "tree_detailed_dark", "tree_pineTallA_detailed", "tree_pineRoundC"]
	for t in 220:
		if placed.size() >= 26:
			break
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * rng.randf_range(4.0, 17.0)
		if near_spot.call(off, 3.9):
			continue
		var crowded := false
		for q in placed:
			if q.distance_to(off) < 3.4:
				crowded = true
				break
		if crowded:
			continue
		placed.append(off)
		var kind: String = pool[rng.randi() % pool.size()]
		if not has("nature", kind):
			kind = "tree_oak"
		if not trees.has(kind):
			trees[kind] = []
		var ts := NATURE * rng.randf_range(1.2, 1.7)
		trees[kind].append(WorldArt.xf(center + off, rng.randf() * TAU, Vector3(ts, ts * rng.randf_range(1.0, 1.25), ts)))
		var cs := CylinderShape3D.new()
		cs.radius = 0.35
		cs.height = 3.0
		WorldArt.collider(parent, cs, center + off + Vector3(0, 1.5, 0))
	for k in trees:
		AssetLib.multi(parent, "nature", k, trees[k])
	# Fallen logs and stumps between the clearings (solid).
	for i in 5:
		for t in 8:
			var a := rng.randf() * TAU
			var off := Vector3(cos(a), 0, sin(a)) * rng.randf_range(4.0, 12.0)
			if near_spot.call(off, 3.3):
				continue
			var piece := "log_large" if i < 2 else ("stump_oldTall" if i == 2 else "stump_old")
			if has("nature", piece):
				tinted_prop(parent, "nature", piece, center + off, rng.randf() * TAU, NATURE * rng.randf_range(0.9, 1.2), "box", Color("6e5440"))
			break
	# A leaning standing stone, moss-green, at the grove's heart.
	var heart := Vector3(-1.5, 0, -2.5)
	if not near_spot.call(heart, 2.6):
		prop(parent, "nature", "rock_tallC", center + heart, 0.7, NATURE * 0.9)


## Market stall keeper (hook from life/stalls.gd): a townsfolk VRM figure
## behind the counter, in one of four looks by stall index. Built the first
## time the keeper is shown (stall rented and stocked), so idle stalls cost
## nothing. False when headless or without the VRM bodies (the stall then
## uses its primitive stand-in).
const KEEPER_LOOKS := [
	{"body": "seed", "outfit_color": "7a4e2e", "skin_color": "e3bc9a", "hair_color": "3a2a20"},
	{"body": "alicia", "outfit_color": "4f6a3a", "hair_color": "c98a4b"},
	{"body": "alicia", "outfit_color": "8a3a3a", "hair_color": "2e2a2a", "skin_color": "d9b08a"},
	{"body": "seed", "outfit_color": "3a4a6a", "hair_color": "d9d9dd"},
]

static func stall_keeper(parent: Node3D, pos: Vector3, rot: float, index: int) -> bool:
	if WorldArt.headless() or Net.dedicated or not VRMCharacter.BODIES.has("alicia"):
		return false
	var look: Dictionary = KEEPER_LOOKS[index % KEEPER_LOOKS.size()].duplicate()
	var build := func():
		if not parent.visible or parent.get_child_count() > 0:
			return
		var v := VRMCharacter.new()
		v.name = "Keeper"
		# Behind the counter, a step off the awning's centre pole.
		v.position = pos + Vector3(sin(rot), 0, cos(rot)) * 0.6 + Vector3(cos(rot), 0, -sin(rot)) * 0.75
		v.rotation.y = rot
		parent.add_child(v)
		v.apply(look)
		if v.instance == null:
			v.queue_free()
			return
		for mi in v.instance.find_children("robo_arm", "MeshInstance3D", true, false):
			mi.visible = false
		var disc := CylinderMesh.new()
		disc.top_radius = 0.42
		disc.bottom_radius = 0.42
		disc.height = 0.02
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.05, 0.05, 0.1, 0.35)
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc.material = dm
		var sh := MeshInstance3D.new()
		sh.mesh = disc
		sh.position = v.position + Vector3(0, 0.02, 0)
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(sh)
	parent.visibility_changed.connect(build)
	return true


## The Guardian's throne at the back of the summit arena (the Floor 1 boss
## waits on a throne at the far end of its hall and leaps down to fight).
## A two-step dais, a high pointed back with a rune disc and two great
## bone horns, armrests, and a red pelt over the seat. Faces +Z (toward
## the arena entry). Solid.
static func boss_throne(parent: Node3D, pos: Vector3, rune: Color) -> void:
	var stone := WorldArt.stone_mat(Color("4a4658"), Color("3a3748"), "castle_brick_07", 0.3, {"detail_strength": 0.45})
	var dark := WorldArt.stone_mat(Color("2e2b39"), Color("252230"), "rock_wall_10", 0.3, {"detail_strength": 0.4})
	var bone := WorldArt.mat(Color("e6dcc4"), 0.03)
	var pelt := WorldArt.mat(Color("7a2a2a"), 0.03)
	var gold := WorldArt.mat(Color("c9a24a"), 0.03, Color("c9a24a"), 0.15)
	var bx := func(size: Vector3, at: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
		var b := BoxMesh.new()
		b.size = size
		return WorldArt.mesh_node(parent, b, pos + at, m, rot)
	# Dais: two steps.
	bx.call(Vector3(5.0, 0.35, 4.0), Vector3(0, 0.175, 0), stone)
	bx.call(Vector3(3.8, 0.35, 3.0), Vector3(0, 0.525, -0.3), stone)
	bx.call(Vector3(3.9, 0.06, 3.1), Vector3(0, 0.73, -0.3), gold)  # gilt edge
	bx.call(Vector3(3.7, 0.06, 2.9), Vector3(0, 0.75, -0.3), dark)
	# Seat and back.
	bx.call(Vector3(2.0, 0.9, 1.6), Vector3(0, 1.2, -0.6), dark)
	bx.call(Vector3(2.4, 3.6, 0.5), Vector3(0, 2.6, -1.35), stone)
	var peak := PrismMesh.new()
	peak.size = Vector3(2.4, 1.2, 0.5)
	WorldArt.mesh_node(parent, peak, pos + Vector3(0, 5.0, -1.35), stone)
	WorldArt.rune_ring(parent, pos + Vector3(0, 3.4, -1.08), 0.6, rune, 0.12).rotation.x = PI / 2
	# Armrests with gilt caps.
	for sx in [-1.0, 1.0]:
		bx.call(Vector3(0.45, 0.6, 1.7), Vector3(sx * 1.2, 1.95, -0.55), stone)
		bx.call(Vector3(0.5, 0.08, 1.75), Vector3(sx * 1.2, 2.28, -0.55), gold)
		# Great bone horns curving up and out from the top of the back.
		var horn := Node3D.new()
		horn.position = pos + Vector3(sx * 1.05, 4.6, -1.35)
		horn.rotation = Vector3(0, 0, sx * -0.55)
		parent.add_child(horn)
		var seg_h := 0.75
		var r := 0.22
		var at := Vector3.ZERO
		var tilt := 0.0
		for k in 4:
			var c := CylinderMesh.new()
			c.top_radius = r * 0.72
			c.bottom_radius = r
			c.height = seg_h
			c.radial_segments = 8
			var dir := Vector3(sx * sin(tilt), cos(tilt), 0)
			var mi := WorldArt.mesh_node(horn, c, at + dir * seg_h * 0.5, bone, Vector3(0, 0, -sx * tilt))
			mi.position = at + dir * seg_h * 0.5
			at += dir * seg_h
			r *= 0.72
			tilt -= 0.38  # curls back inward
	# A red pelt over the seat, hanging over the front edge.
	bx.call(Vector3(1.8, 0.08, 1.5), Vector3(0, 1.69, -0.55), pelt)
	bx.call(Vector3(1.6, 0.7, 0.08), Vector3(0, 1.35, 0.22), pelt, Vector3(0.12, 0, 0))
	# Collision: dais and the throne body.
	WorldArt.box_collider(parent, Vector3(5.0, 0.7, 4.0), pos + Vector3(0, 0.35, 0))
	WorldArt.box_collider(parent, Vector3(2.6, 4.8, 2.2), pos + Vector3(0, 2.4, -0.9))


## Dressing for Rook's tavern, The Hollow Hearth (TavernArt builds the hall;
## this adds the lived-in layer): moonlit windows either side of the door
## for a cool counterpoint to the firelight, a wagon-wheel chandelier, herb
## and garlic bundles on the beams, a hearth rug, mantel clutter and the bard
## on the dais. Visual only, no colliders; room-local like TavernArt.
static func tavern_dress(t: Node3D, c: Vector3, room: Vector3) -> void:
	if WorldArt.headless():
		return
	var hx := room.x * 0.5
	var hz := room.z * 0.5
	var trim := Color("4f3522")
	# Windows on the front wall: deep frame, four moonlit panes, a sill.
	var pane := WorldArt.mat(Color(0.22, 0.32, 0.55), 0.0, Color(0.36, 0.5, 0.86), 1.1)
	for wx in [-3.3, 3.3]:
		var wp := c + Vector3(wx, 1.95, hz - 0.03)
		WorldArt.box(t, Vector3(1.3, 1.4, 0.06), wp + Vector3(0, 0, 0.0), Color("2a1d14"), Vector3.ZERO, 0.0)
		for q in [Vector2(-0.28, 0.3), Vector2(0.28, 0.3), Vector2(-0.28, -0.3), Vector2(0.28, -0.3)]:
			WorldArt.mesh_node(t, _tv_bm(Vector3(0.5, 0.54, 0.02)), wp + Vector3(q.x, q.y, -0.04), pane)
		WorldArt.box(t, Vector3(1.4, 0.1, 0.14), wp + Vector3(0, 0.74, -0.05), trim, Vector3.ZERO, 0.0)
		WorldArt.box(t, Vector3(1.5, 0.08, 0.26), wp + Vector3(0, -0.74, -0.1), trim, Vector3.ZERO, 0.0)
		WorldArt.box(t, Vector3(0.06, 1.3, 0.05), wp + Vector3(0, 0, -0.06), trim, Vector3.ZERO, 0.0)
		WorldArt.box(t, Vector3(1.2, 0.06, 0.05), wp + Vector3(0, 0, -0.06), trim, Vector3.ZERO, 0.0)
		# A small pot of herbs on each sill.
		WorldArt.cyl(t, 0.09, 0.07, 0.14, wp + Vector3(-0.4, -0.63, -0.14), Color("9a5a3a"), 8)
		WorldArt.sphere(t, 0.11, wp + Vector3(-0.4, -0.5, -0.14), Color("5a7a3a"), Vector3(1, 0.8, 1))
		var ml := OmniLight3D.new()
		ml.light_color = Color(0.55, 0.68, 1.0)
		ml.light_energy = 0.55
		ml.omni_range = 3.6
		ml.shadow_enabled = false
		ml.position = wp + Vector3(0, -0.2, -0.9)
		t.add_child(ml)
	# Wagon-wheel chandelier over the door-side table.
	var cp := c + Vector3(0.2, room.y - 1.35, 3.1)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.62
	rim.outer_radius = 0.7
	rim.rings = 20
	rim.ring_segments = 6
	WorldArt.mesh_node(t, rim, cp, WorldArt.mat(Color("4a3020"), 0.02))
	for k in 4:
		WorldArt.box(t, Vector3(1.3, 0.05, 0.06), cp, Color("4a3020"), Vector3(0, k * PI / 4, 0), 0.0)
	WorldArt.cyl(t, 0.08, 0.08, 0.12, cp, Color("3a2618"), 8)
	for k in 4:
		WorldArt.cyl(t, 0.012, 0.012, 1.3, cp + Vector3(cos(k * PI / 2) * 0.62, 0.65, sin(k * PI / 2) * 0.62), Color("2a2830"), 4)
	for k in 6:
		var a := k * TAU / 6.0
		WorldArt.candle(t, cp + Vector3(cos(a) * 0.66, 0.05, sin(a) * 0.66), 0.16, 0.03)
	var cl := OmniLight3D.new()
	cl.light_color = Color("ffcf94")
	cl.light_energy = 0.9
	cl.omni_range = 5.5
	cl.shadow_enabled = false
	cl.position = cp + Vector3(0, -0.3, 0)
	t.add_child(cl)
	# Herb and garlic bundles hung from the beams on the hearth side.
	var beams := [-hz + 0.9 + 1.85 * 2, -hz + 0.9 + 1.85 * 3]
	var herb := [Color("6b7d3e"), Color("8a8a4a"), Color("7a5a8a"), Color("5f7a4a")]
	for bi in beams.size():
		for k in 5:
			var hp := c + Vector3(-5.6 + k * 0.62, room.y - 0.32, float(beams[bi]))
			WorldArt.cyl(t, 0.006, 0.006, 0.22, hp + Vector3(0, -0.06, 0), Color("6a5a40"), 3)
			if (k + bi) % 3 == 2:
				for g in 3:
					WorldArt.sphere(t, 0.06, hp + Vector3((g - 1) * 0.06, -0.24 - (g % 2) * 0.05, 0), Color("ece4d2"), Vector3(1, 1.15, 1))
			else:
				WorldArt.cyl(t, 0.02, 0.1, 0.32, hp + Vector3(0, -0.32, 0), herb[(k + bi * 2) % herb.size()], 6)
	# Hearth rug, mantel jars and candles.
	var hp2 := c + Tavern.HEARTH
	WorldArt.box(t, Vector3(1.7, 0.02, 2.6), hp2 + Vector3(1.9, 0.011, 0), Color("6a2a26"), Vector3.ZERO, 0.0)
	WorldArt.box(t, Vector3(1.4, 0.022, 2.3), hp2 + Vector3(1.9, 0.013, 0), Color("8f3a30"), Vector3.ZERO, 0.0)
	WorldArt.box(t, Vector3(0.7, 0.024, 1.5), hp2 + Vector3(1.9, 0.015, 0), Color("c49a4a"), Vector3.ZERO, 0.0)
	var mantel := hp2 + Vector3(0.25, 1.87, 0)
	for k in 5:
		var z := -1.5 + k * 0.75
		if k == 2:
			continue
		if k % 2 == 0:
			WorldArt.candle(t, mantel + Vector3(0, 0, z), 0.2, 0.035)
		else:
			WorldArt.cyl(t, 0.07, 0.08, 0.2, mantel + Vector3(0, 0.1, z), [Color("6f8aa0"), Color("a0784a")][k % 2 if k < 2 else 0], 8)
	# The bard: a climber-looking regular on the dais, lute at her side.
	if not Net.dedicated and VRMCharacter.BODIES.has("alicia"):
		var v := VRMCharacter.new()
		v.name = "Bard"
		v.position = c + Vector3(-4.95, 0.2, 3.0)
		v.rotation.y = -PI * 0.38  # faces the room (VRM forward is -Z)
		t.add_child(v)
		v.apply({"body": "alicia", "outfit_color": "2f5a8a", "hair_color": "e0b060", "skin_color": "f0d2b8"})
		if v.instance:
			for mi in v.instance.find_children("robo_arm", "MeshInstance3D", true, false):
				mi.visible = false


static func _tv_bm(size: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return bm


## A carved wooden sign hung from an iron bracket over a door. `out` is the
## wall's outward direction; the board faces it and swings a little.
static func hanging_sign(parent: Node3D, at: Vector3, out: Vector3, text: String) -> Node3D:
	var root := Node3D.new()
	root.name = "HangingSign"
	root.position = at
	root.rotation.y = atan2(out.x, out.z)
	parent.add_child(root)
	var iron := Color("2a2830")
	# Bracket: arm out from the wall with a diagonal brace and a scroll end.
	WorldArt.box(root, Vector3(0.07, 0.07, 1.25), Vector3(0, 0.9, 0.55), iron, Vector3.ZERO, 0.015)
	WorldArt.box(root, Vector3(0.05, 0.05, 0.9), Vector3(0, 0.62, 0.32), iron, Vector3(0.62, 0, 0), 0.015)
	WorldArt.box(root, Vector3(0.24, 0.24, 0.05), Vector3(0, 0.9, -0.04), iron, Vector3.ZERO, 0.015)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.05
	ring.outer_radius = 0.075
	WorldArt.mesh_node(root, ring, Vector3(0, 0.95, 1.18), WorldArt.mat(iron, 0.0), Vector3(0, 0, PI / 2))
	# The board swings from the arm on two short chains.
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.86, 0.6)
	root.add_child(pivot)
	for sx in [-0.62, 0.62]:
		WorldArt.box(pivot, Vector3(0.02, 0.26, 0.02), Vector3(sx * 0.55, -0.13, 0), iron, Vector3.ZERO, 0.0)
	var wood := WorldArt.wood_mat(Color("6e4b2c"), Color("5c3e24"), "weathered_planks", 0.2, 0, {"brick_length": 2.0})
	WorldArt.mesh_node(pivot, _tv_bm(Vector3(1.9, 0.62, 0.07)), Vector3(0, -0.58, 0), wood)
	WorldArt.box(pivot, Vector3(2.0, 0.07, 0.09), Vector3(0, -0.26, 0), Color("4f3522"), Vector3.ZERO, 0.0)
	WorldArt.box(pivot, Vector3(2.0, 0.07, 0.09), Vector3(0, -0.9, 0), Color("4f3522"), Vector3.ZERO, 0.0)
	for side in [1, -1]:
		var l := Label3D.new()
		l.text = text
		l.font = UITheme.display_font()
		l.font_size = 72
		l.pixel_size = 0.0042
		l.outline_size = 10
		l.modulate = Color("f0c060")
		l.outline_modulate = Color(0.16, 0.09, 0.04, 1.0)
		l.position = Vector3(0, -0.56, side * 0.045)
		l.rotation.y = 0.0 if side > 0 else PI
		l.double_sided = false
		pivot.add_child(l)
		# A little painted flame under the name: the hearth.
		WorldArt.sphere(pivot, 0.05, Vector3(0, -0.78, side * 0.04), Color("ff9a3a"), Vector3(0.8, 1.3, 0.2))
	var tw := pivot.create_tween().set_loops()
	tw.tween_property(pivot, "rotation:x", 0.05, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(pivot, "rotation:x", -0.04, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return root
