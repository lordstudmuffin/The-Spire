extends VBoxContainer
## Guild panel (P8): opened at the Hollowbrook notice board or with /guild.
## Not in a guild: the charter form (name, tag, fee, level) and any pending
## invitation. In a guild: Roster (ranks, online dots, invite, promote /
## demote / make leader / remove, leave or disband) and Storage (Col and
## goods; everyone deposits, Officers and the Leader take; at the board only).
## Every button sends one guild operation through the Guilds node
## (scripts/life/guilds.gd); the screen draws only the server's "view".

const Guilds := preload("res://scripts/life/guilds.gd")
const Stalls := preload("res://scripts/life/stalls.gd")

var guilds: Node = null
var view: Dictionary = {}
var _tab := "roster"
var _kicker: Label
var _title: Label
var _col_l: Label
var _status: Label
var _tabs: HBoxContainer
var _tab_roster: Button
var _tab_storage: Button
var _list: VBoxContainer
var _name_in: LineEdit
var _tag_in: LineEdit
var _invite_in: LineEdit
var _col_amt := 100
var _qty := {}
var _confirm := ""
var _pending := false


static func build():
	var s = load("res://scripts/ui/guild_screen.gd").new()
	s._build()
	return s


func _build() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(700, 0)
	var head := HBoxContainer.new()
	_kicker = UITheme.kicker("Hollowbrook Notice Board")
	_kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_kicker)
	head.add_child(UITheme.subtle("Esc to close", 13))
	add_child(head)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 12)
	_title = UITheme.heading("Guilds", 28)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(_title)
	_col_l = UITheme.label("", 14, UITheme.GOLD, true)
	_col_l.size_flags_vertical = Control.SIZE_SHRINK_END
	th.add_child(_col_l)
	add_child(th)
	add_child(UITheme.rule())
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_tab_roster = UITheme.make_button("Roster", "chip")
	_tab_roster.pressed.connect(func(): _set_tab("roster"))
	_tabs.add_child(_tab_roster)
	_tab_storage = UITheme.make_button("Storage", "chip")
	_tab_storage.pressed.connect(func(): _set_tab("storage"))
	_tabs.add_child(_tab_storage)
	add_child(_tabs)
	_status = UITheme.label("", 13, UITheme.MUTED, true)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 400)
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	var hint := UITheme.subtle("Guild chat: /g message.  /guild opens this panel anywhere; the storage is kept at the Hollowbrook notice board.", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(hint)


# --- Open / answers ---------------------------------------------------------------

func open(node: Node) -> void:
	guilds = node
	view = {}
	_confirm = ""
	_status.text = "Reading the notices..."
	_clear()
	_send({"op": "view"})


func refresh_view() -> void:
	_send({"op": "view"})


func _send(payload: Dictionary) -> void:
	if guilds == null:
		return
	var res: Dictionary = guilds.request(payload)
	if res.get("pending", false):
		_pending = true
		_status.text = "..."
		return
	show_result(res)


func show_result(res: Dictionary) -> void:
	_pending = false
	if res.has("error"):
		_status.text = str(res["error"])
		_status.add_theme_color_override("font_color", UITheme.ROSE)
		Audio.play("ui_error")
		if not view.is_empty():
			_render()
		return
	_status.add_theme_color_override("font_color", UITheme.GREEN)
	var op := str(res.get("op", "view"))
	_status.text = "" if op == "view" else Guilds.result_text(res)
	match op:
		"found":
			Audio.play("level_up")
		"deposit", "withdraw":
			Audio.play("coins" if res.has("col") else "pickup")
		"view":
			pass
		_:
			Audio.play("ui_tick")
	if res.get("view") is Dictionary:
		view = res["view"]
		_render()


func refresh() -> void:
	if not view.is_empty():
		_render()


# --- Rendering -------------------------------------------------------------------

func _set_tab(t: String) -> void:
	_tab = t
	_confirm = ""
	_render()
	UITheme.focus_first_in(_list)


func _clear() -> void:
	# The text fields survive re-renders (typed text stays); detach them first.
	for le in [_name_in, _tag_in, _invite_in]:
		if le != null and le.get_parent() != null:
			le.get_parent().remove_child(le)
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()


func _render() -> void:
	_clear()
	_col_l.text = "%d Col" % int(view.get("money", GameState.money))
	var inside := bool(view.get("in_guild", false))
	_tabs.visible = inside
	if not inside:
		_title.text = "Guilds"
		_render_charter()
		return
	var g: Dictionary = view.get("guild", {})
	_title.text = "%s  [%s]" % [str(g.get("name", "")), str(g.get("tag", ""))]
	UITheme.set_chip(_tab_roster, _tab == "roster")
	UITheme.set_chip(_tab_storage, _tab == "storage")
	if _tab == "storage":
		_render_storage()
	else:
		_render_roster()


func _render_charter() -> void:
	var inv: Dictionary = view.get("invite", {})
	if not inv.is_empty():
		var a := UITheme.make_button("Accept", "primary")
		a.pressed.connect(func(): _send({"op": "accept"}))
		var d := UITheme.make_button("Decline", "ghost")
		d.pressed.connect(func(): _send({"op": "decline"}))
		_list.add_child(_line_card("scroll", UITheme.GOLD, "Invitation: %s [%s]" % [str(inv.get("guild", "")), str(inv.get("tag", ""))],
			"From %s" % str(inv.get("from", "")), [a, d]))
	var lvl := int(view.get("level", 1))
	var need := int(view.get("min_level", Guilds.MIN_LEVEL))
	var fee := int(view.get("fee", Guilds.FEE))
	_list.add_child(_section("Found a guild", "Lv %d · %d Col charter" % [need, fee]))
	if not bool(view.get("at_board", false)):
		_list.add_child(_note("Charters are signed at the Hollowbrook notice board, beside the well."))
		return
	_list.add_child(_note("Name your guild (3-20 letters, digits, spaces) and pick a 2-4 letter tag; members wear the tag over their heads. Names and tags are unique on this server."))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if _name_in == null:
		_name_in = LineEdit.new()
		_name_in.placeholder_text = "Guild name"
		_name_in.max_length = 20
		_name_in.custom_minimum_size = Vector2(280, 0)
		_tag_in = LineEdit.new()
		_tag_in.placeholder_text = "TAG"
		_tag_in.max_length = 4
		_tag_in.custom_minimum_size = Vector2(90, 0)
	_reparent(_name_in, row)
	_reparent(_tag_in, row)
	var b := UITheme.make_button("Found · %d Col" % fee, "primary")
	b.disabled = lvl < need or int(view.get("money", 0)) < fee
	b.pressed.connect(func(): _send({"op": "found", "name": _name_in.text, "tag": _tag_in.text}))
	row.add_child(b)
	_list.add_child(row)
	if lvl < need:
		_list.add_child(_note("You are Lv %d. Come back at Lv %d." % [lvl, need]))
	elif int(view.get("money", 0)) < fee:
		_list.add_child(_note("The charter costs %d Col." % fee))


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for le in [_name_in, _tag_in, _invite_in]:
			if le != null and is_instance_valid(le) and le.get_parent() == null:
				le.free()


func _reparent(c: Control, to: Node) -> void:
	if c.get_parent() != null:
		c.get_parent().remove_child(c)
	to.add_child(c)


func _render_roster() -> void:
	var me := str(view.get("my_rank", "member"))
	var mv := Guilds.rank_value(me)
	var g: Dictionary = view.get("guild", {})
	var rows: Array = g.get("members", [])
	_list.add_child(_section("Roster", "%d member%s · you are %s" % [rows.size(), "" if rows.size() == 1 else "s", Guilds.RANK_NAMES.get(me, me)]))
	if mv >= Guilds.rank_value("officer"):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		if _invite_in == null:
			_invite_in = LineEdit.new()
			_invite_in.placeholder_text = "Name of someone online"
			_invite_in.max_length = 24
			_invite_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_reparent(_invite_in, row)
		var ib := UITheme.make_button("Invite", "primary")
		ib.pressed.connect(func():
			if _invite_in.text.strip_edges() != "":
				_send({"op": "invite", "name": _invite_in.text.strip_edges()}))
		row.add_child(ib)
		_list.add_child(row)
	for r in rows:
		var nm := str(r.get("name", ""))
		var rank := str(r.get("rank", "member"))
		var rv := Guilds.rank_value(rank)
		var right: Array = []
		if not bool(r.get("me", false)):
			if me == "leader" and rank == "member":
				right.append(_op_button("Promote", "chip", {"op": "promote", "name": nm}))
			if me == "leader" and rank == "officer":
				right.append(_op_button("Demote", "chip", {"op": "demote", "name": nm}))
				right.append(_confirm_button("Make Leader", "transfer:" + nm, {"op": "transfer", "name": nm}))
			if mv >= Guilds.rank_value("officer") and rv < mv:
				right.append(_confirm_button("Remove", "kick:" + nm, {"op": "kick", "name": nm}))
		var c := UITheme.GOLD if rank == "leader" else (UITheme.CYAN if rank == "officer" else UITheme.PARCH)
		var sub := "%s  ·  %s" % [Guilds.RANK_NAMES.get(rank, rank), "online" if bool(r.get("online", false)) else "away"]
		_list.add_child(_line_card("star" if rank == "leader" else "shield", c, nm + ("  (you)" if bool(r.get("me", false)) else ""), sub, right))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	foot.add_child(_confirm_button("Leave guild", "leave", {"op": "leave"}))
	if me == "leader":
		foot.add_child(_confirm_button("Disband", "disband", {"op": "disband"}))
	_list.add_child(foot)


func _op_button(text: String, kind: String, payload: Dictionary) -> Button:
	var b := UITheme.make_button(text, kind)
	b.pressed.connect(func(): _send(payload))
	return b


## A button that needs a second press (leave, disband, remove, hand over).
func _confirm_button(text: String, key: String, payload: Dictionary) -> Button:
	var b := UITheme.make_button("Sure? " + text if _confirm == key else text, "ghost")
	b.pressed.connect(func():
		if _confirm == key:
			_confirm = ""
			_send(payload)
		else:
			_confirm = key
			Audio.play("ui_tick")
			_render())
	return b


func _render_storage() -> void:
	var st: Dictionary = view.get("storage", {})
	var me := str(view.get("my_rank", "member"))
	var can_take := Guilds.rank_value(me) >= Guilds.rank_value("officer")
	var at := bool(view.get("at_board", false))
	if not at:
		_list.add_child(_note("The guild storage is kept at the Hollowbrook notice board. Visit it to deposit or take."))
	var col := int(st.get("col", 0))
	var amt := UITheme.label("%d Col" % _col_amt, 14, UITheme.GOLD, true)
	var minus := UITheme.make_button("-", "chip")
	var plus := UITheme.make_button("+", "chip")
	minus.pressed.connect(func():
		_col_amt = maxi(10, _col_amt - (100 if _col_amt > 100 else 10))
		amt.text = "%d Col" % _col_amt)
	plus.pressed.connect(func():
		_col_amt = mini(99999, _col_amt + (100 if _col_amt >= 100 else 10))
		amt.text = "%d Col" % _col_amt)
	var dep := UITheme.make_button("Deposit", "primary")
	dep.disabled = not at
	dep.pressed.connect(func(): _send({"op": "deposit", "col": _col_amt}))
	var row: Array = [minus, amt, plus, dep]
	if can_take:
		var tk := UITheme.make_button("Take", "normal")
		tk.disabled = not at or col <= 0
		tk.pressed.connect(func(): _send({"op": "withdraw", "col": mini(_col_amt, col)}))
		row.append(tk)
	_list.add_child(_line_card("coin", UITheme.GOLD, "Guild coffers", "%d Col" % col, row))
	var items: Array = st.get("items", [])
	_list.add_child(_section("In storage", "%d item%s%s" % [items.size(), "" if items.size() == 1 else "s", "" if can_take else " · Officers take"]))
	if items.is_empty():
		_list.add_child(_note("Nothing stored yet."))
	for it in items:
		var right: Array = []
		if can_take:
			var id := str(it.get("id", ""))
			var w := UITheme.make_button("Take", "normal")
			w.disabled = not at
			w.pressed.connect(func(): _send({"op": "withdraw", "item": id}))
			right.append(w)
		_list.add_child(_row(it, right))
	if not at:
		return
	_list.add_child(_section("Deposit from your pack", "bound items stay with you"))
	for it in GameState.inventory:
		if not (it is Dictionary) or not (str(it.get("kind", "")) in ["weapon", "armor"]):
			continue
		var id := str(it.get("id", ""))
		var b := UITheme.make_button("Deposit", "primary")
		var bound := bool(it.get("bound", false))
		var worn: bool = GameState.equipped.get("weapon") == it or GameState.equipped.get("armor") == it
		b.disabled = bound or worn
		if bound:
			b.text = "Bound"
		elif worn:
			b.text = "Worn"
		b.pressed.connect(func(): _send({"op": "deposit", "item": id}))
		_list.add_child(_row(it, [b]))
	for m in GameState.MATERIAL_NAMES:
		var have := int(GameState.materials.get(m, 0))
		if have <= 0:
			continue
		if not _qty.has(m):
			_qty[m] = 1
		_qty[m] = clampi(int(_qty[m]), 1, mini(have, Stalls.MAX_STACK))
		var ql := UITheme.label("×%d" % int(_qty[m]), 13, UITheme.PARCH, true)
		var mm: String = m
		var mi := UITheme.make_button("-", "chip")
		var pl := UITheme.make_button("+", "chip")
		mi.pressed.connect(func():
			_qty[mm] = maxi(1, int(_qty[mm]) - 1)
			ql.text = "×%d" % int(_qty[mm]))
		pl.pressed.connect(func():
			_qty[mm] = mini(mini(have, Stalls.MAX_STACK), int(_qty[mm]) + 1)
			ql.text = "×%d" % int(_qty[mm]))
		var b := UITheme.make_button("Deposit", "primary")
		b.pressed.connect(func(): _send({"op": "deposit", "mat": mm, "count": int(_qty[mm])}))
		_list.add_child(_row({"kind": "stack", "mat": m, "count": have, "name": "%s  (have %d)" % [GameState.MATERIAL_NAMES[m], have]}, [mi, ql, pl, b]))


# --- Widgets ---------------------------------------------------------------------

func _section(title: String, right: String) -> Control:
	var h := HBoxContainer.new()
	var k := UITheme.kicker(title, UITheme.GOLD)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(k)
	h.add_child(UITheme.subtle(right, 12))
	return h


func _note(text: String) -> Label:
	var l := UITheme.subtle(text, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l


func _row(r: Dictionary, right: Array) -> PanelContainer:
	var k := str(r.get("kind", ""))
	var glyph := "star"
	var c := UITheme.GOLD
	var sub := "Goods"
	if k == "weapon" or k == "armor":
		glyph = "sword" if k == "weapon" else "shield"
		c = Crafting.rank_color(int(r.get("rank", 0)))
		sub = ("ATK %d" % int(r.get("atk", 0))) if k == "weapon" else ("DEF %d" % int(r.get("def", 0)))
	else:
		var m := str(r.get("mat", ""))
		c = LifeData.item_color(m)
		glyph = "food" if LifeData.RECIPES.has(m) else ("fish" if LifeData.FISH.has(m) else ("herb" if LifeData.is_life_item(m) else "ore"))
		sub = LifeData.item_desc(m) if LifeData.item_desc(m) != "" else "Goods"
	return _line_card(glyph, c, str(r.get("name", "")), sub, right)


func _line_card(glyph: String, c: Color, title: String, sub: String, right: Array) -> PanelContainer:
	var row := PanelContainer.new()
	row.theme_type_variation = "CardFlat"
	var sb: StyleBoxFlat = row.get_theme_stylebox("panel").duplicate()
	sb.set_content_margin_all(8)
	sb.border_color = Color(c.r, c.g, c.b, 0.4)
	row.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var gl := UIGlyph.make(glyph, c, 30, 0.5)
	gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(gl)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", -2)
	var nl := UITheme.label(title, 15, UITheme.PARCH, true)
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(nl)
	var sl := UITheme.label(sub, 11, UITheme.MUTED, true)
	sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sl)
	h.add_child(v)
	for w in right:
		if w is Control:
			(w as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(w)
	row.add_child(h)
	return row
