class_name TavernScreen
extends VBoxContainer
## The Hollow Hearth's screen (Tavern): Rook's menu, this shift's kitchen
## orders (three cooks per order per server, first one gets a bonus), a room
## upstairs, and the rumour of the shift. Every button sends a Tavern
## request; the answer (immediate offline, through on_net online) carries a
## fresh view and the screen rebuilds from it.

var tavern
var view: Dictionary = {}
var _status: Label
var _col_l: Label
var _body: VBoxContainer
var _focus_tab := "counter"


static func build() -> TavernScreen:
	var s := TavernScreen.new()
	s._build()
	return s


func _build() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(700, 0)
	var head := HBoxContainer.new()
	var k := UITheme.kicker("The Hollow Hearth")
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(k)
	head.add_child(UITheme.subtle("Esc to close", 13))
	add_child(head)
	var th := HBoxContainer.new()
	var title := UITheme.heading("Rook's bar", 28)
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


func open(node, tab := "counter") -> void:
	tavern = node
	_focus_tab = tab
	_status.text = "Rook wipes down the bar..."
	_status.remove_theme_color_override("font_color")
	_send({"op": "view"})


func _send(payload: Dictionary) -> void:
	if tavern == null:
		return
	var res: Dictionary = tavern.request(payload)
	if res.get("pending", false):
		_status.text = "..."
		return
	show_result(res)


func show_result(res: Dictionary) -> void:
	if res.has("error"):
		_status.text = str(res["error"])
		_status.add_theme_color_override("font_color", UITheme.ROSE)
		Audio.play("ui_error")
		if res.get("view") is Dictionary:
			view = res["view"]
		_render()
		return
	if res.get("view") is Dictionary:
		view = res["view"]
	_status.remove_theme_color_override("font_color")
	_status.text = ""
	var line: Array = Tavern.result_text(res)
	if not line.is_empty():
		var hud = tavern.hud if tavern else null
		if hud and hud.has_method("toast"):
			hud.toast(line[0], line[1], line[2], UITheme.GOLD)
		if res.has("order"):
			Audio.play("coins")
			Audio.play("quest_complete")
		elif res.has("room"):
			Audio.play("sleep")
		else:
			Audio.play("coins")
			Audio.play("eat")
	_render()


func _render() -> void:
	for c in _body.get_children():
		c.queue_free()
	_col_l.text = "%d Col" % GameState.money
	var first_btn: Button = null
	var tab_btn: Button = null
	_body.add_child(UITheme.kicker("From the kitchen", UITheme.GOLD))
	for id in Tavern.MEALS:
		var m: Dictionary = Tavern.MEALS[id]
		var b := _row(m["name"], "%s\n%s" % [m["desc"], LifeData.buff_text(m["buff"])], "food", Color(str(m["color"])), "%d Col" % int(m["col"]), "Order",
			GameState.money >= int(m["col"]), func(): _send({"op": "meal", "id": id}))
		if first_btn == null:
			first_btn = b
		if _focus_tab == "counter" and tab_btn == null:
			tab_btn = b
	var left := int(view.get("shift_left", 0))
	_body.add_child(UITheme.spacer(2))
	var oh := HBoxContainer.new()
	var ok := UITheme.kicker("Kitchen orders", UITheme.GOLD)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oh.add_child(ok)
	oh.add_child(UITheme.subtle("New orders in %dh %02dm" % [left / 3600, (left % 3600) / 60], 12))
	_body.add_child(oh)
	var orders: Array = view.get("orders", [])
	for i in orders.size():
		var o: Dictionary = orders[i]
		var dish: String = o["dish"]
		var r: Dictionary = LifeData.RECIPES[dish]
		var have := int(GameState.materials.get(dish, 0))
		var mine := bool(o.get("mine", false))
		var slots := int(o.get("left", 0))
		var sub := "%d of %d cooks' places left  ·  you have %d  ·  first cook +%d%%" % [slots, Tavern.ORDER_CAP, have, int(Tavern.FIRST_BONUS * 100)]
		var label := "Filled" if mine else ("Taken" if slots <= 0 else "Deliver")
		var can := not mine and slots > 0 and have >= int(o["qty"])
		var b := _row("%d × %s" % [int(o["qty"]), r["name"]], sub, "food", Color(str(r["color"])), "%d Col" % int(o["col"]), label, can,
			func(): _send({"op": "order", "i": i}))
		if _focus_tab == "orders" and tab_btn == null:
			tab_btn = b
	if orders.is_empty():
		_body.add_child(UITheme.subtle("...", 13))
	_body.add_child(UITheme.spacer(2))
	_body.add_child(UITheme.kicker("Rooms", UITheme.GOLD))
	var rb := _row("A room upstairs", "A soft bed and a locked door. Wake healed and Well Rested (%s)." % LifeData.buff_text(LifeData.REST_BUFF), "rest", UITheme.CYAN,
		"%d Col" % Tavern.ROOM_PRICE, "Rent", GameState.money >= Tavern.ROOM_PRICE, func(): _send({"op": "room"}))
	if _focus_tab == "rooms":
		tab_btn = rb
	var rumour := str(view.get("rumour", ""))
	if rumour != "":
		_body.add_child(UITheme.spacer(4))
		var q := UITheme.label("“%s”" % rumour, 14, UITheme.PARCH)
		q.autowrap_mode = TextServer.AUTOWRAP_WORD
		_body.add_child(q)
		var who := UITheme.subtle("Rook, leaning on the bar", 12)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_body.add_child(who)
	var f: Button = tab_btn if tab_btn != null else first_btn
	if f and not f.disabled:
		f.grab_focus.call_deferred()


func _row(title: String, sub: String, glyph: String, gc: Color, price: String, btn: String, enabled: bool, cb: Callable) -> Button:
	var row := PanelContainer.new()
	row.theme_type_variation = "CardFlat"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var g := UIGlyph.make(glyph, gc, 36, 0.5)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(g)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	v.add_child(UITheme.label(title, 16, UITheme.PARCH, true))
	var s := UITheme.subtle(sub, 12)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(s)
	h.add_child(v)
	var p := UITheme.label(price, 14, UITheme.GOLD, true)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(p)
	var b := UITheme.make_button(btn, "primary" if enabled else "normal")
	b.custom_minimum_size = Vector2(96, 36)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = not enabled
	b.pressed.connect(cb)
	h.add_child(b)
	row.add_child(h)
	_body.add_child(row)
	return b
