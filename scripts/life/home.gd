class_name PlayerHome
extends Node3D
## The player's cottage: a "For Sale" house on the north edge of Hollowbrook
## (Floor 1), in a gap of the village ring with its door toward the well,
## and its interior, built in the same scene inside the island's rock
## underside (INTERIOR). The door and the exit mat teleport between
## the two; the world lists both as pads so the server accepts the jump.
## Inside: a hearth (cooking), a bed (sleep), a storage chest and six
## furniture slots for decorations bought from Trader Pell. Ownership,
## furniture, storage and decorations live in GameState (saved, and sent
## with the snapshot online, where the server whitelists them).

const HOME_POS := Vector3(-143.5, 0, 65.0)  # Hollowbrook + (0.5, 0, -19)
const INTERIOR := Vector3(0, -22, 0)
const ROOM := Vector3(11.0, 4.2, 9.0)
## Furniture slot positions inside the room (relative to INTERIOR).
const SLOTS := [Vector3(-4.3, 0, 1.2), Vector3(-4.3, 0, 3.4), Vector3(4.3, 0, 0.6), Vector3(4.3, 0, 3.0), Vector3(-2.7, 0, -3.9), Vector3(2.7, 0, -3.9)]
const HEARTH := Vector3(0, 0, -4.0)
const BED := Vector3(-4.1, 0, -1.8)
const CHEST := Vector3(4.2, 0, -2.4)
const EXIT := Vector3(0, 0, 3.7)

var door_pos := Vector3.ZERO
var door_out := Vector3.ZERO  # where you stand after leaving
var exit_pos := INTERIOR + EXIT
var spawn_inside := INTERIOR + Vector3(0, 1, 2.4)
var _sign: Label3D
var _owned_fx: Node3D
var _furniture: Node3D
var _confirm_t := 0.0
var _world: Node3D
var _inside := false
var _window_sun: DirectionalLight3D
var _window_lights: Array = []
var _outdoor_ambient: Array = []
const INSIDE_AMBIENT := Color(0.62, 0.52, 0.48)


static func build(world: Node3D) -> PlayerHome:
	var h := PlayerHome.new()
	h.name = "PlayerHome"
	h.process_priority = 100  # after DayNight, see _update_interior_light()
	h._world = world
	world.add_child(h)
	h._build_exterior()
	h._build_interior()
	h.refresh_furniture()
	GameState.home_changed.connect(h._on_home_changed)
	return h


func _exit_tree() -> void:
	if GameState.home_changed.is_connected(_on_home_changed):
		GameState.home_changed.disconnect(_on_home_changed)


func _process(delta: float) -> void:
	if _confirm_t > 0.0:
		_confirm_t -= delta
	_update_interior_light()


## The cottage interior sits under the island, so while the local player is
## inside, the sun, sky fill and moon are hidden (on this client only) and
## the interior's own window light takes over, following the day:
## cool daylight through the panes by day, faint moonlight at night. The
## hearth fire, candles and lanterns do the rest.
func _update_interior_light() -> void:
	# Whatever this client is looking through decides it (the follow camera
	# sits by the player; a cutscene or debug camera counts too).
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var at: Vector3
	if cam:
		at = cam.global_position
	else:
		var pl = _world.get("player") if _world else null
		if pl == null or not is_instance_valid(pl):
			return
		at = (pl as Node3D).global_position
	var inside: bool = at.distance_to(INTERIOR + Vector3(0, 2, 0)) < 9.0
	if inside != _inside:
		_inside = inside
		if _window_sun:
			_window_sun.visible = inside
		# Ambient: the bright HDRI sky would flood the room, so inside it
		# becomes a dim warm colour (DayNight still scales its energy).
		var we := _world.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we and we.environment:
			var env := we.environment
			if inside:
				_outdoor_ambient = [env.ambient_light_source, env.ambient_light_color, env.reflected_light_source]
				env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				env.ambient_light_color = INSIDE_AMBIENT
				env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
			elif not _outdoor_ambient.is_empty():
				env.ambient_light_source = _outdoor_ambient[0]
				env.ambient_light_color = _outdoor_ambient[1]
				env.reflected_light_source = _outdoor_ambient[2]
	if not inside:
		return
	# DayNight re-shows these every frame; PlayerHome processes after it
	# (process_priority), so hiding them here holds for the frame.
	for nm in ["Sun", "SkyFill", "Moon"]:
		var l := _world.get_node_or_null(nm) as Light3D
		if l:
			l.visible = false
	if _window_sun == null:
		return
	var dn = _world.get("day_night")
	var day: float = dn.daylight() if dn != null else 1.0
	var day_k := smoothstep(0.0, 0.35, day)
	_window_sun.light_energy = lerpf(0.12, 0.5, day_k)
	_window_sun.light_color = Color("7f93d6").lerp(Color("d8e4ff"), day_k)
	for l in _window_lights:
		l.light_energy = lerpf(0.08, 0.6, day_k)
		l.light_color = Color("7f93d6").lerp(Color("cfe0ff"), day_k)


# --- Exterior ------------------------------------------------------------------

func _build_exterior() -> void:
	var rel: Vector3 = HOME_POS - _world.HOLLOWBROOK
	var face := atan2(-rel.x, -rel.z)
	var scl: float = WorldProps.HOUSE * 0.9
	WorldProps.house(_world, HOME_POS, "home_B", "yellow", face, scl)
	var fp := WorldProps.footprint("home_B", "yellow", scl)
	_build_window_glow(face, scl)
	var fwd := Vector3(sin(face), 0, cos(face))
	var side := Vector3(cos(face), 0, -sin(face))
	door_pos = HOME_POS + fwd * (fp.y * 0.5 + 1.5)
	door_out = HOME_POS + fwd * (fp.y * 0.5 + 3.2)
	# Welcome mat, stepping stones toward the well and the sale sign.
	WorldArt.box(_world, Vector3(1.4, 0.06, 0.9), door_pos + Vector3(0, 0.03, 0), Color("8a3a2e"), Vector3(0, face, 0), 0.0)
	for k in 4:
		var sp := door_pos + fwd * (1.2 + k * 1.1) + side * (0.25 * ((k % 2) * 2 - 1))
		if not WorldProps.prop(_world, "survival", "rock-flat", sp, face + k * 1.3, WorldProps.SURVIVAL * 0.1, "none"):
			WorldArt.cyl(_world, 0.45, 0.5, 0.08, sp + Vector3(0, 0.04, 0), WorldArt.STONE, 8)
	var sign_pos := door_pos + side * 2.1
	if not WorldProps.signpost(_world, sign_pos, face + PI):
		WorldArt.cyl(_world, 0.06, 0.08, 1.6, sign_pos + Vector3(0, 0.8, 0), WorldArt.WOOD, 6)
		WorldArt.box(_world, Vector3(1.1, 0.5, 0.06), sign_pos + Vector3(0, 1.45, 0), WorldArt.WOOD_LIGHT, Vector3(0, face, 0))
	_sign = Label3D.new()
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.position = sign_pos + Vector3(0, 2.4, 0)
	_sign.font_size = 44
	_sign.outline_size = 12
	_sign.modulate = Color(1, 0.93, 0.6)
	_sign.outline_modulate = Color(0.12, 0.08, 0.2, 0.9)
	_world.add_child(_sign)
	# A lantern post, flower planters by the door, and the owner's touches
	# (a lit door lamp and chimney smoke) that only show once it is bought.
	WorldProps.lantern(_world, door_pos - side * 2.4, face)
	for sx in [-1, 1]:
		var pp: Vector3 = door_pos - fwd * 0.9 + side * (sx * 1.25)
		if WorldProps.prop(_world, "nature", "pot_large", pp, face, WorldProps.NATURE * 0.75, "none"):
			WorldProps.prop(_world, "nature", ["flower_redA", "flower_purpleA"][(sx + 1) / 2], pp + Vector3(0, 0.1, 0), face + sx, WorldProps.NATURE * 0.9, "none")
			WorldProps.prop(_world, "nature", "flower_yellowB", pp + Vector3(0, 0.1, 0) + side * sx * 0.25, face - sx, WorldProps.NATURE * 0.8, "none")
		else:
			WorldArt.cyl(_world, 0.3, 0.24, 0.4, pp + Vector3(0, 0.2, 0), WorldArt.TERRACOTTA, 10)
	_owned_fx = Node3D.new()
	_owned_fx.name = "OwnedFx"
	_world.add_child(_owned_fx)
	var lamp := door_pos - fwd * 0.55 + side * 0.95 + Vector3(0, 2.3, 0)
	WorldArt.box(_owned_fx, Vector3(0.08, 0.08, 0.45), lamp + Vector3(0, 0.12, 0) + fwd * 0.2, Color("3a3440"), Vector3(0, face, 0))
	WorldArt.box(_owned_fx, Vector3(0.3, 0.42, 0.3), lamp + fwd * 0.4, Color("fff0c0"), Vector3(0, face, 0), 0.0).mesh.material = WorldArt.mat(Color("ffe9a8"), 0.0, Color("ffb347"), 2.0)
	WorldArt.box(_owned_fx, Vector3(0.38, 0.06, 0.38), lamp + fwd * 0.4 + Vector3(0, 0.24, 0), Color("3a3440"), Vector3(0, face, 0))
	if not WorldArt.headless():
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.5)
		l.light_energy = 1.0
		l.omni_range = 6.0
		l.shadow_enabled = false
		l.position = lamp + fwd * 0.6
		_owned_fx.add_child(l)
		var smoke := WorldArt._particles(HOME_POS + Vector3(0, fp.y * 0.95, 0) - fwd * fp.y * 0.15, 14, 3.5, Vector3(0.15, 0.05, 0.15), Color(0.9, 0.9, 0.95, 0.35), 0.45, 0.0)
		smoke.process_material.initial_velocity_min = 0.7
		smoke.process_material.initial_velocity_max = 1.1
		smoke.process_material.spread = 10.0
		smoke.process_material.scale_max = 2.4
		_owned_fx.add_child(smoke)
	_refresh_sign()


## Warm window spill light for the cottage after dusk (High and Ultra).
func _build_window_glow(face: float, scl: float) -> void:
	if WorldArt.headless():
		return
	# The glass itself glows through the hex atlas material
	# (WorldArt.light_hex_windows, applied by AssetLib.house); overlay panes
	# here covered whole wall bands, so only the spill light is added.
	# One warm spill light at the front window, High and Ultra only; it
	# joins the lantern group so DayNight switches it on after dusk.
	if RenderProfile.current in ["High", "Ultra"]:
		var fwd := Vector3(sin(face), 0, cos(face))
		var l := WorldArt.lantern_light(_world, HOME_POS + fwd * (0.21 * scl + 1.2) + Vector3(0, 0.55 * scl, 0))
		if l:
			l.light_color = WorldArt.WINDOW_GLOW
			l.omni_range = 7.0


func _refresh_sign() -> void:
	if _sign:
		_sign.text = "%s's Cottage" % GameState.character.get("name", "Your") if GameState.home_owned else "FOR SALE  ·  %d Col" % LifeData.HOME_PRICE
	if _owned_fx:
		_owned_fx.visible = GameState.home_owned


# --- Interior ------------------------------------------------------------------

const TRIM := Color("4f3522")
const TIMBER := Color("3e2a1c")

func _build_interior() -> void:
	var c := INTERIOR
	var hx := ROOM.x * 0.5
	var hz := ROOM.z * 0.5
	var plaster := WorldArt.plaster_mat()
	var wainscot := WorldArt.wood_mat(Color("8c6a46"), Color("74573a"), "wood_planks_grey", 0.24, 0, {"brick_length": 1.0})
	# Floor (plank boards along x) and a plank ceiling with exposed beams.
	_box_body(Vector3(ROOM.x, 0.4, ROOM.z), c + Vector3(0, -0.2, 0), WorldArt.wood_mat(Color("9a7046"), Color("7c5838"), "weathered_planks", 0.34, 0))
	_slab(Vector3(ROOM.x, 0.3, ROOM.z), c + Vector3(0, ROOM.y + 0.15, 0), WorldArt.wood_mat(Color("5e4631"), Color("4c3827"), "wood_planks_grey", 0.3, 1, {"brick_length": 3.2}))
	for k in 5:
		var bz := -hz + 0.9 + k * 1.8
		WorldArt.box(self, Vector3(ROOM.x, 0.26, 0.26), c + Vector3(0, ROOM.y - 0.13, bz), TIMBER, Vector3.ZERO, 0.0)
	for sx in [-1, 1]:
		WorldArt.box(self, Vector3(0.22, 0.22, ROOM.z), c + Vector3(sx * 3.4, ROOM.y - 0.37, 0), TIMBER, Vector3.ZERO, 0.0)
	# Walls: plaster above a plank wainscot, with window openings cut in.
	# Windows: [wall, along-position, half width]; wall 0/1 = left/right (x
	# = -hx/+hx, along z), 2 = front (z = +hz, along x).
	var win_y0 := 1.45
	var win_y1 := 2.95
	var windows := [[0, -0.3, 0.65], [1, -1.0, 0.65], [2, -3.0, 0.65]]
	_wall_z(c, -hz, plaster, wainscot, [])            # back wall (hearth)
	_wall_z(c, hz, plaster, wainscot, [[-3.0, 0.65]])  # front wall (door, window)
	_wall_x(c, -hx, plaster, wainscot, [[-0.3, 0.65]])
	_wall_x(c, hx, plaster, wainscot, [[-1.0, 0.65]])
	for w in windows:
		var wall: int = w[0]
		var at: float = w[1]
		var half: float = w[2]
		var wp: Vector3
		var rot := 0.0
		match wall:
			0:
				wp = c + Vector3(-hx, 0, at)
				rot = PI / 2
			1:
				wp = c + Vector3(hx, 0, at)
				rot = -PI / 2
			_:
				wp = c + Vector3(at, 0, hz)
				rot = PI
		_window(wp, rot, half * 2.0, win_y0, win_y1)
	# Half-timber frame: corner posts, top plate, studs and skirting.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			WorldArt.box(self, Vector3(0.3, ROOM.y, 0.3), c + Vector3(sx * (hx - 0.13), ROOM.y * 0.5, sz * (hz - 0.13)), TIMBER, Vector3.ZERO, 0.0)
	WorldArt.box(self, Vector3(ROOM.x, 0.2, 0.14), c + Vector3(0, ROOM.y - 0.1, -hz + 0.07), TIMBER, Vector3.ZERO, 0.0)
	WorldArt.box(self, Vector3(ROOM.x, 0.2, 0.14), c + Vector3(0, ROOM.y - 0.1, hz - 0.07), TIMBER, Vector3.ZERO, 0.0)
	WorldArt.box(self, Vector3(0.14, 0.2, ROOM.z), c + Vector3(-hx + 0.07, ROOM.y - 0.1, 0), TIMBER, Vector3.ZERO, 0.0)
	WorldArt.box(self, Vector3(0.14, 0.2, ROOM.z), c + Vector3(hx - 0.07, ROOM.y - 0.1, 0), TIMBER, Vector3.ZERO, 0.0)
	for z in [-2.4, 2.4]:
		for sx in [-1, 1]:
			WorldArt.box(self, Vector3(0.12, ROOM.y - 1.1, 0.16), c + Vector3(sx * (hx - 0.08), 1.1 + (ROOM.y - 1.1) * 0.5, z), TIMBER, Vector3.ZERO, 0.0)
	for x in [-4.4, 4.4]:
		WorldArt.box(self, Vector3(0.16, ROOM.y - 1.1, 0.12), c + Vector3(x, 1.1 + (ROOM.y - 1.1) * 0.5, -hz + 0.08), TIMBER, Vector3.ZERO, 0.0)
		WorldArt.box(self, Vector3(0.16, ROOM.y - 1.1, 0.12), c + Vector3(x, 1.1 + (ROOM.y - 1.1) * 0.5, hz - 0.08), TIMBER, Vector3.ZERO, 0.0)
	# Wainscot rail and skirting all round.
	for sz in [-1, 1]:
		WorldArt.box(self, Vector3(ROOM.x, 0.1, 0.16), c + Vector3(0, 1.08, sz * (hz - 0.08)), TRIM, Vector3.ZERO, 0.0)
		WorldArt.box(self, Vector3(ROOM.x, 0.2, 0.12), c + Vector3(0, 0.1, sz * (hz - 0.06)), TRIM, Vector3.ZERO, 0.0)
	for sx in [-1, 1]:
		WorldArt.box(self, Vector3(0.16, 0.1, ROOM.z), c + Vector3(sx * (hx - 0.08), 1.08, 0), TRIM, Vector3.ZERO, 0.0)
		WorldArt.box(self, Vector3(0.12, 0.2, ROOM.z), c + Vector3(sx * (hx - 0.06), 0.1, 0), TRIM, Vector3.ZERO, 0.0)
	# The front door (the exit): plank door with iron bands, frame and mat.
	var dp := c + EXIT + Vector3(0, 0, hz - EXIT.z)
	WorldArt.box(self, Vector3(1.3, 2.5, 0.1), dp + Vector3(0, 1.25, -0.16), Color("6b4a2e"), Vector3.ZERO, 0.0).material_override = WorldArt.wood_mat(Color("6e4b2c"), Color("5c3e24"), "weathered_planks", 0.2, 0, {"brick_length": 2.6})
	for sx in [-1, 1]:
		WorldArt.box(self, Vector3(0.22, 2.75, 0.24), dp + Vector3(sx * 0.76, 1.37, -0.14), TRIM, Vector3.ZERO, 0.0)
	WorldArt.box(self, Vector3(1.75, 0.22, 0.26), dp + Vector3(0, 2.83, -0.14), TRIM, Vector3.ZERO, 0.0)
	for y in [0.55, 1.9]:
		WorldArt.box(self, Vector3(1.26, 0.1, 0.03), dp + Vector3(0, y, -0.22), Color("3b3b44"), Vector3.ZERO, 0.0)
	WorldArt.sphere(self, 0.06, dp + Vector3(0.48, 1.15, -0.24), UITheme.GOLD)
	WorldArt.box(self, Vector3(1.2, 0.04, 0.8), c + EXIT + Vector3(0, 0.02, 0), Color("8a3a2e"), Vector3.ZERO, 0.0)
	if WorldProps.has("dungeon", "keyring_hanging"):
		AssetLib.prop(self, "dungeon", "keyring_hanging", dp + Vector3(1.25, 1.75, -0.2), PI, WorldProps.DUNGEON * 0.8, "none")
	# Hearth: brick surround, dark firebox with a live fire (the room's main
	# light), a mantel with candles, the chimney breast, a trophy shield and
	# banners above, a log pile and the cooking pot on its crane.
	_build_hearth(c + HEARTH)
	# Bed against the left wall, head to the wall.
	var bp := c + BED
	if WorldProps.has("dungeon", "bed_decorated"):
		AssetLib.prop(self, "dungeon", "bed_decorated", bp + Vector3(0.1, 0, 0), PI / 2, WorldProps.DUNGEON * 1.15, "box")
	else:
		_box_body(Vector3(1.4, 0.5, 2.2), bp + Vector3(0, 0.25, 0), _warm_wood())
		WorldArt.box(self, Vector3(1.3, 0.25, 1.9), bp + Vector3(0, 0.6, 0.1), Color("c9d9e8"), Vector3.ZERO, 0.0)
		WorldArt.box(self, Vector3(1.0, 0.18, 0.5), bp + Vector3(0, 0.6, -0.75), Color("f3eee4"), Vector3.ZERO, 0.0)
		WorldArt.box(self, Vector3(1.4, 1.0, 0.1), bp + Vector3(0, 0.5, -1.1), _warm_wood(), Vector3.ZERO, 0.0)
	# A small candle shelf over the bed.
	if WorldProps.has("dungeon", "shelf_small_candles"):
		AssetLib.prop(self, "dungeon", "shelf_small_candles", c + Vector3(-hx + 0.2, 2.35, -2.0), PI / 2, WorldProps.DUNGEON * 0.9, "none")
	# Storage chest against the right wall, with a crate of odds and ends.
	var cp := c + CHEST
	if WorldProps.has("survival", "chest"):
		AssetLib.prop(self, "survival", "chest", cp, -PI / 2, WorldProps.SURVIVAL * 0.6, "box")
	else:
		_box_body(Vector3(1.0, 0.7, 0.7), cp + Vector3(0, 0.35, 0), _warm_wood())
		WorldArt.box(self, Vector3(1.04, 0.1, 0.74), cp + Vector3(0, 0.72, 0), WorldArt.WOOD, Vector3.ZERO, 0.0)
		WorldArt.sphere(self, 0.06, cp + Vector3(0, 0.45, 0.37), UITheme.GOLD)
	if WorldProps.has("dungeon", "box_small_decorated"):
		AssetLib.prop(self, "dungeon", "box_small_decorated", cp + Vector3(0.2, 0, -1.3), -0.4, WorldProps.DUNGEON * 0.55, "box")
	# Dining table with a meal, two chairs and a candle, between hearth and chest.
	var tp := c + Vector3(1.9, 0, -1.0)
	if WorldProps.has("dungeon", "table_medium_tablecloth"):
		AssetLib.prop(self, "dungeon", "table_medium_tablecloth", tp, 0.0, WorldProps.DUNGEON, "box")
		AssetLib.prop(self, "dungeon", "chair", tp + Vector3(0, 0, 1.1), PI, WorldProps.DUNGEON, "box")
		AssetLib.prop(self, "dungeon", "chair", tp + Vector3(-1.1, 0, 0), -PI / 2, WorldProps.DUNGEON, "box")
		var top := 0.8
		AssetLib.prop(self, "dungeon", "plate_food_B", tp + Vector3(0.1, top, 0.2), 0.3, WorldProps.DUNGEON * 0.8, "none")
		AssetLib.prop(self, "dungeon", "bottle_A_labeled_green", tp + Vector3(-0.4, top, -0.35), 0.0, WorldProps.DUNGEON * 0.7, "none")
		AssetLib.prop(self, "dungeon", "plate_small", tp + Vector3(0.45, top, -0.45), 0.0, WorldProps.DUNGEON * 0.8, "none")
		WorldArt.candle(self, tp + Vector3(-0.35, top, 0.45), 0.2, 0.04)
	else:
		WorldArt.cyl(self, 0.75, 0.75, 0.08, tp + Vector3(0, 0.78, 0), _warm_wood(), 16)
		WorldArt.cyl(self, 0.1, 0.14, 0.75, tp + Vector3(0, 0.38, 0), WorldArt.WOOD, 8)
	# Wall shelves of jars, bottles and books on the front wall by the door.
	_build_shelves(c + Vector3(3.3, 0, hz - 0.3), PI)
	# Herb bundles drying under the beam by the hearth.
	for k in 5:
		var hp := c + Vector3(-3.0 + k * 0.45, ROOM.y - 0.3, -hz + 0.9)
		WorldArt.cyl(self, 0.004, 0.004, 0.3, hp + Vector3(0, -0.15, 0), Color("b8a070"), 4)
		var bundle := CylinderMesh.new()
		bundle.top_radius = 0.02
		bundle.bottom_radius = 0.1
		bundle.height = 0.32
		bundle.radial_segments = 6
		WorldArt.mesh_node(self, bundle, hp + Vector3(0, -0.52, 0), WorldArt.mat([Color("5f7f45"), Color("7a8f4f"), Color("a08a5a")][k % 3], 0.015), Vector3(PI, 0, 0))
	# Potted fern by the door and a rolled rug in the corner.
	var fp := c + Vector3(-1.5, 0, hz - 0.8)
	WorldArt.cyl(self, 0.26, 0.2, 0.4, fp + Vector3(0, 0.2, 0), WorldArt.TERRACOTTA, 10)
	if not WorldProps.prop(self, "nature", "plant_flatTall", fp + Vector3(0, 0.42, 0), 0.4, WorldProps.NATURE * 0.9, "none"):
		WorldArt.sphere(self, 0.3, fp + Vector3(0, 0.7, 0), Color("6fbf5a"))
	# A round braided rug in front of the fire.
	var rp := c + HEARTH + Vector3(0, 0, 2.0)
	var rings := [[1.0, Color("6d4a3a")], [0.82, Color("c9a36a")], [0.62, Color("8a3a2e")], [0.42, Color("d9b98a")], [0.22, Color("6d4a3a")]]
	for k in rings.size():
		var rr: float = rings[k][0]
		var disc := WorldArt.cyl(self, rr, rr, 0.03, rp + Vector3(0, 0.015 + k * 0.004, 0), rings[k][1], 28)
		disc.scale = Vector3(1.0, 1.0, 0.72)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Window light: a cool soft fill from each pane (the fire does the rest).
	if not WorldArt.headless():
		for w in windows:
			var wp2: Vector3
			match int(w[0]):
				0: wp2 = c + Vector3(-hx + 0.6, 2.2, w[1])
				1: wp2 = c + Vector3(hx - 0.6, 2.2, w[1])
				_: wp2 = c + Vector3(w[1], 2.2, hz - 0.6)
			var l := OmniLight3D.new()
			l.light_color = Color("c9dcff")
			l.light_energy = 0.3
			l.omni_range = 4.5
			l.shadow_enabled = false
			l.position = wp2
			add_child(l)
			_window_lights.append(l)
		# Soft daylight through the panes (only while the player is inside).
		_window_sun = DirectionalLight3D.new()
		_window_sun.name = "CottageWindowLight"
		_window_sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		_window_sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-120), 0)
		_window_sun.shadow_enabled = false
		_window_sun.light_specular = 0.0
		_window_sun.visible = false
		add_child(_window_sun)
	# The six decoration slots: faint gold floor runes.
	for i in SLOTS.size():
		var sp: Vector3 = c + SLOTS[i]
		var rune := WorldArt.rune_floor(self, sp, 0.62, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 1.0), 0.7)
		rune.name = "SlotMark%d" % i
		rune.position.y = sp.y + 0.012
	_furniture = Node3D.new()
	_furniture.name = "Furniture"
	add_child(_furniture)


## One wall along x at z = zc (back/front), with the door cut from the front
## and `holes` = [[x, half_width], ...] window openings.
func _wall_z(c: Vector3, zc: float, plaster: Material, wainscot: Material, holes: Array) -> void:
	var hx := ROOM.x * 0.5
	var z := c.z + zc + signf(zc) * 0.2
	var cuts := []
	for h in holes:
		cuts.append([h[0] - h[1], h[0] + h[1], 1.45, 2.95])
	if zc > 0.0:
		cuts.append([-0.75, 0.75, 0.0, 2.75])
	_wall_strip(Vector3(c.x - hx, c.y, z), Vector3(1, 0, 0), ROOM.x, 0.4, plaster, wainscot, cuts)


## One wall along z at x = xc (left/right) with window `holes` = [[z, half]].
func _wall_x(c: Vector3, xc: float, plaster: Material, wainscot: Material, holes: Array) -> void:
	var hz := ROOM.z * 0.5
	var x := c.x + xc + signf(xc) * 0.2
	var cuts := []
	for h in holes:
		cuts.append([h[0] - h[1], h[0] + h[1], 1.45, 2.95])
	_wall_strip(Vector3(x, c.y, c.z - hz), Vector3(0, 0, 1), ROOM.z, 0.4, plaster, wainscot, cuts)


## A wall from `origin` along `dir` for `length`, built as plaster (above
## 1.1 m) over wainscot, with rectangular openings [a0, a1, y0, y1] (a
## measured from the strip's centre) left open.
func _wall_strip(origin: Vector3, dir: Vector3, length: float, thick: float, plaster: Material, wainscot: Material, cuts: Array) -> void:
	var edges := [0.0, length]
	for cut in cuts:
		edges.append(cut[0] + length * 0.5)
		edges.append(cut[1] + length * 0.5)
	edges.sort()
	for i in edges.size() - 1:
		var a0: float = edges[i]
		var a1: float = edges[i + 1]
		if a1 - a0 < 0.01:
			continue
		var mid := (a0 + a1) * 0.5 - length * 0.5
		var open: Array = []
		for cut in cuts:
			if mid > cut[0] and mid < cut[1]:
				open = cut
		var bands := [[0.0, 1.1, wainscot], [1.1, ROOM.y, plaster]]
		for b in bands:
			var y0: float = b[0]
			var y1: float = b[1]
			var segs := [[y0, y1]]
			if not open.is_empty():
				segs = []
				if open[2] > y0:
					segs.append([y0, minf(open[2], y1)])
				if open[3] < y1:
					segs.append([maxf(open[3], y0), y1])
			for sg in segs:
				if sg[1] - sg[0] < 0.01:
					continue
				var size := Vector3(a1 - a0, sg[1] - sg[0], thick) if dir.x != 0.0 else Vector3(thick, sg[1] - sg[0], a1 - a0)
				var pos := origin + dir * ((a0 + a1) * 0.5) + Vector3(0, (sg[0] + sg[1]) * 0.5, 0)
				_box_body(size, pos, b[2])


## Window opening dressing at wall point `wp` (y = floor), facing `rot`
## (local +z points into the room): frame, sill, mullions, sky pane behind
## the wall and a pair of curtains on a rod.
func _window(wp: Vector3, rot: float, width: float, y0: float, y1: float) -> void:
	var n := Node3D.new()
	n.position = wp
	n.rotation.y = rot
	add_child(n)
	var h := y1 - y0
	var ym := (y0 + y1) * 0.5
	for sx in [-1, 1]:
		WorldArt.box(n, Vector3(0.14, h + 0.28, 0.5), Vector3(sx * (width * 0.5 + 0.07), ym, 0.0), TRIM, Vector3.ZERO, 0.0)
	WorldArt.box(n, Vector3(width + 0.28, 0.14, 0.5), Vector3(0, y1 + 0.07, 0.0), TRIM, Vector3.ZERO, 0.0)
	WorldArt.box(n, Vector3(width + 0.44, 0.1, 0.62), Vector3(0, y0 - 0.05, 0.06), TRIM, Vector3.ZERO, 0.0)
	WorldArt.box(n, Vector3(0.05, h, 0.05), Vector3(0, ym, 0.0), TRIM, Vector3.ZERO, 0.0)
	WorldArt.box(n, Vector3(width, 0.05, 0.05), Vector3(0, ym, 0.0), TRIM, Vector3.ZERO, 0.0)
	# Sky quad a little way outside, filling the opening from any angle.
	var pane := PlaneMesh.new()
	pane.size = Vector2(width + 1.6, h + 1.4)
	pane.orientation = PlaneMesh.FACE_Z
	var sky := WorldArt.mesh_node(n, pane, Vector3(0, ym, -0.7), WorldArt.window_sky_mat())
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Glass: a faint pane in the opening so it catches a highlight.
	var glass := BoxMesh.new()
	glass.size = Vector3(width, h, 0.02)
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.85, 0.93, 1.0, 0.12)
	gm.roughness = 0.1
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	WorldArt.mesh_node(n, glass, Vector3(0, ym, -0.02), gm)
	# Curtain rod and two gathered curtains.
	WorldArt.cyl(n, 0.025, 0.025, width + 0.7, Vector3(0, y1 + 0.26, 0.34), Color("3a3440"), 6, Vector3(0, 0, PI / 2))
	for sx in [-1, 1]:
		var cw := 0.36
		var cx: float = sx * (width * 0.5 + 0.1)
		var curtain := WorldArt.box(n, Vector3(cw, h + 0.5, 0.1), Vector3(cx, ym + 0.02, 0.33), Color("b5473c"), Vector3.ZERO, 0.02)
		curtain.material_override = WorldArt.stone_mat(Color("b5473c"), Color("9a3a32"), "", 1.0, {"plank_period": 0.09, "band_width": 0.02, "band_dark": 0.78, "brick_length": 40.0, "shadow_level": 0.55})
		WorldArt.box(n, Vector3(cw + 0.06, 0.08, 0.14), Vector3(cx, ym - 0.35, 0.33), Color("d9a441"), Vector3.ZERO, 0.0)
		WorldArt.sphere(n, 0.05, Vector3(sx * (width * 0.5 + 0.45), y1 + 0.26, 0.34), Color("d9a441"))


func _build_hearth(hp: Vector3) -> void:
	var brick := WorldArt.stone_mat(Color("8c7a74"), Color("6e5f5c"), "castle_brick_07", 0.5, {"band_period": 0.24, "band_width": 0.035, "brick_length": 0.5, "band_dark": 0.62, "detail_strength": 0.45})
	var cap := WorldArt.stone_mat(Color("a09890"), Color("8a827c"), "rock_wall_10", 0.4, {"detail_strength": 0.4})
	# Surround and firebox (collider on the surround).
	_box_body(Vector3(3.0, 1.55, 0.95), hp + Vector3(0, 0.775, -0.08), brick)
	WorldArt.box(self, Vector3(1.6, 1.05, 0.7), hp + Vector3(0, 0.55, 0.32), Color("17121a"), Vector3.ZERO, 0.0)
	WorldArt.box(self, Vector3(1.8, 0.12, 0.9), hp + Vector3(0, 0.06, 0.5), Color("2a2328"), Vector3.ZERO, 0.0)
	WorldArt.mesh_node(self, BoxMesh.new(), hp + Vector3(0, 1.62, -0.03), cap, Vector3.ZERO, Vector3(3.5, 0.16, 1.2))
	WorldArt.box(self, Vector3(3.3, 0.06, 1.1), hp + Vector3(0, 1.73, -0.03), WorldArt.WOOD_LIGHT, Vector3.ZERO, 0.0)
	# Chimney breast to the ceiling, tapering above the mantel.
	WorldArt.mesh_node(self, BoxMesh.new(), hp + Vector3(0, 1.8 + (ROOM.y - 1.8) * 0.5, -0.12), brick, Vector3.ZERO, Vector3(2.4, ROOM.y - 1.8, 0.78))
	WorldArt.mesh_node(self, BoxMesh.new(), hp + Vector3(0, 1.95, 0.08), cap, Vector3.ZERO, Vector3(2.6, 0.3, 1.0))
	# Fire: andirons, logs, the flame and its warm light.
	for k in 3:
		WorldArt.cyl(self, 0.09, 0.1, 0.8, hp + Vector3(-0.15 + k * 0.15, 0.2 + (k % 2) * 0.12, 0.3), [Color("5a3a22"), Color("4a3020"), Color("6a4428")][k], 6, Vector3(0, 0.9 + k * 0.8, PI / 2.1))
	for sx in [-1, 1]:
		WorldArt.box(self, Vector3(0.06, 0.3, 0.6), hp + Vector3(sx * 0.5, 0.15, 0.3), Color("3b3b44"), Vector3.ZERO, 0.0)
	WorldArt.flame(self, hp + Vector3(0, 0.22, 0.3), 0.6, false)
	if not WorldArt.headless():
		# The hearth glow, out in front of the firebox so it washes the floor.
		var fire_l := OmniLight3D.new()
		fire_l.name = "HearthLight"
		fire_l.light_color = Color("ff9a4a")
		fire_l.light_energy = 2.6
		fire_l.omni_range = 9.0
		fire_l.omni_attenuation = 1.2
		fire_l.shadow_enabled = false
		fire_l.position = hp + Vector3(0, 0.9, 1.1)
		add_child(fire_l)
		var lt := fire_l.create_tween().set_loops()
		lt.tween_property(fire_l, "light_energy", 2.25, 0.23).set_trans(Tween.TRANS_SINE)
		lt.tween_property(fire_l, "light_energy", 2.8, 0.31).set_trans(Tween.TRANS_SINE)
		lt.tween_property(fire_l, "light_energy", 2.6, 0.27).set_trans(Tween.TRANS_SINE)
	# Pot crane: an iron arm from the firebox wall with the stew pot.
	WorldArt.cyl(self, 0.025, 0.025, 0.95, hp + Vector3(-0.55, 0.95, 0.3), Color("3b3b44"), 6, Vector3(0, 0, PI / 2))
	WorldArt.cyl(self, 0.02, 0.02, 0.2, hp + Vector3(-0.05, 0.85, 0.3), Color("3b3b44"), 5)
	WorldArt.cyl(self, 0.24, 0.19, 0.26, hp + Vector3(-0.05, 0.62, 0.3), Color("34323b"), 12)
	WorldArt.cyl(self, 0.26, 0.26, 0.04, hp + Vector3(-0.05, 0.76, 0.3), Color("2a282f"), 12)
	WorldArt.cyl(self, 0.21, 0.21, 0.02, hp + Vector3(-0.05, 0.75, 0.3), Color("b8743a"), 12)
	# Mantel: candles, a jug and a small frame; a gold shield above with
	# banners either side of the breast.
	WorldArt.candle(self, hp + Vector3(-1.1, 1.76, 0.1), 0.22, 0.04)
	WorldArt.candle(self, hp + Vector3(-0.95, 1.76, 0.25), 0.14, 0.035)
	WorldArt.candle(self, hp + Vector3(1.15, 1.76, 0.15), 0.18, 0.04)
	if WorldProps.has("dungeon", "bottle_B_brown"):
		AssetLib.prop(self, "dungeon", "bottle_B_brown", hp + Vector3(0.5, 1.76, 0.1), 0.0, WorldProps.DUNGEON * 0.7, "none")
		AssetLib.prop(self, "dungeon", "plate_stack", hp + Vector3(-0.3, 1.76, 0.05), 0.0, WorldProps.DUNGEON * 0.55, "none")
	if WorldProps.has("dungeon", "sword_shield_gold"):
		AssetLib.prop(self, "dungeon", "sword_shield_gold", hp + Vector3(0, 3.05, 0.3), 0.0, WorldProps.DUNGEON * 0.62, "none")
	if WorldProps.has("dungeon", "banner_thin_red"):
		for sx in [-1, 1]:
			AssetLib.prop(self, "dungeon", "banner_thin_red", hp + Vector3(sx * 1.6, 1.95, -0.42), 0.0, WorldProps.DUNGEON * 0.6, "none")
	# Log pile to the right of the hearth and fire irons on the left.
	for k in 6:
		var lx := 1.95 + (k % 3) * 0.2
		var ly := 0.1 + int(k / 3) * 0.2 + (k % 3) * 0.02
		WorldArt.cyl(self, 0.09, 0.09, 0.6, hp + Vector3(lx, ly, 0.0), [Color("7a5a3a"), Color("6a4a2e")][k % 2], 7, Vector3(PI / 2, 0, 0))
	WorldArt.box(self, Vector3(0.7, 0.04, 0.6), hp + Vector3(2.15, 0.02, 0.0), Color("4a3422"), Vector3.ZERO, 0.0)
	WorldArt.cyl(self, 0.015, 0.015, 1.0, hp + Vector3(-1.85, 0.5, 0.35), Color("3b3b44"), 5, Vector3(0.15, 0, 0.08))
	WorldArt.cyl(self, 0.015, 0.015, 1.0, hp + Vector3(-1.95, 0.5, 0.2), Color("3b3b44"), 5, Vector3(-0.1, 0, 0.12))
	WorldArt.cyl(self, 0.12, 0.14, 0.04, hp + Vector3(-1.9, 0.02, 0.3), Color("3b3b44"), 8)


## Two wall shelves with jars, bottles, plates and a row of books. `rot`
## turns local +z toward the room.
func _build_shelves(pos: Vector3, rot: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot
	add_child(n)
	var shelf_mat := WorldArt.wood_mat(Color("7c5a3a"), Color("684a2e"), "wood_planks_grey", 0.4, 0, {"brick_length": 1.6})
	for y in [1.35, 2.15]:
		WorldArt.mesh_node(n, BoxMesh.new(), Vector3(0, y, 0.12), shelf_mat, Vector3.ZERO, Vector3(2.4, 0.07, 0.4))
		for sx in [-1, 1]:
			var br := PrismMesh.new()
			br.size = Vector3(0.3, 0.3, 0.06)
			WorldArt.mesh_node(n, br, Vector3(sx * 1.0, y - 0.18, 0.12), WorldArt.mat(TRIM), Vector3(0, 0, PI / 2 if sx < 0 else -PI / 2))
	var y0 := 1.385
	if WorldProps.has("dungeon", "bottle_A_green"):
		AssetLib.prop(n, "dungeon", "bottle_A_green", Vector3(-0.95, y0, 0.1), 0.0, WorldProps.DUNGEON * 0.6, "none")
		AssetLib.prop(n, "dungeon", "bottle_A_labeled_brown", Vector3(-0.7, y0, 0.15), 0.4, WorldProps.DUNGEON * 0.6, "none")
		AssetLib.prop(n, "dungeon", "bottle_C_green", Vector3(-0.48, y0, 0.1), 0.0, WorldProps.DUNGEON * 0.6, "none")
		AssetLib.prop(n, "dungeon", "plate_stack", Vector3(0.75, y0, 0.12), 0.0, WorldProps.DUNGEON * 0.5, "none")
		AssetLib.prop(n, "dungeon", "coin_stack_small", Vector3(0.25, y0, 0.1), 0.0, WorldProps.DUNGEON * 0.5, "none")
	_books(n, Vector3(-1.1, y0 + 0.8, 0.12), 2.1, 0.3)
	# Jars: squat cylinders with cork lids.
	for k in 3:
		var jx := -0.1 + k * 0.28
		WorldArt.cyl(n, 0.08, 0.09, 0.2, Vector3(jx, y0 + 0.1, 0.1), [Color("c9ced8"), Color("d9a441"), Color("7fa06a")][k], 10)
		WorldArt.cyl(n, 0.06, 0.06, 0.04, Vector3(jx, y0 + 0.22, 0.1), Color("b8906a"), 8)


## A row of books (spines out) from `at` for `width`, `depth` deep.
func _books(parent: Node, at: Vector3, width: float, depth: float, seed_k := 0) -> void:
	var x := 0.0
	var j := seed_k
	while x < width - 0.05:
		var w := 0.07 + 0.035 * (j % 3)
		var hgt := 0.24 + 0.05 * ((j * 2) % 4)
		var lean := 0.0 if (j % 7) != 6 else 0.18
		var col: Color = [Color("8a3a2e"), Color("2f4858"), Color("4a7a5a"), Color("d9a441"), Color("6d597a"), Color("b0633a")][j % 6]
		WorldArt.box(parent, Vector3(w, hgt, depth), at + Vector3(x + w * 0.5, hgt * 0.5, 0), col, Vector3(0, 0, lean), 0.02)
		WorldArt.box(parent, Vector3(w * 0.7, 0.012, depth * 0.3), at + Vector3(x + w * 0.5, hgt * 0.62, depth * 0.52), UITheme.GOLD, Vector3.ZERO, 0.0)
		x += w + 0.012
		j += 1


func _warm_wood() -> Color:
	return Color("a9815a")


func _slab(size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return WorldArt.mesh_node(self, bm, pos, m)


func _box_body(size: Vector3, pos: Vector3, color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = color if color is Material else WorldArt.mat(color, 0.02)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


# --- Furniture -----------------------------------------------------------------

func _on_home_changed() -> void:
	_refresh_sign()
	refresh_furniture()


## Rebuilds the decoration meshes from GameState.home_furniture.
func refresh_furniture() -> void:
	if _furniture == null:
		return
	for ch in _furniture.get_children():
		ch.queue_free()
	for i in mini(GameState.home_furniture.size(), SLOTS.size()):
		var id: String = GameState.home_furniture[i]
		if id == "" or not LifeData.DECOR.has(id):
			continue
		var n := Node3D.new()
		n.name = "Decor%d_%s" % [i, id]
		n.position = INTERIOR + SLOTS[i]
		# Face the room centre.
		n.rotation.y = atan2(-SLOTS[i].x, -SLOTS[i].z)
		_furniture.add_child(n)
		_build_decor(n, id)


## Decoration meshes, built live (never batched) so a slot can be cleared.
func _build_decor(n: Node3D, id: String) -> void:
	match id:
		"rug":
			WorldArt.box(n, Vector3(2.0, 0.035, 1.4), Vector3(0, 0.018, 0), Color("3a1f2a"), Vector3.ZERO, 0.0)
			var pm := PlaneMesh.new()
			pm.size = Vector2(2.0, 1.4)
			var rug := WorldArt.mesh_node(n, pm, Vector3(0, 0.04, 0), WorldArt.rug_mat())
			rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"bookshelf":
			var wood := WorldArt.wood_mat(Color("8a6240"), Color("745034"), "wood_planks_grey", 0.3, 0, {"brick_length": 1.2})
			var depth := 0.42
			var w := 1.3
			var h := 2.0
			for sx in [-1, 1]:
				WorldArt.mesh_node(n, BoxMesh.new(), Vector3(sx * (w * 0.5 - 0.03), h * 0.5, 0), wood, Vector3.ZERO, Vector3(0.06, h, depth))
			WorldArt.mesh_node(n, BoxMesh.new(), Vector3(0, h * 0.5, -depth * 0.5 + 0.02), wood, Vector3.ZERO, Vector3(w, h, 0.04))
			WorldArt.mesh_node(n, BoxMesh.new(), Vector3(0, h + 0.04, 0.02), wood, Vector3.ZERO, Vector3(w + 0.14, 0.08, depth + 0.08))
			WorldArt.box(n, Vector3(w + 0.1, 0.12, depth + 0.04), Vector3(0, 0.06, 0), TRIM, Vector3.ZERO, 0.0)
			for k in 4:
				var y := 0.12 + k * 0.47
				WorldArt.mesh_node(n, BoxMesh.new(), Vector3(0, y, 0), wood, Vector3.ZERO, Vector3(w - 0.12, 0.04, depth - 0.04))
				if k < 3:
					_books(n, Vector3(-w * 0.5 + 0.08, y + 0.02, -0.02), w - 0.16 if k != 1 else w * 0.55, 0.3, k * 5)
			if WorldProps.has("dungeon", "bottle_A_labeled_green"):
				WorldProps.live_prop(n, "dungeon", "bottle_A_labeled_green", Vector3(0.25, 0.12 + 0.47 + 0.02, 0.0), 0.3, WorldProps.DUNGEON * 0.55, "none")
				WorldProps.live_prop(n, "dungeon", "bottle_B_brown", Vector3(0.45, 0.12 + 0.47 + 0.02, 0.05), 0.0, WorldProps.DUNGEON * 0.55, "none")
			WorldArt.candle(n, Vector3(0.1, 0.12 + 3 * 0.47 + 0.02, 0.05), 0.16, 0.035)
			WorldArt.box_collider(n, Vector3(w, h, depth), Vector3(0, h * 0.5, 0))
		"plant":
			WorldArt.cyl(n, 0.3, 0.23, 0.46, Vector3(0, 0.23, 0), WorldArt.TERRACOTTA, 12)
			WorldArt.cyl(n, 0.33, 0.33, 0.06, Vector3(0, 0.44, 0), Color("b8532e"), 12)
			WorldArt.cyl(n, 0.26, 0.26, 0.04, Vector3(0, 0.46, 0), Color("3e2a1c"), 10)
			if WorldProps.has("nature", "plant_flatTall"):
				WorldProps.live_prop(n, "nature", "plant_flatTall", Vector3(0, 0.5, 0), 0.0, WorldProps.NATURE * 1.15, "none")
				WorldProps.live_prop(n, "nature", "grass_leafsLarge", Vector3(0.05, 0.5, 0.05), 1.2, WorldProps.NATURE * 0.8, "none")
			else:
				for k in 5:
					var a := TAU * k / 5.0
					WorldArt.sphere(n, 0.22, Vector3(cos(a) * 0.22, 0.75 + 0.08 * (k % 2), sin(a) * 0.22), Color("5fa052").lerp(Color("8fd36a"), k / 5.0), Vector3(1.0, 1.5, 0.6))
				WorldArt.sphere(n, 0.2, Vector3(0, 1.0, 0), Color("7fc46a"), Vector3(1, 1.4, 1))
		"lantern":
			# Brass lantern on a wooden stand.
			if not WorldProps.live_prop(n, "dungeon", "stool", Vector3.ZERO, 0.0, WorldProps.DUNGEON * 1.1, "box"):
				WorldArt.box(n, Vector3(0.55, 0.42, 0.55), Vector3(0, 0.21, 0), _warm_wood())
			var base_y := 0.44
			WorldArt.box(n, Vector3(0.44, 0.05, 0.44), Vector3(0, base_y + 0.025, 0), Color("b8862e"), Vector3.ZERO, 0.0)
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					WorldArt.box(n, Vector3(0.035, 0.5, 0.035), Vector3(sx * 0.17, base_y + 0.3, sz * 0.17), Color("8a6420"), Vector3.ZERO, 0.0)
			WorldArt.box(n, Vector3(0.32, 0.44, 0.32), Vector3(0, base_y + 0.29, 0), Color("fff0c0"), Vector3.ZERO, 0.0).material_override = WorldArt.mat(Color("ffe9a8"), 0.0, Color("ffb347"), 2.4)
			var cap := CylinderMesh.new()
			cap.top_radius = 0.1
			cap.bottom_radius = 0.3
			cap.height = 0.18
			cap.radial_segments = 4
			WorldArt.mesh_node(n, cap, Vector3(0, base_y + 0.62, 0), WorldArt.mat(Color("b8862e"), 0.02), Vector3(0, PI / 4, 0))
			var ring := TorusMesh.new()
			ring.inner_radius = 0.05
			ring.outer_radius = 0.08
			WorldArt.mesh_node(n, ring, Vector3(0, base_y + 0.78, 0), WorldArt.mat(Color("8a6420"), 0.0), Vector3(PI / 2, 0, 0))
			if not WorldArt.headless():
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.8, 0.5)
				l.light_energy = 0.7
				l.omni_range = 4.5
				l.shadow_enabled = false
				l.position = Vector3(0, base_y + 0.3, 0)
				n.add_child(l)
		"trophy":
			var stone := WorldArt.stone_mat(Color("8d86a6"), Color("746d8c"), "castle_brick_07", 0.45, {"band_period": 0.3, "band_width": 0.04, "brick_length": 0.45, "band_dark": 0.62})
			WorldArt.mesh_node(n, BoxMesh.new(), Vector3(0, 0.45, 0), stone, Vector3.ZERO, Vector3(0.9, 0.9, 0.9))
			WorldArt.mesh_node(n, BoxMesh.new(), Vector3(0, 0.95, 0), WorldArt.ruin_mat("ledge"), Vector3.ZERO, Vector3(1.05, 0.12, 1.05))
			WorldArt.mesh_node(n, BoxMesh.new(), Vector3(0, 0.05, 0), WorldArt.ruin_mat("ledge"), Vector3.ZERO, Vector3(1.05, 0.1, 1.05))
			WorldArt.rune_ring(n, Vector3(0, 1.02, 0), 0.42, Color("b06bff"), 0.05)
			var rock := WorldArt.sphere(n, 0.42, Vector3(0, 1.38, 0), Color("806b8c"), Vector3(1.2, 0.9, 1.0))
			rock.mesh = WorldArt.rock_mesh()
			rock.scale = Vector3(0.42, 0.34, 0.4)
			rock.material_override = WorldArt.stone_mat(Color("7d6a8c"), Color("5f5070"), "rock_wall_10", 0.8, {"detail_strength": 0.5, "rune_heights": Vector3(1.3, -10000, -10000), "rune_width": 0.12, "rune_strength": 1.2, "rune_color": Color("b06bff")})
			var shard := CylinderMesh.new()
			shard.top_radius = 0.0
			shard.bottom_radius = 0.12
			shard.height = 0.5
			shard.radial_segments = 4
			WorldArt.mesh_node(n, shard, Vector3(0.1, 1.72, 0), WorldArt.mat(Color("d6b4ff"), 0.0, Color("b06bff"), 3.0), Vector3(0.2, 0.4, 0))
			WorldArt.mesh_node(n, shard, Vector3(-0.18, 1.6, 0.12), WorldArt.mat(Color("d6b4ff"), 0.0, Color("b06bff"), 2.6), Vector3(-0.3, 0.9, 0.4), Vector3(0.6, 0.6, 0.6))
			var plaque := Label3D.new()
			plaque.text = "GRAVELMAW"
			plaque.font_size = 28
			plaque.outline_size = 8
			plaque.modulate = UITheme.GOLD
			plaque.position = Vector3(0, 0.62, 0.46)
			n.add_child(plaque)
			WorldArt.box(n, Vector3(0.5, 0.16, 0.02), Vector3(0, 0.62, 0.455), Color("2a2530"), Vector3.ZERO, 0.0)
			if not WorldArt.headless():
				var l := OmniLight3D.new()
				l.light_color = Color("b06bff")
				l.light_energy = 0.5
				l.omni_range = 3.0
				l.shadow_enabled = false
				l.position = Vector3(0, 1.7, 0)
				n.add_child(l)
			WorldArt.box_collider(n, Vector3(1.0, 1.1, 1.0), Vector3(0, 0.55, 0))


# --- Interaction ---------------------------------------------------------------

## What the player can use here: {"kind", "index", "label"} or {} when nothing.
func nearest(from: Vector3) -> Dictionary:
	if from.distance_to(door_pos) < 2.6:
		if GameState.home_owned:
			return {"kind": "door", "index": 0, "label": "Enter your cottage"}
		if _confirm_t > 0.0:
			return {"kind": "door", "index": 0, "label": "Buy the cottage for %d Col  (E again to confirm)" % LifeData.HOME_PRICE}
		return {"kind": "door", "index": 0, "label": "For Sale  ·  %d Col" % LifeData.HOME_PRICE}
	if from.distance_to(INTERIOR) > 12.0:
		return {}
	var best := {}
	var best_d := 99.0
	for cand in [["exit", INTERIOR + EXIT, 1.6, "Leave the cottage"], ["hearth", INTERIOR + HEARTH + Vector3(0, 0, 0.6), 2.1, "Cook at the hearth"],
			["bed", INTERIOR + BED, 1.9, "Sleep until morning" if not Net.online else "Rest a while"], ["chest", INTERIOR + CHEST, 1.8, "Open the storage chest"]]:
		var d: float = from.distance_to(cand[1])
		if d < cand[2] and d < best_d:
			best_d = d
			best = {"kind": cand[0], "index": 0, "label": cand[3]}
	for i in SLOTS.size():
		var d: float = from.distance_to(INTERIOR + SLOTS[i])
		if d < 1.4 and d < best_d:
			best_d = d
			var cur: String = GameState.home_furniture[i]
			var label := "Place a decoration (slot %d)" % (i + 1) if cur == "" else "Change %s (slot %d)" % [LifeData.DECOR[cur]["name"], i + 1]
			best = {"kind": "slot", "index": i, "label": label}
	return best


## Runs an interaction from `nearest()`. `player` is moved for door/exit.
## Returns a line for the HUD dialogue, or "" when the action spoke for itself.
func interact(hit: Dictionary, player: Node3D, hud: Node, world: Node3D) -> String:
	match hit.get("kind", ""):
		"door":
			if GameState.home_owned:
				Audio.play("door_open", door_pos)
				player.global_position = spawn_inside
				player.velocity = Vector3.ZERO
				if hud:
					hud.toast("Your cottage", "Hearth, bed, chest and %d furniture slots" % SLOTS.size(), "Home", UITheme.GOLD)
				return ""
			if _confirm_t > 0.0:
				_confirm_t = 0.0
				if GameState.buy_home(LifeData.HOME_PRICE):
					Audio.play("coins")
					Audio.play("quest_complete")
					if hud:
						hud.toast("Cottage purchased!", "Hollowbrook has a new neighbour. Step inside.", "Home", UITheme.GOLD)
					return ""
				Audio.play("craft_fail")
				return "You cannot afford the cottage yet (%d Col). Boars pay, and so does the fisher." % LifeData.HOME_PRICE
			_confirm_t = 6.0
			Audio.play("ui_tick")
			return "A snug cottage, hearth and all, for %d Col. Elder Wren says the roof is sound.\nPress E again to buy it." % LifeData.HOME_PRICE
		"exit":
			Audio.play("door_close", exit_pos)
			player.global_position = door_out + Vector3(0, 1, 0)
			player.velocity = Vector3.ZERO
			return ""
		"bed":
			var dn = world.get("day_night")
			if not Net.online and dn != null:
				dn.time_of_day = 7.0
				LifeData.rest()
				Audio.play("sleep")
				if hud:
					hud.toast("You sleep until morning", "Well Rested: %s" % LifeData.buff_text(LifeData.REST_BUFF), "Home", UITheme.CYAN)
			else:
				LifeData.rest()
				Audio.play("sleep")
				if hud:
					hud.toast("You rest a while", "Well Rested: %s" % LifeData.buff_text(LifeData.REST_BUFF), "Home", UITheme.CYAN)
			return ""
		"chest":
			if hud and hud.get("life") != null:
				hud.life.open_storage()
			return ""
		"hearth":
			if world.has_method("_open_cooking"):
				world._open_cooking("Your hearth")
			return ""
		"slot":
			return cycle_slot(int(hit.get("index", 0)), hud)
	return ""


## Steps a furniture slot through: empty -> each owned, unplaced decoration -> empty.
func cycle_slot(i: int, hud: Node = null) -> String:
	var cur: String = GameState.home_furniture[i]
	var options := [""]
	for id in LifeData.DECOR:
		if id == cur or GameState.decor_free(id) > 0:
			options.append(id)
	if options.size() == 1:
		Audio.play("ui_error")
		return "You own no decorations to place. Trader Pell in the town plaza sells rugs, shelves, plants and lanterns."
	var idx := options.find(cur)
	var next: String = options[(idx + 1) % options.size()]
	GameState.place_furniture(i, next)
	Audio.play("drop" if next != "" else "pickup", INTERIOR + SLOTS[i])
	if hud and hud.has_method("toast"):
		if next == "":
			hud.toast("Slot %d cleared" % (i + 1), "", "Decorate", UITheme.MUTED)
		else:
			hud.toast(LifeData.DECOR[next]["name"], "Slot %d  ·  E again to cycle" % (i + 1), "Decorate", UITheme.GOLD)
	return ""
