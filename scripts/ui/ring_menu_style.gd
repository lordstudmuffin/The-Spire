class_name RingMenuStyle
extends RefCounted
## Look of the ring menu (scripts/ui/ring_menu.gd): colours, sizes, timings,
## sound events and the line-icon glyphs. Behaviour lives in ring_menu.gd;
## everything visual lives here so restyling is a one-file edit.
## Owned by the visuals thread after the first version.

# --- Palette: white/silver glass with an amber selection accent -----------
const BTN_FILL := Color(0.97, 0.97, 0.98, 0.92)
const BTN_FILL_SEL := Color(1.0, 0.66, 0.18, 0.96)
const BTN_RIM := Color(0.62, 0.65, 0.72, 0.9)
const BTN_RIM_SEL := Color(1.0, 0.85, 0.55, 1.0)
const ICON := Color(0.36, 0.38, 0.44)
const ICON_SEL := Color(1, 1, 1)
const GLOW_SEL := Color(1.0, 0.7, 0.25, 0.35)

const PANEL_BG := Color(0.96, 0.96, 0.97, 0.95)
const PANEL_HEADER := Color(0.88, 0.89, 0.91, 0.96)
const PANEL_ACCENT := Color(1.0, 0.62, 0.14)
const PANEL_TEXT := Color(0.22, 0.24, 0.29)
const PANEL_SUBTLE := Color(0.45, 0.47, 0.53)
const PANEL_ROW_SEL := Color(1.0, 0.62, 0.14, 0.22)
const ROW_RULE := Color(0.2, 0.22, 0.28, 0.08)
const BTN_SHADOW := Color(0.05, 0.07, 0.12, 0.22)
## Pointer from the selected button to the open panel.
const NOTCH := 9.0
const BAR_BG := Color(0.78, 0.8, 0.84)
const HP_GREEN := Color(0.45, 0.85, 0.3)
const HP_YELLOW := Color(0.95, 0.8, 0.2)
const HP_RED := Color(0.9, 0.25, 0.2)
const XP_FILL := Color(0.3, 0.7, 1.0)

# --- Layout ---------------------------------------------------------------
const BTN_SIZE := 54.0
const BTN_GAP := 12.0
## Column sits right of screen centre, where the player's right hand is.
const COLUMN_OFFSET := Vector2(110, 0)
const PANEL_W := 330.0
const PANEL_GAP := 44.0
const SUB_PANEL_W := 250.0
const PANEL_RADIUS := 3
const LABEL_SIZE := 15

# --- Timing (seconds) -----------------------------------------------------
const STAGGER := 0.04
const BTN_IN := 0.18
const BTN_DROP := 46.0
const PANEL_IN := 0.22
const PANEL_SLIDE := 36.0

# --- Sounds (Audio EVENTS names) -----------------------------------------
const SND_OPEN := "menu_open"
const SND_CLOSE := "menu_close"
const SND_SELECT := "menu_select"
const SND_CONFIRM := "ui_confirm"
const SND_PANEL := "panel_slide"
const SND_BACK := "ui_back"


static func hp_color(frac: float) -> Color:
	if frac <= 0.25:
		return HP_RED
	if frac <= 0.5:
		return HP_YELLOW
	return HP_GREEN


static func panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(PANEL_RADIUS)
	sb.border_color = Color(1, 1, 1, 0.9)
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 14
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 12
	return sb


static func header_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_HEADER
	sb.corner_radius_top_left = PANEL_RADIUS
	sb.corner_radius_top_right = PANEL_RADIUS
	sb.border_color = PANEL_ACCENT
	sb.border_width_bottom = 2
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


static func row_box(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_ROW_SEL if selected else Color(0, 0, 0, 0)
	# Rows read as a ruled list: a hairline under each, and the selected row
	# gets an amber tab on its left edge.
	sb.border_color = PANEL_ACCENT if selected else ROW_RULE
	sb.border_width_bottom = 0 if selected else 1
	sb.border_width_left = 3 if selected else 0
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## Draws one round menu button on `ci` centred at `c`.
static func draw_button(ci: CanvasItem, c: Vector2, r: float, selected: bool, glyph: String) -> void:
	# Soft contact shadow so the white glass reads against bright skies.
	ci.draw_circle(c + Vector2(0, 2.5), r + 1.5, BTN_SHADOW)
	if selected:
		ci.draw_circle(c, r + 7.0, GLOW_SEL)
		ci.draw_arc(c, r + 4.0, 0, TAU, 48, Color(BTN_RIM_SEL, 0.8), 1.5, true)
	ci.draw_circle(c, r, BTN_FILL_SEL if selected else BTN_FILL)
	# Soft top highlight for the glassy look.
	ci.draw_circle(c + Vector2(0, -r * 0.35), r * 0.62, Color(1, 1, 1, 0.18 if selected else 0.35))
	ci.draw_arc(c, r, 0, TAU, 48, BTN_RIM_SEL if selected else BTN_RIM, 2.0, true)
	draw_glyph(ci, glyph, c, r * 0.48, ICON_SEL if selected else ICON)


## Pointer from the selected button (centre `from`, radius `r`) to the open
## panel `panel` (a rect in the same space): an amber hairline that ends in
## a notch cut into the panel's left edge. `a` is the panel's fade.
static func draw_connector(ci: CanvasItem, from: Vector2, r: float, panel: Rect2, a: float) -> void:
	if a <= 0.01:
		return
	var y := clampf(from.y, panel.position.y + PANEL_RADIUS + NOTCH + 6.0, panel.end.y - NOTCH - 6.0)
	var tip := Vector2(panel.position.x - NOTCH, y)
	var start := from + Vector2(r + 5.0, 0)
	var acc := Color(PANEL_ACCENT, 0.9 * a)
	if absf(y - from.y) < 1.0:
		ci.draw_line(start, tip, acc, 1.5, true)
	else:
		var knee := Vector2(lerpf(start.x, tip.x, 0.5), from.y)
		ci.draw_polyline(PackedVector2Array([start, knee, Vector2(knee.x, y), tip]), acc, 1.5, true)
	var tri := PackedVector2Array([tip, Vector2(panel.position.x + 1.0, y - NOTCH), Vector2(panel.position.x + 1.0, y + NOTCH)])
	ci.draw_colored_polygon(tri, Color(PANEL_BG, PANEL_BG.a * a))
	ci.draw_circle(start, 2.5, acc)


## Simple line icons drawn in code (original art, no textures).
static func draw_glyph(ci: CanvasItem, glyph: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(2.0, s * 0.16)
	match glyph:
		"status":  # person
			ci.draw_circle(c + Vector2(0, -s * 0.45), s * 0.32, col)
			ci.draw_arc(c + Vector2(0, s * 0.75), s * 0.75, PI, TAU, 20, col, w * 1.4, true)
		"items":  # bag
			var r := Rect2(c + Vector2(-s * 0.7, -s * 0.3), Vector2(s * 1.4, s * 1.1))
			ci.draw_rect(r, col, false, w)
			ci.draw_arc(c + Vector2(0, -s * 0.3), s * 0.38, PI, TAU, 14, col, w, true)
		"skills":  # sword
			ci.draw_line(c + Vector2(-s * 0.7, s * 0.7), c + Vector2(s * 0.75, -s * 0.75), col, w * 1.2, true)
			ci.draw_line(c + Vector2(-s * 0.55, s * 0.15), c + Vector2(-s * 0.15, s * 0.55), col, w, true)
			ci.draw_line(c + Vector2(-s * 0.7, s * 0.7), c + Vector2(-s * 0.9, s * 0.9), col, w * 1.4, true)
		"quests":  # scroll / list
			for i in 3:
				var y := -s * 0.55 + i * s * 0.55
				ci.draw_circle(c + Vector2(-s * 0.6, y), w * 0.7, col)
				ci.draw_line(c + Vector2(-s * 0.3, y), c + Vector2(s * 0.75, y), col, w, true)
		"map":  # pin
			ci.draw_arc(c + Vector2(0, -s * 0.25), s * 0.5, 0, TAU, 20, col, w, true)
			ci.draw_line(c + Vector2(-s * 0.42, 0), c + Vector2(0, s * 0.85), col, w, true)
			ci.draw_line(c + Vector2(s * 0.42, 0), c + Vector2(0, s * 0.85), col, w, true)
		"party":  # two people
			for dx in [-0.42, 0.42]:
				var o := c + Vector2(s * dx, 0)
				ci.draw_circle(o + Vector2(0, -s * 0.4), s * 0.24, col)
				ci.draw_arc(o + Vector2(0, s * 0.65), s * 0.5, PI, TAU, 14, col, w, true)
		"messages":  # envelope
			var r := Rect2(c + Vector2(-s * 0.8, -s * 0.5), Vector2(s * 1.6, s * 1.1))
			ci.draw_rect(r, col, false, w)
			ci.draw_line(r.position, c + Vector2(0, s * 0.1), col, w, true)
			ci.draw_line(r.position + Vector2(r.size.x, 0), c + Vector2(0, s * 0.1), col, w, true)
		"settings":  # gear
			ci.draw_arc(c, s * 0.45, 0, TAU, 20, col, w, true)
			for i in 8:
				var a := TAU * i / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * s * 0.55, c + Vector2(cos(a), sin(a)) * s * 0.85, col, w * 1.3, true)
		"logout":  # power
			ci.draw_arc(c, s * 0.7, -PI * 0.3, PI * 1.3, 24, col, w, true)
			ci.draw_line(c + Vector2(0, -s * 0.9), c + Vector2(0, -s * 0.1), col, w, true)
		_:
			ci.draw_circle(c, s * 0.3, col)
