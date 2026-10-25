class_name ShopScreen
extends VBoxContainer
## Trader Pell's stall: the Willow Rod and the cottage decorations. One row
## per ware with price, what you own and a Buy button (LifeData.buy). Rows
## are built once and refreshed in place.

signal bought(id: String)

var _col_l: Label
var _rows := {}  # id -> {"btn", "own", "price", "card"}


static func build() -> ShopScreen:
	var s := ShopScreen.new()
	s._build()
	return s


func _build() -> void:
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	var k := UITheme.kicker("Trader Pell's stall")
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(k)
	head.add_child(UITheme.subtle("Esc to close", 13))
	add_child(head)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 12)
	var title := UITheme.heading("Wares", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(title)
	_col_l = UITheme.label("", 14, UITheme.GOLD, true)
	_col_l.size_flags_vertical = Control.SIZE_SHRINK_END
	th.add_child(_col_l)
	add_child(th)
	add_child(UITheme.rule())
	var wares := [["willow_rod", LifeData.TOOLS["willow_rod"]["name"], LifeData.ROD_PRICE, LifeData.TOOLS["willow_rod"]["desc"], "rod", LifeData.item_color("willow_rod")]]
	for id in LifeData.DECOR:
		var d: Dictionary = LifeData.DECOR[id]
		wares.append([id, d["name"], int(d["col"]), d["desc"], "home", UITheme.GOLD])
	for w in wares:
		var id: String = w[0]
		var row := PanelContainer.new()
		row.theme_type_variation = "CardFlat"
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var g := UIGlyph.make(w[4], w[5], 40, 0.5)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(g)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 2)
		var nr := HBoxContainer.new()
		nr.add_theme_constant_override("separation", 8)
		nr.add_child(UITheme.label(w[1], 16, UITheme.PARCH, true))
		var own := UITheme.label("", 12, UITheme.CYAN, true)
		nr.add_child(own)
		v.add_child(nr)
		var desc := UITheme.subtle(w[3], 13)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		v.add_child(desc)
		h.add_child(v)
		var price := UITheme.label("%d Col" % int(w[2]), 14, UITheme.GOLD, true)
		price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(price)
		var b := UITheme.make_button("Buy", "primary")
		b.custom_minimum_size = Vector2(84, 36)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func(): _buy(id))
		h.add_child(b)
		row.add_child(h)
		add_child(row)
		_rows[id] = {"btn": b, "own": own, "price": price, "card": row, "cost": int(w[2])}
	var hint := UITheme.subtle("Decorations go in the six slots of your Hollowbrook cottage (For Sale by the well, %d Col)." % LifeData.HOME_PRICE, 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(hint)


func refresh() -> void:
	_col_l.text = "%d Col" % GameState.money
	for id in _rows:
		var r: Dictionary = _rows[id]
		var owned := int(GameState.materials.get(id, 0)) if id == "willow_rod" else int(GameState.decor_owned.get(id, 0))
		(r["own"] as Label).text = ("owned x%d" % owned) if owned > 0 else ""
		var locked := LifeData.DECOR.has(id) and not LifeData.decor_available(id)
		var can: bool = GameState.money >= int(r["cost"]) and not locked
		var b: Button = r["btn"]
		b.disabled = not can
		b.text = "Locked" if locked else "Buy"
		b.theme_type_variation = "PrimaryButton" if can else ""
		(r["card"] as Control).modulate.a = 0.6 if locked else 1.0


func _buy(id: String) -> void:
	var err := LifeData.buy(id)
	if err == "pending":
		return  # online: the server sells; the world toasts its answer
	if err == "":
		Audio.play("coins")
		bought.emit(id)
	else:
		Audio.play("craft_fail")
	refresh()
