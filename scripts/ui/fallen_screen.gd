class_name FallenScreen
extends Control
## Permadeath fall (Permadeath, one life): the world fades to black behind a
## slow crimson vignette, "<NAME> HAS FALLEN" rises in ash white, the fall
## line (cause, place, level, date) follows, then the name is struck through
## with a red line, as it now is on the Monument of Climbers. A countdown
## runs for `secs` (Permadeath.FALL_SCREEN); the caller returns to the menu.
## FallenScreen.show_in(root, name, info, secs)

const ASH := Color(0.92, 0.9, 0.9)
const BLOOD := Color(0.86, 0.16, 0.2)

var _name := ""
var _info: Dictionary
var _secs := 9.0
var _left := 0.0
var _count: Label
var _strike: ColorRect
var _name_l: Label


static func show_in(root: Control, char_name: String, info: Dictionary, secs := 9.0) -> FallenScreen:
	for c in root.get_children():
		if c is FallenScreen:
			c.queue_free()
	var f := FallenScreen.new()
	f._name = char_name
	f._info = info
	f._secs = secs
	root.add_child(f)
	return f


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# Crimson vignette: a radial gradient, transparent in the middle.
	var vig := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(BLOOD, 0.0), Color(BLOOD, 0.0), Color(BLOOD.darkened(0.5), 0.55)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	vig.texture = gt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.modulate.a = 0.0
	add_child(vig)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var k := _caption("PERMADEATH", 14, BLOOD, UITheme.ui_bold(), 8)
	v.add_child(k)
	# The name, with the strike line drawn over it.
	var name_box := CenterContainer.new()
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_box)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_box.add_child(holder)
	_name_l = _caption(_name.to_upper(), 52, ASH, UITheme.display_font(), 6)
	holder.add_child(_name_l)
	var sz := _name_l.get_minimum_size()
	holder.custom_minimum_size = sz
	_strike = ColorRect.new()
	_strike.color = BLOOD
	_strike.position = Vector2(-12, sz.y * 0.52)
	_strike.size = Vector2(0, 4)
	_strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_strike)
	var fell := _caption("HAS  FALLEN", 26, ASH.darkened(0.15), UITheme.display_font(), 10)
	v.add_child(fell)
	v.add_child(UITheme.spacer(6))
	var line := _caption(Permadeath.fall_text(_info) if not _info.is_empty() else "", 16, Color(0.75, 0.72, 0.74), UITheme.ui_font(), 1)
	v.add_child(line)
	var mon := _caption("The name is struck from the Monument of Climbers.", 15, Color(0.6, 0.58, 0.62), UITheme.ui_font(), 1)
	v.add_child(mon)
	v.add_child(UITheme.spacer(18))
	_count = _caption("", 13, Color(0.55, 0.55, 0.6), UITheme.ui_bold(), 3)
	v.add_child(_count)
	for c in [k, _name_l, fell, line, mon, _count]:
		(c as CanvasItem).modulate.a = 0.0
	_left = _secs
	Audio.play("player_death", null, 0.0, -4.0, 0.7)
	var tw := create_tween()
	tw.tween_property(bg, "color:a", 0.9, 1.2)
	tw.parallel().tween_property(vig, "modulate:a", 1.0, 2.0)
	tw.tween_property(k, "modulate:a", 1.0, 0.5)
	tw.tween_property(_name_l, "modulate:a", 1.0, 0.9)
	tw.tween_property(fell, "modulate:a", 1.0, 0.7)
	tw.tween_property(line, "modulate:a", 1.0, 0.6)
	tw.tween_interval(0.4)
	tw.tween_callback(func(): Audio.play("shatter", null, 0.0, -6.0, 0.6))
	tw.tween_property(_strike, "size:x", sz.x + 24.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_name_l, "modulate", Color(0.62, 0.5, 0.52, 1.0), 0.55)
	tw.tween_property(mon, "modulate:a", 1.0, 0.6)
	tw.tween_property(_count, "modulate:a", 1.0, 0.4)


func _process(dt: float) -> void:
	_left = maxf(_left - dt, 0.0)
	if _count:
		_count.text = "RETURNING TO THE TITLE IN %d" % maxi(ceili(_left), 1)


func _caption(text: String, px: int, col: Color, font: Font, spacing: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", UITheme.spaced(font, spacing))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	return l
