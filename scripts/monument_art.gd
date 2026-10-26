class_name MonumentArt
extends Node3D
## The Monument of Climbers in front of the Hall of Iron: a black stone slab on
## a stepped plinth with the realm's players inscribed in two columns.
## Names glow while their player is in the realm and turn gold once they
## have cleared Floor 1. Gameplay feeds it through the "monument" group:
## set_names([{name, level, floors, online}, ...]), sorted by level then
## name, about every 20 s and on joins. Original procedural art.

const ROWS := 12
const COLS := 2
const SLAB := Vector3(3.4, 3.0, 0.4)
const ROW_H := 0.19
const ONLINE := Color(0.82, 0.95, 1.0)
const OFFLINE := Color(0.62, 0.66, 0.74, 0.55)
const CLEARED := Color(1.0, 0.84, 0.45)
const GLOW := Color(0.3, 0.7, 1.0, 0.8)

var _rows: Array[Label3D] = []
var _count: Label3D


static func make(parent: Node3D, pos: Vector3, rot_y := 0.0) -> MonumentArt:
	var m := MonumentArt.new()
	m.name = "MonumentArt"
	m.position = pos
	m.rotation.y = rot_y
	parent.add_child(m)
	return m


func _ready() -> void:
	add_to_group("monument")
	var trim := WorldArt.stone_mat(Color("51535f"), Color("434551"), "rock_wall_10", 0.3, {"detail_strength": 0.4})
	for k in 2:
		var step := BoxMesh.new()
		step.size = Vector3(SLAB.x + 1.2 - k * 0.5, 0.28, SLAB.z + 1.3 - k * 0.5)
		WorldArt.mesh_node(self, step, Vector3(0, 0.14 + k * 0.28, 0), trim)
	var slab := BoxMesh.new()
	slab.size = SLAB
	var y0 := 0.56
	WorldArt.mesh_node(self, slab, Vector3(0, y0 + SLAB.y * 0.5, 0), WorldArt.mat(Color("16181f"), 0.03, Color("0c1a2e"), 0.4))
	# Bevelled iron frame and a pointed cap.
	for sx in [-1.0, 1.0]:
		var side := BoxMesh.new()
		side.size = Vector3(0.16, SLAB.y + 0.1, SLAB.z + 0.12)
		WorldArt.mesh_node(self, side, Vector3(sx * (SLAB.x * 0.5 + 0.05), y0 + SLAB.y * 0.5, 0), trim)
	var cap := PrismMesh.new()
	cap.size = Vector3(SLAB.x + 0.3, 0.55, SLAB.z + 0.16)
	WorldArt.mesh_node(self, cap, Vector3(0, y0 + SLAB.y + 0.27, 0), trim)
	WorldArt.box_collider(self, Vector3(SLAB.x + 1.2, y0 + SLAB.y, SLAB.z + 1.3), Vector3(0, (y0 + SLAB.y) * 0.5, 0))
	var face := SLAB.z * 0.5 + 0.012
	var title := _label(Vector3(0, y0 + SLAB.y - 0.22, face), 0.0046, 38, HORIZONTAL_ALIGNMENT_CENTER)
	title.font = UITheme.display_font()
	title.text = "MONUMENT  OF  CLIMBERS"
	title.modulate = Color(0.75, 0.9, 1.0)
	title.outline_modulate = Color(0.2, 0.55, 1.0, 0.6)
	var rule := BoxMesh.new()
	rule.size = Vector3(SLAB.x - 0.5, 0.012, 0.01)
	WorldArt.mesh_node(self, rule, Vector3(0, y0 + SLAB.y - 0.4, face), WorldArt.rune_mat(Color("6fb8ff"), 1.2))
	var col_w := (SLAB.x - 0.5) / COLS
	for c in COLS:
		for r in ROWS:
			var x := -SLAB.x * 0.5 + 0.25 + col_w * c + 0.05
			var l := _label(Vector3(x, y0 + SLAB.y - 0.58 - r * ROW_H, face), 0.0036, 34, HORIZONTAL_ALIGNMENT_LEFT)
			l.width = col_w / 0.0036
			_rows.append(l)
	_count = _label(Vector3(0, y0 + 0.14, face), 0.003, 26, HORIZONTAL_ALIGNMENT_CENTER)
	_count.modulate = Color(0.6, 0.7, 0.85, 0.8)
	set_names([])


func _label(pos: Vector3, px: float, size: int, align: HorizontalAlignment) -> Label3D:
	var l := Label3D.new()
	l.position = pos
	l.pixel_size = px
	l.font_size = size
	l.font = UITheme.ui_bold()
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.double_sided = false
	l.shaded = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(l)
	return l


## entries: [{"name": String, "level": int, "floors": int, "online": bool}],
## already sorted. Up to ROWS * COLS are inscribed; the rest are counted.
func set_names(entries: Array) -> void:
	if _rows.is_empty():
		return
	for i in _rows.size():
		var l := _rows[i]
		if i >= entries.size():
			l.text = ""
			continue
		var e: Dictionary = entries[i]
		var cleared := int(e.get("floors", 0)) >= 1
		var online := bool(e.get("online", false))
		l.text = "%s   Lv %d" % [String(e.get("name", "?")).to_upper(), int(e.get("level", 1))]
		var col := CLEARED if cleared else ONLINE
		if not online:
			col = Color(col.lerp(OFFLINE, 0.55), OFFLINE.a)
		l.modulate = col
		l.outline_modulate = Color(CLEARED, 0.55) if cleared and online else (GLOW if online else Color(0, 0, 0, 0))
	var online_n := 0
	for e in entries:
		if bool((e as Dictionary).get("online", false)):
			online_n += 1
	if entries.is_empty():
		_count.text = "No names are inscribed yet."
	else:
		var more := entries.size() - _rows.size()
		_count.text = "%d inscribed  ·  %d in the realm%s" % [entries.size(), online_n, ("  ·  +%d more" % more) if more > 0 else ""]
