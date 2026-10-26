class_name BattleResult
extends PanelContainer
## Post-battle result window (SAO's "Result" pop-up after a fight): slides
## in on the right under the quest tracker, counts the EXP and Col up, lists what
## dropped, flags a level up, then fades. One at a time; a new result
## replaces the old one. Fed by hud.show_battle_result(data) with
## {kills, foes {name: n}, xp, col, items {id: n}, level_ups}.

const W := 300.0
const HOLD := 4.2

var _data: Dictionary
var _xp_l: Label
var _col_l: Label
var _t := 0.0


static func show_in(root: Control, data: Dictionary) -> BattleResult:
	for c in root.get_children():
		if c is BattleResult:
			c.queue_free()
	var p := BattleResult.new()
	p._data = data
	root.add_child(p)
	return p


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_right = -24.0
	offset_left = -24.0 - W
	offset_top = 410.0  # below the quest tracker, above the key hints
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(W, 0)
	var sb := UITheme.box(Color(UITheme.NAVY, 0.84), Color(UITheme.CYAN, 0.45), 10, 1, 10)
	sb.border_width_top = 3
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	var k := UITheme.kicker("Result", UITheme.CYAN)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(k)
	var kills := int(_data.get("kills", 0))
	head.add_child(UITheme.label("%d %s" % [kills, "foe" if kills == 1 else "foes"], 12, UITheme.MUTED, true))
	v.add_child(head)
	var foes: Dictionary = _data.get("foes", {})
	if not foes.is_empty():
		var names: Array = []
		for n in foes:
			var short := str(n).get_slice(":", 1).strip_edges() if ":" in str(n) else str(n)
			names.append(short + ("  ×%d" % int(foes[n]) if int(foes[n]) > 1 else ""))
		var fl := UITheme.label(" · ".join(names), 12, UITheme.PARCH, false)
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(fl)
	v.add_child(UITheme.rule())
	_xp_l = _stat_row(v, "EXP", UITheme.CYAN)
	_col_l = _stat_row(v, "COL", UITheme.GOLD)
	var items: Dictionary = _data.get("items", {})
	if not items.is_empty():
		v.add_child(UITheme.rule())
		v.add_child(UITheme.label("ITEMS", 10, UITheme.MUTED, true))
		for id in items:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var gem := Control.new()
			gem.custom_minimum_size = Vector2(12, 12)
			gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var col := LifeData.item_color(str(id))
			gem.draw.connect(func():
				var c := gem.size * 0.5
				gem.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(5, 0), c + Vector2(0, 6), c + Vector2(-5, 0)]), col))
			row.add_child(gem)
			var nm := UITheme.label(str(GameState.MATERIAL_NAMES.get(id, str(id).capitalize())), 14, UITheme.PARCH, true)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nm)
			row.add_child(UITheme.label("×%d" % int(items[id]), 14, UITheme.PARCH, true))
			v.add_child(row)
	if int(_data.get("level_ups", 0)) > 0:
		var lv := UITheme.heading("LEVEL UP!", 18, UITheme.GOLD)
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(lv)
		var tw0 := lv.create_tween().set_loops(4)
		tw0.tween_property(lv, "modulate:a", 0.55, 0.3)
		tw0.tween_property(lv, "modulate:a", 1.0, 0.3)
	_set_counts(0.0)
	# Slide in from the right, count up, hold, fade.
	modulate.a = 0.0
	offset_left += 60.0
	offset_right += 60.0
	var tw := create_tween()
	tw.set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	tw.tween_property(self, "offset_left", offset_left - 60.0, 0.35)
	tw.tween_property(self, "offset_right", offset_right - 60.0, 0.35)
	tw.chain().tween_method(_set_counts, 0.0, 1.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(HOLD)
	tw.chain().tween_property(self, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(queue_free)


func _stat_row(v: VBoxContainer, key: String, col: Color) -> Label:
	var row := HBoxContainer.new()
	var k := UITheme.label(key, 12, col, true)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(k)
	var val := UITheme.label("", 20, UITheme.PARCH, true)
	row.add_child(val)
	v.add_child(row)
	return val


func _set_counts(t: float) -> void:
	_xp_l.text = "+%d" % roundi(float(_data.get("xp", 0)) * t)
	_col_l.text = "+%d" % roundi(float(_data.get("col", 0)) * t)
