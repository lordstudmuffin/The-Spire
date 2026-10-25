class_name PlayerStatus
extends Control
## Player status, top left of the HUD, in the style of a VR-MMO system
## readout: a pale name plate, then a long HP gauge whose frame steps down
## and tapers toward its end, with the numbers and level in small type
## under the tip. A thin EXP line runs under the gauge, a guard line under
## that while guarding, and Col / floor sit under the name plate.
## Drawn in code (original art). Owned by the visuals thread; hud.gd feeds it.

const PLATE_W := 150.0
const PLATE_H := 30.0
const GAUGE_W := 330.0
const GAUGE_H := 20.0     # thick section, at the plate end
const GAUGE_H2 := 13.0    # thin section after the step
const STEP_AT := 0.62     # fraction of the gauge length where it steps down
const SLANT := 10.0
const CHIP_HOLD := 0.4
const CHIP_DRAIN := 0.45

const PLATE_BG := Color(0.95, 0.95, 0.97, 0.9)
const PLATE_TEXT := Color(0.2, 0.22, 0.27)
const FRAME := Color(1, 1, 1, 0.92)
const WELL := Color(0.06, 0.08, 0.13, 0.62)
const HP_GREEN := [Color("4fb83a"), Color("9be86a")]
const HP_YELLOW := [Color("d9a514"), Color("ffe066")]
const HP_RED := [Color("c62a22"), Color("ff6b5a")]
const CHIP := Color(1.0, 0.93, 0.86, 0.9)
const XP_COL := Color(0.35, 0.75, 1.0)
const GUARD_COL := Color(0.62, 0.82, 1.0)
const TEXT := Color(1, 1, 1)
const TEXT_SHADOW := Color(0.05, 0.07, 0.12, 0.85)

var player_name := "PLAYER"
var class_text := ""
var level := 1
var hp := 1.0
var hp_max := 1.0
var xp := 0.0
var xp_need := 1.0
var money := 0
var floor_no := 1
var guard_visible := false
var guard := 0.0
var guard_max := 1.0
var stunned := false

var _chip := 1.0          # chip value in HP units
var _chip_hold := 0.0
var _flash := 0.0         # brief white flash on the gauge when hit
var _font: Font
var _bold: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PLATE_W + GAUGE_W + 24.0, 96.0)


func _ready() -> void:
	_font = UITheme.ui_font()
	_bold = UITheme.ui_bold()


func set_identity(n: String, cls: String, lv: int) -> void:
	player_name = n
	class_text = cls
	level = lv
	queue_redraw()


func set_hp(value: float, maximum: float) -> void:
	maximum = maxf(maximum, 1.0)
	if value < hp - 0.01:
		_chip = maxf(_chip, hp)
		_chip_hold = CHIP_HOLD
		_flash = 1.0
	elif value >= _chip:
		_chip = value
	hp = clampf(value, 0.0, maximum)
	hp_max = maximum
	queue_redraw()


func set_xp(value: float, need: float) -> void:
	xp = value
	xp_need = maxf(need, 1.0)
	queue_redraw()


func set_guard(show: bool, value: float, maximum: float, is_stunned: bool) -> void:
	guard_visible = show
	guard = value
	guard_max = maxf(maximum, 1.0)
	stunned = is_stunned
	queue_redraw()


func set_money_floor(col: int, fl: int) -> void:
	money = col
	floor_no = fl
	queue_redraw()


func _process(delta: float) -> void:
	var busy := false
	if _chip > hp:
		if _chip_hold > 0.0:
			_chip_hold -= delta
		else:
			_chip = maxf(hp, _chip - hp_max * delta / CHIP_DRAIN)
		busy = true
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		busy = true
	if busy:
		queue_redraw()


static func band_colors(frac: float) -> Array:
	if frac <= 0.2:
		return HP_RED
	if frac <= 0.5:
		return HP_YELLOW
	return HP_GREEN


## Outline of the gauge: thick near the plate, a slanted step down, then a
## thinner run that ends in a slanted tip. Top edge is flat.
func _gauge_shape(x0: float, y0: float) -> PackedVector2Array:
	var xs := x0 + GAUGE_W * STEP_AT
	var xe := x0 + GAUGE_W
	return PackedVector2Array([
		Vector2(x0, y0),
		Vector2(xe, y0),
		Vector2(xe - SLANT * 0.7, y0 + GAUGE_H2),
		Vector2(xs + SLANT * 0.5, y0 + GAUGE_H2),
		Vector2(xs - SLANT * 0.5, y0 + GAUGE_H),
		Vector2(x0, y0 + GAUGE_H),
	])


func _clip_to(shape: PackedVector2Array, x_from: float, x_to: float) -> Array:
	if x_to <= x_from + 0.5:
		return []
	var r := PackedVector2Array([Vector2(x_from, -1000), Vector2(x_to, -1000), Vector2(x_to, 1000), Vector2(x_from, 1000)])
	return Geometry2D.intersect_polygons(shape, r)


func _text(pos: Vector2, s: String, px: int, col: Color, bold := false, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	var f := _bold if bold else _font
	if f == null:
		f = get_theme_default_font()
	draw_string(f, pos + Vector2(0, 1.5), s, align, w, px, TEXT_SHADOW)
	draw_string(f, pos, s, align, w, px, col)


func _draw() -> void:
	var y_plate := 8.0
	# Name plate with a subtle drop shadow and a thin accent tab on the left.
	var plate := Rect2(Vector2(0, y_plate), Vector2(PLATE_W, PLATE_H))
	var sh := StyleBoxFlat.new()
	sh.bg_color = PLATE_BG
	sh.set_corner_radius_all(4)
	sh.shadow_color = Color(0, 0, 0, 0.25)
	sh.shadow_size = 6
	sh.shadow_offset = Vector2(0, 2)
	draw_style_box(sh, plate)
	draw_rect(Rect2(plate.position + Vector2(0, 5), Vector2(3, PLATE_H - 10)), Color(1.0, 0.62, 0.14))
	var nf := _bold if _bold else get_theme_default_font()
	var name_px := 17
	while name_px > 11 and nf.get_string_size(player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_px).x > PLATE_W - 24:
		name_px -= 1
	draw_string(nf, plate.position + Vector2(12, PLATE_H * 0.5 + name_px * 0.36), player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_px, PLATE_TEXT)

	# HP gauge.
	var gx := PLATE_W + 8.0
	var gy := y_plate + (PLATE_H - GAUGE_H) * 0.5
	var shape := _gauge_shape(gx, gy)
	draw_colored_polygon(shape, WELL)
	var frac := clampf(hp / hp_max, 0.0, 1.0)
	var cfrac := clampf(_chip / hp_max, 0.0, 1.0)
	for poly in _clip_to(shape, gx + GAUGE_W * frac, gx + GAUGE_W * cfrac):
		draw_colored_polygon(poly, CHIP)
	var cols := band_colors(frac)
	for poly in _clip_to(shape, gx, gx + GAUGE_W * frac):
		var pc := PackedColorArray()
		for p in poly:
			# Vertical gradient: brighter toward the top edge.
			var t := clampf((p.y - gy) / GAUGE_H, 0.0, 1.0)
			pc.append((cols[1] as Color).lerp(cols[0], t))
		draw_polygon(poly, pc)
	# Glossy highlight along the top third.
	for poly in _clip_to(PackedVector2Array([Vector2(gx, gy), Vector2(gx + GAUGE_W, gy), Vector2(gx + GAUGE_W - 2, gy + 4), Vector2(gx, gy + 4)]), gx, gx + GAUGE_W * frac):
		draw_colored_polygon(poly, Color(1, 1, 1, 0.28))
	if _flash > 0.0:
		draw_colored_polygon(shape, Color(1, 1, 1, 0.35 * _flash))
	var outline := shape.duplicate()
	outline.append(shape[0])
	draw_polyline(outline, FRAME, 1.5, true)
	# Tick marks every 10% on the thin run, like a gauge scale.
	for i in range(1, 10):
		var tx := gx + GAUGE_W * i / 10.0
		if tx > gx + GAUGE_W * STEP_AT + SLANT:
			draw_line(Vector2(tx, gy + GAUGE_H2 - 3), Vector2(tx, gy + GAUGE_H2), Color(1, 1, 1, 0.35), 1.0)

	# EXP line under the gauge.
	var ly := gy + GAUGE_H + 5.0
	var lx0 := gx
	var lw := GAUGE_W * STEP_AT - SLANT
	draw_rect(Rect2(lx0, ly, lw, 3), Color(0.05, 0.07, 0.12, 0.55))
	draw_rect(Rect2(lx0, ly, lw * clampf(xp / xp_need, 0.0, 1.0), 3), XP_COL)
	if guard_visible:
		var gcol := Color(1.0, 0.45, 0.4) if stunned else GUARD_COL
		draw_rect(Rect2(lx0, ly + 6, lw, 3), Color(0.05, 0.07, 0.12, 0.55))
		draw_rect(Rect2(lx0, ly + 6, lw * clampf(guard / guard_max, 0.0, 1.0), 3), gcol)

	# Numbers and level under the gauge tip, right-aligned to it.
	var tip_x := gx + GAUGE_W
	var ny := gy + GAUGE_H2 + 17.0
	_text(Vector2(gx + GAUGE_W * STEP_AT, ny), "%d/%d" % [int(ceil(hp)), int(hp_max)], 14, TEXT, true, HORIZONTAL_ALIGNMENT_RIGHT, tip_x - (gx + GAUGE_W * STEP_AT) - 64)
	_text(Vector2(tip_x - 60, ny), "Lv: %d" % level, 14, TEXT, true, HORIZONTAL_ALIGNMENT_RIGHT, 56)

	# Under the plate: class, Col and floor in small type.
	var sy := y_plate + PLATE_H + 18.0
	var info := class_text
	_text(Vector2(2, sy), info, 12, Color(0.85, 0.92, 1.0), true)
	_text(Vector2(2, sy + 17), "%d Col   ·   Floor %d" % [money, floor_no], 12, Color(1, 0.93, 0.8))
