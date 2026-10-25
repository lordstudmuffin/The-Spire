extends VBoxContainer
## Hollowbrook farm plot screen (P8). Shows the plot's four soil beds (crop,
## growth, thirst, wither warning) with Plant / Water / Harvest / Clear, the
## rent, and the seed cart. Every button sends one farm operation through the
## FarmField node (scripts/life/farms.gd): offline and on the host it runs at
## once on the realm, online the server answers through show_result(). The
## screen only draws the server's "view". Plot -1 is the seed cart alone.

const Farms := preload("res://scripts/life/farms.gd")

var farms: Node = null
var index := 0
var view: Dictionary = {}
var _kicker: Label
var _title: Label
var _col_l: Label
var _status: Label
var _list: VBoxContainer
var _seed_pick := "turnip"
var _qty := {}
var _pending := false
var _poll := 0.0


static func build():
	var s = load("res://scripts/ui/farm_screen.gd").new()
	s._build()
	return s


func _build() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(680, 0)
	var head := HBoxContainer.new()
	_kicker = UITheme.kicker("Hollowbrook Fields")
	_kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_kicker)
	head.add_child(UITheme.subtle("Esc to close", 13))
	add_child(head)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 12)
	_title = UITheme.heading("Farm plot", 28)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(_title)
	_col_l = UITheme.label("", 14, UITheme.GOLD, true)
	_col_l.size_flags_vertical = Control.SIZE_SHRINK_END
	th.add_child(_col_l)
	add_child(th)
	add_child(UITheme.rule())
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
	var hint := UITheme.subtle("Rent is %d Col a week; one plot per character. Crops grow only while the soil is wet: water after sowing and whenever a bed turns thirsty. Unripe crops left dry too long wither. When the rent runs out the field is turned over." % Farms.RENT, 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(hint)


# --- Open / answers ---------------------------------------------------------------

func open(node: Node, i: int) -> void:
	farms = node
	index = i
	view = {}
	_qty.clear()
	_kicker.text = "Hollowbrook Fields  ·  %s" % ("Seed cart" if i < 0 else "Plot %d" % (i + 1))
	_title.text = "Seed Cart" if i < 0 else "Plot %d" % (i + 1)
	_status.text = "Looking over the field..."
	_clear()
	_send({"op": "view"})


func _send(payload: Dictionary) -> void:
	if farms == null:
		return
	var res: Dictionary = farms.request(index, payload)
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
	match str(res.get("op", "view")):
		"view":
			_status.text = ""
		"rent":
			Audio.play("coins")
			_status.text = "Rent paid: %d Col. %s" % [int(res.get("paid", 0)), "Another week is yours." if res.get("renewed", false) else "The plot is yours for a week."]
		"seeds":
			Audio.play("coins")
			_status.text = "Bought %d %s for %d Col." % [int(res.get("count", 0)), str(res.get("bought", "")), int(res.get("cost", 0))]
		"plant":
			Audio.play("drop")
			_status.text = "%s sown. Water the bed to start it growing." % str(LifeData.CROPS.get(str(res.get("planted", "")), {}).get("name", "Seed"))
		"water":
			Audio.play("pickup")
			_status.text = "Watered %d bed%s." % [int(res.get("watered", 0)), "" if int(res.get("watered", 0)) == 1 else "s"]
		"harvest":
			Audio.play("level_up" if int(res.get("seeds_back", 0)) > 0 else "pickup")
			_status.text = "Harvested %s.%s" % [str(res.get("text", "")), "  A seed fell loose too." if int(res.get("seeds_back", 0)) > 0 else ""]
		"clear":
			Audio.play("ui_tick")
			_status.text = "Bed turned over."
	if res.get("view") is Dictionary:
		view = res["view"]
		_render()


func refresh() -> void:
	if not view.is_empty():
		_render()


func _process(delta: float) -> void:
	# Growth is time based: ask again now and then while the screen is open.
	if not is_visible_in_tree() or farms == null or _pending:
		return
	_poll -= delta
	if _poll <= 0.0:
		_poll = 15.0
		if not view.is_empty():
			_send({"op": "view"})


# --- Rendering -------------------------------------------------------------------

func _clear() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()


func _render() -> void:
	_clear()
	_col_l.text = "%d Col" % int(view.get("money", GameState.money))
	if index >= 0:
		_render_plot()
	_render_seeds()


func _render_plot() -> void:
	var my := int(view.get("my_plot", -1))
	if bool(view.get("free", false)):
		_title.text = "Plot %d  ·  For rent" % (index + 1)
		if my >= 0 and my != index:
			_list.add_child(_note("You already rent plot %d. One plot per character." % (my + 1)))
			return
		var b := UITheme.make_button("Rent for a week · %d Col" % Farms.RENT, "primary")
		b.disabled = int(view.get("money", 0)) < Farms.RENT
		b.pressed.connect(func(): _send({"op": "rent"}))
		_list.add_child(_line_card("home", UITheme.GOLD, "Rent this plot", "Four soil beds. Prepay up to %d weeks." % Farms.MAX_WEEKS, [b]))
		return
	if not bool(view.get("mine", false)):
		_title.text = "%s's Plot" % str(view.get("owner", "Someone"))
		_list.add_child(_note("%s tends this plot." % str(view.get("owner", "Someone"))))
		for st in view.get("beds", []):
			_list.add_child(_bed_card(-1, st, false))
		return
	_title.text = "Your Plot"
	var left := float(view.get("left", 0.0))
	var ext := UITheme.make_button("Extend · %d Col" % Farms.RENT, "normal")
	ext.disabled = int(view.get("money", 0)) < Farms.RENT or left > (Farms.MAX_WEEKS - 1) * Farms.RENT_SECS
	ext.pressed.connect(func(): _send({"op": "rent"}))
	var water := UITheme.make_button("Water all", "primary")
	water.pressed.connect(func(): _send({"op": "water", "bed": -1}))
	var harvest := UITheme.make_button("Harvest all", "normal")
	harvest.pressed.connect(func(): _send({"op": "harvest", "bed": -1}))
	_list.add_child(_line_card("home", UITheme.CYAN, "Rent", "Paid for %s" % _dur(left), [water, harvest, ext]))
	# Seed picker for empty beds.
	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 6)
	pick.add_child(UITheme.label("Sow:", 13, UITheme.MUTED, true))
	var seeds: Dictionary = view.get("seeds", {})
	for c in LifeData.CROPS:
		var chip := UITheme.make_button("%s ×%d" % [LifeData.CROPS[c]["name"], int(seeds.get(c, 0))], "chip")
		UITheme.set_chip(chip, _seed_pick == c)
		var cc: String = c
		chip.pressed.connect(func():
			_seed_pick = cc
			Audio.play("ui_tick")
			_render())
		pick.add_child(chip)
	_list.add_child(pick)
	var beds: Array = view.get("beds", [])
	for b in beds.size():
		_list.add_child(_bed_card(b, beds[b], true))


func _bed_card(b: int, st: Dictionary, mine: bool) -> Control:
	var stage := str(st.get("stage", "empty"))
	var crop := str(st.get("crop", ""))
	var d: Dictionary = LifeData.CROPS.get(crop, {})
	var nm := str(d.get("name", "Bare soil"))
	var sub := ""
	var c := Color("8a7a52")
	var right: Array = []
	match stage:
		"empty":
			sub = "Tilled and ready for seed."
			if mine:
				var have := int((view.get("seeds", {}) as Dictionary).get(_seed_pick, 0))
				var p := UITheme.make_button("Plant %s" % LifeData.CROPS[_seed_pick]["name"], "primary")
				p.disabled = have <= 0
				p.pressed.connect(func(): _send({"op": "plant", "bed": b, "crop": _seed_pick}))
				right.append(p)
		"withered":
			c = Color("9a6a3a")
			sub = "Withered for want of water."
			if mine:
				var cl := UITheme.make_button("Clear", "ghost")
				cl.pressed.connect(func(): _send({"op": "clear", "bed": b}))
				right.append(cl)
		"ripe":
			c = Color(str(d.get("color", "f0c060")))
			sub = "Ripe! Ready to harvest."
			if mine:
				var h := UITheme.make_button("Harvest", "primary")
				h.pressed.connect(func(): _send({"op": "harvest", "bed": b}))
				right.append(h)
		_:
			c = Color("7bdc8a")
			var pct := int(round(float(st.get("progress", 0.0)) * 100.0))
			var dry := bool(st.get("dry", false))
			sub = "%s  ·  %d%%  ·  %s" % [stage.capitalize(), pct, ("thirsty: growth paused, withers in %s" % _dur(float(st.get("wither_in", 0.0)))) if dry else ("ripe in about %s of wet soil" % _dur(float(st.get("left", 0.0))))]
			if dry:
				c = Color("e0b060")
			if mine:
				var w := UITheme.make_button("Water", "primary" if dry else "normal")
				w.pressed.connect(func(): _send({"op": "water", "bed": b}))
				right.append(w)
				var cl := UITheme.make_button("Pull", "ghost")
				cl.tooltip_text = "Dig the crop up (it is lost)."
				cl.pressed.connect(func(): _send({"op": "clear", "bed": b}))
				right.append(cl)
	var title := ("Bed %d  ·  " % (b + 1) if b >= 0 else "") + nm
	return _line_card("herb", c, title, sub, right)


func _render_seeds() -> void:
	_list.add_child(_section("Seed cart", "Col %d" % int(view.get("money", 0))))
	var seeds: Dictionary = view.get("seeds", {})
	for c in LifeData.CROPS:
		var d: Dictionary = LifeData.CROPS[c]
		if not _qty.has(c):
			_qty[c] = 5
		var price := int(d["seed_price"])
		var ql := UITheme.label("×%d" % int(_qty[c]), 13, UITheme.PARCH, true)
		var cost := UITheme.label("%d Col" % (price * int(_qty[c])), 14, UITheme.GOLD, true)
		cost.custom_minimum_size = Vector2(70, 0)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var minus := UITheme.make_button("-", "chip")
		var plus := UITheme.make_button("+", "chip")
		var cc: String = c
		var upd := func(dir: int):
			_qty[cc] = clampi(int(_qty[cc]) + dir, 1, Farms.MAX_SEEDS)
			ql.text = "×%d" % int(_qty[cc])
			cost.text = "%d Col" % (price * int(_qty[cc]))
			Audio.play("ui_tick")
		minus.pressed.connect(func(): upd.call(-1))
		plus.pressed.connect(func(): upd.call(1))
		var buy := UITheme.make_button("Buy", "primary")
		buy.pressed.connect(func(): _send({"op": "seeds", "crop": cc, "count": int(_qty[cc])}))
		var sub := "%d Col each  ·  ripens in %s  ·  you have %d" % [price, _dur(float(d["grow"])), int(seeds.get(c, 0))]
		_list.add_child(_line_card("herb", Color("b89a6a"), str(d["seed_name"]), sub, [minus, ql, plus, cost, buy]))
	if index < 0:
		var my := int(view.get("my_plot", -1))
		_list.add_child(_note("Your plot: %d. Walk into it to tend it." % (my + 1) if my >= 0 else "Rent one of the eight plots in the field behind the cart: walk onto a plot and press interact."))


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
	if t >= 60:
		return "%d min" % (t / 60)
	return "%d s" % maxi(t, 0)
