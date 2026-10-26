class_name InventoryScreen
extends HBoxContainer
## Inventory & Equipment (key I / Tab). Built once by the HUD and refreshed
## in place: item cards are pooled, never rebuilt per open.
##   left   - character summary, attributes (stat points), equipped slots
##   centre - item grid (rank border + glow), sort chips, materials, Col
##   right  - detail panel for the focused / hovered item
## Keyboard: arrows move between cards, Enter equips/unequips, Esc closes.

signal item_toggled(item: Dictionary, equipped: bool)
signal food_used(food_id: String)

const COLUMNS := 4
const CARD_SIZE := Vector2(148, 132)
const SORTS := ["Rank", "Newest", "Type"]

var _name_l: Label
var _class_l: Label
var _prof_line: UITheme.ProfLine
var _level_l: Label
var _cells := {}  # key -> value Label
var _attr_rows := {}  # stat -> {"val": Label, "bar": ProgressBar, "btn": Button}
var _points_l: Label
var _points_pill: PanelContainer
var _slot_cards := {}  # kind -> {"btn": Button, "name": Label, "stat": Label, "glyph": UIGlyph, "hint": Label}
var _grid: GridContainer
var _scroll: ScrollContainer
var _cards: Array = []  # pooled item cards (Button)
var _count_l: Label
var _empty_l: Label
var _sort_btns: Array = []
var _sort := 0
var _mats := {}  # material id -> count Label
var _prov := {}  # life item id -> {"cell", "count", "btn"}
var _prov_empty: Label
var _col_l: Label
var _detail := {}  # name/rank/kind/stat/cmp/by/hint labels + glyph
var _detail_item := {}
var _rank_styles := {}  # "rank:state" -> StyleBoxFlat
var _sorted: Array = []  # current item order
var _focus_index := -1


static func build() -> InventoryScreen:
	var s := InventoryScreen.new()
	s._build()
	return s


func _build() -> void:
	add_theme_constant_override("separation", 18)
	_build_left()
	_build_centre()
	_build_right()


# --- Left column ---------------------------------------------------------------

func _build_left() -> void:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(300, 0)
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	v.add_child(UITheme.kicker("Character"))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(56, 56)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.ring(badge, UITheme.NAVY2, UITheme.GOLD, 3.0)
	var bv := VBoxContainer.new()
	bv.set_anchors_preset(Control.PRESET_FULL_RECT)
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_theme_constant_override("separation", -6)
	var lk := UITheme.label("LV", 9, UITheme.GOLD, true)
	lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(lk)
	_level_l = Label.new()
	_level_l.theme_type_variation = "Heading"
	_level_l.add_theme_font_size_override("font_size", 22)
	_level_l.add_theme_color_override("font_color", UITheme.PARCH)
	_level_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_level_l)
	badge.add_child(bv)
	head.add_child(badge)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_l = UITheme.heading("", 24, UITheme.PARCH)
	_name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_child(_name_l)
	_class_l = UITheme.label("", 13, UITheme.CYAN, true)
	nv.add_child(_class_l)
	head.add_child(nv)
	v.add_child(head)
	v.add_child(UITheme.rule())

	var cells := GridContainer.new()
	cells.columns = 2
	cells.add_theme_constant_override("h_separation", 8)
	cells.add_theme_constant_override("v_separation", 8)
	for pair in [["hp", "Max HP", UITheme.ROSE], ["atk", "Attack", UITheme.GOLD], ["def", "Defense", UITheme.CYAN], ["smith", "Smithing", Color("ff9a3c")]]:
		var cell := PanelContainer.new()
		cell.theme_type_variation = "CardFlat"
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb: StyleBoxFlat = cell.get_theme_stylebox("panel").duplicate()
		sb.set_content_margin_all(10)
		sb.border_color = Color(pair[2].r, pair[2].g, pair[2].b, 0.25)
		cell.add_theme_stylebox_override("panel", sb)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 0)
		cv.add_child(UITheme.label(pair[1].to_upper(), 10, UITheme.MUTED, true))
		var val := UITheme.label("", 20, UITheme.PARCH, true)
		cv.add_child(val)
		var sub := UITheme.label("", 11, pair[2], true)
		cv.add_child(sub)
		cell.add_child(cv)
		cells.add_child(cell)
		_cells[pair[0]] = val
		_cells[pair[0] + "_sub"] = sub
	v.add_child(cells)
	# Weapon proficiency: notches at each Sword Art's unlock.
	_prof_line = UITheme.ProfLine.new()
	v.add_child(_prof_line)

	v.add_child(UITheme.spacer(2))
	var ah := HBoxContainer.new()
	var ak := UITheme.kicker("Attributes")
	ak.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ah.add_child(ak)
	_points_l = UITheme.label("", 11, UITheme.NAVY, true)
	_points_pill = _pill(_points_l, UITheme.GOLD)
	ah.add_child(_points_pill)
	v.add_child(ah)
	for s in GameState.STAT_NAMES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := UITheme.label(s.capitalize(), 14, UITheme.PARCH, true)
		l.custom_minimum_size = Vector2(84, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = 30
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("fill", UITheme.gradient_fill_box([UITheme.CYAN, UITheme.GOLD]))
		row.add_child(bar)
		var val := UITheme.label("", 16, UITheme.GOLD, true)
		val.custom_minimum_size = Vector2(30, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		var b := UITheme.make_button("+", "round")
		b.custom_minimum_size = Vector2(28, 28)
		b.tooltip_text = "Spend a stat point on %s" % s
		b.pressed.connect(func(): Net.spend_point(s))
		row.add_child(b)
		v.add_child(row)
		_attr_rows[s] = {"val": val, "bar": bar, "btn": b}

	v.add_child(UITheme.spacer(2))
	v.add_child(UITheme.kicker("Equipment"))
	for kind in ["weapon", "armor"]:
		v.add_child(_build_slot(kind))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var col_row := HBoxContainer.new()
	col_row.add_theme_constant_override("separation", 8)
	col_row.add_child(UIGlyph.make("coin", UITheme.GOLD, 26))
	_col_l = UITheme.label("", 18, UITheme.GOLD, true)
	_col_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col_row.add_child(_col_l)
	v.add_child(col_row)


func _build_slot(kind: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 64)
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = "Unequip"
	b.mouse_entered.connect(func(): Audio.play("ui_hover"))
	b.pressed.connect(func(): _toggle_slot(kind))
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -10
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := UIGlyph.make("sword" if kind == "weapon" else "shield", UITheme.MUTED, 40, 1.0)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(g)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(UITheme.label(kind.to_upper(), 10, UITheme.MUTED, true))
	var nl := UITheme.label("", 14, UITheme.PARCH, true)
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(nl)
	var sl := UITheme.label("", 12, UITheme.MUTED, true)
	tv.add_child(sl)
	h.add_child(tv)
	var hint := UITheme.label("", 10, UITheme.MUTED, true)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hint)
	b.add_child(h)
	_slot_cards[kind] = {"btn": b, "name": nl, "stat": sl, "glyph": g, "hint": hint}
	_style_slot(kind, null)
	return b


func _style_slot(kind: String, item) -> void:
	var b: Button = _slot_cards[kind]["btn"]
	var c: Color = Crafting.rank_color(int(item["rank"])) if item != null else UITheme.MUTED
	b.add_theme_stylebox_override("normal", _rank_style(c, 0, item != null))
	b.add_theme_stylebox_override("hover", _rank_style(c, 1, item != null))
	b.add_theme_stylebox_override("pressed", _rank_style(c, 1, item != null))
	b.add_theme_stylebox_override("focus", _rank_style(c, 2, item != null))
	b.add_theme_stylebox_override("disabled", _rank_style(c, 0, false))


# --- Centre -------------------------------------------------------------------

func _build_centre() -> void:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var k := UITheme.kicker("Inventory")
	head.add_child(k)
	_count_l = UITheme.subtle("", 12)
	_count_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_l.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_count_l)
	head.add_child(UITheme.subtle("Sort", 12))
	for i in SORTS.size():
		var b := UITheme.make_button(SORTS[i], "chip")
		b.pressed.connect(func(): _set_sort(i))
		head.add_child(b)
		_sort_btns.append(b)
	v.add_child(head)
	v.add_child(UITheme.rule())

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(COLUMNS * (CARD_SIZE.x + 10) + 12, 2 * (CARD_SIZE.y + 10))
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	v.add_child(_scroll)
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(wrap)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	wrap.add_child(_grid)
	_empty_l = UITheme.subtle("Your pack is empty. Forge gear at Haldor's anvil in the plaza.", 14)
	_empty_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	wrap.add_child(_empty_l)

	v.add_child(UITheme.rule())
	# Flow rows: they wrap to the grid's width instead of widening the
	# screen past the viewport as materials and provisions grow.
	var mh := HFlowContainer.new()
	mh.add_theme_constant_override("h_separation", 10)
	mh.add_theme_constant_override("v_separation", 8)
	var mk := UITheme.kicker("Materials")
	mk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mh.add_child(mk)
	mh.add_child(UITheme.spacer(4))
	var glyphs := {"iron_ore": ["ore", Color("b8bcc8")], "beast_hide": ["hide", Color("c98a3a")], "spirit_shard": ["shard", UITheme.CYAN],
		"wisp_essence": ["shard", Color("5ee0b0")], "stag_horn": ["horn", Color("e8a432")]}
	for m in GameState.MATERIAL_NAMES:
		if LifeData.is_life_item(m):
			continue  # fish, herbs, food and the rod live under Provisions
		var cell := PanelContainer.new()
		cell.theme_type_variation = "CardFlat"
		var sb: StyleBoxFlat = cell.get_theme_stylebox("panel").duplicate()
		sb.set_content_margin_all(6)
		sb.content_margin_right = 14
		cell.add_theme_stylebox_override("panel", sb)
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 8)
		var gk: Array = glyphs.get(m, ["ore", UITheme.MUTED])
		ch.add_child(UIGlyph.make(gk[0], gk[1], 34, 0.8))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", -2)
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_child(UITheme.label(GameState.MATERIAL_NAMES[m], 12, UITheme.MUTED, true))
		var cnt := UITheme.label("0", 18, UITheme.PARCH, true)
		cv.add_child(cnt)
		ch.add_child(cv)
		cell.add_child(ch)
		mh.add_child(cell)
		_mats[m] = cnt
	v.add_child(mh)
	_build_provisions(v)


## Provisions: fish, herbs, the rod and cooked food (stackables from the
## life layer). Food has a Use button that eats one portion for its buff.
func _build_provisions(v: VBoxContainer) -> void:
	v.add_child(UITheme.rule())
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 10)
	var pk := UITheme.kicker("Provisions")
	pk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pk)
	ph.add_child(UITheme.subtle("Use food for a timed buff", 12))
	v.add_child(ph)
	var strip := HFlowContainer.new()
	strip.add_theme_constant_override("h_separation", 8)
	strip.add_theme_constant_override("v_separation", 8)
	v.add_child(strip)
	for id in GameState.MATERIAL_NAMES:
		if not LifeData.is_life_item(id):
			continue
		var c := LifeData.item_color(id)
		var cell := PanelContainer.new()
		cell.theme_type_variation = "CardFlat"
		var sb: StyleBoxFlat = cell.get_theme_stylebox("panel").duplicate()
		sb.set_content_margin_all(6)
		sb.content_margin_right = 10
		sb.border_color = Color(c.r, c.g, c.b, 0.4)
		cell.add_theme_stylebox_override("panel", sb)
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 6)
		var kind := "fish" if LifeData.is_fish(id) else ("food" if LifeData.is_food(id) else ("rod" if LifeData.TOOLS.has(id) else ("shard" if LifeData.is_crystal(id) else "herb")))
		ch.add_child(UIGlyph.make(kind, c, 30, 0.6))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", -2)
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_child(UITheme.label(GameState.MATERIAL_NAMES[id], 11, UITheme.MUTED, true))
		var cnt := UITheme.label("0", 15, UITheme.PARCH, true)
		cv.add_child(cnt)
		ch.add_child(cv)
		var btn: Button = null
		if LifeData.is_food(id):
			btn = UITheme.mini_button("Use")
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			btn.tooltip_text = LifeData.buff_text(LifeData.RECIPES[id]["buff"])
			btn.pressed.connect(func(): use_food(id))
			ch.add_child(btn)
		elif LifeData.is_crystal(id):
			btn = UITheme.mini_button("Use")
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			btn.tooltip_text = LifeData.item_desc(id)
			btn.pressed.connect(func(): use_crystal(id))
			ch.add_child(btn)
		cell.add_child(ch)
		cell.tooltip_text = LifeData.item_desc(id)
		cell.hide()
		strip.add_child(cell)
		_prov[id] = {"cell": cell, "count": cnt, "btn": btn}
	_prov_empty = UITheme.subtle("Catch fish at the pond, pick Wild Herbs on the grass, cook at a camp fire.", 12)
	strip.add_child(_prov_empty)


## Eats one portion of a cooked food from the pack (its buff shows on the HUD).
func use_food(id: String) -> bool:
	if not LifeData.eat(id):
		Audio.play("ui_error")
		return false
	Audio.play("eat")
	food_used.emit(id)
	refresh()
	return true


## Crushes a crystal from the pack. Offline the world plays the effect at
## once; online it waits for the server's answer (world._on_net_action).
func use_crystal(id: String) -> bool:
	var err := LifeData.use_crystal(id)
	if err == "pending":
		return true
	if err != "":
		Audio.play("ui_error")
		var hud := get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast(err, "", "", UITheme.ROSE)
		return false
	var w := get_tree().current_scene
	if w and w.has_method("crystal_effect"):
		w.crystal_effect(id)
	refresh()
	return true


func _make_card() -> Button:
	var b := Button.new()
	b.custom_minimum_size = CARD_SIZE
	b.focus_mode = Control.FOCUS_ALL
	b.clip_contents = true
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -10
	v.offset_top = 8
	v.offset_bottom = -8
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := UIGlyph.make("sword", UITheme.PARCH, 38, 1.0)
	top.add_child(g)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	var eq := _pill(UITheme.label("EQUIPPED", 9, UITheme.NAVY, true), UITheme.GOLD)
	(eq.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = UITheme.GOLD
	eq.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	eq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(eq)
	v.add_child(top)
	var nl := UITheme.label("", 13, UITheme.PARCH, true)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size = Vector2(0, 36)
	nl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	var sl := UITheme.label("", 12, UITheme.MUTED, true)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sl)
	var by := UITheme.label("", 10, UITheme.MUTED)
	by.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	by.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(by)
	b.add_child(v)
	b.set_meta("glyph", g)
	b.set_meta("name", nl)
	b.set_meta("stat", sl)
	b.set_meta("by", by)
	b.set_meta("eq", eq)
	var idx := _cards.size()
	b.pressed.connect(func(): _activate(idx))
	b.focus_entered.connect(func(): _show_detail(idx))
	b.mouse_entered.connect(func():
		Audio.play("ui_hover")
		_show_detail(idx))
	UITheme.hover_fx(b, 1.03)
	_grid.add_child(b)
	_cards.append(b)
	return b


func _rank_style(c: Color, state: int, lit: bool) -> StyleBoxFlat:
	var key := "%s:%d:%s" % [c.to_html(false), state, lit]
	if _rank_styles.has(key):
		return _rank_styles[key]
	var alpha: float = [0.55, 0.9, 1.0][state]
	var s := UITheme.box(Color(UITheme.NAVY2.r, UITheme.NAVY2.g, UITheme.NAVY2.b, 0.9 if lit else 0.5), Color(c.r, c.g, c.b, alpha if lit else 0.25), 10, 2 if state > 0 else 1)
	s.set_content_margin_all(0)
	if lit:
		s.shadow_color = Color(c.r, c.g, c.b, [0.18, 0.35, 0.45][state])
		s.shadow_size = [6, 10, 12][state]
		s.shadow_offset = Vector2.ZERO
	if state == 2:
		s.bg_color = Color(c.r, c.g, c.b, 0.12).blend(Color(UITheme.NAVY2.r, UITheme.NAVY2.g, UITheme.NAVY2.b, 0.6))
	_rank_styles[key] = s
	return s


# --- Right: detail panel ------------------------------------------------------

func _build_right() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = "CardFlat"
	card.custom_minimum_size = Vector2(240, 0)
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
	sb.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(UITheme.kicker("Details"))
	var g := UIGlyph.make("sword", UITheme.PARCH, 72, 1.0)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(g)
	var nm := UITheme.heading("", 18, UITheme.PARCH)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 6)
	var rk := UITheme.label("", 10, UITheme.NAVY, true)
	var rk_pill := _pill(rk, UITheme.MUTED)
	chips.add_child(rk_pill)
	var kd := UITheme.label("", 10, UITheme.PARCH, true)
	chips.add_child(_pill(kd, UITheme.MUTED))
	v.add_child(chips)
	v.add_child(UITheme.rule())
	var stat := UITheme.heading("", 30, UITheme.GOLD)
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stat)
	var cmp := UITheme.label("", 12, UITheme.MUTED, true)
	cmp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cmp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(cmp)
	# Durability: small caps line over a wear gauge (not in the big stat).
	var dur_l := UITheme.label("", 11, UITheme.MUTED, true)
	dur_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(dur_l)
	var dur_g := UITheme.WearGauge.new(1.0, 200.0)
	dur_g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(dur_g)
	v.add_child(UITheme.spacer(4))
	var by := UITheme.subtle("", 12)
	by.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(by)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	var hint := HBoxContainer.new()
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	hint.add_theme_constant_override("separation", 8)
	hint.add_child(UITheme.action_cap("confirm"))
	var ht := UITheme.subtle("Equip", 12)
	hint.add_child(ht)
	v.add_child(hint)
	var hint2 := HBoxContainer.new()
	hint2.alignment = BoxContainer.ALIGNMENT_CENTER
	hint2.add_theme_constant_override("separation", 8)
	hint2.add_child(UITheme.action_cap("back"))
	hint2.add_child(UITheme.subtle("Close", 12))
	v.add_child(hint2)
	_detail = {"glyph": g, "name": nm, "rank": rk, "rank_pill": rk_pill, "kind": kd, "stat": stat, "cmp": cmp, "by": by, "hint": ht, "dur": dur_l, "dur_g": dur_g}


# --- Behaviour ----------------------------------------------------------------

func _pill(inner: Control, c: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := UITheme.box(Color(c.r, c.g, c.b, 0.14), Color(c.r, c.g, c.b, 0.45), 999, 1)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	p.add_child(inner)
	return p


static func is_equipped(item: Dictionary) -> bool:
	var worn: Variant = GameState.equipped.get(item.get("kind", ""))
	return worn != null and worn.get("id") == item.get("id")


## GameState has equip(); taking gear off is the mirror of it.
static func unequip(kind: String) -> void:
	if GameState.equipped.get(kind) == null:
		return
	GameState.equipped[kind] = null
	GameState.hp = minf(GameState.hp, GameState.max_hp())
	GameState.stats_changed.emit()
	GameState.health_changed.emit(GameState.hp, GameState.max_hp())
	GameState.inventory_changed.emit()


func _toggle_slot(kind: String) -> void:
	var worn: Variant = GameState.equipped.get(kind)
	if worn == null:
		Audio.play("ui_toggle")
		return
	Net.unequip(kind)
	Audio.play("ui_toggle")
	item_toggled.emit(worn, false)


func _activate(idx: int) -> void:
	if idx < 0 or idx >= _sorted.size():
		return
	var item: Dictionary = _sorted[idx]
	if is_equipped(item):
		Net.unequip(item["kind"])
		item_toggled.emit(item, false)
	else:
		Net.equip(item)
		item_toggled.emit(item, true)
	Audio.play("ui_toggle")
	_focus_index = idx


func _set_sort(i: int) -> void:
	_sort = i
	refresh()


func _sorted_items() -> Array:
	var items := GameState.inventory.duplicate()
	match _sort:
		0:
			items.sort_custom(func(a, b):
				if int(a.get("rank", 0)) != int(b.get("rank", 0)):
					return int(a.get("rank", 0)) > int(b.get("rank", 0))
				return int(a.get("atk", 0)) + int(a.get("def", 0)) > int(b.get("atk", 0)) + int(b.get("def", 0)))
		1:
			items.reverse()
		2:
			items.sort_custom(func(a, b):
				if a.get("kind") != b.get("kind"):
					return str(a.get("kind")) < str(b.get("kind"))
				return int(a.get("rank", 0)) > int(b.get("rank", 0)))
	return items


func _stat_text(item: Dictionary) -> String:
	var s := ("ATK %d" % int(item.get("atk", 0))) if item.get("kind") == "weapon" else ("DEF %d" % int(item.get("def", 0)))
	if Durability.is_broken(item):
		return s + "  ·  BROKEN"
	if Durability.fraction(item) < Durability.LOW:
		return s + "  ·  worn"
	return s


## Fill every widget from GameState. Safe to call often; only text and
## styles change, no nodes are created unless the inventory grew.
func refresh() -> void:
	_name_l.text = str(GameState.character.get("name", "")).to_upper()
	_class_l.text = GameState.class_title().to_upper()
	var marks: Array = []
	for sk in Player.SKILLS:
		marks.append(int(sk.get("prof", 0)))
	_prof_line.set_value(GameState.sword_prof, GameState.PROF_CAP, marks)
	_level_l.text = str(GameState.level)
	_cells["hp"].text = str(int(GameState.max_hp()))
	_cells["hp_sub"].text = "%d now" % ceili(GameState.hp)
	_cells["atk"].text = str(int(GameState.attack_damage()))
	_cells["atk_sub"].text = "+%d weapon" % int(GameState.weapon_attack()) if GameState.weapon_attack() > 0 else "no weapon"
	_cells["def"].text = str(int(GameState.armor_defense()))
	_cells["def_sub"].text = "soaks %d / hit" % int(GameState.armor_defense() * 0.5) if GameState.armor_defense() > 0 else "no armor"
	_cells["smith"].text = "Lv %d" % GameState.smithing_level
	_cells["smith_sub"].text = "%d / %d xp" % [GameState.smithing_xp, GameState.smithing_xp_to_next()]
	var pts := GameState.stat_points
	_points_l.text = ("%d POINTS TO SPEND" % pts) if pts > 0 else "NO POINTS"
	_points_l.add_theme_color_override("font_color", UITheme.NAVY if pts > 0 else UITheme.MUTED)
	var ps: StyleBoxFlat = _points_pill.get_theme_stylebox("panel")
	ps.bg_color = UITheme.GOLD if pts > 0 else Color(UITheme.MUTED.r, UITheme.MUTED.g, UITheme.MUTED.b, 0.12)
	ps.border_color = UITheme.GOLD if pts > 0 else Color(UITheme.MUTED.r, UITheme.MUTED.g, UITheme.MUTED.b, 0.4)
	for s in _attr_rows:
		var r: Dictionary = _attr_rows[s]
		r["val"].text = str(GameState.stats.get(s, 0))
		r["bar"].value = GameState.stats.get(s, 0)
		r["btn"].disabled = pts <= 0
		r["btn"].modulate.a = 1.0 if pts > 0 else 0.35
	for kind in _slot_cards:
		var sc: Dictionary = _slot_cards[kind]
		var worn: Variant = GameState.equipped.get(kind)
		if worn != null:
			var c := Crafting.rank_color(int(worn.get("rank", 0)))
			sc["name"].text = str(worn.get("name", ""))
			sc["name"].add_theme_color_override("font_color", c)
			sc["stat"].text = "%s  ·  %s" % [_stat_text(worn), Crafting.RANKS[int(worn.get("rank", 0))]]
			sc["glyph"].set_glyph("sword" if kind == "weapon" else "shield", c)
			sc["hint"].text = "UNEQUIP"
			sc["btn"].disabled = false
		else:
			sc["name"].text = "Empty slot"
			sc["name"].add_theme_color_override("font_color", UITheme.MUTED)
			sc["stat"].text = "Nothing equipped"
			sc["glyph"].set_glyph("sword" if kind == "weapon" else "shield", Color(UITheme.MUTED.r, UITheme.MUTED.g, UITheme.MUTED.b, 0.5))
			sc["hint"].text = ""
			sc["btn"].disabled = true
		_style_slot(kind, worn)
	for i in _sort_btns.size():
		UITheme.set_chip(_sort_btns[i], i == _sort)

	_sorted = _sorted_items()
	_count_l.text = "%d item%s" % [_sorted.size(), "" if _sorted.size() == 1 else "s"]
	_empty_l.visible = _sorted.is_empty()
	while _cards.size() < _sorted.size():
		_make_card()
	for i in _cards.size():
		var b: Button = _cards[i]
		if i >= _sorted.size():
			b.hide()
			continue
		var item: Dictionary = _sorted[i]
		var rank := int(item.get("rank", 0))
		var c := Crafting.rank_color(rank)
		var worn := is_equipped(item)
		b.show()
		b.add_theme_stylebox_override("normal", _rank_style(c, 0, true))
		b.add_theme_stylebox_override("hover", _rank_style(c, 1, true))
		b.add_theme_stylebox_override("pressed", _rank_style(c, 1, true))
		b.add_theme_stylebox_override("focus", _rank_style(c, 2, true))
		(b.get_meta("glyph") as UIGlyph).set_glyph("sword" if item.get("kind") == "weapon" else "shield", c)
		var nl: Label = b.get_meta("name")
		nl.text = str(item.get("name", ""))
		nl.add_theme_color_override("font_color", c)
		(b.get_meta("stat") as Label).text = _stat_text(item)
		(b.get_meta("by") as Label).text = "by %s" % str(item.get("crafted_by", "?"))
		(b.get_meta("eq") as Control).visible = worn
		# Wear: a thin gauge along the card foot, and a crack once broken.
		var broken := Durability.is_broken(item)
		var wf := Durability.fraction(item)
		if not b.has_meta("wear"):
			var g := UITheme.WearGauge.new(1.0, 10.0)
			g.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			g.offset_left = 10
			g.offset_right = -10
			g.offset_top = -9
			g.offset_bottom = -4
			b.add_child(g)
			b.set_meta("wear", g)
			var ck := UITheme.CrackOverlay.new(i * 7919 + 13)
			b.add_child(ck)
			b.set_meta("crack", ck)
		var wg: UITheme.WearGauge = b.get_meta("wear")
		wg.visible = wf < 0.999
		wg.set_frac(wf)
		(b.get_meta("crack") as Control).visible = broken
		b.tooltip_text = "%s\n%s  ·  %s\nCrafted by %s%s" % [item.get("name", ""), Crafting.RANKS[rank], _stat_text(item), item.get("crafted_by", "?"), _work_suffix(item)]
	for m in _mats:
		_mats[m].text = str(GameState.materials.get(m, 0))
	var any_prov := false
	for id in _prov:
		var n := int(GameState.materials.get(id, 0))
		var pr: Dictionary = _prov[id]
		(pr["cell"] as Control).visible = n > 0
		(pr["count"] as Label).text = ("x%d" % n) + ("  ·  active" if GameState.has_buff(id) else "")
		any_prov = any_prov or n > 0
	_prov_empty.visible = not any_prov
	_col_l.text = "%d Col" % GameState.money
	if _detail_item.is_empty() and not _sorted.is_empty():
		_show_detail(0)
	elif not _detail_item.is_empty():
		# Re-point at the live item (it may have moved after a sort).
		var found := -1
		for i in _sorted.size():
			if _sorted[i].get("id") == _detail_item.get("id"):
				found = i
		_show_detail(found if found >= 0 else (0 if not _sorted.is_empty() else -1))


func _show_detail(idx: int) -> void:
	if idx < 0 or idx >= _sorted.size():
		_detail_item = {}
		_detail["name"].text = "NOTHING HERE"
		_detail["name"].add_theme_color_override("font_color", UITheme.MUTED)
		_detail["rank_pill"].visible = false
		_detail["kind"].text = "—"
		_detail["stat"].text = ""
		_detail["dur"].visible = false
		(_detail["dur_g"] as Control).visible = false
		_detail["cmp"].text = "Forge gear at Haldor's anvil, or loot it from the Labyrinth."
		_detail["by"].text = ""
		_detail["glyph"].set_glyph("sword", Color(UITheme.MUTED.r, UITheme.MUTED.g, UITheme.MUTED.b, 0.4))
		_detail["hint"].text = "Equip"
		return
	var item: Dictionary = _sorted[idx]
	_detail_item = item
	var rank := int(item.get("rank", 0))
	var c := Crafting.rank_color(rank)
	_detail["glyph"].set_glyph("sword" if item.get("kind") == "weapon" else "shield", c)
	_detail["name"].text = str(item.get("name", "")).to_upper()
	_detail["name"].add_theme_color_override("font_color", c)
	_detail["rank"].text = "RATING: %s" % Crafting.RANKS[rank].to_upper()
	_detail["rank_pill"].visible = true
	var rs: StyleBoxFlat = _detail["rank_pill"].get_theme_stylebox("panel")
	rs.bg_color = c
	rs.border_color = c
	_detail["kind"].text = str(item.get("kind", "")).to_upper()
	_detail["stat"].text = ("ATK %d" % int(item.get("atk", 0))) if item.get("kind") == "weapon" else ("DEF %d" % int(item.get("def", 0)))
	var dt := Durability.text(item)
	_detail["dur"].text = dt.to_upper()
	_detail["dur"].add_theme_color_override("font_color", UITheme.ROSE if Durability.is_broken(item) else UITheme.MUTED)
	_detail["dur"].visible = dt != ""
	(_detail["dur_g"] as UITheme.WearGauge).visible = dt != ""
	(_detail["dur_g"] as UITheme.WearGauge).set_frac(Durability.fraction(item))
	var worn: Variant = GameState.equipped.get(item.get("kind"))
	var mine := int(item.get("atk", 0)) + int(item.get("def", 0))
	if is_equipped(item):
		_detail["cmp"].text = "Currently equipped"
		_detail["cmp"].add_theme_color_override("font_color", UITheme.GOLD)
		_detail["hint"].text = "Unequip"
	elif worn != null:
		var theirs := int(worn.get("atk", 0)) + int(worn.get("def", 0))
		var d := mine - theirs
		_detail["cmp"].text = "%s%d vs %s" % ["+" if d >= 0 else "", d, worn.get("name", "equipped")]
		_detail["cmp"].add_theme_color_override("font_color", UITheme.GREEN if d > 0 else (UITheme.ROSE if d < 0 else UITheme.MUTED))
		_detail["hint"].text = "Equip"
	else:
		_detail["cmp"].text = "Slot is empty"
		_detail["cmp"].add_theme_color_override("font_color", UITheme.MUTED)
		_detail["hint"].text = "Equip"
	_detail["by"].text = "Crafted by %s" % str(item.get("crafted_by", "?")) + _work_suffix(item)


## "  ·  Fine work" for forged pieces (Forging quality), "" for older items.
static func _work_suffix(item: Dictionary) -> String:
	if not item.has("quality"):
		return ""
	return "  ·  %s work" % Forging.quality_word(float(item["quality"]) / 100.0)


## Put keyboard focus on the first card (or the slot) when the screen opens.
func focus_first() -> void:
	var idx := clampi(_focus_index, 0, _sorted.size() - 1)
	if idx >= 0 and idx < _cards.size() and _cards[idx].visible:
		_cards[idx].grab_focus()
	elif not _slot_cards.is_empty():
		for kind in _slot_cards:
			var b: Button = _slot_cards[kind]["btn"]
			if not b.disabled:
				b.grab_focus()
				return
		_sort_btns[0].grab_focus()
