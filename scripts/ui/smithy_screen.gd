class_name SmithyScreen
extends VBoxContainer
## Hollowbrook Forge's commission board (Smithy): this shift's three
## villager commissions, how many smiths' places are left, the piece from
## your pack that would go (the lowest rank that qualifies) and a Deliver
## button. Same request/answer flow as the tavern screen.

var smithy
var view: Dictionary = {}
var _status: Label
var _col_l: Label
var _body: VBoxContainer


static func build() -> SmithyScreen:
	var s := SmithyScreen.new()
	s._build()
	return s


func _build() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(680, 0)
	var head := HBoxContainer.new()
	var k := UITheme.kicker("Hollowbrook Forge")
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(k)
	head.add_child(UITheme.subtle("Esc to close", 13))
	add_child(head)
	var th := HBoxContainer.new()
	var title := UITheme.heading("Commissions", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(title)
	_col_l = UITheme.label("", 14, UITheme.GOLD, true)
	_col_l.size_flags_vertical = Control.SIZE_SHRINK_END
	th.add_child(_col_l)
	add_child(th)
	add_child(UITheme.rule())
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	add_child(_body)
	_status = UITheme.subtle("", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_status)


func open(node) -> void:
	smithy = node
	_status.text = "Reading the board..."
	_status.remove_theme_color_override("font_color")
	_send({"op": "view"})


func _send(payload: Dictionary) -> void:
	if smithy == null:
		return
	var res: Dictionary = smithy.request(payload)
	if res.get("pending", false):
		_status.text = "..."
		return
	show_result(res)


func show_result(res: Dictionary) -> void:
	if res.get("view") is Dictionary:
		view = res["view"]
	if res.has("error"):
		_status.text = str(res["error"])
		_status.add_theme_color_override("font_color", UITheme.ROSE)
		Audio.play("ui_error")
	else:
		_status.remove_theme_color_override("font_color")
		_status.text = ""
		var line: Array = Smithy.result_text(res)
		if not line.is_empty():
			var hud = smithy.hud if smithy else null
			if hud and hud.has_method("toast"):
				hud.toast(line[0], line[1], line[2], UITheme.GOLD)
			Audio.play("coins")
			Audio.play("anvil", null, 0.05, 0.0, 1.2)
	_render()


func _render() -> void:
	for c in _body.get_children():
		c.queue_free()
	_col_l.text = "%d Col  ·  Smithing Lv %d" % [GameState.money, GameState.smithing_level]
	var left := int(view.get("shift_left", 0))
	_body.add_child(UITheme.subtle("New commissions in %dh %02dm. Three smiths per commission; the first gets +%d%%. Each rank above the ask pays +%d%%." % [left / 3600, (left % 3600) / 60, int(Smithy.FIRST_BONUS * 100), int(Smithy.RANK_BONUS * 100)], 12))
	var first: Button = null
	var cs: Array = view.get("commissions", [])
	for i in cs.size():
		var c: Dictionary = cs[i]
		var rank := int(c["rank"])
		var row := PanelContainer.new()
		row.theme_type_variation = "CardFlat"
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var g := UIGlyph.make("sword" if str(c["recipe"]).ends_with("Sword") or str(c["recipe"]).ends_with("Blade") else "shield", Crafting.rank_color(rank), 36, 0.5)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(g)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 2)
		var nr := HBoxContainer.new()
		nr.add_theme_constant_override("separation", 8)
		nr.add_child(UITheme.label(str(c["recipe"]), 16, UITheme.PARCH, true))
		nr.add_child(UITheme.label("%s+" % Crafting.RANKS[rank], 12, Crafting.rank_color(rank), true))
		v.add_child(nr)
		var why := UITheme.subtle("%s, %s." % [str(c["for"]), str(c["why"])], 12)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD
		v.add_child(why)
		var fit := str(c.get("fit", ""))
		v.add_child(UITheme.label(("Would hand over: %s" % fit) if fit != "" else "Nothing in your pack fits yet", 12, UITheme.CYAN if fit != "" else UITheme.MUTED, true))
		v.add_child(UITheme.subtle("%d of %d smiths' places left" % [int(c.get("left", 0)), Smithy.CAP], 12))
		h.add_child(v)
		var p := UITheme.label("%d+ Col" % int(c["col"]), 14, UITheme.GOLD, true)
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(p)
		var mine := bool(c.get("mine", false))
		var can := not mine and int(c.get("left", 0)) > 0 and fit != ""
		var b := UITheme.make_button("Filled" if mine else ("Taken" if int(c.get("left", 0)) <= 0 else "Deliver"), "primary" if can else "normal")
		b.custom_minimum_size = Vector2(96, 36)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = not can
		b.pressed.connect(func(): _send({"op": "deliver", "i": i}))
		h.add_child(b)
		row.add_child(h)
		_body.add_child(row)
		if first == null and can:
			first = b
	if first:
		first.grab_focus.call_deferred()
