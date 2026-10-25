class_name FishingWidget
extends Control
## Fishing minigame overlay: a track with a green zone and a bobbing marker.
## The world's Fishing node starts it with the fish's difficulty, polls
## `in_zone()` when E is pressed and reads `expired()` when the bite window
## runs out. Everything is drawn in code; the widget owns the oscillation so
## the feel is identical offline and online.

const W := 420.0
const H := 30.0

var _active := false
var _t := 0.0
var _zone := 0.3
var _speed := 1.0
var _window := 3.0
var _left := 0.0
var _zone_center := 0.5
var _phase := 0.0
var _title: Label
var _hint: Label
var _flash := 0.0
var _flash_color := Color.WHITE
var _marker := 0.5


static func attach(parent: Control) -> FishingWidget:
	var w := FishingWidget.new()
	w.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	w.grow_horizontal = Control.GROW_DIRECTION_BOTH
	w.grow_vertical = Control.GROW_DIRECTION_BEGIN
	w.offset_left = -W * 0.5 - 24
	w.offset_right = W * 0.5 + 24
	w.offset_top = -150 - 96
	w.offset_bottom = -150
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(w)
	w._build()
	w.hide()
	return w


func _build() -> void:
	_title = UITheme.heading("", 22, UITheme.PARCH)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 0
	_title.offset_bottom = 30
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_title.add_theme_constant_override("outline_size", 6)
	add_child(_title)
	_hint = UITheme.label("", 13, UITheme.MUTED, true)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -22
	_hint.offset_bottom = 0
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 5)
	add_child(_hint)


## Starts the bite phase. `diff` comes from LifeData.difficulty().
func start(diff: Dictionary, fish_name := "") -> void:
	_zone = float(diff.get("zone", 0.3))
	_speed = float(diff.get("speed", 1.0))
	_window = float(diff.get("window", 3.0))
	_left = _window
	_zone_center = randf_range(0.25, 0.75)
	_phase = randf() * TAU
	_t = 0.0
	_flash = 0.0
	_active = true
	_title.text = "Something bites!" if fish_name == "" else "Something bites!"
	_hint.text = "Press  E  when the marker is in the green"
	show()
	queue_redraw()


## Visible resolution: tint the track, then fade out.
func finish(success: bool, text: String) -> void:
	_active = false
	_flash = 1.0
	_flash_color = UITheme.GREEN if success else UITheme.ROSE
	_title.text = text
	_hint.text = ""
	queue_redraw()
	var tw := create_tween()
	tw.tween_interval(1.1)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func():
		hide()
		modulate.a = 1.0)


func cancel() -> void:
	_active = false
	hide()


func is_active() -> bool:
	return _active


func marker() -> float:
	return _marker


func in_zone() -> bool:
	return _active and absf(_marker - _zone_center) <= _zone * 0.5


func expired() -> bool:
	return _active and _left <= 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	if _active:
		_t += delta
		_left -= delta
		# A sine with a slower second harmonic: readable, not metronomic.
		_marker = 0.5 + 0.47 * sin(_t * _speed * TAU * 0.5 + _phase) * (0.8 + 0.2 * sin(_t * 1.3))
		_marker = clampf(_marker, 0.03, 0.97)
	elif _flash > 0.0:
		_flash = maxf(_flash - delta * 1.4, 0.0)
	queue_redraw()


func _draw() -> void:
	var x0 := (size.x - W) * 0.5
	var y0 := 36.0
	var track := Rect2(x0, y0, W, H)
	# Track with a soft outer shadow.
	draw_rect(Rect2(track.position - Vector2(3, 3), track.size + Vector2(6, 6)), Color(0, 0, 0, 0.35))
	draw_rect(track, Color(UITheme.NAVY.r, UITheme.NAVY.g, UITheme.NAVY.b, 0.9))
	# Water tint fading to the sides.
	draw_rect(Rect2(x0 + 2, y0 + 2, W - 4, H - 4), Color(0.1, 0.3, 0.45, 0.55))
	# Green zone.
	var zx := x0 + (_zone_center - _zone * 0.5) * W
	var zw := _zone * W
	var zc := UITheme.GREEN if _flash <= 0.0 else _flash_color
	draw_rect(Rect2(zx, y0 + 2, zw, H - 4), Color(zc.r, zc.g, zc.b, 0.55))
	draw_rect(Rect2(zx, y0 + 2, zw, 3), Color(zc.r, zc.g, zc.b, 0.95))
	draw_rect(Rect2(zx, y0 + H - 5, zw, 3), Color(zc.r, zc.g, zc.b, 0.95))
	# Gold frame.
	draw_rect(track, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.8), false, 2.0)
	# Marker: a fish-shaped teardrop.
	var mx := x0 + _marker * W
	var my := y0 + H * 0.5
	var mc := UITheme.PARCH if _flash <= 0.0 else _flash_color
	var pts := PackedVector2Array([Vector2(mx - 9, my), Vector2(mx - 2, my - 8), Vector2(mx + 9, my - 3), Vector2(mx + 14, my - 8), Vector2(mx + 13, my + 8), Vector2(mx + 9, my + 3), Vector2(mx - 2, my + 8)])
	draw_colored_polygon(pts, Color(0, 0, 0, 0.5))
	for i in pts.size():
		pts[i] -= Vector2(1.5, 1.5)
	draw_colored_polygon(pts, mc)
	draw_circle(Vector2(mx - 4, my - 2), 1.6, UITheme.NAVY)
	# Bite window timer under the track.
	var frac := clampf(_left / maxf(_window, 0.01), 0.0, 1.0) if _active else 0.0
	draw_rect(Rect2(x0, y0 + H + 6, W, 5), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(x0, y0 + H + 6, W * frac, 5), Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.9))
	if _flash > 0.0:
		draw_rect(track, Color(_flash_color.r, _flash_color.g, _flash_color.b, 0.35 * _flash))
