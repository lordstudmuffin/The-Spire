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


static func make() -> ForgeWidget:
	var w := ForgeWidget.new()
	w.custom_minimum_size = Vector2(W + 40, 210)
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
	grades.append(g)
	_last = at
	if online:
		Net.request_action("forge_strike", {"i": i, "at": at})
	_pop = g
	_pop_t = 1.0
	_shake = 1.0 if g != "miss" else 0.4
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
	queue_redraw()


func _draw() -> void:
	if specs.is_empty():
		return
	var x0 := (size.x - W) * 0.5
	var y0 := 58.0
	var i := mini(grades.size(), specs.size() - 1)
	var spec: Dictionary = specs[i]
	var jolt := Vector2(sin(_shake * 40.0) * 3.0 * _shake, 0)
	var track := Rect2(Vector2(x0, y0) + jolt, Vector2(W, H))
	# Iron bed with a cool-to-hot sheen.
	draw_rect(Rect2(track.position - Vector2(4, 4), track.size + Vector2(8, 8)), Color(0, 0, 0, 0.45))
	draw_rect(track, Color(0.09, 0.08, 0.1, 0.95))
	for k in 12:
		var t := float(k) / 12.0
		draw_rect(Rect2(track.position.x + t * W, track.position.y + 2, W / 12.0, H - 4), Color(0.25 + 0.1 * t, 0.12, 0.08, 0.35))
	# Hot zone: glow, body, white-hot perfect core.
	var c := float(spec["center"])
	var w := float(spec["width"])
	var zx := track.position.x + (c - w * 0.85) * W
	draw_rect(Rect2(zx, track.position.y + 2, w * 1.7 * W, H - 4), Color(0.88, 0.42, 0.18, 0.28))
	draw_rect(Rect2(track.position.x + (c - w * 0.5) * W, track.position.y + 2, w * W, H - 4), Color(1.0, 0.6, 0.2, 0.7))
	draw_rect(Rect2(track.position.x + (c - w * 0.18) * W, track.position.y + 2, w * 0.36 * W, H - 4), Color(1.0, 0.95, 0.75, 0.95))
	draw_rect(track, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.75), false, 2.0)
	# Spark.
	if _active:
		var m := Forging.mark(spec, float(_elapsed() - _last))
		var mx := track.position.x + m * W
		draw_rect(Rect2(mx - 2, track.position.y - 6, 4, H + 12), Color(1, 1, 1, 0.95))
		draw_circle(Vector2(mx, track.position.y - 8), 5.0, Color(1.0, 0.85, 0.5, 0.9))
		draw_circle(Vector2(mx, track.position.y - 8), 9.0, Color(1.0, 0.6, 0.2, 0.25))
		# Strike window, cooling away under the bar.
		var left := 1.0 - clampf(float(_elapsed() - _last) / (Forging.STRIKE_WINDOW * 1000.0), 0.0, 1.0)
		draw_rect(Rect2(x0, y0 + H + 8, W, 5), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(x0, y0 + H + 8, W * left, 5), Color(1.0, 0.55 + 0.3 * left, 0.2, 0.9))
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
