extends VBoxContainer
## Hollowbrook market stall screen (P7). Two tabs: Browse (the wares on the
## counter, Buy) and Manage (rent the stall, Shop / Restaurant, the till,
## prices, withdraw, and stock from your pack). Every button sends one stall
## operation through the MarketStalls node (scripts/life/stalls.gd): offline
## and on the host it runs at once on the realm, online the server answers
## through show_result(). The screen only ever shows the server's "view".

const Stalls := preload("res://scripts/life/stalls.gd")

var stalls: Node = null           # the world's MarketStalls node
var index := 0
var view: Dictionary = {}
var _tab := "browse"
var _kicker: Label
var _title: Label
var _col_l: Label
var _status: Label
var _tab_browse: Button
var _tab_manage: Button
var _list: VBoxContainer
var _prices := {}                  # row id -> asking price being edited
var _qty := {}                     # material id -> stack size being edited
var _pending := false


static func build():
	var s = load("res://scripts/ui/stall_screen.gd").new()
	s._build()
	return s


func _build() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(700, 0)
	var head := HBoxContainer.new()
	_kicker = UITheme.kicker("Hollowbrook Market")
	_kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_kicker)
	head.add_child(UITheme.subtle("Esc to close", 13))
	add_child(head)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 12)
	_title = UITheme.heading("Stall", 28)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(_title)
	_col_l = UITheme.label("", 14, UITheme.GOLD, true)
	_col_l.size_flags_vertical = Control.SIZE_SHRINK_END
	th.add_child(_col_l)
	add_child(th)
	add_child(UITheme.rule())
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	_tab_browse = UITheme.make_button("Browse", "chip")
	_tab_browse.pressed.connect(func(): _set_tab("browse"))
	tabs.add_child(_tab_browse)
	_tab_manage = UITheme.make_button("Manage", "chip")
	_tab_manage.pressed.connect(func(): _set_tab("manage"))
	tabs.add_child(_tab_manage)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(sp)
	_status = UITheme.label("", 13, UITheme.MUTED, true)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tabs.add_child(_status)
	add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 380)
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	var hint := UITheme.subtle("Rent is %d Col a week, paid up front; one stall per character, and Officers can rent one more for their guild. %d%% of every sale goes to the market as tax. Wares stay on sale while you are away; when the rent runs out they return to your till." % [Stalls.RENT, int(Stalls.TAX_RATE * 100)], 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(hint)


# --- Open / answers ---------------------------------------------------------------

func open(node: Node, i: int) -> void:
	stalls = node
	index = i
	view = {}
	_prices.clear()
	_qty.clear()
	_tab = "browse"
	_kicker.text = "Hollowbrook Market  ·  Stall %d" % (i + 1)
	_title.text = "Stall %d" % (i + 1)
	_status.text = "Asking the stall keeper..."
	_clear()
	_send({"op": "view"})


func _send(payload: Dictionary) -> void:
	if stalls == null:
		return
	var res: Dictionary = stalls.request(index, payload)
	if res.get("pending", false):
		_pending = true
		_status.text = "..."
		return
	show_result(res)


## A stall result: feedback line, sounds, and the fresh view.
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
	match str(res.get("op", "view")):
		"view":
			_status.text = ""
		"rent":
			Audio.play("coins")
			_status.text = "Rent paid: %d Col. %s" % [int(res.get("paid", 0)), "Another week is paid." if res.get("renewed", false) else ("The stall is your guild's for a week." if res.get("guild", false) else "The stall is yours for a week.")]
		"type":
			Audio.play("ui_tick")
			_status.text = "Now a %s." % ("restaurant" if str(res.get("type", "")) == "restaurant" else "shop")
		"stock":
			Audio.play("drop")
			_status.text = "%s on the counter at %d Col." % [str(res.get("stocked", "")), int(res.get("price", 0))]
		"price":
			Audio.play("ui_tick")
			_status.text = "Price set to %d Col." % int(res.get("price", 0))
		"withdraw":
			Audio.play("pickup")
			_status.text = "%s back in your pack." % str(res.get("withdrawn", ""))
		"collect":
			Audio.play("coins")
			_status.text = "Collected %d Col%s from your till." % [int(res.get("collected", 0)), (" and %d item(s)" % int(res["items"])) if int(res.get("items", 0)) > 0 else ""]
		"buy":
			Audio.play("coins")
			_status.text = "Bought %s for %d Col.%s" % [str(res.get("bought", "")), int(res.get("price", 0)), "  Eat it from your Provisions." if res.get("dish", false) else ""]
	if res.get("view") is Dictionary:
		view = res["view"]
		if _tab == "manage" and not _can_manage():
			_tab = "browse"
		_render()


func refresh() -> void:
	if not view.is_empty():
		_render()


# --- Rendering -------------------------------------------------------------------

func _can_manage() -> bool:
	return bool(view.get("mine", false)) or bool(view.get("free", false))


func _set_tab(t: String) -> void:
	if t == "manage" and not _can_manage():
		Audio.play("ui_error")
		return
	_tab = t
	_render()
	UITheme.focus_first_in(_list)


func _clear() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()


func _render() -> void:
	_clear()
	_col_l.text = "%d Col" % GameState.money
	var resto := str(view.get("type", "shop")) == "restaurant"
	var owner := str(view.get("owner", ""))
	if bool(view.get("free", true)):
		_title.text = "Stall %d  ·  For rent" % (index + 1)
	else:
		_title.text = "%s's %s" % [owner, "Kitchen" if resto else "Stall"] if not bool(view.get("mine", false)) else ("%s %s" % ["Your guild's" if bool(view.get("guild_owned", false)) else "Your", "Kitchen" if resto else "Stall"])
	_tab_manage.visible = _can_manage()
	_tab_manage.text = "Rent" if bool(view.get("free", false)) else "Manage"
	UITheme.set_chip(_tab_browse, _tab == "browse")
	UITheme.set_chip(_tab_manage, _tab == "manage")
	if _tab == "manage":
		_render_manage(resto)
	else:
		_render_browse(resto)


func _render_browse(resto: bool) -> void:
	if bool(view.get("free", false)):
		_list.add_child(_note("Nobody rents this stall. Open the Rent tab to take it for %d Col a week and sell your own wares or dishes." % Stalls.RENT))
	else:
		var rows: Array = view.get("listings", [])
		_list.add_child(_section("Restaurant menu" if resto else "On the counter", "%d ware%s" % [rows.size(), "" if rows.size() == 1 else "s"]))
		if rows.is_empty():
			_list.add_child(_note("Sold out. Come back later."))
		for r in rows:
			var price := int(r.get("price", 0))
			var b := UITheme.make_button("Buy", "primary")
			var mine := bool(view.get("mine", false))
			b.disabled = mine or GameState.money < price
			if b.disabled:
				b.theme_type_variation = ""
			var id := str(r.get("id", ""))
			b.pressed.connect(func(): _send({"op": "buy", "item": id, "price": price}))
			var row := _row(r, [_price_label(price), b])
			_list.add_child(row)
	_till_footer()


func _till_footer() -> void:
	var tc := int(view.get("till_col", 0))
	var ti: Array = view.get("till_items", [])
	if tc <= 0 and ti.is_empty():
		return
	var b := UITheme.make_button("Collect", "primary")
	b.pressed.connect(func(): _send({"op": "collect"}))
	var txt := "%d Col" % tc + ((" · %d item%s: %s" % [ti.size(), "" if ti.size() == 1 else "s", ", ".join(ti.slice(0, 3))]) if not ti.is_empty() else "")
	_list.add_child(_line_card("coin", UITheme.GOLD, "Your till", txt, [b]))


func _render_manage(resto: bool) -> void:
	var my := int(view.get("my_stall", -1))
	if bool(view.get("free", false)):
		if my >= 0 and my != index:
			_list.add_child(_note("You already rent stall %d. One stall per character." % (my + 1)))
		else:
			_list.add_child(_section("Rent this stall", "%d Col / week" % Stalls.RENT))
			_list.add_child(_note("Pick what it will be, then pay the first week. You can prepay up to %d weeks." % Stalls.MAX_WEEKS))
			_list.add_child(_rent_buttons(false))
		if bool(view.get("guild_officer", false)):
			var gs_i := int(view.get("guild_stall", -1))
			_list.add_child(_section("Rent for [%s]" % str(view.get("guild_tag", "")), "%d Col / week" % Stalls.RENT))
			if gs_i >= 0:
				_list.add_child(_note("Your guild already rents stall %d. One stall per guild." % (gs_i + 1)))
			else:
				_list.add_child(_note("You pay the rent; any Officer or the Leader can stock and price it, and sales go to the guild storage at the notice board."))
				_list.add_child(_rent_buttons(true))
		_till_footer()
		return
	# Rent and type.
	var left := float(view.get("left", 0.0))
	var ext := UITheme.make_button("Extend a week · %d Col" % Stalls.RENT, "normal")
	ext.disabled = GameState.money < Stalls.RENT or left > (Stalls.MAX_WEEKS - 1) * Stalls.RENT_SECS
	ext.pressed.connect(func(): _send({"op": "rent"}))
	_list.add_child(_line_card("home", UITheme.CYAN, "Rent", "Paid for %s" % _dur(left), [ext]))
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 6)
	for t in ["shop", "restaurant"]:
		var c := UITheme.make_button("Shop" if t == "shop" else "Restaurant", "chip")
		UITheme.set_chip(c, str(view.get("type", "shop")) == t)
		var tt: String = t
		c.pressed.connect(func(): _send({"op": "type", "type": tt}))
		tb.add_child(c)
	_list.add_child(_line_card("food" if resto else "coin", Color("ffcf8a") if resto else UITheme.GOLD, "Stall type",
		"Cooked dishes only; seating out front" if resto else "Gear and goods of any kind", [tb]))
	if bool(view.get("guild_owned", false)):
		_list.add_child(_line_card("coin", UITheme.GOLD, "Guild storage", "Sales go here: %d Col so far. Officers draw it at the notice board." % int(view.get("guild_col", 0)), []))
	else:
		var tc := int(view.get("till_col", 0))
		var ti: Array = view.get("till_items", [])
		var cb := UITheme.make_button("Collect", "primary")
		cb.disabled = tc <= 0 and ti.is_empty()
		cb.pressed.connect(func(): _send({"op": "collect"}))
		_list.add_child(_line_card("coin", UITheme.GOLD, "Till", "%d Col%s" % [tc, (" · %d returned item(s)" % ti.size()) if not ti.is_empty() else ""], [cb]))
	# The counter.
	var rows: Array = view.get("listings", [])
	_list.add_child(_section("On the counter", "%d / %d" % [rows.size(), int(view.get("max_listings", Stalls.MAX_LISTINGS))]))
	if rows.is_empty():
		_list.add_child(_note("Nothing listed yet. Stock something from your pack below."))
	for r in rows:
		var id := str(r.get("id", ""))
		if not _prices.has(id):
			_prices[id] = int(r.get("price", 1))
		var pl := _price_label(int(_prices[id]))
		var set_b := UITheme.make_button("Set", "chip")
		set_b.pressed.connect(func(): _send({"op": "price", "item": id, "price": int(_prices[id])}))
		var wd := UITheme.make_button("Withdraw", "ghost")
		wd.pressed.connect(func(): _send({"op": "withdraw", "item": id}))
		_list.add_child(_row(r, [_stepper(_prices, id, pl, 1, Stalls.MAX_PRICE, true), set_b, wd]))
	# Stock from the pack.
	_list.add_child(_section("Stock from your pack", "dishes only" if resto else "set a price, then Stock"))
	var any := false
	if not resto:
		for it in GameState.inventory:
			if not (it is Dictionary) or not (str(it.get("kind", "")) in ["weapon", "armor"]):
				continue
			any = true
			var id := str(it.get("id", ""))
			var key: String = "inv:" + id
			if not _prices.has(key):
				_prices[key] = Stalls.suggest_price(it)
			var pl := _price_label(int(_prices[key]))
			var b := UITheme.make_button("Stock", "primary")
			var bound := bool(it.get("bound", false))
			b.disabled = bound
			if bound:
				b.text = "Bound"
				b.theme_type_variation = ""
			b.pressed.connect(func(): _send({"op": "stock", "item": id, "price": int(_prices[key])}))
			var d: Dictionary = it.duplicate()
			d["kind"] = it.get("kind", "")
			_list.add_child(_row(d, [_stepper(_prices, key, pl, 1, Stalls.MAX_PRICE, true), b]))
	for m in GameState.MATERIAL_NAMES:
		var have := int(GameState.materials.get(m, 0))
		if have <= 0 or (resto and not LifeData.RECIPES.has(m)):
			continue
		any = true
		var key: String = "mat:" + str(m)
		if not _qty.has(m):
			_qty[m] = 1
		_qty[m] = clampi(int(_qty[m]), 1, mini(have, Stalls.MAX_STACK))
		if not _prices.has(key):
			_prices[key] = Stalls.suggest_price({"kind": "stack", "mat": m, "count": int(_qty[m])})
		var ql := UITheme.label("x%d" % int(_qty[m]), 13, UITheme.PARCH, true)
		var pl := _price_label(int(_prices[key]))
		var b := UITheme.make_button("Stock", "primary")
		var mm: String = m
		b.pressed.connect(func(): _send({"op": "stock", "mat": mm, "count": int(_qty[mm]), "price": int(_prices[key])}))
		var info := {"kind": "stack", "mat": m, "count": have, "name": "%s  (have %d)" % [GameState.MATERIAL_NAMES[m], have]}
		_list.add_child(_row(info, [_stepper(_qty, m, ql, 1, mini(have, Stalls.MAX_STACK), false), _stepper(_prices, key, pl, 1, Stalls.MAX_PRICE, true), b]))
	if not any:
		_list.add_child(_note("Cook something at a fire first: grilled trout, boar stew, eel pie..." if resto else "Your pack has nothing to sell."))


# --- Widgets ---------------------------------------------------------------------

func _rent_buttons(guild: bool) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	for t in ["shop", "restaurant"]:
		var b := UITheme.make_button("Rent as Shop" if t == "shop" else "Rent as Restaurant", "primary" if t == "shop" else "normal")
		b.disabled = GameState.money < Stalls.RENT
		var tt: String = t
		b.pressed.connect(func(): _send({"op": "rent", "type": tt, "guild": guild}))
		hb.add_child(b)
	return hb


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


func _price_label(p: int) -> Label:
	var l := UITheme.label("%d Col" % p, 14, UITheme.GOLD, true)
	l.custom_minimum_size = Vector2(76, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## [-] value [+] that edits store[key]; prices step by ~10 %.
func _stepper(store: Dictionary, key: String, shown: Label, lo: int, hi: int, is_price: bool) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var minus := UITheme.make_button("-", "chip")
	var plus := UITheme.make_button("+", "chip")
	var upd := func(dir: int):
		var v := int(store[key])
		var step := maxi(1, roundi(v * 0.1)) if is_price else 1
		store[key] = clampi(v + dir * step, lo, hi)
		shown.text = ("%d Col" % int(store[key])) if is_price else ("x%d" % int(store[key]))
		Audio.play("ui_tick")
	minus.pressed.connect(func(): upd.call(-1))
	plus.pressed.connect(func(): upd.call(1))
	h.add_child(minus)
	h.add_child(shown)
	h.add_child(plus)
	return h


func _glyph_for(r: Dictionary) -> Array:
	var k := str(r.get("kind", ""))
	if k == "weapon":
		return ["sword", Crafting.rank_color(int(r.get("rank", 0)))]
	if k == "armor":
		return ["shield", Crafting.rank_color(int(r.get("rank", 0)))]
	var m := str(r.get("mat", ""))
	if LifeData.RECIPES.has(m):
		return ["food", LifeData.item_color(m)]
	if LifeData.FISH.has(m):
		return ["fish", LifeData.item_color(m)]
	if m == "wild_herb":
		return ["herb", LifeData.item_color(m)]
	if m == "willow_rod":
		return ["rod", LifeData.item_color(m)]
	if m == "iron_ore":
		return ["ore", Color("b8b8c8")]
	if m in ["beast_hide", "wolf_pelt"]:
		return ["hide", Color("b08560")]
	if m in ["spirit_shard", "wisp_essence"]:
		return ["shard", UITheme.CYAN]
	return ["star", UITheme.GOLD]


func _sub_for(r: Dictionary) -> String:
	var k := str(r.get("kind", ""))
	if k == "weapon":
		return "ATK %d  ·  %s" % [int(r.get("atk", 0)), Crafting.RANKS[clampi(int(r.get("rank", 0)), 0, Crafting.RANKS.size() - 1)]]
	if k == "armor":
		return "DEF %d  ·  %s" % [int(r.get("def", 0)), Crafting.RANKS[clampi(int(r.get("rank", 0)), 0, Crafting.RANKS.size() - 1)]]
	var m := str(r.get("mat", ""))
	if LifeData.RECIPES.has(m):
		return "Dish  ·  " + LifeData.buff_text(LifeData.RECIPES[m]["buff"])
	return LifeData.item_desc(m) if LifeData.item_desc(m) != "" else "Goods"


func _row(r: Dictionary, right: Array) -> PanelContainer:
	var g := _glyph_for(r)
	return _line_card(g[0], g[1], str(r.get("name", "")), _sub_for(r), right)


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


func _dur(s: float) -> String:
	var t := int(s)
	if t >= 86400:
		return "%d d %d h" % [t / 86400, (t % 86400) / 3600]
	if t >= 3600:
		return "%d h %d min" % [t / 3600, (t % 3600) / 60]
	return "%d min" % maxi(t / 60, 0)
