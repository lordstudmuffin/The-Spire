class_name UIGlyph
extends Control
## Small vector icons drawn in code so the UI needs no icon art:
## sword, shield, ore, hide, shard, star, coin, scroll, skull, fish, herb,
## rod, food, home, rest.
## Everything is drawn from the control's size, so it scales with layout.

var kind := "sword"
var color := Color.WHITE
var glow := 0.0  # 0..1 soft halo behind the glyph

var _pts := PackedVector2Array()


static func make(k: String, c: Color, px := 36, halo := 0.0) -> UIGlyph:
	var g := UIGlyph.new()
	g.kind = k
	g.color = c
	g.glow = halo
	g.custom_minimum_size = Vector2(px, px)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func set_glyph(k: String, c: Color) -> void:
	if k == kind and c == color:
		return
	kind = k
	color = c
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	if glow > 0.0:
		draw_circle(c, s * 0.5, Color(color.r, color.g, color.b, 0.10 * glow))
		draw_circle(c, s * 0.36, Color(color.r, color.g, color.b, 0.12 * glow))
	var dark := Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, color.a)
	var light := Color(minf(color.r * 1.35, 1.0), minf(color.g * 1.35, 1.0), minf(color.b * 1.35, 1.0), color.a)
	match kind:
		"sword":
			# Blade from bottom-left to top-right, gold guard, dark grip.
			_poly([Vector2(0.22, 0.78), Vector2(0.30, 0.86), Vector2(0.86, 0.30), Vector2(0.84, 0.16), Vector2(0.70, 0.14)], s, light)
			_poly([Vector2(0.22, 0.78), Vector2(0.86, 0.30), Vector2(0.84, 0.16)], s, color)
			_poly([Vector2(0.14, 0.60), Vector2(0.40, 0.86), Vector2(0.34, 0.92), Vector2(0.08, 0.66)], s, Color("f0c060"))
			_poly([Vector2(0.10, 0.80), Vector2(0.20, 0.90), Vector2(0.06, 0.94)], s, Color("6b4a1e"))
		"shield":
			_poly([Vector2(0.5, 0.08), Vector2(0.88, 0.22), Vector2(0.84, 0.56), Vector2(0.5, 0.92), Vector2(0.16, 0.56), Vector2(0.12, 0.22)], s, dark)
			_poly([Vector2(0.5, 0.16), Vector2(0.80, 0.27), Vector2(0.77, 0.54), Vector2(0.5, 0.83), Vector2(0.23, 0.54), Vector2(0.20, 0.27)], s, color)
			_poly([Vector2(0.5, 0.26), Vector2(0.64, 0.42), Vector2(0.5, 0.70), Vector2(0.36, 0.42)], s, light)
		"ore":
			_poly([Vector2(0.18, 0.78), Vector2(0.12, 0.52), Vector2(0.34, 0.24), Vector2(0.66, 0.18), Vector2(0.88, 0.46), Vector2(0.82, 0.80)], s, dark)
			_poly([Vector2(0.34, 0.24), Vector2(0.66, 0.18), Vector2(0.88, 0.46), Vector2(0.56, 0.50)], s, color)
			_poly([Vector2(0.18, 0.78), Vector2(0.12, 0.52), Vector2(0.34, 0.24), Vector2(0.56, 0.50)], s, light)
			draw_circle(Vector2(0.50, 0.62) * s, s * 0.05, Color("f0c060"))
			draw_circle(Vector2(0.66, 0.70) * s, s * 0.035, Color("f0c060"))
		"hide":
			_poly([Vector2(0.14, 0.30), Vector2(0.30, 0.14), Vector2(0.70, 0.14), Vector2(0.86, 0.30), Vector2(0.80, 0.56), Vector2(0.86, 0.84), Vector2(0.60, 0.74), Vector2(0.40, 0.74), Vector2(0.14, 0.84), Vector2(0.20, 0.56)], s, color)
			_poly([Vector2(0.28, 0.32), Vector2(0.40, 0.24), Vector2(0.60, 0.24), Vector2(0.72, 0.32), Vector2(0.66, 0.56), Vector2(0.34, 0.56)], s, light)
		"shard":
			_poly([Vector2(0.5, 0.06), Vector2(0.78, 0.40), Vector2(0.5, 0.94), Vector2(0.22, 0.40)], s, dark)
			_poly([Vector2(0.5, 0.06), Vector2(0.78, 0.40), Vector2(0.5, 0.44)], s, light)
			_poly([Vector2(0.5, 0.06), Vector2(0.22, 0.40), Vector2(0.5, 0.44)], s, color)
			_poly([Vector2(0.22, 0.40), Vector2(0.5, 0.94), Vector2(0.5, 0.44)], s, light)
			_poly([Vector2(0.78, 0.40), Vector2(0.5, 0.94), Vector2(0.5, 0.44)], s, color)
		"horn":
			_poly([Vector2(0.18, 0.86), Vector2(0.30, 0.56), Vector2(0.50, 0.30), Vector2(0.80, 0.12), Vector2(0.86, 0.22), Vector2(0.62, 0.42), Vector2(0.46, 0.66), Vector2(0.36, 0.90)], s, color)
			_poly([Vector2(0.30, 0.56), Vector2(0.50, 0.30), Vector2(0.56, 0.38), Vector2(0.40, 0.62)], s, light)
			_poly([Vector2(0.18, 0.86), Vector2(0.36, 0.90), Vector2(0.30, 0.96), Vector2(0.14, 0.94)], s, dark)
		"coin":
			draw_circle(c, s * 0.42, dark)
			draw_circle(c, s * 0.36, color)
			draw_arc(c, s * 0.26, 0.0, TAU, 32, dark, s * 0.05, true)
		"star":
			_pts.resize(10)
			for i in 10:
				var a := -PI / 2 + i * PI / 5
				var r := 0.46 if i % 2 == 0 else 0.20
				_pts[i] = (Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * r) * s
			draw_colored_polygon(_pts, color)
		"scroll":
			draw_rect(Rect2(Vector2(0.22, 0.14) * s, Vector2(0.56, 0.72) * s), color)
			draw_rect(Rect2(Vector2(0.16, 0.10) * s, Vector2(0.68, 0.12) * s), dark)
			draw_rect(Rect2(Vector2(0.16, 0.78) * s, Vector2(0.68, 0.12) * s), dark)
			for i in 3:
				draw_rect(Rect2(Vector2(0.30, 0.32 + i * 0.14) * s, Vector2(0.40, 0.05) * s), dark)
		"skull":
			draw_circle(c + Vector2(0, -s * 0.06), s * 0.30, color)
			draw_rect(Rect2(c + Vector2(-s * 0.18, s * 0.14), Vector2(s * 0.36, s * 0.20)), color)
			draw_circle(c + Vector2(-s * 0.11, -s * 0.08), s * 0.08, dark)
			draw_circle(c + Vector2(s * 0.11, -s * 0.08), s * 0.08, dark)
			draw_rect(Rect2(c + Vector2(-s * 0.03, s * 0.04), Vector2(s * 0.06, s * 0.08)), dark)
		"arrow":
			_poly([Vector2(0.5, 0.06), Vector2(0.86, 0.90), Vector2(0.5, 0.70), Vector2(0.14, 0.90)], s, color)
		"fish":
			# Body, tail and an eye.
			_poly([Vector2(0.14, 0.5), Vector2(0.34, 0.26), Vector2(0.62, 0.22), Vector2(0.80, 0.42), Vector2(0.80, 0.58), Vector2(0.62, 0.78), Vector2(0.34, 0.74)], s, color)
			_poly([Vector2(0.78, 0.5), Vector2(0.94, 0.30), Vector2(0.94, 0.70)], s, dark)
			_poly([Vector2(0.34, 0.26), Vector2(0.62, 0.22), Vector2(0.56, 0.44), Vector2(0.30, 0.46)], s, light)
			draw_circle(Vector2(0.30, 0.46) * s, s * 0.045, Color("0b1024"))
		"herb":
			for k in 3:
				var ang := -PI / 2 + (k - 1) * 0.6
				var tip := Vector2(0.5, 0.86) + Vector2(cos(ang), sin(ang)) * 0.62
				var mid := Vector2(0.5, 0.86) + Vector2(cos(ang), sin(ang)) * 0.32
				var nrm := Vector2(-sin(ang), cos(ang)) * 0.11
				_poly([Vector2(0.5, 0.86), mid + nrm, tip, mid - nrm], s, [dark, color, light][k])
			draw_circle(Vector2(0.5, 0.26) * s, s * 0.06, Color("f3e9b0"))
		"rod":
			_poly([Vector2(0.12, 0.90), Vector2(0.18, 0.92), Vector2(0.88, 0.14), Vector2(0.84, 0.10)], s, color)
			draw_line(Vector2(0.86, 0.12) * s, Vector2(0.72, 0.62) * s, light, maxf(s * 0.03, 1.0))
			draw_circle(Vector2(0.72, 0.66) * s, s * 0.06, Color("e63946"))
			_poly([Vector2(0.12, 0.90), Vector2(0.18, 0.92), Vector2(0.30, 0.78), Vector2(0.24, 0.76)], s, dark)
		"food":
			# Bowl with a steaming heap.
			_poly([Vector2(0.14, 0.52), Vector2(0.86, 0.52), Vector2(0.76, 0.84), Vector2(0.24, 0.84)], s, dark)
			draw_rect(Rect2(Vector2(0.14, 0.48) * s, Vector2(0.72, 0.08) * s), light)
			draw_circle(Vector2(0.5, 0.46) * s, s * 0.22, color)
			draw_circle(Vector2(0.38, 0.40) * s, s * 0.12, light)
			draw_circle(Vector2(0.62, 0.42) * s, s * 0.10, light)
			for k in 2:
				var x := 0.40 + k * 0.2
				draw_line(Vector2(x, 0.22) * s, Vector2(x + 0.04, 0.10) * s, Color(1, 1, 1, 0.45), maxf(s * 0.03, 1.0))
		"home":
			_poly([Vector2(0.5, 0.10), Vector2(0.92, 0.46), Vector2(0.08, 0.46)], s, dark)
			draw_rect(Rect2(Vector2(0.20, 0.46) * s, Vector2(0.60, 0.42) * s), color)
			draw_rect(Rect2(Vector2(0.42, 0.62) * s, Vector2(0.16, 0.26) * s), dark)
			draw_rect(Rect2(Vector2(0.64, 0.18) * s, Vector2(0.10, 0.18) * s), light)
		"rest":
			draw_circle(c, s * 0.34, color)
			draw_circle(c + Vector2(s * 0.14, -s * 0.10), s * 0.28, Color(UITheme.NAVY.r, UITheme.NAVY.g, UITheme.NAVY.b, 0.85))
			draw_circle(Vector2(0.80, 0.22) * s, s * 0.04, light)
			draw_circle(Vector2(0.88, 0.40) * s, s * 0.03, light)
		_:
			draw_circle(c, s * 0.3, color)


func _poly(unit: Array, s: float, col: Color) -> void:
	_pts.resize(unit.size())
	for i in unit.size():
		_pts[i] = unit[i] * s
	draw_colored_polygon(_pts, col)
