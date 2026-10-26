class_name ForgeWidget
extends Control
## The anvil's forging minigame (Forging): a heat bar with a hot zone and a
## sweeping spark, one bar per hammer strike. The HUD puts it in the anvil
## panel; the widget owns the clock and grades each strike locally for
## instant feedback. Online every strike also goes to the server, whose own
## grading decides the piece; offline the HUD forges with `finished`'s
## quality. Drawn in code.

signal finished(recipe: String, quality: float, grades: Array)

const W := 520.0
const H := 34.0
const Y0 := 84.0  # bar top; the grade pop sits between the title and the bar
const GRADE_COLORS := {"perfect": Color("fff1b8"), "good": Color("f0c060"), "glance": Color("e08a4a"), "miss": Color("ff4d6d")}

var recipe := ""
var specs: Array = []
var grades: Array = []
var online := false
var _start_ms := 0
var _last := 0          # client ms of the previous strike (strike i opens there)
var _active := false
var _waiting := false   # online: all strikes sent, the server answers
var _pop := ""
var _pop_t := 0.0
var _shake := 0.0
var _title: Label
var _hint: Label
## Visual-only: hammer flash, spark spray, embers and the spark's trail.
var _flash := 0.0
var _flash_col := Color.WHITE
var _sparks: Array = []   # {p, v, life, max, col}
var _embers: Array = []   # {p, v, life, max}
var _trail: Array = []    # recent spark x positions (track fraction)
var _ember_t := 0.0


static func make() -> ForgeWidget:
	var w := ForgeWidget.new()
	w.custom_minimum_size = Vector2(W + 40, 226)
	w.mouse_filter = Control.MOUSE_FILTER_STOP
	w._build()
	return w


func _build() -> void:
	_title = UITheme.heading("", 24, UITheme.PARCH)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_bottom = 32
	add_child(_title)
	_hint = UITheme.hint_label("Strike: %s / %s / click", ["interact", "jump"], 13)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -22
	add_child(_hint)


func begin(recipe_name: String, strike_specs: Array, is_online: bool) -> void:
	recipe = recipe_name
	specs = strike_specs
	online = is_online
	grades = []
	_start_ms = Time.get_ticks_msec()
	_last = 0
	_active = true
	_waiting = false
	_pop = ""
	_title.text = "Forging %s" % recipe_name
	queue_redraw()


func is_active() -> bool:
	return _active or _waiting


func cancel() -> void:
	_active = false
	_waiting = false


## Online: the server's answer arrived (or refused the piece).
func resolve(text: String) -> void:
	_waiting = false
	_title.text = text
	queue_redraw()


func _elapsed() -> int:
	return Time.get_ticks_msec() - _start_ms


## Strike now. Ignores presses closer than the server's minimum gap.
func strike() -> void:
	if not _active:
		return
	var at := _elapsed()
	if at < _last + Forging.MIN_GAP_MS + 20:
		return
	_land(at)


func _land(at: int) -> void:
	var i := grades.size()
	var g := Forging.grade(specs[i], float(at - _last))
	var hit_x := Forging.mark(specs[i], float(at - _last))
	grades.append(g)
	_last = at
	if online:
		Net.request_action("forge_strike", {"i": i, "at": at})
	_pop = g
	_pop_t = 1.0
	_shake = 1.0 if g != "miss" else 0.4
	_spray(hit_x, g)
	match g:
		"perfect":
			Audio.play("anvil", null, 0.02, 2.0, 1.25)
			Audio.play("craft_pot", null, 0.04, -6.0, 1.4)
		"good":
			Audio.play("anvil", null, 0.06, 0.0, 1.05)
		"glance":
			Audio.play("anvil", null, 0.06, -4.0, 0.8)
		_:
			Audio.play("craft_fail", null, 0.04, -8.0)
	if grades.size() >= specs.size():
		_active = false
		var q := Forging.quality(grades)
		_title.text = "%s work" % Forging.quality_word(q)
		_waiting = true  # until the piece is forged (resolve) or refused
		finished.emit(recipe, q, grades.duplicate())
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not _active or not is_visible_in_tree():
		return
	var hit := false
	if event is InputEventMouseButton:
		hit = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif not event.is_echo():
		hit = event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("ui_accept")
	if hit:
		strike()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _active and float(_elapsed() - _last) > Forging.STRIKE_WINDOW * 1000.0:
		_land(_elapsed())  # the strike window ran out: a miss
	_pop_t = maxf(_pop_t - delta * 1.3, 0.0)
	_shake = maxf(_shake - delta * 6.0, 0.0)
	_flash = maxf(_flash - delta * 4.0, 0.0)
	_tick_fx(delta)
	queue_redraw()


## Heat colour at distance d (in zone widths) from the zone centre: white-hot
## core (Perfect), orange body (Good), dull red fringe (Glance).
func _heat(d: float) -> Color:
	if d <= 0.18:
		return Color(1.0, 0.96, 0.8, 0.96).lerp(Color(1.0, 0.86, 0.55, 0.92), d / 0.18)
	if d <= 0.5:
		return Color(1.0, 0.8, 0.45, 0.88).lerp(Color(1.0, 0.5, 0.16, 0.72), (d - 0.18) / 0.32)
	return Color(0.9, 0.32, 0.12, 0.5).lerp(Color(0.6, 0.15, 0.08, 0.0), clampf((d - 0.5) / 0.5, 0.0, 1.0))


## Horizontal-gradient quad from x0 to x1 (no seams between neighbours).
func _hquad(x0: float, x1: float, y: float, h: float, c0: Color, c1: Color) -> void:
	draw_polygon(PackedVector2Array([Vector2(x0, y), Vector2(x1, y), Vector2(x1, y + h), Vector2(x0, y + h)]), PackedColorArray([c0, c1, c1, c0]))


## Sparks fly from the strike point; a Perfect throws a white-hot fan and
## flashes the bar, a miss only spits a few dull cinders.
func _spray(x_frac: float, g: String) -> void:
	var n: int = {"perfect": 34, "good": 20, "glance": 10}.get(g, 5)
	var col: Color = GRADE_COLORS.get(g, Color.WHITE)
	_flash = {"perfect": 1.0, "good": 0.6, "glance": 0.35}.get(g, 0.15)
	_flash_col = Color(1, 0.97, 0.85) if g == "perfect" else col
	for k in n:
		var a := randf_range(PI * 1.05, PI * 1.95)  # upward fan
		var sp := randf_range(120.0, 360.0) * (1.25 if g == "perfect" else 1.0)
		var life := randf_range(0.35, 0.8)
		_sparks.append({"p": Vector2((size.x - W) * 0.5 + x_frac * W, Y0 + H * 0.5), "v": Vector2(cos(a), sin(a)) * sp, "life": life, "max": life,
			"col": col.lerp(Color(1, 0.55, 0.2), randf() * 0.5) if g != "miss" else Color(0.5, 0.3, 0.25)})


func _tick_fx(delta: float) -> void:
	var x0 := (size.x - W) * 0.5
	for sp in _sparks:
		sp["v"].y += 520.0 * delta
		sp["v"] *= 1.0 - 1.5 * delta
		sp["p"] += sp["v"] * delta
		sp["life"] -= delta
	_sparks = _sparks.filter(func(sp): return sp["life"] > 0.0)
	# Embers rise from the hot zone while the bar is live.
	if _active and not specs.is_empty():
		_ember_t -= delta
		if _ember_t <= 0.0:
			_ember_t = 0.06
			var spec: Dictionary = specs[mini(grades.size(), specs.size() - 1)]
			var c := float(spec["center"])
			var w := float(spec["width"])
			var life := randf_range(0.8, 1.6)
			_embers.append({"p": Vector2(x0 + (c + randf_range(-w, w) * 0.8) * W, Y0 + randf_range(4.0, H - 4.0)),
				"v": Vector2(randf_range(-10, 10), randf_range(-38, -20)), "life": life, "max": life})
	for e in _embers:
		e["p"] += e["v"] * delta
		e["v"].x += sin(e["life"] * 7.0) * 12.0 * delta
		e["life"] -= delta
	_embers = _embers.filter(func(e): return e["life"] > 0.0)
	# Spark trail.
	if _active and not specs.is_empty():
		_trail.push_front(Forging.mark(specs[mini(grades.size(), specs.size() - 1)], float(_elapsed() - _last)))
		if _trail.size() > 7:
			_trail.pop_back()
	else:
		_trail.clear()


func _draw() -> void:
	if specs.is_empty():
		return
	var x0 := (size.x - W) * 0.5
	var y0 := Y0
	var i := mini(grades.size(), specs.size() - 1)
	var spec: Dictionary = specs[i]
	var jolt := Vector2(sin(_shake * 40.0) * 3.0 * _shake, 0)
	var track := Rect2(Vector2(x0, y0) + jolt, Vector2(W, H))
	# Iron bed with a cool-to-hot sheen.
	draw_rect(Rect2(track.position - Vector2(4, 4), track.size + Vector2(8, 8)), Color(0, 0, 0, 0.45))
	draw_rect(track, Color(0.09, 0.08, 0.1, 0.95))
	_hquad(track.position.x, track.position.x + W, track.position.y + 2, H - 4, Color(0.25, 0.12, 0.08, 0.35), Color(0.35, 0.12, 0.08, 0.35))
	# Hot zone: soft heat falloff in slices (dull red at the fringe, orange
	# body, white-hot perfect core), so the zone reads as glowing metal.
	var c := float(spec["center"])
	var w := float(spec["width"])
	var slices := 40
	var span := w * 1.0  # the fringe reaches past the glance edge (0.85w)
	for k in slices:
		var f0 := -span + 2.0 * span * float(k) / slices
		var f1 := -span + 2.0 * span * float(k + 1) / slices
		var a0 := clampf(c + f0, 0.0, 1.0)
		var a1 := clampf(c + f1, 0.0, 1.0)
		if a1 > a0:
			_hquad(track.position.x + a0 * W, track.position.x + a1 * W, track.position.y + 2, H - 4, _heat(absf(f0) / w), _heat(absf(f1) / w))
	# Grade edges as faint ticks (perfect and good bounds).
	for e in [-0.5, -0.18, 0.18, 0.5]:
		var ex := track.position.x + clampf(c + e * w, 0.0, 1.0) * W
		draw_line(Vector2(ex, track.position.y + 2), Vector2(ex, track.position.y + 6), Color(0, 0, 0, 0.25), 1.0)
		draw_line(Vector2(ex, track.position.y + H - 6), Vector2(ex, track.position.y + H - 2), Color(0, 0, 0, 0.25), 1.0)
	# Embers drifting up off the heat.
	for e2 in _embers:
		var t2: float = e2["life"] / e2["max"]
		draw_circle(e2["p"] + jolt, 1.6 + t2, Color(1.0, 0.55 + 0.3 * t2, 0.2, 0.75 * t2))
	draw_rect(track, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.75), false, 2.0)
	# Spark.
	if _active:
		var m := Forging.mark(spec, float(_elapsed() - _last))
		var mx := track.position.x + m * W
		# Fading trail behind the spark.
		for k in range(_trail.size() - 1, 0, -1):
			var tx: float = track.position.x + float(_trail[k]) * W
			var ta := 0.35 * (1.0 - float(k) / _trail.size())
			draw_rect(Rect2(tx - 2, track.position.y + 2, 4, H - 4), Color(1.0, 0.8, 0.5, ta))
		draw_rect(Rect2(mx - 2, track.position.y - 6, 4, H + 12), Color(1, 1, 1, 0.95))
		draw_circle(Vector2(mx, track.position.y - 8), 5.0, Color(1.0, 0.85, 0.5, 0.9))
		draw_circle(Vector2(mx, track.position.y - 8), 9.0, Color(1.0, 0.6, 0.2, 0.25))
		# Strike window, cooling away under the bar.
		var left := 1.0 - clampf(float(_elapsed() - _last) / (Forging.STRIKE_WINDOW * 1000.0), 0.0, 1.0)
		draw_rect(Rect2(x0, y0 + H + 8, W, 5), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(x0, y0 + H + 8, W * left, 5), Color(1.0, 0.55 + 0.3 * left, 0.2, 0.9))
	# Hammer flash over the bar, then flying sparks.
	if _flash > 0.0:
		draw_rect(track.grow(2.0 + 6.0 * _flash), Color(_flash_col, 0.18 * _flash))
		draw_rect(track, Color(_flash_col, 0.55 * _flash))
	for sp in _sparks:
		var t3: float = sp["life"] / sp["max"]
		var tail: Vector2 = sp["v"] * 0.025
		var sc: Color = sp["col"]
		draw_line(sp["p"] - tail * 1.4, sp["p"], Color(sc, t3), 2.6)
		draw_circle(sp["p"], 1.9, Color(1, 1, 0.9, t3))
	# Strike pips.
	var font := UITheme.ui_bold()
	var n := specs.size()
	var px0 := size.x * 0.5 - (n - 1) * 22.0
	for k in n:
		var p := Vector2(px0 + k * 44.0, y0 + H + 40)
		var col := Color(1, 1, 1, 0.18)
		if k < grades.size():
			col = GRADE_COLORS.get(grades[k], col)
		elif k == grades.size() and _active:
			col = Color(1, 1, 1, 0.55)
		draw_circle(p, 9.0, Color(0, 0, 0, 0.5))
		draw_circle(p, 7.0, col)
	# Grade pop.
	if _pop != "" and _pop_t > 0.0:
		var gc: Color = GRADE_COLORS.get(_pop, Color.WHITE)
		gc.a = _pop_t
		var txt: String = Forging.GRADE_NAMES.get(_pop, _pop)
		var fs := 22 + int(6.0 * _pop_t)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, Vector2(size.x * 0.5 - tw * 0.5, y0 - 12 - 10.0 * (1.0 - _pop_t)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.7 * _pop_t))
		draw_string(font, Vector2(size.x * 0.5 - tw * 0.5, y0 - 12 - 10.0 * (1.0 - _pop_t)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, gc)
