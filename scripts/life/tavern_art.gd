class_name TavernArt
extends RefCounted
## The Hollow Hearth's interior, built in code like the cottage: a timbered
## hall with plaster over a plank wainscot, the bar along the back wall
## (kegs, bottle shelves, Rook's spot behind it), a big stone hearth on the
## west wall, long tables with stools, a bard's corner by the door, the
## stairs up to the rooms on the east wall and the kitchen orders board at
## the bar end. Room-local layout comes from Tavern's constants. Everything
## a player can walk into has a box collider; KayKit dungeon props where the
## pack is present, plain boxes otherwise.

const TIMBER := Color("3e2a1c")
const TRIM := Color("4f3522")


static func build(t: Node3D, c: Vector3, room: Vector3) -> void:
	var hx := room.x * 0.5
	var hz := room.z * 0.5
	var plaster := WorldArt.plaster_mat(Color("ead9bd"), Color("dcc7a5"))
	var wainscot := WorldArt.wood_mat(Color("7c5a3a"), Color("664a30"), "wood_planks_grey", 0.24, 0, {"brick_length": 1.0})
	# Floor, ceiling and beams.
	_solid(t, Vector3(room.x, 0.4, room.z), c + Vector3(0, -0.2, 0), WorldArt.wood_mat(Color("8a6240"), Color("6e4c30"), "weathered_planks", 0.34, 0))
	WorldArt.mesh_node(t, _bm(Vector3(room.x, 0.3, room.z)), c + Vector3(0, room.y + 0.15, 0), WorldArt.wood_mat(Color("4e3a28"), Color("3f2e20"), "wood_planks_grey", 0.3, 1, {"brick_length": 3.2}))
	for k in 6:
		WorldArt.box(t, Vector3(room.x, 0.3, 0.3), c + Vector3(0, room.y - 0.15, -hz + 0.9 + k * 1.85), TIMBER, Vector3.ZERO, 0.0)
	# Walls: wainscot to 1.1 m, plaster above; the front wall has the door.
	for sz in [-1, 1]:
		var cuts := [[-0.8, 0.8, 0.0, 2.8]] if sz > 0 else []
		_wall(t, Vector3(c.x - hx, c.y, c.z + sz * (hz + 0.2)), Vector3(1, 0, 0), room.x, room.y, plaster, wainscot, cuts)
	for sx in [-1, 1]:
		_wall(t, Vector3(c.x + sx * (hx + 0.2), c.y, c.z - hz), Vector3(0, 0, 1), room.z, room.y, plaster, wainscot, [])
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			WorldArt.box(t, Vector3(0.32, room.y, 0.32), c + Vector3(sx * (hx - 0.14), room.y * 0.5, sz * (hz - 0.14)), TIMBER, Vector3.ZERO, 0.0)
	for x in [-3.6, 3.6]:
		for sz in [-1, 1]:
			WorldArt.box(t, Vector3(0.18, room.y - 1.1, 0.14), c + Vector3(x, 1.1 + (room.y - 1.1) * 0.5, sz * (hz - 0.08)), TIMBER, Vector3.ZERO, 0.0)
	for sz in [-1, 1]:
		WorldArt.box(t, Vector3(room.x, 0.1, 0.16), c + Vector3(0, 1.08, sz * (hz - 0.08)), TRIM, Vector3.ZERO, 0.0)
	for sx in [-1, 1]:
		WorldArt.box(t, Vector3(0.16, 0.1, room.z), c + Vector3(sx * (hx - 0.08), 1.08, 0), TRIM, Vector3.ZERO, 0.0)
	# Door (the exit) with frame and mat.
	var dp := c + Vector3(0, 0, hz)
	var door := WorldArt.box(t, Vector3(1.5, 2.7, 0.1), dp + Vector3(0, 1.35, -0.16), Color("6b4a2e"), Vector3.ZERO, 0.0)
	door.material_override = WorldArt.wood_mat(Color("6e4b2c"), Color("5c3e24"), "weathered_planks", 0.2, 0, {"brick_length": 2.6})
	for sx in [-1, 1]:
		WorldArt.box(t, Vector3(0.22, 2.95, 0.24), dp + Vector3(sx * 0.86, 1.47, -0.14), TRIM, Vector3.ZERO, 0.0)
	WorldArt.box(t, Vector3(1.95, 0.22, 0.26), dp + Vector3(0, 2.93, -0.14), TRIM, Vector3.ZERO, 0.0)
	WorldArt.box(t, Vector3(1.4, 0.04, 0.9), c + Tavern.EXIT + Vector3(0, 0.02, -0.1), Color("7a3a2e"), Vector3.ZERO, 0.0)
	_bar(t, c, hz)
	_hearth(t, c + Tavern.HEARTH, room)
	_tables(t, c)
	_stairs(t, c + Tavern.STAIRS, hx)
	_board(t, c + Tavern.BOARD)
	_bard_corner(t, c + Vector3(-4.8, 0, 3.4))
	# Hanging iron lamps over the tables and wall torches.
	if not WorldArt.headless():
		for lp in [Vector3(-2.2, room.y - 1.0, 1.0), Vector3(2.2, room.y - 1.0, 1.0), Vector3(0, room.y - 1.0, -1.8)]:
			WorldArt.cyl(t, 0.01, 0.01, 1.0, c + lp + Vector3(0, 0.5, 0), Color("2a2830"), 4)
			WorldArt.cyl(t, 0.16, 0.22, 0.24, c + lp, Color("2a2830"), 8)
			var l := OmniLight3D.new()
			l.light_color = Color("ffb366")
			l.light_energy = 1.1
			l.omni_range = 6.0
			l.shadow_enabled = false
			l.position = c + lp + Vector3(0, -0.2, 0)
			t.add_child(l)
		WorldArt.flame(t, c + Vector3(-2.2, room.y - 1.14, 1.0), 0.18, false)
		WorldArt.flame(t, c + Vector3(2.2, room.y - 1.14, 1.0), 0.18, false)
		WorldArt.flame(t, c + Vector3(0, room.y - 1.14, -1.8), 0.18, false)
	for tp in [[Vector3(-hx + 0.2, 2.3, 2.6), PI / 2], [Vector3(hx - 0.2, 2.3, -1.0), -PI / 2]]:
		if WorldProps.has("dungeon", "torch_mounted"):
			AssetLib.prop(t, "dungeon", "torch_mounted", c + tp[0], tp[1], WorldProps.DUNGEON, "none")


static func _bm(size: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return bm


## A box with a collider. `look` is a Color or a Material.
static func _solid(t: Node3D, size: Vector3, pos: Vector3, look) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mi := MeshInstance3D.new()
	var mesh := _bm(size)
	mesh.material = look if look is Material else WorldArt.mat(look, 0.02)
	mi.mesh = mesh
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	t.add_child(body)
	return body


## A wall strip from `origin` along `dir` (wainscot under plaster) with
## [a0, a1, y0, y1] openings measured from the strip's centre.
static func _wall(t: Node3D, origin: Vector3, dir: Vector3, length: float, height: float, plaster: Material, wainscot: Material, cuts: Array) -> void:
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
		for b in [[0.0, 1.1, wainscot], [1.1, height, plaster]]:
			var segs := [[b[0], b[1]]]
			if not open.is_empty():
				segs = []
				if open[2] > b[0]:
					segs.append([b[0], minf(open[2], b[1])])
				if open[3] < b[1]:
					segs.append([maxf(open[3], b[0]), b[1]])
			for sg in segs:
				if sg[1] - sg[0] < 0.01:
					continue
				var size := Vector3(a1 - a0, sg[1] - sg[0], 0.4) if dir.x != 0.0 else Vector3(0.4, sg[1] - sg[0], a1 - a0)
				_solid(t, size, origin + dir * ((a0 + a1) * 0.5) + Vector3(0, (sg[0] + sg[1]) * 0.5, 0), b[2])


## The bar: a long counter, Rook's side with kegs and bottle shelves.
static func _bar(t: Node3D, c: Vector3, hz: float) -> void:
	var top := WorldArt.wood_mat(Color("8c5e36"), Color("6e4628"), "weathered_planks", 0.2, 0, {"brick_length": 4.0})
	var front := WorldArt.wood_mat(Color("5e3e24"), Color("4a301c"), "wood_planks_grey", 0.18, 1, {"brick_length": 1.0})
	var bz := Tavern.COUNTER.z - 0.95
	_solid(t, Vector3(7.0, 1.05, 0.7), c + Vector3(0, 0.525, bz), front)
	WorldArt.mesh_node(t, _bm(Vector3(7.3, 0.08, 0.9)), c + Vector3(0, 1.09, bz), top)
	WorldArt.box(t, Vector3(7.0, 0.06, 0.08), c + Vector3(0, 0.2, bz + 0.38), Color("b08a3c"), Vector3.ZERO, 0.0)  # brass foot rail
	for sx in [-1, 1]:
		_solid(t, Vector3(0.7, 1.05, 1.2), c + Vector3(sx * 3.85, 0.525, bz - 0.25), front)
	# On the bar: mugs, a plate, candles, the order bell.
	for k in 4:
		WorldArt.cyl(t, 0.07, 0.06, 0.16, c + Vector3(-2.4 + k * 0.5, 1.21, bz + 0.1), Color("a07a4a"), 8)
	WorldArt.candle(t, c + Vector3(-1.0, 1.13, bz), 0.16, 0.035)
	WorldArt.candle(t, c + Vector3(2.6, 1.13, bz), 0.2, 0.04)
	WorldArt.cyl(t, 0.07, 0.11, 0.1, c + Vector3(0.6, 1.18, bz + 0.15), UITheme.GOLD, 10)
	if WorldProps.has("dungeon", "plate_food_A"):
		AssetLib.prop(t, "dungeon", "plate_food_A", c + Vector3(1.4, 1.13, bz), 0.4, WorldProps.DUNGEON * 0.8, "none")
	# Back wall: shelves of bottles and a rack of kegs.
	var wz := -hz + 0.35
	# Two plank shelves on iron brackets, bottles and jars along both.
	for y in [1.75, 2.42]:
		WorldArt.box(t, Vector3(6.6, 0.06, 0.34), c + Vector3(0, y, wz + 0.05), Color("5e3e24"), Vector3.ZERO, 0.0)
		for x in [-3.0, 0.0, 3.0]:
			WorldArt.box(t, Vector3(0.05, 0.22, 0.28), c + Vector3(x, y - 0.13, wz + 0.02), Color("2a2830"), Vector3.ZERO, 0.0)
		for k in 11:
			var bx := -3.0 + k * 0.6 + (0.12 if y > 2.0 else 0.0)
			var bc: Color = [Color("4a6a3a"), Color("6a3a2a"), Color("3a4a6a"), Color("8a6a2a"), Color("a07a4a")][(k + int(y * 10)) % 5]
			var bh := 0.26 if k % 3 != 2 else 0.18
			WorldArt.cyl(t, 0.045 if bh > 0.2 else 0.07, 0.065, bh, c + Vector3(bx, y + 0.03 + bh * 0.5, wz + 0.05), bc, 8)
	for k in 3:
		var kp := c + Vector3(-0.8 + k * 0.8, 0, wz + 0.1)
		if WorldProps.has("dungeon", "keg_decorated"):
			AssetLib.prop(t, "dungeon", "keg_decorated" if k == 1 else "keg", kp, 0.0, WorldProps.DUNGEON * 0.9, "box")
		else:
			WorldArt.cyl(t, 0.35, 0.35, 0.8, kp + Vector3(0, 0.4, 0), Color("6b4a2e"), 12, Vector3(PI / 2, 0, 0))
	if WorldProps.has("dungeon", "barrel_large"):
		AssetLib.prop(t, "dungeon", "barrel_large", c + Vector3(-3.7, 0, wz + 0.2), 0.3, WorldProps.DUNGEON, "box")
		AssetLib.prop(t, "dungeon", "barrel_small_stack", c + Vector3(3.7, 0, wz + 0.2), -0.2, WorldProps.DUNGEON, "box")
	if WorldProps.has("dungeon", "banner_patternB_red"):
		AssetLib.prop(t, "dungeon", "banner_patternB_red", c + Vector3(0, 2.6, -hz + 0.05), 0.0, WorldProps.DUNGEON * 0.7, "none")


## West-wall hearth: fieldstone surround, live fire (the room's warm light),
## the stew pot on its crane and a log pile.
static func _hearth(t: Node3D, hp: Vector3, room: Vector3) -> void:
	var stone := WorldArt.stone_mat(Color("8a8078"), Color("6a605a"), "rock_wall_10", 0.4, {"detail_strength": 0.5})
	# The hearth faces +x (into the room).
	_solid(t, Vector3(1.0, 1.7, 3.4), hp + Vector3(-0.35, 0.85, 0), stone)
	WorldArt.box(t, Vector3(0.75, 1.1, 1.8), hp + Vector3(0.0, 0.58, 0), Color("17121a"), Vector3.ZERO, 0.0)
	WorldArt.mesh_node(t, _bm(Vector3(1.3, 0.18, 3.8)), hp + Vector3(-0.2, 1.78, 0), stone)
	WorldArt.mesh_node(t, _bm(Vector3(0.9, room.y - 1.85, 2.6)), hp + Vector3(-0.45, 1.85 + (room.y - 1.85) * 0.5, 0), stone)
	WorldArt.box(t, Vector3(1.0, 0.1, 2.0), hp + Vector3(0.55, 0.05, 0), Color("2a2328"), Vector3.ZERO, 0.0)
	for k in 3:
		WorldArt.cyl(t, 0.1, 0.11, 0.9, hp + Vector3(0.15, 0.2 + (k % 2) * 0.12, -0.2 + k * 0.2), [Color("5a3a22"), Color("4a3020"), Color("6a4428")][k], 6, Vector3(PI / 2.1, 0.9 + k * 0.8, 0))
	WorldArt.flame(t, hp + Vector3(0.15, 0.24, 0), 0.75, false)
	WorldArt.cyl(t, 0.28, 0.22, 0.3, hp + Vector3(0.2, 0.7, 0.5), Color("34323b"), 12)
	WorldArt.cyl(t, 0.25, 0.25, 0.02, hp + Vector3(0.2, 0.86, 0.5), Color("b8743a"), 12)
	for k in 6:
		WorldArt.cyl(t, 0.1, 0.1, 0.65, hp + Vector3(0.5 + (k % 3) * 0.22, 0.1 + int(k / 3) * 0.2, 2.2), [Color("7a5a3a"), Color("6a4a2e")][k % 2], 7, Vector3(0, 0, PI / 2))
	if not WorldArt.headless():
		var fl := OmniLight3D.new()
		fl.name = "TavernHearthLight"
		fl.light_color = Color("ff9a4a")
		fl.light_energy = 3.0
		fl.omni_range = 11.0
		fl.omni_attenuation = 1.1
		fl.shadow_enabled = false
		fl.position = hp + Vector3(1.2, 1.0, 0)
		t.add_child(fl)
		var tw := fl.create_tween().set_loops()
		tw.tween_property(fl, "light_energy", 2.6, 0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(fl, "light_energy", 3.2, 0.33).set_trans(Tween.TRANS_SINE)
		tw.tween_property(fl, "light_energy", 3.0, 0.28).set_trans(Tween.TRANS_SINE)
	if WorldProps.has("dungeon", "sword_shield"):
		AssetLib.prop(t, "dungeon", "sword_shield", hp + Vector3(0.05, 2.9, 0), PI / 2, WorldProps.DUNGEON * 0.65, "none")


## Three long tables with stools, plates and candles.
static func _tables(t: Node3D, c: Vector3) -> void:
	for tp in [Vector3(-2.2, 0, 1.0), Vector3(2.2, 0, 1.0), Vector3(-2.6, 0, 3.4) + Vector3(5.0, 0, 0)]:
		var p: Vector3 = c + tp
		if WorldProps.has("dungeon", "table_long"):
			AssetLib.prop(t, "dungeon", "table_long_decorated_A" if tp.x < 0 else "table_long", p, 0.0, WorldProps.DUNGEON, "box")
		else:
			_solid(t, Vector3(2.4, 0.8, 1.0), p + Vector3(0, 0.4, 0), Color("7a5534"))
		for sx in [-0.7, 0.7]:
			for sz in [-1, 1]:
				var sp := p + Vector3(sx, 0, sz * 0.85)
				if WorldProps.has("dungeon", "stool"):
					AssetLib.prop(t, "dungeon", "stool", sp, sx * 0.3, WorldProps.DUNGEON, "box")
				else:
					WorldArt.cyl(t, 0.2, 0.2, 0.45, sp + Vector3(0, 0.22, 0), Color("6b4a2e"), 8)
		WorldArt.candle(t, p + Vector3(0.3, 0.82, 0.0), 0.16, 0.035)
		WorldArt.cyl(t, 0.07, 0.06, 0.16, p + Vector3(-0.5, 0.9, 0.2), Color("a07a4a"), 8)


## Stairs up to the rooms (blocked at the landing) on the east wall.
static func _stairs(t: Node3D, sp: Vector3, hx: float) -> void:
	var tread := WorldArt.wood_mat(Color("7a5534"), Color("604228"), "weathered_planks", 0.2, 0)
	var wall_x := sp.x - Tavern.STAIRS.x + hx  # world x of the east wall
	for k in 8:
		var h := 0.3 * (k + 1)
		_solid(t, Vector3(1.2, h, 0.42), Vector3(wall_x - 0.7, sp.y + h * 0.5, sp.z - 0.6 - k * 0.42), tread)
	_solid(t, Vector3(1.2, 0.2, 1.2), Vector3(wall_x - 0.7, sp.y + 2.4, sp.z - 4.3), tread)
	WorldArt.box(t, Vector3(1.0, 2.0, 0.1), Vector3(wall_x - 0.7, sp.y + 3.4, sp.z - 4.95), Color("5c3e24"), Vector3.ZERO, 0.0)
	# A key rack and a little sign at the foot of the stairs.
	var s := Label3D.new()
	s.text = "Rooms · %d Col" % Tavern.ROOM_PRICE
	s.font_size = 36
	s.pixel_size = 0.005
	s.outline_size = 8
	s.modulate = Color("f3eee4")
	s.position = Vector3(wall_x - 0.15, sp.y + 1.7, sp.z)
	s.rotation.y = -PI / 2
	t.add_child(s)
	if WorldProps.has("dungeon", "keyring_hanging"):
		AssetLib.prop(t, "dungeon", "keyring_hanging", Vector3(wall_x - 0.1, sp.y + 1.3, sp.z + 0.6), -PI / 2, WorldProps.DUNGEON * 0.8, "none")


## The kitchen orders board: a framed cork board with pinned slips.
static func _board(t: Node3D, bp: Vector3) -> void:
	WorldArt.box(t, Vector3(0.1, 1.9, 0.1), bp + Vector3(-0.5, 0.95, -0.5), TIMBER, Vector3.ZERO, 0.0)
	WorldArt.box(t, Vector3(0.1, 1.9, 0.1), bp + Vector3(0.5, 0.95, -0.5), TIMBER, Vector3.ZERO, 0.0)
	WorldArt.box(t, Vector3(1.2, 0.9, 0.08), bp + Vector3(0, 1.45, -0.5), Color("a07a50"), Vector3.ZERO, 0.0)
	for k in Tavern.ORDERS_PER_SHIFT:
		WorldArt.box(t, Vector3(0.28, 0.34, 0.02), bp + Vector3(-0.36 + k * 0.36, 1.48, -0.45), Color("f3eee4"), Vector3(0, 0, (k - 1) * 0.08), 0.0)
		WorldArt.sphere(t, 0.025, bp + Vector3(-0.36 + k * 0.36, 1.63, -0.44), Color("c4262e"))
	var s := Label3D.new()
	s.text = "Kitchen orders"
	s.font_size = 32
	s.pixel_size = 0.005
	s.outline_size = 8
	s.modulate = Color("f0c060")
	s.position = bp + Vector3(0, 2.05, -0.5)
	t.add_child(s)
	WorldArt.candle(t, bp + Vector3(0.75, 1.0, -0.4), 0.2, 0.04)
	if not WorldArt.headless():
		var l := OmniLight3D.new()
		l.light_color = Color("ffb366")
		l.light_energy = 0.9
		l.omni_range = 3.5
		l.shadow_enabled = false
		l.position = bp + Vector3(0.4, 1.9, 0.4)
		t.add_child(l)


## The bard's corner: a low dais, a stool, a lute-ish silhouette and candles.
static func _bard_corner(t: Node3D, bp: Vector3) -> void:
	_solid(t, Vector3(2.2, 0.2, 1.8), bp + Vector3(0, 0.1, 0), WorldArt.wood_mat(Color("6e4b2c"), Color("5c3e24"), "weathered_planks", 0.2, 0))
	if WorldProps.has("dungeon", "stool"):
		AssetLib.prop(t, "dungeon", "stool", bp + Vector3(0, 0.2, -0.2), 0.4, WorldProps.DUNGEON, "none")
	var body := WorldArt.sphere(t, 0.22, bp + Vector3(0.4, 0.75, 0.3), Color("a9653a"), Vector3(1.0, 1.25, 0.4))
	body.rotation.z = 0.5
	WorldArt.box(t, Vector3(0.06, 0.6, 0.04), bp + Vector3(0.62, 1.12, 0.3), Color("4a301c"), Vector3(0, 0, 0.5), 0.0)
	WorldArt.candle(t, bp + Vector3(-0.8, 0.2, 0.6), 0.22, 0.04)
	WorldArt.candle(t, bp + Vector3(-0.6, 0.2, 0.75), 0.14, 0.035)
