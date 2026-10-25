class_name StorageScreen
extends VBoxContainer
## The cottage chest: your pack on the left, the chest on the right, one
## button per item to move it across (GameState.store_item). Equipped gear
## moved into the chest is unequipped first. Rows are pooled per side.

const ROWS := 12

var _pack_rows: Array = []
var _chest_rows: Array = []
var _pack_count: Label
var _chest_count: Label
var _pack_empty: Label
var _chest_empty: Label


static func build() -> StorageScreen:
	var s := StorageScreen.new()
	s._build()
	return s


func _build() -> void:
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	var k := UITheme.kicker("Your cottage")
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(k)
	head.add_child(UITheme.subtle("Esc to close", 13))
	add_child(head)
	add_child(UITheme.heading("Storage Chest", 28))
	add_child(UITheme.rule())
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	add_child(cols)
	var pack := _column(cols, "Pack", "Store")
	_pack_rows = pack["rows"]
	_pack_count = pack["count"]
	_pack_empty = pack["empty"]
	var chest := _column(cols, "Chest", "Take")
	_chest_rows = chest["rows"]
	_chest_count = chest["count"]
	_chest_empty = chest["empty"]
	var hint := UITheme.subtle("Stored gear stays in the cottage and in your save. Equipped pieces are unequipped when stored.", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(hint)


func _column(parent: Control, title: String, action: String) -> Dictionary:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(330, 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	parent.add_child(v)
	var h := HBoxContainer.new()
	var k := UITheme.kicker(title, UITheme.GOLD if title == "Chest" else UITheme.CYAN)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(k)
	var count := UITheme.subtle("", 12)
	h.add_child(count)
	v.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 300)
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var rows := []
	for i in ROWS:
		var row := PanelContainer.new()
		row.theme_type_variation = "CardFlat"
		var sb: StyleBoxFlat = row.get_theme_stylebox("panel").duplicate()
		sb.set_content_margin_all(8)
		row.add_theme_stylebox_override("panel", sb)
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 10)
		var g := UIGlyph.make("sword", UITheme.PARCH, 28, 0.6)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rh.add_child(g)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", -2)
		var nl := UITheme.label("", 14, UITheme.PARCH, true)
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tv.add_child(nl)
		var sl := UITheme.label("", 11, UITheme.MUTED, true)
		tv.add_child(sl)
		rh.add_child(tv)
		var b := UITheme.make_button(action, "chip")
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rh.add_child(b)
		row.add_child(rh)
		row.hide()
		list.add_child(row)
		rows.append({"row": row, "sb": sb, "glyph": g, "name": nl, "stat": sl, "btn": b, "id": ""})
		var idx := i
		b.pressed.connect(func(): _move(title == "Pack", idx))
	var empty := UITheme.subtle("Empty", 13)
	list.add_child(empty)
	return {"rows": rows, "count": count, "empty": empty}


func _move(from_pack: bool, idx: int) -> void:
	var rows: Array = _pack_rows if from_pack else _chest_rows
	var id: String = rows[idx]["id"]
	if id == "":
		Audio.play("ui_error")
		return
	if Net.remote_client():
		Net.request_action("store", {"id": id, "to_storage": from_pack})  # the server moves it; the patch refreshes us
		return
	if not GameState.store_item(id, from_pack):
		Audio.play("ui_error")
		return
	Audio.play("drop" if from_pack else "pickup")
	refresh()


func refresh() -> void:
	_fill(_pack_rows, GameState.inventory, _pack_count, _pack_empty)
	_fill(_chest_rows, GameState.home_storage, _chest_count, _chest_empty)


func _fill(rows: Array, items: Array, count: Label, empty: Label) -> void:
	count.text = "%d / %d" % [items.size(), ROWS] if rows == _chest_rows else "%d item%s" % [items.size(), "" if items.size() == 1 else "s"]
	empty.visible = items.is_empty()
	for i in rows.size():
		var r: Dictionary = rows[i]
		if i >= items.size():
			(r["row"] as Control).hide()
			r["id"] = ""
			continue
		var item: Dictionary = items[i]
		var c := Crafting.rank_color(int(item.get("rank", 0)))
		(r["row"] as Control).show()
		(r["sb"] as StyleBoxFlat).border_color = Color(c.r, c.g, c.b, 0.45)
		(r["glyph"] as UIGlyph).set_glyph("sword" if item.get("kind") == "weapon" else "shield", c)
		(r["name"] as Label).text = str(item.get("name", ""))
		(r["name"] as Label).add_theme_color_override("font_color", c)
		var stat := ("ATK %d" % int(item.get("atk", 0))) if item.get("kind") == "weapon" else ("DEF %d" % int(item.get("def", 0)))
		(r["stat"] as Label).text = stat + ("  ·  equipped" if InventoryScreen.is_equipped(item) else "")
		r["id"] = str(item.get("id", ""))
		(r["btn"] as Button).disabled = rows == _pack_rows and GameState.home_storage.size() >= ROWS
