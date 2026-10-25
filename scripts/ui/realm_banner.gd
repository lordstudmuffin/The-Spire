class_name RealmBanner
extends Control
## Server-wide announcement (HUD.realm_announce): a full-width strip of
## drifting hexagon lines opens from the centre of the upper screen with a
## "SYSTEM ANNOUNCEMENT" kicker and the message, holds, then closes. One
## banner at a time; a new announcement replaces the old one.

const HEIGHT := 112.0
const TOP := 0.2  # fraction of the screen height
const HOLD := 3.6

var _strip: ColorRect
var _mat: ShaderMaterial
var _kicker: Label
var _text: Label
var _tw: Tween


static func show_on(parent: Control, text: String) -> void:
	var b: RealmBanner = null
	for c in parent.get_children():
		if c is RealmBanner:
			b = c
	if b == null:
		b = RealmBanner.new()
		parent.add_child(b)
	b.play(text)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	_strip = ColorRect.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/system_banner.gdshader")
	_strip.material = _mat
	add_child(_strip)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	_kicker = _label(13, Color(1.0, 0.72, 0.5), 6)
	_kicker.text = "SYSTEM ANNOUNCEMENT"
	v.add_child(_kicker)
	_text = _label(26, Color(1, 0.97, 0.94), 2)
	v.add_child(_text)


func _label(px: int, col: Color, spacing: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UITheme.spaced(UITheme.ui_bold(), spacing))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.02, 0.0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func play(text: String) -> void:
	var vp := get_viewport_rect().size
	position = Vector2(0, vp.y * TOP)
	size = Vector2(vp.x, HEIGHT)
	_mat.set_shader_parameter("rect_size", size)
	_text.text = text
	visible = true
	if _tw:
		_tw.kill()
	_mat.set_shader_parameter("open_amount", 0.0)
	_kicker.modulate.a = 0.0
	_text.modulate.a = 0.0
	_tw = create_tween()
	_tw.tween_method(_set_open, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw.parallel().tween_property(_kicker, "modulate:a", 1.0, 0.3).set_delay(0.15)
	_tw.parallel().tween_property(_text, "modulate:a", 1.0, 0.35).set_delay(0.25)
	_tw.tween_interval(HOLD)
	_tw.tween_property(_text, "modulate:a", 0.0, 0.25)
	_tw.parallel().tween_property(_kicker, "modulate:a", 0.0, 0.25)
	_tw.tween_method(_set_open, 1.0, 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tw.tween_callback(func(): visible = false)


func _set_open(v: float) -> void:
	_mat.set_shader_parameter("open_amount", v)
