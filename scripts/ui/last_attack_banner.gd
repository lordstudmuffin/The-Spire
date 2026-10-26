class_name LastAttackBanner
extends Control
## "LAST ATTACK BONUS" window (hud.show_last_attack): the system pop-up the
## player who lands the killing blow on a boss or named elite gets (SAO's
## Last Attack bonus). A gold-framed window pops in at the upper centre with
## a light sweep across it, names the won item in large type (or, once the
## limited items are all claimed, the fallback EXP / Col / materials), then
## fades. One at a time; a new one replaces the old.
## data = {foe, item (item name or ""), xp, col, mats {id: n}}

const W := 540.0
const TOP := 0.15  # fraction of the screen height
const HOLD := 4.6

var _data: Dictionary
var _panel: PanelContainer


static func show_in(root: Control, data: Dictionary) -> LastAttackBanner:
	for c in root.get_children():
		if c is LastAttackBanner:
			c.queue_free()
	var b := LastAttackBanner.new()
	b._data = data
	root.add_child(b)
	return b


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var item := str(_data.get("item", ""))
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.clip_contents = true
	_panel.custom_minimum_size = Vector2(W, 0)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = TOP
	_panel.anchor_bottom = TOP
	_panel.offset_left = -W * 0.5
	_panel.offset_right = W * 0.5
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	var sb := UITheme.box(Color(UITheme.NAVY, 0.9), Color(UITheme.GOLD, 0.85), 10, 2, 18)
	sb.border_width_top = 4
	sb.shadow_color = Color(UITheme.GOLD, 0.25)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 16
	sb.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	_panel.add_child(v)
	var k := UITheme.kicker("Congratulations", UITheme.GOLD_DIM)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(k)
	var title := _caption("LAST  ATTACK  BONUS", 30, UITheme.GOLD, UITheme.display_font(), 4)
	v.add_child(title)
	v.add_child(UITheme.rule())
	if item != "":
		v.add_child(_caption(item, 24, Color(1, 0.97, 0.9), UITheme.ui_bold(), 1))
		var got := UITheme.label("has been added to your inventory", 13, UITheme.MUTED)
		got.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(got)
	else:
		var gone := UITheme.label("The bonus items are all claimed  ·  bonus rewards instead", 13, UITheme.MUTED)
		gone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(gone)
	# Rewards line: EXP, Col, materials as small chips.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	if int(_data.get("xp", 0)) > 0:
		row.add_child(_chip("+%d EXP" % int(_data["xp"]), UITheme.CYAN))
	if int(_data.get("col", 0)) > 0:
		row.add_child(_chip("+%d COL" % int(_data["col"]), UITheme.GOLD))
	var mats: Dictionary = _data.get("mats", {})
	for id in mats:
		row.add_child(_chip("%s ×%d" % [GameState.MATERIAL_NAMES.get(id, str(id).capitalize()), int(mats[id])], LifeData.item_color(str(id))))
	if row.get_child_count() > 0:
		v.add_child(row)
	var foe := str(_data.get("foe", ""))
	if foe != "":
		var fl := UITheme.label(foe, 12, UITheme.PARCH)
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fl.modulate.a = 0.7
		v.add_child(fl)
	# The light sweep: a soft diagonal band crossing the window once (a free
	# Control layer over the content; the panel clips it).
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(layer)
	var gt := UITheme.gradient_tex([Color(1, 0.95, 0.75, 0.0), Color(1, 0.95, 0.75, 0.3), Color(1, 0.95, 0.75, 0.0)], [0.0, 0.5, 1.0], false, 64, 4)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size = Vector2(110, 420)
	tr.rotation = 0.35
	tr.position = Vector2(-220, -140)
	layer.add_child(tr)
	Audio.play("item_rare", null, 0.0, 0.0, 1.0)
	Audio.play("level_up", null, 0.0, -6.0, 1.12)
	# Pop in, sweep, hold, fade.
	_panel.pivot_offset = Vector2(W * 0.5, 60)
	_panel.scale = Vector2(0.86, 0.86)
	_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.35)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.2)
	tw.chain().tween_property(tr, "position:x", W + 80.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_interval(HOLD)
	tw.chain().tween_property(_panel, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(queue_free)


func _caption(text: String, px: int, col: Color, font: Font, spacing: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UITheme.spaced(font, spacing))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _chip(text: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UITheme.box(Color(col, 0.14), Color(col, 0.55), 8, 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(UITheme.label(text, 13, col.lightened(0.25), true))
	return p
