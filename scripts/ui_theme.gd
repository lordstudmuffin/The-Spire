class_name UITheme
extends RefCounted
## Shared look for every menu and the HUD: palette, fonts, a full Theme and
## small builders (panels, buttons, headings, swatches). Everything is built
## in code; the only art is two OFL fonts in assets/fonts (optional: the
## engine default font is used when they are missing).

const NAVY := Color("0b1024")
const NAVY2 := Color("121a33")
const NAVY3 := Color("1b2546")
const GOLD := Color("f0c060")
const GOLD_DIM := Color("b08a3c")
const CYAN := Color("4cc9f0")
const ROSE := Color("ff4d6d")
const PARCH := Color("f3eee4")
const MUTED := Color("a7afc6")
const GREEN := Color("7bdc8a")

const SWATCHES_HAIR := ["1a1a2e", "3b2418", "7a4a21", "c98a3a", "f1d9a0", "e8e4de", "c4262e", "f06292", "7b61ff", "4cc9f0", "3cb371"]
const SWATCHES_EYE := ["4cc9f0", "2d6cdf", "3cb371", "a0522d", "5b3a29", "f0c060", "ff4d6d", "9b59b6", "e8e4de", "1a1a2e"]
const SWATCHES_SKIN := ["fde7d4", "f2d0b5", "e6b592", "d9a176", "c08457", "a06a44", "7a4a2e", "55331f", "d7c7e8", "b9d9e8"]
const SWATCHES_OUTFIT := ["e63946", "f0c060", "4cc9f0", "2d6cdf", "3cb371", "9b59b6", "f06292", "f3eee4", "1a1a2e", "ff8c42"]

static var _theme: Theme
static var _ui: Font
static var _ui_bold: Font
static var _display: Font

const _TAG_WGHT := (119 << 24) | (103 << 16) | (104 << 8) | 116  # 'wght'


static func _base(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f = load(path)
		if f is Font:
			return f
	return ThemeDB.fallback_font


static func ui_font() -> Font:
	if _ui == null:
		_ui = _weight(_base("res://assets/fonts/Nunito.ttf"), 560, 0)
	return _ui


static func ui_bold() -> Font:
	if _ui_bold == null:
		_ui_bold = _weight(_base("res://assets/fonts/Nunito.ttf"), 800, 0)
	return _ui_bold


static func display_font() -> Font:
	if _display == null:
		_display = _weight(_base("res://assets/fonts/Cinzel.ttf"), 700, 2)
	return _display


## A variation of a (variable) font with a given weight and letter spacing.
static func _weight(base: Font, w: int, spacing: int) -> Font:
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {_TAG_WGHT: w}
	v.spacing_glyph = spacing
	return v


static func spaced(base: Font, spacing: int) -> Font:
	var v := FontVariation.new()
	v.base_font = base
	v.spacing_glyph = spacing
	if base is FontVariation:
		v.variation_opentype = (base as FontVariation).variation_opentype
	return v


# --- Style boxes ----------------------------------------------------------

static func box(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 12, border_w: int = 1, shadow: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border_w if border.a > 0.0 else 0)
	s.border_color = border
	s.anti_aliasing = true
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.45)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, 4)
	return s


static func card_box(border: Color = GOLD, alpha: float = 0.86) -> StyleBoxFlat:
	var s := box(Color(NAVY.r, NAVY.g, NAVY.b, alpha), Color(border.r, border.g, border.b, 0.65), 14, 1, 14)
	s.set_content_margin_all(20)
	return s


static func _btn(bg: Color, border: Color, fg_alpha := 1.0) -> StyleBoxFlat:
	var s := box(bg, border, 10, 1)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	return s


# --- The Theme -------------------------------------------------------------

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	_theme = t
	t.default_font = ui_font()
	t.default_font_size = 17

	# Panels.
	t.set_stylebox("panel", "Panel", card_box())
	t.set_stylebox("panel", "PanelContainer", card_box())
	t.set_type_variation("CardCyan", "PanelContainer")
	t.set_stylebox("panel", "CardCyan", card_box(CYAN))
	t.set_type_variation("CardFlat", "PanelContainer")
	var flat := box(Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.08), 10)
	flat.set_content_margin_all(12)
	t.set_stylebox("panel", "CardFlat", flat)
	t.set_type_variation("Dim", "PanelContainer")
	var dim := StyleBoxFlat.new()
	dim.bg_color = Color(0.02, 0.03, 0.08, 0.5)
	t.set_stylebox("panel", "Dim", dim)
	t.set_type_variation("Pill", "PanelContainer")
	var pill := box(Color(NAVY.r, NAVY.g, NAVY.b, 0.8), Color(CYAN.r, CYAN.g, CYAN.b, 0.6), 999, 1)
	pill.content_margin_top = 6
	pill.content_margin_bottom = 6
	t.set_stylebox("panel", "Pill", pill)
	t.set_type_variation("KeyCap", "PanelContainer")
	var cap := box(Color(PARCH.r, PARCH.g, PARCH.b, 0.95), Color(0, 0, 0, 0), 6, 0)
	cap.set_content_margin_all(2)
	cap.content_margin_left = 8
	cap.content_margin_right = 8
	t.set_stylebox("panel", "KeyCap", cap)
	t.set_type_variation("Slot", "PanelContainer")
	var slot := box(Color(NAVY.r, NAVY.g, NAVY.b, 0.82), Color(GOLD.r, GOLD.g, GOLD.b, 0.55), 12, 2, 8)
	slot.set_content_margin_all(0)
	t.set_stylebox("panel", "Slot", slot)

	# Labels.
	t.set_color("font_color", "Label", PARCH)
	t.set_type_variation("Heading", "Label")
	t.set_font("font", "Heading", display_font())
	t.set_font_size("font_size", "Heading", 22)
	t.set_color("font_color", "Heading", GOLD)
	t.set_type_variation("Subtle", "Label")
	t.set_color("font_color", "Subtle", MUTED)
	t.set_font_size("font_size", "Subtle", 15)
	t.set_type_variation("Kicker", "Label")
	t.set_font("font", "Kicker", spaced(ui_bold(), 4))
	t.set_font_size("font_size", "Kicker", 13)
	t.set_color("font_color", "Kicker", CYAN)
	t.set_type_variation("Bold", "Label")
	t.set_font("font", "Bold", ui_bold())
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", display_font())
	t.set_font_size("font_size", "Title", 104)
	t.set_color("font_color", "Title", GOLD)
	t.set_color("font_shadow_color", "Title", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Title", 0)
	t.set_constant("shadow_offset_y", "Title", 6)
	t.set_constant("shadow_outline_size", "Title", 10)
	t.set_type_variation("Outlined", "Label")
	t.set_color("font_outline_color", "Outlined", Color(0.02, 0.03, 0.08, 0.9))
	t.set_constant("outline_size", "Outlined", 6)

	# Buttons.
	_button_styles(t, "Button", Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.16), PARCH, GOLD)
	t.set_type_variation("PrimaryButton", "Button")
	_button_styles(t, "PrimaryButton", Color(GOLD.r, GOLD.g, GOLD.b, 0.92), GOLD, Color("ffd98a"), NAVY, NAVY)
	t.set_type_variation("GhostButton", "Button")
	_button_styles(t, "GhostButton", Color(0, 0, 0, 0), Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.12), MUTED, PARCH)
	t.set_type_variation("DangerButton", "Button")
	_button_styles(t, "DangerButton", Color(ROSE.r, ROSE.g, ROSE.b, 0.14), Color(ROSE.r, ROSE.g, ROSE.b, 0.3), Color(ROSE.r, ROSE.g, ROSE.b, 0.45), PARCH, PARCH, ROSE)
	t.set_type_variation("Chip", "Button")
	_button_styles(t, "Chip", Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.14), MUTED, PARCH, Color(1, 1, 1, 0.12), 999)
	t.set_type_variation("ChipOn", "Button")
	_button_styles(t, "ChipOn", Color(CYAN.r, CYAN.g, CYAN.b, 0.18), Color(CYAN.r, CYAN.g, CYAN.b, 0.26), Color(CYAN.r, CYAN.g, CYAN.b, 0.32), CYAN, PARCH, CYAN, 999)
	t.set_type_variation("Round", "Button")
	_button_styles(t, "Round", Color(1, 1, 1, 0.08), Color(GOLD.r, GOLD.g, GOLD.b, 0.3), Color(GOLD.r, GOLD.g, GOLD.b, 0.5), PARCH, NAVY, Color(1, 1, 1, 0.14), 999)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var s: StyleBoxFlat = t.get_stylebox(st, "Round")
		s.set_content_margin_all(0)
	t.set_font("font", "Round", ui_bold())
	t.set_font_size("font_size", "Round", 20)
	t.set_font("font", "PrimaryButton", ui_bold())
	t.set_font_size("font_size", "PrimaryButton", 18)

	# LineEdit.
	var le := box(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.14), 10)
	le.content_margin_top = 9
	le.content_margin_bottom = 9
	t.set_stylebox("normal", "LineEdit", le)
	var lef := box(Color(0, 0, 0, 0.4), CYAN, 10, 2)
	lef.content_margin_top = 9
	lef.content_margin_bottom = 9
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", PARCH)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED.r, MUTED.g, MUTED.b, 0.6))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(CYAN.r, CYAN.g, CYAN.b, 0.35))

	# OptionButton / PopupMenu.
	t.set_color("font_color", "OptionButton", PARCH)
	var pm := box(Color(NAVY2.r, NAVY2.g, NAVY2.b, 0.98), Color(GOLD.r, GOLD.g, GOLD.b, 0.5), 10, 1, 10)
	pm.set_content_margin_all(6)
	t.set_stylebox("panel", "PopupMenu", pm)
	var pmh := box(Color(CYAN.r, CYAN.g, CYAN.b, 0.18), Color(0, 0, 0, 0), 6, 0)
	t.set_stylebox("hover", "PopupMenu", pmh)
	t.set_color("font_color", "PopupMenu", PARCH)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_constant("v_separation", "PopupMenu", 6)

	# Slider.
	var track := box(Color(0, 0, 0, 0.4), Color(1, 1, 1, 0.1), 6)
	track.set_content_margin_all(0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var area := box(CYAN, Color(0, 0, 0, 0), 6, 0)
	area.set_content_margin_all(0)
	t.set_stylebox("grabber_area", "HSlider", area)
	t.set_stylebox("grabber_area_highlight", "HSlider", area)
	var knob := radial_dot(GOLD, 22)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", radial_dot(Color("ffd98a"), 22))
	t.set_icon("grabber_disabled", "HSlider", radial_dot(MUTED, 22))

	# Focus rings on the controls that have none of their own.
	t.set_stylebox("focus", "HSlider", focus_box(8, 4))
	t.set_stylebox("focus", "CheckButton", focus_box(10))
	t.set_stylebox("focus", "CheckBox", focus_box(10))
	t.set_stylebox("focus", "OptionButton", focus_box(10))
	t.set_stylebox("focus", "LinkButton", focus_box(6))

	# ProgressBar.
	var pbg := box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.1), 6)
	pbg.set_content_margin_all(1)
	t.set_stylebox("background", "ProgressBar", pbg)
	var pfill := box(CYAN, Color(0, 0, 0, 0), 5, 0)
	pfill.set_content_margin_all(0)
	t.set_stylebox("fill", "ProgressBar", pfill)
	t.set_color("font_color", "ProgressBar", PARCH)

	# Scroll bars.
	var sb_bg := box(Color(0, 0, 0, 0.2), Color(0, 0, 0, 0), 4, 0)
	sb_bg.set_content_margin_all(0)
	var sb_g := box(Color(GOLD.r, GOLD.g, GOLD.b, 0.55), Color(0, 0, 0, 0), 4, 0)
	sb_g.set_content_margin_all(0)
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, sb_bg)
		t.set_stylebox("grabber", bar, sb_g)
		t.set_stylebox("grabber_highlight", bar, box(GOLD, Color(0, 0, 0, 0), 4, 0))
		t.set_stylebox("grabber_pressed", bar, box(GOLD, Color(0, 0, 0, 0), 4, 0))
	var empty := StyleBoxEmpty.new()
	t.set_stylebox("panel", "ScrollContainer", empty)

	# Tooltip.
	t.set_stylebox("panel", "TooltipPanel", box(Color(NAVY2.r, NAVY2.g, NAVY2.b, 0.96), GOLD, 8))
	t.set_color("font_color", "TooltipLabel", PARCH)

	# ColorPicker popup gets a dark panel too.
	t.set_stylebox("panel", "PopupPanel", pm)
	return t


## The focus ring every control shares: a 2 px cyan outline just outside
## the control, so gamepad / keyboard navigation always has a visible cursor.
static func focus_box(radius := 10, expand := 2) -> StyleBoxFlat:
	var sf := StyleBoxFlat.new()
	sf.draw_center = false
	sf.set_border_width_all(2)
	sf.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.85)
	sf.set_corner_radius_all(radius)
	sf.set_expand_margin_all(expand)
	return sf


static func _button_styles(t: Theme, type: String, n: Color, h: Color, p: Color, fg: Color, fg_hover: Color, border: Color = Color(1, 1, 1, 0.1), radius: int = 10) -> void:
	var sn := _btn(n, border)
	sn.set_corner_radius_all(radius)
	var sh := _btn(h, Color(GOLD.r, GOLD.g, GOLD.b, 0.8) if border.a < 0.5 else border)
	sh.set_corner_radius_all(radius)
	var sp := _btn(p, GOLD)
	sp.set_corner_radius_all(radius)
	var sd := _btn(Color(n.r, n.g, n.b, n.a * 0.4), Color(1, 1, 1, 0.05))
	sd.set_corner_radius_all(radius)
	var sf := focus_box(radius)
	t.set_stylebox("normal", type, sn)
	t.set_stylebox("hover", type, sh)
	t.set_stylebox("pressed", type, sp)
	t.set_stylebox("disabled", type, sd)
	t.set_stylebox("focus", type, sf)
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, fg_hover)
	t.set_color("font_pressed_color", type, fg_hover)
	t.set_color("font_focus_color", type, fg)
	t.set_color("font_disabled_color", type, Color(MUTED.r, MUTED.g, MUTED.b, 0.45))
	if type == "Button":
		t.set_font("font", type, ui_bold())


# --- Textures made from gradients (no art files) ---------------------------

static func radial_dot(c: Color, px: int, soft := false) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.7, 1.0]) if not soft else PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([c, c if not soft else Color(c.r, c.g, c.b, c.a * 0.35), Color(c.r, c.g, c.b, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = px
	tex.height = px
	return tex


static func gradient_tex(colors: Array, offsets: Array = [], vertical := true, w := 8, h := 256) -> GradientTexture2D:
	var g := Gradient.new()
	var cs := PackedColorArray()
	for c in colors:
		cs.append(c if c is Color else Color(c))
	var offs := PackedFloat32Array()
	if offsets.is_empty():
		for i in cs.size():
			offs.append(float(i) / max(cs.size() - 1, 1))
	else:
		for o in offsets:
			offs.append(o)
	g.colors = cs
	g.offsets = offs
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = w
	tex.height = h
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	return tex


static func gradient_fill_box(colors: Array, radius := 5) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = gradient_tex(colors, [], false, 256, 8)
	s.set_texture_margin_all(0)
	return s


# --- Builders -----------------------------------------------------------------

## A card with an optional heading; returns the VBox you add content to.
static func make_panel(parent: Node, title: String = "", variation: String = "") -> VBoxContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	if title != "":
		v.add_child(heading(title))
		v.add_child(rule())
	return v


static func heading(text: String, size: int = 22, color: Color = GOLD) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.theme_type_variation = "Heading"
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func kicker(text: String, color: Color = CYAN) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.theme_type_variation = "Kicker"
	l.add_theme_color_override("font_color", color)
	return l


static func subtle(text: String, size := 15) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Subtle"
	l.add_theme_font_size_override("font_size", size)
	return l


## Thin gold rule that fades to the right.
static func rule(color: Color = GOLD) -> TextureRect:
	var r := TextureRect.new()
	r.texture = gradient_tex([Color(color.r, color.g, color.b, 0.9), Color(color.r, color.g, color.b, 0.0)], [], false, 256, 2)
	r.custom_minimum_size = Vector2(0, 2)
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	return r


## kind: "normal" | "primary" | "ghost" | "danger" | "chip" | "round"
static func make_button(text: String, kind: String = "normal") -> Button:
	var b := Button.new()
	b.text = text
	match kind:
		"primary": b.theme_type_variation = "PrimaryButton"
		"ghost": b.theme_type_variation = "GhostButton"
		"danger": b.theme_type_variation = "DangerButton"
		"chip": b.theme_type_variation = "Chip"
		"round":
			b.theme_type_variation = "Round"
			b.custom_minimum_size = Vector2(34, 34)
	hover_fx(b)
	b.pressed.connect(func(): Audio.play("ui_click"))
	b.mouse_entered.connect(func():
		if not b.disabled:
			Audio.play("ui_hover"))
	return b


## Small inline action ("Use" on a provision cell): cyan outline pill,
## 12 px bold text, 24 px tall, so it sits inside a grid cell.
static func mini_button(text: String) -> Button:
	var b := make_button(text, "chip")
	b.add_theme_font_override("font", ui_bold())
	b.add_theme_font_size_override("font_size", 12)
	for st in ["normal", "hover", "pressed", "focus"]:
		var bg := Color(CYAN, 0.16 if st == "normal" else 0.32)
		var sb := box(bg, Color(CYAN, 0.7 if st != "normal" else 0.45), 999, 1)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", PARCH)
	b.custom_minimum_size = Vector2(0, 24)
	return b


## Thin durability / wear gauge: fill in the HP band colours (green, yellow
## under half, red under a fifth), grey track. set_frac(0..1).
class WearGauge extends Control:
	var frac := 1.0

	func _init(f := 1.0, w := 120.0) -> void:
		frac = f
		custom_minimum_size = Vector2(w, 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_frac(f: float) -> void:
		frac = clampf(f, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(0, (size.y - 5) * 0.5), Vector2(size.x, 5))
		draw_rect(r, Color(1, 1, 1, 0.12))
		if frac > 0.0:
			var cols: Array = PlayerStatus.band_colors(frac)
			draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), cols[0])
			draw_rect(Rect2(r.position, Vector2(r.size.x * frac, 1.5)), Color(cols[1], 0.9))
		else:
			draw_rect(r, Color(UITheme.ROSE, 0.35))


## Broken-gear cover for an item card: a dim wash and a branching crack
## across the face (fixed pattern per card so it does not flicker).
class CrackOverlay extends Control:
	var seed_v := 1

	func _init(sd := 1) -> void:
		seed_v = sd
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.03, 0.04, 0.45)
		bg.set_corner_radius_all(10)
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		var p := Vector2(size.x * rng.randf_range(0.55, 0.8), 0)
		var pts := PackedVector2Array([p])
		while p.y < size.y:
			p += Vector2(rng.randf_range(-18, 14), rng.randf_range(10, 22))
			pts.append(p)
			if rng.randf() < 0.3:
				# A short branch off the main crack.
				var q := p + Vector2(rng.randf_range(-26, 26), rng.randf_range(6, 16))
				draw_line(p, q, Color(1, 0.86, 0.86, 0.75), 1.0, true)
		draw_polyline(pts, Color(0, 0, 0, 0.6), 3.0, true)
		draw_polyline(pts, Color(1, 0.9, 0.9, 0.9), 1.2, true)


## 150 ms scale pop on hover (pivot kept centred as the button resizes).
static func hover_fx(b: Control, amount := 1.04) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func():
		if b is BaseButton and (b as BaseButton).disabled:
			return
		b.pivot_offset = b.size * 0.5
		var tw := b.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2(amount, amount), 0.15))
	b.mouse_exited.connect(func():
		var tw := b.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2.ONE, 0.15))


static func set_chip(b: Button, on: bool) -> void:
	b.theme_type_variation = "ChipOn" if on else "Chip"


## Square colour swatch button; `selected` draws a gold ring.
static func swatch(c: Color, px := 30) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(px, px)
	b.tooltip_text = "#" + c.to_html(false)
	set_swatch_selected(b, c, false)
	hover_fx(b, 1.12)
	return b


static func set_swatch_selected(b: Button, c: Color, on: bool) -> void:
	var s := box(c, GOLD if on else Color(1, 1, 1, 0.18), 8, 3 if on else 1)
	s.set_content_margin_all(0)
	var h := box(c, Color(PARCH.r, PARCH.g, PARCH.b, 0.9), 8, 2)
	h.set_content_margin_all(0)
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", s)
	b.add_theme_stylebox_override("focus", focus_box(8, 3))


## Small keyboard key cap, e.g. [E].
static func keycap(key: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "KeyCap"
	var l := Label.new()
	l.text = key
	l.add_theme_font_override("font", ui_bold())
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", NAVY)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(16, 0)
	p.add_child(l)
	return p


## Key cap that follows the input device and the player's remaps: "I" on the
## keyboard, a coloured "D-Up" / "A" badge on a gamepad. `action` is an
## InputMap action or one of InputSetup.hint()'s composite names.
static func action_cap(action: String) -> PanelContainer:
	return ActionCap.new(action)


class ActionCap extends PanelContainer:
	var action := ""
	var _label: Label

	func _init(a: String) -> void:
		action = a
		theme_type_variation = "KeyCap"
		_label = Label.new()
		_label.add_theme_font_override("font", UITheme.ui_bold())
		_label.add_theme_font_size_override("font_size", 14)
		_label.add_theme_color_override("font_color", UITheme.NAVY)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.custom_minimum_size = Vector2(16, 0)
		add_child(_label)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		InputSetup.input_device_changed.connect(_on_device)
		InputSetup.bindings_changed.connect(refresh)
		refresh()

	func _exit_tree() -> void:
		if InputSetup.input_device_changed.is_connected(_on_device):
			InputSetup.input_device_changed.disconnect(_on_device)
		if InputSetup.bindings_changed.is_connected(refresh):
			InputSetup.bindings_changed.disconnect(refresh)

	func _on_device(_d: String) -> void:
		refresh()

	func refresh() -> void:
		var t: String = InputSetup.hint(action)
		# Unique arts have no pad button of their own: they are the target
		# trigger held plus the matching Sword Art button ("LT+RB").
		# Hidden-class arts likewise: target + Attack / Dash ("LT+X", "LT+B").
		var chord := InputSetup.using_gamepad() and action in ["skill_4", "skill_5", "skill_6", "class_1", "class_2"]
		if chord and action.begins_with("class_"):
			t = "%s+%s" % [InputSetup.hint("target"), InputSetup.hint("attack" if action == "class_1" else "dash")]
		elif chord:
			t = "%s+%s" % [InputSetup.hint("target"), InputSetup.hint("skill_%d" % (int(action.substr(6)) - 3))]
		_label.text = t
		if chord:
			var cb := UITheme.box(Color(UITheme.GOLD, 0.95), Color(1, 1, 1, 0.5), 999, 1)
			cb.set_content_margin_all(2)
			cb.content_margin_left = 7
			cb.content_margin_right = 7
			add_theme_stylebox_override("panel", cb)
			_label.add_theme_color_override("font_color", UITheme.NAVY)
			_label.add_theme_font_size_override("font_size", 12)
			return
		_label.add_theme_font_size_override("font_size", 14)
		if InputSetup.using_gamepad():
			var fc: Color = InputSetup.face_color(t)
			var sb: StyleBoxFlat
			if fc.a > 0.0:
				sb = UITheme.box(fc, Color(1, 1, 1, 0.35), 999, 1)
				_label.add_theme_color_override("font_color", UITheme.NAVY)
				_label.custom_minimum_size = Vector2(18, 0)
			else:
				sb = UITheme.box(Color(UITheme.NAVY3.r, UITheme.NAVY3.g, UITheme.NAVY3.b, 0.95), Color(UITheme.PARCH.r, UITheme.PARCH.g, UITheme.PARCH.b, 0.6), 999, 1)
				_label.add_theme_color_override("font_color", UITheme.PARCH)
				_label.custom_minimum_size = Vector2(16, 0)
			sb.set_content_margin_all(2)
			sb.content_margin_left = 9
			sb.content_margin_right = 9
			add_theme_stylebox_override("panel", sb)
		else:
			remove_theme_stylebox_override("panel")
			_label.add_theme_color_override("font_color", UITheme.NAVY)
			_label.custom_minimum_size = Vector2(16, 0)


## Label whose text is rebuilt from a format and action names whenever the
## device or the bindings change, e.g. hint_label("%s resumes  ·  %s saves", ["pause", "quick_save"]).
static func hint_label(fmt: String, actions: Array, size := 12) -> Label:
	var l := HintLabel.new()
	l.fmt = fmt
	l.actions = actions
	l.theme_type_variation = "Subtle"
	l.add_theme_font_size_override("font_size", size)
	l.refresh()
	return l


class HintLabel extends Label:
	var fmt := "%s"
	var actions: Array = []

	func _ready() -> void:
		InputSetup.input_device_changed.connect(_on_device)
		InputSetup.bindings_changed.connect(refresh)
		refresh()

	func _exit_tree() -> void:
		if InputSetup.input_device_changed.is_connected(_on_device):
			InputSetup.input_device_changed.disconnect(_on_device)
		if InputSetup.bindings_changed.is_connected(refresh):
			InputSetup.bindings_changed.disconnect(refresh)

	func _on_device(_d: String) -> void:
		refresh()

	func refresh() -> void:
		var parts: Array = []
		for a in actions:
			parts.append(InputSetup.hint(a))
		text = fmt % parts


## Draws the shared focus ring around `c` while it has focus, for controls
## that never draw one themselves (sliders).
static func focus_ring(c: Control, radius := 8) -> void:
	var ring_box := focus_box(radius, 4)
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", ring_box)
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	p.z_index = 1
	c.add_child(p)
	c.focus_entered.connect(func(): p.visible = true)
	c.focus_exited.connect(func(): p.visible = false)


## Put keyboard / gamepad focus on the first focusable control under `root`
## (depth first, visible and enabled). Returns it, or null.
static func focus_first_in(root: Node) -> Control:
	var c := _first_focusable(root)
	if c:
		c.grab_focus()
	return c


static func _first_focusable(n: Node) -> Control:
	if n is Control:
		var c := n as Control
		if not c.visible:
			return null
		if c.focus_mode == Control.FOCUS_ALL and not (c is BaseButton and (c as BaseButton).disabled):
			return c
	for ch in n.get_children():
		var r := _first_focusable(ch)
		if r:
			return r
	return null


static func label(text: String, size := 17, color: Color = PARCH, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", ui_bold())
	return l


static func spacer(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Fade+slide a control in over `dur` seconds after `delay`.
static func enter(c: Control, from_offset: Vector2, delay := 0.0, dur := 0.6) -> void:
	var target := c.position
	c.modulate.a = 0.0
	c.position = target + from_offset
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, dur).set_delay(delay)
	tw.tween_property(c, "position", target, dur).set_delay(delay)


## Fade only (safe for children of containers, whose position is managed).
static func fade_in(c: Control, delay := 0.0, dur := 0.5) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 1.0, dur).set_delay(delay)


## Rainbow-ringed square used as the "custom colour" button next to swatches.
static func style_custom_picker(b: Button) -> void:
	var hue := Gradient.new()
	hue.offsets = PackedFloat32Array([0.0, 0.17, 0.34, 0.51, 0.68, 0.85, 1.0])
	hue.colors = PackedColorArray([Color.RED, Color.YELLOW, Color.GREEN, Color.CYAN, Color.BLUE, Color.MAGENTA, Color.RED])
	var tex := GradientTexture2D.new()
	tex.gradient = hue
	tex.width = 64
	tex.height = 8
	tex.fill_to = Vector2(1, 0)
	var st := StyleBoxTexture.new()
	st.texture = tex
	st.set_texture_margin_all(0)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	b.add_theme_stylebox_override("focus", focus_box(8, 3))
	# Dark inner square so the rainbow reads as a border.
	var inner := ColorRect.new()
	inner.color = NAVY
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 3
	inner.offset_top = 3
	inner.offset_right = -3
	inner.offset_bottom = -3
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(inner)
	var plus := Label.new()
	plus.text = "+"
	plus.add_theme_font_override("font", ui_bold())
	plus.add_theme_font_size_override("font_size", 18)
	plus.add_theme_color_override("font_color", PARCH)
	plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus.set_anchors_preset(Control.PRESET_FULL_RECT)
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(plus)
	hover_fx(b, 1.12)


## Anti-aliased ring + filled disc drawn in code (for badges).
static func ring(parent: Control, fill: Color, stroke: Color, width := 3.0) -> void:
	parent.draw.connect(func():
		var c := parent.size * 0.5
		var r: float = min(parent.size.x, parent.size.y) * 0.5 - width
		parent.draw_circle(c, r, fill)
		parent.draw_arc(c, r, 0.0, TAU, 64, stroke, width, true)
		parent.draw_arc(c, r - width - 2.0, 0.0, TAU, 64, Color(stroke.r, stroke.g, stroke.b, 0.35), 1.0, true))
	parent.resized.connect(parent.queue_redraw)


## Look of HUD.show_death's overlay: grey-out shader on the ColorRect (its
## colour alpha stays the fade strength) and a spaced system-font title.
## Duel countdown / "DUEL!" / VICTORY-DEFEAT: big bold system type
## with a dark outline and a soft drop shadow (keeps the label's colour).
static func style_duel_label(l: Label) -> void:
	if l == null or l.has_meta("duel_styled"):
		return
	l.set_meta("duel_styled", true)
	var f := ui_bold()
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", 104)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.1, 0.95))
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.add_theme_constant_override("shadow_offset_x", 0)


static func death_screen(overlay: ColorRect, title: Label, sub: Label) -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/death_screen.gdshader")
	overlay.material = m
	title.add_theme_font_override("font", spaced(ui_bold(), 10))
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.26))
	title.add_theme_color_override("font_outline_color", Color(0.2, 0.0, 0.0, 0.85))
	title.add_theme_constant_override("outline_size", 6)
	sub.add_theme_font_override("font", spaced(ui_font(), 2))
	sub.add_theme_color_override("font_color", Color(0.88, 0.88, 0.92))


## Look of the HUD guard bar (shown while guarding or recovering): a thin
## steel-blue gauge in a dark sleeve, so it reads as separate from HP.
static func style_guard_bar(bar: ProgressBar) -> void:
	bar.custom_minimum_size.y = 6
	var bg := box(Color(0.03, 0.05, 0.1, 0.7), Color(0.55, 0.75, 1.0, 0.35), 3, 1)
	bg.content_margin_left = 0
	bg.content_margin_right = 0
	bg.content_margin_top = 0
	bg.content_margin_bottom = 0
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", gradient_fill_box([Color("3d7bd9"), Color("8cc4ff"), Color("e6f3ff")], 3))


## Locked-art cover for a skill slot: the card darkens, a padlock sits in
## the middle with the proficiency the art needs under it, and a thin bar
## along the bottom fills toward it. set_state(prof, need) each refresh.
class LockOverlay extends Control:
	var prof := 0
	var need := 1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func set_state(p: int, n: int) -> void:
		var locked := p < n
		if locked != visible or p != prof or n != need:
			prof = p
			need = maxi(n, 1)
			visible = locked
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var cover := StyleBoxFlat.new()
		cover.bg_color = Color(UITheme.NAVY, 0.72)
		cover.set_corner_radius_all(10)
		draw_style_box(cover, r)
		# Diagonal hatching, very faint, so it reads as sealed rather than empty.
		var step := 9.0
		var x := -size.y
		while x < size.x:
			draw_line(Vector2(x, size.y), Vector2(x + size.y, 0), Color(1, 1, 1, 0.035), 1.0)
			x += step
		# Padlock: rounded body and an open-topped shackle.
		var c := Vector2(size.x * 0.5, size.y * 0.38)
		var body := Rect2(c + Vector2(-9, -2), Vector2(18, 14))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UITheme.MUTED, 0.95)
		sb.set_corner_radius_all(3)
		draw_style_box(sb, body)
		draw_arc(c + Vector2(0, -3), 5.5, PI, TAU, 14, Color(UITheme.MUTED, 0.95), 2.5, true)
		draw_line(c + Vector2(-5.5, -3), c + Vector2(-5.5, -1), Color(UITheme.MUTED, 0.95), 2.5)
		draw_line(c + Vector2(5.5, -3), c + Vector2(5.5, -1), Color(UITheme.MUTED, 0.95), 2.5)
		draw_circle(c + Vector2(0, 4), 1.8, UITheme.NAVY)
		draw_line(c + Vector2(0, 4), c + Vector2(0, 8), UITheme.NAVY, 1.5)
		var f := UITheme.ui_bold()
		var t := "PROF %d" % need
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(f, Vector2((size.x - tw) * 0.5, c.y + 25), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UITheme.GOLD, 0.95))
		# Progress toward the unlock.
		var bw := size.x - 16.0
		draw_rect(Rect2(8, size.y - 5, bw, 2), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(8, size.y - 5, bw * clampf(float(prof) / need, 0.0, 1.0), 2), Color(UITheme.CYAN, 0.9))


## Weapon proficiency readout (SAO's skill proficiency): the skill name and
## "41 / 1000" over a thin gauge with a notch at each Sword Art unlock.
class ProfLine extends Control:
	var skill := "One-Handed Sword"
	var value := 0
	var cap := 1000
	var marks: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(0, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(v: int, c: int, m: Array) -> void:
		value = v
		cap = maxi(c, 1)
		marks = m
		queue_redraw()

	func _draw() -> void:
		var f := UITheme.ui_bold()
		draw_string(f, Vector2(0, 13), skill.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)
		var t := "%d / %d" % [value, cap]
		draw_string(f, Vector2(0, 13), t, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 12, UITheme.PARCH)
		var y := 20.0
		var w := size.x
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.08, 0.13, 0.7)
		sb.border_color = Color(1, 1, 1, 0.18)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		draw_style_box(sb, Rect2(0, y, w, 6))
		var frac := clampf(float(value) / cap, 0.0, 1.0)
		if frac > 0.0:
			var fill := StyleBoxFlat.new()
			fill.bg_color = UITheme.CYAN
			fill.set_corner_radius_all(3)
			draw_style_box(fill, Rect2(1, y + 1, maxf((w - 2) * frac, 3.0), 4))
		for m in marks:
			var mx := w * clampf(float(m) / cap, 0.0, 1.0)
			if m <= 0:
				continue
			var got: bool = value >= int(m)
			draw_line(Vector2(mx, y - 2), Vector2(mx, y + 8), UITheme.GOLD if got else Color(1, 1, 1, 0.45), 2.0)


## Permadeath look for a save-slot card (main_menu _slot_card). A living
## one-life climber gets a crimson frame, a crimson portrait ring and a
## "ONE LIFE" badge in the header; a fallen one becomes a memorial: ash
## frame, the card dimmed, the name struck through in red.
static func style_life_card(card: PanelContainer, header: HBoxContainer, name_l: Label, fallen: bool) -> void:
	var crimson := Color(0.86, 0.18, 0.24)
	var sb := card_box(crimson if not fallen else Color(0.45, 0.4, 0.42), 0.9)
	sb.border_width_top = 3
	if not fallen:
		sb.shadow_color = Color(crimson, 0.22)
		sb.shadow_size = 16
	card.add_theme_stylebox_override("panel", sb)
	var badge := PanelContainer.new()
	var bb := box(Color(crimson, 0.18 if not fallen else 0.08), Color(crimson, 0.7 if not fallen else 0.35), 8, 1)
	bb.content_margin_left = 8
	bb.content_margin_right = 8
	bb.content_margin_top = 1
	bb.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", bb)
	var bl := label("FALLEN" if fallen else "ONE LIFE", 11, crimson.lightened(0.25) if not fallen else Color(0.7, 0.55, 0.58), true)
	bl.add_theme_font_override("font", spaced(ui_bold(), 3))
	badge.add_child(bl)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(badge)
	header.move_child(badge, 1)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	header.add_child(gap)
	header.move_child(gap, 1)
	if fallen:
		card.modulate = Color(0.78, 0.74, 0.76)
		var strike := ColorRect.new()
		strike.color = Color(crimson, 0.9)
		strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_l.add_child(strike)
		name_l.resized.connect(func():
			var w := name_l.get_theme_font("font").get_string_size(name_l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_l.get_theme_font_size("font_size")).x
			strike.position = Vector2(-4, name_l.size.y * 0.5)
			strike.size = Vector2(w + 8, 3))
