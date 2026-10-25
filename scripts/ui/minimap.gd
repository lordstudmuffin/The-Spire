class_name Minimap
extends Control
## Stylised 2D map drawn from MapData (no render-to-texture). Two modes:
##   compact - circular minimap, rotates with the camera, player at centre
##   full    - north-up island map with labels and a legend-friendly API
## Dots: enemies (group "enemies"), other players ("players"), NPCs ("npcs"),
## ore veins ("ore_veins"). Node lists are rescanned every 0.5 s; positions
## are read live. Nothing is allocated per frame except label strings.

const RING := 6.0
const ISLAND_FILL := Color("1f3b2e")
const ISLAND_EDGE := Color("6fbf5a")
const FIELD_LINE := Color(1, 1, 1, 0.05)

var full := false
var view_radius := 55.0  # world units from centre to the ring (compact mode)
var tracked_giver := ""  # NPC name to highlight (quest turn-in)
var player_pos := Vector2.ZERO
var yaw := 0.0
var _player: Node3D
var _enemies: Array = []
var _players: Array = []
var _npcs: Array = []
var _veins: Array = []
var _scan_t := 0.0
var _canvas: Control
var _overlay: Control
var _font: Font
var _font_b: Font
var _xf := Transform2D.IDENTITY
var _scale := 1.0
var _tri := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _tri3 := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _hex := PackedVector2Array()
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_canvas)
	add_child(_canvas)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_font = UITheme.ui_font()
	_font_b = UITheme.ui_bold()
	_hex.resize(6)
	for i in 6:
		_hex[i] = Vector2(cos(i * TAU / 6.0), sin(i * TAU / 6.0))


func zoom(factor: float) -> void:
	view_radius = clampf(view_radius * factor, 22.0, 120.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_scan_t -= delta
	if _scan_t <= 0.0 or _player == null or not is_instance_valid(_player):
		_scan_t = 0.5
		_rescan()
	if _player != null and is_instance_valid(_player):
		var p := _player.global_position
		player_pos = Vector2(p.x, p.z)
		if "cam_pivot" in _player and _player.cam_pivot != null:
			yaw = _player.cam_pivot.rotation.y
	queue_redraw()
	_canvas.queue_redraw()
	_overlay.queue_redraw()


func _rescan() -> void:
	var tree := get_tree()
	if tree == null:
		return
	_player = tree.get_first_node_in_group("player") as Node3D
	_enemies = tree.get_nodes_in_group("enemies")
	_players = tree.get_nodes_in_group("players")
	_npcs = tree.get_nodes_in_group("npcs")
	_veins = tree.get_nodes_in_group("ore_veins")


func _radius() -> float:
	return minf(size.x, size.y) * 0.5


## Backdrop disc; children are clipped to it.
func _draw() -> void:
	var c := size * 0.5
	var r := _radius()
	draw_circle(c, r, Color(UITheme.NAVY.r, UITheme.NAVY.g, UITheme.NAVY.b, 0.82 if not full else 0.96))


func _update_xf() -> void:
	var c := size * 0.5
	var r := _radius() - RING
	if full:
		_scale = r / (MapData.island_radius() + 6.0)
		_xf = Transform2D(0.0, Vector2.ONE * _scale, 0.0, c)
	else:
		_scale = r / view_radius
		_xf = Transform2D(yaw, Vector2.ONE * _scale, 0.0, c) * Transform2D(0.0, -player_pos)


func _draw_canvas() -> void:
	_update_xf()
	var ci := _canvas
	ci.draw_set_transform_matrix(_xf)
	var px := 1.0 / _scale  # one screen pixel in world units
	# Island and the void around it.
	var ir := MapData.island_radius()
	ci.draw_circle(Vector2.ZERO, ir, ISLAND_FILL)
	ci.draw_arc(Vector2.ZERO, ir, 0.0, TAU, 96, Color(ISLAND_EDGE.r, ISLAND_EDGE.g, ISLAND_EDGE.b, 0.55), 2.0 * px, true)
	# Faint range rings so distance reads at a glance (compact) / grid (full).
	if full:
		for i in range(1, 4):
			ci.draw_arc(Vector2.ZERO, ir * i / 4.0, 0.0, TAU, 64, FIELD_LINE, px, true)
		ci.draw_line(Vector2(-ir, 0), Vector2(ir, 0), FIELD_LINE, px)
		ci.draw_line(Vector2(0, -ir), Vector2(0, ir), FIELD_LINE, px)
	else:
		ci.draw_arc(player_pos, view_radius * 0.5, 0.0, TAU, 48, Color(1, 1, 1, 0.06), px, true)
	# Landmarks: areas first, points on top.
	for l in MapData.landmarks():
		var col := MapData.kind_color(l["kind"])
		var p: Vector2 = l["pos"]
		var lr: float = l["radius"]
		match l["kind"]:
			"town":
				ci.draw_circle(p, lr, Color(col.r, col.g, col.b, 0.10))
				ci.draw_arc(p, lr, 0.0, TAU, 64, Color(col.r, col.g, col.b, 0.75), 2.0 * px, true)
			"village", "camp":
				ci.draw_circle(p, lr, Color(col.r, col.g, col.b, 0.12))
				ci.draw_arc(p, lr, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.6), 1.5 * px, true)
				_hexagon(ci, p, 3.0 * px * (1.2 if full else 1.0), col)
			"water":
				ci.draw_circle(p, lr, Color(col.r, col.g, col.b, 0.35))
				ci.draw_arc(p, lr, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.7), px, true)
			"tower":
				ci.draw_circle(p, lr, Color(col.r, col.g, col.b, 0.18))
				_hexagon(ci, p, 6.0 * px, col)
				_hexagon(ci, p, 3.0 * px, UITheme.NAVY)
			"gate":
				ci.draw_arc(p, lr, 0.0, TAU, 24, col, 1.5 * px, true)
			"smith", "market", "farm", "board":
				ci.draw_circle(p, 2.0 * px, col)
	# Ore veins (visible = mineable).
	for v in _veins:
		if is_instance_valid(v) and v.visible:
			var gp: Vector3 = v.global_position
			ci.draw_circle(Vector2(gp.x, gp.z), 2.2 * px, UITheme.GOLD)
	# NPCs.
	for n in _npcs:
		if not is_instance_valid(n):
			continue
		var gp: Vector3 = n.global_position
		var np := Vector2(gp.x, gp.z)
		var is_tracked: bool = tracked_giver != "" and "npc_name" in n and n.npc_name == tracked_giver
		if is_tracked:
			var pulse := 4.0 + 2.0 * sin(_t * 5.0)
			ci.draw_arc(np, pulse * px, 0.0, TAU, 24, UITheme.GOLD, 1.5 * px, true)
		_diamond(ci, np, 3.0 * px, UITheme.GOLD if is_tracked else UITheme.PARCH)
	# Enemies: red dots, boss gets a ring.
	for e in _enemies:
		if not is_instance_valid(e) or not e.visible:
			continue
		var gp: Vector3 = e.global_position
		var ep := Vector2(gp.x, gp.z)
		if "is_boss" in e and e.is_boss:
			ci.draw_circle(ep, 5.0 * px, Color(UITheme.ROSE.r, UITheme.ROSE.g, UITheme.ROSE.b, 0.35))
			ci.draw_arc(ep, 5.0 * px, 0.0, TAU, 20, UITheme.ROSE, 1.5 * px, true)
			ci.draw_circle(ep, 2.5 * px, UITheme.ROSE)
		else:
			ci.draw_circle(ep, 2.4 * px, Color("ff6b6b"))
	# Other players: cyan; party members (Net.party_ids) green and larger.
	for pl in _players:
		if not is_instance_valid(pl) or pl == _player:
			continue
		var gp: Vector3 = pl.global_position
		var pp := Vector2(gp.x, gp.z)
		if Net.party_ids.has(int(pl.get("peer_id"))):
			ci.draw_circle(pp, 5.5 * px, Color(UITheme.GREEN.r, UITheme.GREEN.g, UITheme.GREEN.b, 0.35))
			ci.draw_circle(pp, 3.2 * px, UITheme.GREEN)
			continue
		ci.draw_circle(pp, 4.0 * px, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.35))
		ci.draw_circle(pp, 2.6 * px, UITheme.CYAN)
	# Player arrow (full mode only; compact draws it in the overlay at centre).
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	if full:
		var sp := _xf * player_pos
		_arrow(ci, sp, -yaw, 12.0, Color(0, 0, 0, 0.6))
		_arrow(ci, sp, -yaw, 10.0, UITheme.GOLD)
		# Labels.
		for l in MapData.landmarks():
			if l["kind"] in ["gate", "smith", "board"]:
				continue
			var lp := _xf * (l["pos"] as Vector2)
			var col := MapData.kind_color(l["kind"])
			var sz := 15 if l["kind"] in ["town", "tower"] else 12
			var w := _font_b.get_string_size(l["label"], HORIZONTAL_ALIGNMENT_CENTER, -1, sz).x
			var at := lp + Vector2(-w * 0.5, float(l["radius"]) * _scale + sz + 2.0)
			ci.draw_string_outline(_font_b, at, l["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, 0.8))
			ci.draw_string(_font_b, at, l["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
		for pl in _players:
			if not is_instance_valid(pl) or pl == _player or not ("display_name" in pl):
				continue
			var gp: Vector3 = pl.global_position
			var lp := _xf * Vector2(gp.x, gp.z) + Vector2(7, 4)
			ci.draw_string_outline(_font_b, lp, str(pl.display_name), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.8))
			ci.draw_string(_font_b, lp, str(pl.display_name), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.GREEN if Net.party_ids.has(int(pl.get("peer_id"))) else UITheme.CYAN)
		var you := "You  ·  " + MapData.place_name(player_pos)
		var yp := sp + Vector2(12, -8)
		ci.draw_string_outline(_font_b, yp, you, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
		ci.draw_string(_font_b, yp, you, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.GOLD)


func _draw_overlay() -> void:
	var ci := _overlay
	var c := size * 0.5
	var r := _radius()
	# Inner vignette and frame rings.
	ci.draw_arc(c, r - RING - 1.0, 0.0, TAU, 96, Color(0, 0, 0, 0.35), 3.0, true)
	ci.draw_arc(c, r - 1.5, 0.0, TAU, 96, UITheme.GOLD, 2.0, true)
	ci.draw_arc(c, r - RING, 0.0, TAU, 96, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.35), 1.0, true)
	if not full:
		# Edge chevrons for places beyond the ring.
		for l in MapData.landmarks():
			if not (l["kind"] in ["town", "village", "camp", "tower"]):
				continue
			var d: Vector2 = (l["pos"] as Vector2) - player_pos
			if d.length() - float(l["radius"]) <= view_radius:
				continue
			var dir := d.rotated(yaw).normalized()
			var at := c + dir * (r - RING - 7.0)
			_arrow(ci, at, dir.angle() + PI / 2, 6.0, MapData.kind_color(l["kind"]))
		# Player arrow at the centre, pointing up (camera forward).
		ci.draw_circle(c, 9.0, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.22))
		_arrow(ci, c, 0.0, 11.0, Color(0, 0, 0, 0.6))
		_arrow(ci, c, 0.0, 9.0, UITheme.GOLD)
	# North marker on the rim.
	var north := Vector2(0, -1).rotated(yaw) if not full else Vector2(0, -1)
	var np := c + north * (r - RING - 4.0)
	ci.draw_circle(np, 9.0, UITheme.NAVY)
	ci.draw_arc(np, 9.0, 0.0, TAU, 24, UITheme.GOLD, 1.5, true)
	ci.draw_string(_font_b, np + Vector2(-4.5, 4.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.GOLD)


func _arrow(ci: CanvasItem, at: Vector2, angle: float, s: float, col: Color) -> void:
	_tri[0] = at + Vector2(0, -s).rotated(angle)
	_tri[1] = at + Vector2(s * 0.7, s * 0.8).rotated(angle)
	_tri[2] = at + Vector2(0, s * 0.4).rotated(angle)
	_tri[3] = at + Vector2(-s * 0.7, s * 0.8).rotated(angle)
	ci.draw_colored_polygon(_tri, col)


func _hexagon(ci: CanvasItem, at: Vector2, s: float, col: Color) -> void:
	for i in 6:
		_tri3[0] = at
		_tri3[1] = at + _hex[i] * s
		_tri3[2] = at + _hex[(i + 1) % 6] * s
		ci.draw_colored_polygon(_tri3, col)


func _diamond(ci: CanvasItem, at: Vector2, s: float, col: Color) -> void:
	_tri[0] = at + Vector2(0, -s)
	_tri[1] = at + Vector2(s, 0)
	_tri[2] = at + Vector2(0, s)
	_tri[3] = at + Vector2(-s, 0)
	ci.draw_colored_polygon(_tri, col)


## Distance (m) from the player to a landmark, for legends.
func distance_to(p: Vector2) -> float:
	return player_pos.distance_to(p)
