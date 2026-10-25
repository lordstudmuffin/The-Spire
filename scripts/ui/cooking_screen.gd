class_name CookingScreen
extends VBoxContainer
## Cooking screen (camp fires, Thornwick's fire pit, the cottage hearth).
## Mirrors the forge UI: a header with the cooking skill and ingredient
## pills, one row per recipe with its buff, cost and a Cook button, and a
## Provisions row to eat what you carry. Built once by LifeHUD, refreshed in
## place: rows are created on first refresh and then only retextured.

signal cooked(result: Dictionary)
signal ate(food_id: String)

var where := "Camp fire"
var _kicker: Label
var _skill_pill: Label
var _ing_box: HBoxContainer
var _ing_labels := {}  # material id -> Label
var _rows := {}  # recipe id -> {"btn": Button, "cost": Label, "lock": Label, "card": PanelContainer}
var _food_cards := {}  # food id -> {"card", "count", "btn"}
var _food_empty: Label
var _hint: Label


static func build() -> CookingScreen:
	var s := CookingScreen.new()
	s._build()
	return s


func _build() -> void:
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	_kicker = UITheme.kicker(where)
	_kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_kicker)
	head.add_child(UITheme.subtle("Esc to close", 13))
	add_child(head)
	add_child(UITheme.heading("Cooking", 28))
	add_child(UITheme.rule())
	_ing_box = HBoxContainer.new()
	_ing_box.add_theme_constant_override("separation", 8)
	_skill_pill = UITheme.label("", 12, Color("ff9a3c"), true)
	_ing_box.add_child(_pill(_skill_pill, Color("ff9a3c")))
	for m in ["river_trout", "mire_eel", "moonscale_koi", "beast_hide", "wild_herb"]:
		var l := UITheme.label("", 12, UITheme.PARCH, true)
		_ing_box.add_child(_pill(l, LifeData.item_color(m)))
		_ing_labels[m] = l
	add_child(_ing_box)
	add_child(UITheme.spacer(2))
	for id in LifeData.RECIPES:
		var r: Dictionary = LifeData.RECIPES[id]
		var row := PanelContainer.new()
		row.theme_type_variation = "CardFlat"
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var g := UIGlyph.make("food", Color(r["color"]), 40, 0.6)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(g)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 2)
		var nr := HBoxContainer.new()
		nr.add_theme_constant_override("separation", 8)
		nr.add_child(UITheme.label(r["name"], 16, UITheme.PARCH, true))
		nr.add_child(UITheme.label(LifeData.buff_text(r["buff"]), 12, UITheme.CYAN, true))
		var lock := UITheme.label("Cooking Lv %d" % int(r.get("level", 1)), 11, UITheme.ROSE, true)
		nr.add_child(lock)
		v.add_child(nr)
		var cost := UITheme.subtle(LifeData.recipe_cost_text(id), 13)
		v.add_child(cost)
		h.add_child(v)
		var b := UITheme.make_button("Cook", "primary")
		b.custom_minimum_size = Vector2(96, 36)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func(): _cook(id))
		h.add_child(b)
		row.add_child(h)
		add_child(row)
		_rows[id] = {"btn": b, "cost": cost, "lock": lock, "card": row}
	add_child(UITheme.spacer(2))
	var ph := HBoxContainer.new()
	var pk := UITheme.kicker("Provisions")
	pk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pk)
	ph.add_child(UITheme.subtle("Eat for a timed buff; buffs stack across foods", 12))
	add_child(ph)
	var foods := HBoxContainer.new()
	foods.add_theme_constant_override("separation", 8)
	add_child(foods)
	for id in LifeData.RECIPES:
		var r: Dictionary = LifeData.RECIPES[id]
		var card := PanelContainer.new()
		card.theme_type_variation = "CardFlat"
		var sb: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
		sb.set_content_margin_all(8)
		sb.border_color = Color(Color(r["color"]).r, Color(r["color"]).g, Color(r["color"]).b, 0.4)
		card.add_theme_stylebox_override("panel", sb)
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 8)
		ch.add_child(UIGlyph.make("food", Color(r["color"]), 30, 0.5))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", -2)
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_child(UITheme.label(r["name"], 12, UITheme.PARCH, true))
		var cnt := UITheme.label("", 11, UITheme.MUTED, true)
		cv.add_child(cnt)
		ch.add_child(cv)
		var eb := UITheme.make_button("Eat", "chip")
		eb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		eb.pressed.connect(func(): _eat(id))
		ch.add_child(eb)
		card.add_child(ch)
		foods.add_child(card)
		_food_cards[id] = {"card": card, "count": cnt, "btn": eb}
	_food_empty = UITheme.subtle("Nothing cooked yet.", 12)
	foods.add_child(_food_empty)
	_hint = UITheme.subtle("Fish come from the pond, the stream and the Mere. Wild Herbs grow in clumps on the open grass. Hides drop from boars and toads.", 12)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_hint)


func _pill(inner: Control, c: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := UITheme.box(Color(c.r, c.g, c.b, 0.12), Color(c.r, c.g, c.b, 0.4), 999, 1)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", s)
	p.add_child(inner)
	return p


func set_where(text: String) -> void:
	where = text
	if _kicker:
		_kicker.text = text


func refresh() -> void:
	_kicker.text = where
	_skill_pill.text = "Cooking Lv %d  ·  %d/%d" % [GameState.cooking_level, GameState.cooking_xp, GameState.life_xp_to_next(GameState.cooking_level)]
	for m in _ing_labels:
		_ing_labels[m].text = "%s %d" % [GameState.MATERIAL_NAMES.get(m, m), int(GameState.materials.get(m, 0))]
	for id in _rows:
		var r: Dictionary = LifeData.RECIPES[id]
		var row: Dictionary = _rows[id]
		var known: bool = GameState.cooking_level >= int(r.get("level", 1))
		var can := LifeData.can_cook(id)
		(row["lock"] as Label).visible = not known
		var b: Button = row["btn"]
		b.disabled = not can
		b.theme_type_variation = "PrimaryButton" if can else ""
		(row["card"] as Control).modulate.a = 1.0 if known else 0.6
	var any := false
	for id in _food_cards:
		var n := int(GameState.materials.get(id, 0))
		var fc: Dictionary = _food_cards[id]
		(fc["card"] as Control).visible = n > 0
		(fc["count"] as Label).text = "x%d%s" % [n, "  ·  active" if GameState.has_buff(id) else ""]
		any = any or n > 0
	_food_empty.visible = not any


func _cook(id: String) -> void:
	var res := LifeData.cook(id)
	if res.has("pending"):
		return  # online: the server cooks; the world toasts its answer
	if res.has("error"):
		Audio.play("craft_fail")
	else:
		Audio.play("cook")
		if res.get("skill_up", false):
			Audio.play("craft_success")
	cooked.emit(res)
	refresh()


func _eat(id: String) -> void:
	if LifeData.eat(id):
		Audio.play("eat")
		ate.emit(id)
	else:
		Audio.play("ui_error")
	refresh()
