class_name SmithyArt
extends RefCounted
## Hollowbrook Forge's workshop, in code (shares TavernArt's wall and
## collider helpers): stone floor, timber and plaster walls, the coal forge
## with its hood and bellows on the back wall, the anvil on a stump, a quench
## trough, weapon racks, an ore pile and the commission board.

static func build(t: Node3D, c: Vector3, room: Vector3) -> void:
	var hx := room.x * 0.5
	var hz := room.z * 0.5
	var plaster := WorldArt.plaster_mat(Color("d9cbb4"), Color("c8b89e"))
	var wainscot := WorldArt.stone_mat(Color("7c746c"), Color("625b55"), "castle_brick_07", 0.4, {"band_period": 0.28, "band_width": 0.03, "brick_length": 0.6})
	TavernArt._solid(t, Vector3(room.x, 0.4, room.z), c + Vector3(0, -0.2, 0), WorldArt.stone_mat(Color("6e6862"), Color("57524d"), "castle_brick_07", 0.3, {"band_period": 0.5, "band_width": 0.04, "brick_length": 0.5}))
	WorldArt.mesh_node(t, TavernArt._bm(Vector3(room.x, 0.3, room.z)), c + Vector3(0, room.y + 0.15, 0), WorldArt.wood_mat(Color("3e2e22"), Color("33261c"), "wood_planks_grey", 0.3, 1, {"brick_length": 3.2}))
	for k in 5:
		WorldArt.box(t, Vector3(room.x, 0.3, 0.3), c + Vector3(0, room.y - 0.15, -hz + 1.0 + k * 2.0), TavernArt.TIMBER, Vector3.ZERO, 0.0)
	for sz in [-1, 1]:
		var cuts := [[-0.8, 0.8, 0.0, 2.8]] if sz > 0 else []
		TavernArt._wall(t, Vector3(c.x - hx, c.y, c.z + sz * (hz + 0.2)), Vector3(1, 0, 0), room.x, room.y, plaster, wainscot, cuts)
	for sx in [-1, 1]:
		TavernArt._wall(t, Vector3(c.x + sx * (hx + 0.2), c.y, c.z - hz), Vector3(0, 0, 1), room.z, room.y, plaster, wainscot, [])
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			WorldArt.box(t, Vector3(0.32, room.y, 0.32), c + Vector3(sx * (hx - 0.14), room.y * 0.5, sz * (hz - 0.14)), TavernArt.TIMBER, Vector3.ZERO, 0.0)
	var dp := c + Vector3(0, 0, hz)
	WorldArt.box(t, Vector3(1.5, 2.7, 0.1), dp + Vector3(0, 1.35, -0.16), Color("5c3e24"), Vector3.ZERO, 0.0)
	for sx in [-1, 1]:
		WorldArt.box(t, Vector3(0.22, 2.95, 0.24), dp + Vector3(sx * 0.86, 1.47, -0.14), TavernArt.TRIM, Vector3.ZERO, 0.0)
	_forge(t, c + Smithy.FORGE, room)
	_anvil(t, c + Smithy.ANVIL)
	# Quench trough by the anvil.
	TavernArt._solid(t, Vector3(1.4, 0.6, 0.6), c + Vector3(2.6, 0.3, -2.4), Color("4a3a2a"))
	WorldArt.box(t, Vector3(1.25, 0.04, 0.45), c + Vector3(2.6, 0.58, -2.4), Color("2f4f5f"), Vector3.ZERO, 0.0)
	# Racks of finished blades and shields on the west wall.
	for k in 4:
		var rp := c + Vector3(-hx + 0.3, 1.2, -2.6 + k * 1.2)
		WorldArt.box(t, Vector3(0.08, 1.6, 0.06), rp + Vector3(0, 0.2, 0), Color("9aa0a8"), Vector3(0, 0, 0.12 * (k % 2 * 2 - 1)), 0.0)
		WorldArt.box(t, Vector3(0.1, 0.06, 0.3), rp + Vector3(0, -0.45, 0), Color("6b4a2e"), Vector3.ZERO, 0.0)
	WorldArt.box(t, Vector3(0.12, 0.1, 5.0), c + Vector3(-hx + 0.25, 0.5, -0.8), TavernArt.TIMBER, Vector3.ZERO, 0.0)
	if WorldProps.has("dungeon", "sword_shield"):
		AssetLib.prop(t, "dungeon", "sword_shield", c + Vector3(-hx + 0.1, 2.9, 1.8), PI / 2, WorldProps.DUNGEON * 0.7, "none")
	# Ore pile and crates on the east side, a workbench by the board.
	for k in 7:
		WorldArt.sphere(t, 0.22 + 0.04 * (k % 3), c + Vector3(hx - 1.0 + (k % 3) * 0.25, 0.15 + int(k / 3) * 0.18, -3.6 + (k % 2) * 0.3), Color("6e5a4a"))
	if WorldProps.has("dungeon", "crates_stacked"):
		AssetLib.prop(t, "dungeon", "crates_stacked", c + Vector3(hx - 0.9, 0, -1.6), 0.2, WorldProps.DUNGEON, "box")
	else:
		TavernArt._solid(t, Vector3(1.0, 1.0, 1.0), c + Vector3(hx - 0.9, 0.5, -1.6), Color("7a5534"))
	TavernArt._solid(t, Vector3(0.8, 0.9, 2.0), c + Vector3(hx - 0.6, 0.45, 3.2), Color("6b4a2e"))
	for k in 3:
		WorldArt.box(t, Vector3(0.3, 0.05, 0.08), c + Vector3(hx - 0.6, 0.93, 2.6 + k * 0.5), Color("3b3b44"), Vector3(0, 0.4 * k, 0), 0.0)
	_board(t, c + Smithy.BOARD)
	if not WorldArt.headless():
		var l := OmniLight3D.new()
		l.light_color = Color("ffc98a")
		l.light_energy = 0.8
		l.omni_range = 7.0
		l.shadow_enabled = false
		l.position = c + Vector3(2.0, room.y - 1.0, 1.5)
		t.add_child(l)


## The coal forge: a brick hearth with a glowing bed, a hood and chimney,
## and a leather bellows on the side.
static func _forge(t: Node3D, fp: Vector3, room: Vector3) -> void:
	var brick := WorldArt.stone_mat(Color("7a5a4c"), Color("5e463c"), "castle_brick_07", 0.45, {"band_period": 0.22, "band_width": 0.035, "brick_length": 0.45})
	TavernArt._solid(t, Vector3(2.6, 0.9, 1.4), fp + Vector3(0, 0.45, 0), brick)
	var coals := WorldArt.box(t, Vector3(1.6, 0.06, 0.8), fp + Vector3(0, 0.93, 0.05), Color("ff6a1a"), Vector3.ZERO, 0.0)
	coals.material_override = WorldArt.mat(Color("ff6a1a"), 0.0, Color("ff5a10"), 2.2)
	WorldArt.flame(t, fp + Vector3(0, 0.98, 0.05), 0.45, false)
	WorldArt.mesh_node(t, TavernArt._bm(Vector3(2.4, 0.9, 1.3)), fp + Vector3(0, 2.6, -0.05), brick)
	WorldArt.mesh_node(t, TavernArt._bm(Vector3(1.0, room.y - 3.0, 0.9)), fp + Vector3(0, 3.05 + (room.y - 3.05) * 0.5, -0.2), brick)
	# Bellows: two boards and a leather bag, a nozzle into the hearth.
	var bp := fp + Vector3(-1.75, 0.75, 0.1)
	WorldArt.box(t, Vector3(0.9, 0.05, 0.5), bp + Vector3(0, 0.18, 0), Color("6b4a2e"), Vector3(0, 0, 0.12), 0.0)
	WorldArt.box(t, Vector3(0.9, 0.05, 0.5), bp + Vector3(0, -0.12, 0), Color("6b4a2e"), Vector3.ZERO, 0.0)
	WorldArt.sphere(t, 0.3, bp + Vector3(0.05, 0.03, 0), Color("6a4a32"), Vector3(1.4, 0.4, 0.8))
	WorldArt.cyl(t, 0.04, 0.06, 0.5, bp + Vector3(0.6, 0.0, 0), Color("3b3b44"), 6, Vector3(0, 0, PI / 2))
	TavernArt._solid(t, Vector3(0.4, 0.6, 0.4), bp + Vector3(0, -0.45, 0), Color("4a3422"))
	if not WorldArt.headless():
		var l := OmniLight3D.new()
		l.name = "ForgeLight"
		l.light_color = Color("ff7a2a")
		l.light_energy = 3.2
		l.omni_range = 10.0
		l.omni_attenuation = 1.1
		l.shadow_enabled = false
		l.position = fp + Vector3(0, 1.4, 1.2)
		t.add_child(l)
		var tw := l.create_tween().set_loops()
		tw.tween_property(l, "light_energy", 2.7, 0.4).set_trans(Tween.TRANS_SINE)
		tw.tween_property(l, "light_energy", 3.4, 0.5).set_trans(Tween.TRANS_SINE)


static func _anvil(t: Node3D, ap: Vector3) -> void:
	TavernArt._solid(t, Vector3(0.6, 0.55, 0.6), ap + Vector3(0, 0.275, 0), Color("5a3f2a"))
	WorldArt.box(t, Vector3(0.9, 0.22, 0.34), ap + Vector3(0, 0.7, 0), Color("3b3b44"), Vector3.ZERO, 0.02)
	WorldArt.box(t, Vector3(0.4, 0.16, 0.26), ap + Vector3(0, 0.57, 0), Color("34343c"), Vector3.ZERO, 0.0)
	WorldArt.cyl(t, 0.02, 0.12, 0.35, ap + Vector3(0.6, 0.72, 0), Color("3b3b44"), 8, Vector3(0, 0, -PI / 2))
	# Hammer and tongs on the anvil face.
	WorldArt.box(t, Vector3(0.05, 0.05, 0.4), ap + Vector3(-0.15, 0.84, 0.0), Color("6b4a2e"), Vector3(0, 0.5, 0), 0.0)
	WorldArt.box(t, Vector3(0.16, 0.08, 0.08), ap + Vector3(-0.05, 0.85, 0.16), Color("2a2830"), Vector3(0, 0.5, 0), 0.0)


static func _board(t: Node3D, bp: Vector3) -> void:
	for sx in [-0.55, 0.55]:
		WorldArt.box(t, Vector3(0.1, 1.9, 0.1), bp + Vector3(sx, 0.95, 0.5), TavernArt.TIMBER, Vector3.ZERO, 0.0)
	WorldArt.box(t, Vector3(1.3, 0.9, 0.08), bp + Vector3(0, 1.45, 0.5), Color("8a6a48"), Vector3.ZERO, 0.0)
	for k in 3:
		WorldArt.box(t, Vector3(0.3, 0.36, 0.02), bp + Vector3(-0.4 + k * 0.4, 1.47, 0.45), Color("efe6d2"), Vector3(0, 0, (k - 1) * 0.07), 0.0)
		WorldArt.box(t, Vector3(0.12, 0.04, 0.02), bp + Vector3(-0.4 + k * 0.4, 1.6, 0.44), Color("3b3b44"), Vector3.ZERO, 0.0)
	var s := Label3D.new()
	s.text = "Commissions"
	s.font_size = 32
	s.pixel_size = 0.005
	s.outline_size = 8
	s.modulate = Color("ff9a4a")
	s.position = bp + Vector3(0, 2.05, 0.5)
	s.rotation.y = PI
	t.add_child(s)
