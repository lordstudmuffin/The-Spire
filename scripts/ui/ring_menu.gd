class_name RingMenu
extends Control
## Main in-game menu: a vertical column of round glass buttons that drops in
## beside the player (one by one, top to bottom), with translucent panels
## that slide out to the right. A second, narrower panel slides out further
## right for confirmations. Replaces the old pause modal as the menu entry
## point (Esc / Start); the existing full screens open from it.
##
## Behaviour only: every colour, size, timing and sound comes from
## RingMenuStyle (scripts/ui/ring_menu_style.gd).

const S := preload("res://scripts/ui/ring_menu_style.gd")

## id, label, glyph. Order is top to bottom.
const ENTRIES := [
	["status", "Status", "status"],
	["items", "Items", "items"],
	["skills", "Skills", "skills"],
	["quests", "Quests", "quests"],
	["map", "Map", "map"],
	["party", "Friends", "party"],
	["messages", "Messages", "messages"],
	["settings", "Settings", "settings"],
	["logout", "Log Out", "logout"],
]

signal closed

var hud: Node
var is_open := false
var selected := 0
var current_panel := ""
var _buttons: Array[RoundButton] = []
var _column: Control
var _name_tag: Label
var _panel: PanelContainer
var _panel_body: VBoxContainer
var _panel_title: Label
var _sub: PanelContainer
var _sub_body: VBoxContainer
var _sub_title: Label
var _tween: Tween
var _panel_tween: Tween
var _sub_tween: Tween


## One round button. A real Button so mouse, keyboard and pad focus all work.
class RoundButton extends Button:
	var glyph := ""
	var entry_id := ""
	var lit := false

	func _init() -> void:
		flat = true
		text = ""
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(st, empty)
		custom_minimum_size = Vector2(S.BTN_SIZE, S.BTN_SIZE)
		size = custom_minimum_size
		focus_mode = Control.FOCUS_ALL

	func set_lit(on: bool) -> void:
		if lit != on:
			lit = on
			queue_redraw()

	func _draw() -> void:
		S.draw_button(self, size * 0.5, S.BTN_SIZE * 0.5, lit, glyph)


static func build(owner_hud: Node) -> RingMenu:
	var m := RingMenu.new()
	m.hud = owner_hud
	return m


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_column = Control.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	for i in ENTRIES.size():
		var e: Array = ENTRIES[i]
		var b := RoundButton.new()
		b.entry_id = e[0]
		b.glyph = e[2]
		b.tooltip_text = e[1]
		b.position = Vector2(0, i * (S.BTN_SIZE + S.BTN_GAP))
		b.pivot_offset = Vector2(S.BTN_SIZE, S.BTN_SIZE) * 0.5
		var idx := i
		b.focus_entered.connect(func(): _select(idx))
		b.mouse_entered.connect(func(): b.grab_focus())
		b.pressed.connect(func(): activate(idx))
		_column.add_child(b)
		_buttons.append(b)
	for i in _buttons.size():
		var b := _buttons[i]
		b.focus_neighbor_top = b.get_path_to(_buttons[(i - 1 + _buttons.size()) % _buttons.size()])
		b.focus_neighbor_bottom = b.get_path_to(_buttons[(i + 1) % _buttons.size()])
		b.focus_neighbor_left = b.get_path()
	_name_tag = Label.new()
	_name_tag.add_theme_font_size_override("font_size", S.LABEL_SIZE)
	_name_tag.add_theme_color_override("font_color", Color(1, 1, 1))
	_name_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_name_tag.add_theme_constant_override("outline_size", 4)
	_name_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_name_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_tag.size = Vector2(140, 24)
	_column.add_child(_name_tag)
	var p := _make_panel(S.PANEL_W)
	_panel = p[0]
	_panel_title = p[1]
	_panel_body = p[2]
	var q := _make_panel(S.SUB_PANEL_W)
	_sub = q[0]
	_sub_title = q[1]
	_sub_body = q[2]
	get_viewport().size_changed.connect(_layout)
	_layout()


func _make_panel(width: float) -> Array:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", S.panel_box())
	pc.custom_minimum_size = Vector2(width, 0)
	# Content is measured a frame late (wrapped labels report a huge height
	# first), so shrink back whenever the real minimum arrives.
	pc.minimum_size_changed.connect(func(): pc.size = Vector2(pc.size.x, 0.0))
	pc.visible = false
	add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", S.header_box())
	v.add_child(head)
	var t := Label.new()
	t.add_theme_font_size_override("font_size", 17)
	t.add_theme_color_override("font_color", S.PANEL_TEXT)
	head.add_child(t)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	v.add_child(body)
	return [pc, t, body]


## Connector from the selected button to the open panel (look in RingMenuStyle).
func _draw() -> void:
	if _panel and _panel.visible and selected < _buttons.size():
		var b := _buttons[selected]
		var c := b.get_global_rect().get_center() - get_global_rect().position
		var pr := Rect2(_panel.get_global_rect().position - get_global_rect().position, _panel.size)
		S.draw_connector(self, c, S.BTN_SIZE * 0.5, pr, _panel.modulate.a)


func _process(_dt: float) -> void:
	if is_open:
		queue_redraw()


func _layout() -> void:
	var vp := get_viewport_rect().size
	var col_h := ENTRIES.size() * (S.BTN_SIZE + S.BTN_GAP) - S.BTN_GAP
	_column.position = vp * 0.5 + S.COLUMN_OFFSET - Vector2(0, col_h * 0.5)
	_place_panels()


func _place_panels() -> void:
	var vp := get_viewport_rect().size
	var px := _column.position.x + S.BTN_SIZE + S.PANEL_GAP
	_panel.position = Vector2(px, clampf(_column.position.y, 16.0, vp.y - 400.0))
	_sub.position = Vector2(px + S.PANEL_W + S.PANEL_GAP * 0.6, _panel.position.y + 40.0)


# --- Open / close -------------------------------------------------------------

func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_layout()
	_hide_panels(false)
	Audio.play(S.SND_OPEN)
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	for i in _buttons.size():
		var b := _buttons[i]
		var home := Vector2(0, i * (S.BTN_SIZE + S.BTN_GAP))
		b.position = home - Vector2(0, S.BTN_DROP)
		b.modulate.a = 0.0
		b.scale = Vector2(0.6, 0.6)
		var d := i * S.STAGGER
		_tween.tween_property(b, "position", home, S.BTN_IN).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(b, "modulate:a", 1.0, S.BTN_IN * 0.7).set_delay(d)
		_tween.tween_property(b, "scale", Vector2.ONE, S.BTN_IN).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	selected = clampi(selected, 0, _buttons.size() - 1)
	_buttons[selected].grab_focus()
	_select(selected, false)


## Reverse of open: buttons rise and fade bottom to top.
func close(silent := false) -> void:
	if not is_open:
		return
	is_open = false
	if not silent:
		Audio.play(S.SND_CLOSE)
	_hide_panels(false)
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	var n := _buttons.size()
	for i in n:
		var b := _buttons[i]
		var d := (n - 1 - i) * S.STAGGER * 0.6
		_tween.tween_property(b, "position:y", b.position.y - S.BTN_DROP * 0.6, S.BTN_IN * 0.8).set_delay(d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_tween.tween_property(b, "modulate:a", 0.0, S.BTN_IN * 0.8).set_delay(d)
	_tween.chain().tween_callback(func():
		if not is_open:
			visible = false)
	var f := get_viewport().gui_get_focus_owner()
	if f and is_ancestor_of(f):
		f.release_focus()
	closed.emit()


## Shows the column again without the open fanfare (e.g. after Settings).
func reshow() -> void:
	is_open = false
	open()


func _select(idx: int, sound := true) -> void:
	if idx != selected and sound:
		Audio.play(S.SND_SELECT)
	selected = idx
	for i in _buttons.size():
		_buttons[i].set_lit(i == idx)
	var b := _buttons[idx]
	_name_tag.text = ENTRIES[idx][1]
	_name_tag.position = Vector2(-_name_tag.size.x - 14, b.position.y + (S.BTN_SIZE - _name_tag.size.y) * 0.5)
	# Hovering a different button while a panel is open swaps the panel.
	if current_panel != "" and current_panel != ENTRIES[idx][0] and _panel_kind(ENTRIES[idx][0]):
		_open_panel(ENTRIES[idx][0])


# --- Actions ------------------------------------------------------------------

func _panel_kind(id: String) -> bool:
	return id in ["status", "items", "skills", "quests", "messages", "logout"]


func activate(idx: int) -> void:
	var id: String = ENTRIES[idx][0]
	if selected != idx:
		_buttons[idx].grab_focus()  # may already swap the open panel to this one
		if current_panel == id:
			return
	if _panel_kind(id):
		if current_panel == id:
			_hide_panels()
		else:
			Audio.play(S.SND_CONFIRM)
			_open_panel(id)
		return
	Audio.play(S.SND_CONFIRM)
	match id:
		"map":
			_leave_then(func(): hud.toggle_map())
		"party":
			_leave_then(func(): hud.toggle_nearby())
		"settings":
			_hide_panels(false)
			visible = false
			hud._open_settings()


## Closes the menu (and unpauses) and then opens a full screen.
func _leave_then(fn: Callable) -> void:
	hud._toggle_pause()
	fn.call()


func back() -> bool:
	if _sub.visible:
		_hide_sub()
		Audio.play(S.SND_BACK)
		return true
	if _panel.visible:
		_hide_panels()
		Audio.play(S.SND_BACK)
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or not visible:
		return
	if event.is_action_pressed("ui_cancel") and back():
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") and _panel.visible:
		_buttons[selected].grab_focus()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and _column_rect().has_point(event.position):
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_buttons[(selected - 1 + _buttons.size()) % _buttons.size()].grab_focus()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_buttons[(selected + 1) % _buttons.size()].grab_focus()
			get_viewport().set_input_as_handled()


func _column_rect() -> Rect2:
	var h := ENTRIES.size() * (S.BTN_SIZE + S.BTN_GAP)
	return Rect2(_column.position - Vector2(160, 20), Vector2(S.BTN_SIZE + 180, h + 40))


# --- Panels -------------------------------------------------------------------

func _hide_panels(animate := true) -> void:
	_hide_sub()
	current_panel = ""
	if not _panel.visible:
		return
	if not animate:
		_panel.visible = false
		return
	if _panel_tween:
		_panel_tween.kill()
	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.tween_property(_panel, "modulate:a", 0.0, S.PANEL_IN * 0.6)
	_panel_tween.tween_property(_panel, "position:x", _panel.position.x - S.PANEL_SLIDE * 0.5, S.PANEL_IN * 0.6)
	_panel_tween.chain().tween_callback(func():
		if current_panel == "":
			_panel.visible = false
		_place_panels())


func _hide_sub() -> void:
	_sub.visible = false


func _slide_in(pc: PanelContainer, tw_ref: String) -> void:
	_place_panels()
	var home := pc.position
	pc.position = home - Vector2(S.PANEL_SLIDE, 0)
	pc.modulate.a = 0.0
	pc.visible = true
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(pc, "position", home, S.PANEL_IN)
	tw.tween_property(pc, "modulate:a", 1.0, S.PANEL_IN)
	if tw_ref == "panel":
		if _panel_tween:
			_panel_tween.kill()
		_panel_tween = tw
	else:
		if _sub_tween:
			_sub_tween.kill()
		_sub_tween = tw
	Audio.play(S.SND_PANEL)


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _open_panel(id: String) -> void:
	_hide_sub()
	current_panel = id
	_clear(_panel_body)
	_panel_title.text = _title_for(id)
	match id:
		"status":
			_fill_status()
		"items":
			_fill_items()
		"skills":
			_fill_skills()
		"quests":
			_fill_quests()
		"messages":
			_fill_messages()
		"logout":
			_fill_logout()
	_panel.size = Vector2(S.PANEL_W, 0)
	_panel.reset_size()
	_slide_in(_panel, "panel")
	_wire_panel_focus()


func _title_for(id: String) -> String:
	for e in ENTRIES:
		if e[0] == id:
			return e[1]
	return id.capitalize()


## Right from the selected button enters the panel; up/down walk its rows.
func _wire_panel_focus() -> void:
	var rows: Array[Control] = []
	for c in _panel_body.get_children():
		if c is Button:
			rows.append(c)
	var b := _buttons[selected]
	if rows.is_empty():
		b.focus_neighbor_right = b.get_path()
		return
	b.focus_neighbor_right = b.get_path_to(rows[0])
	for i in rows.size():
		var r := rows[i]
		r.focus_neighbor_left = r.get_path_to(b)
		r.focus_neighbor_top = r.get_path_to(rows[maxi(i - 1, 0)])
		r.focus_neighbor_bottom = r.get_path_to(rows[mini(i + 1, rows.size() - 1)])


func _text(t: String, size := 15, col: Color = S.PANEL_TEXT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _row_label(left: String, right := "", col: Color = S.PANEL_TEXT) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	var h := HBoxContainer.new()
	m.add_child(h)
	var a := _text(left, 15, col)
	a.autowrap_mode = TextServer.AUTOWRAP_OFF
	a.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	a.clip_text = true
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	if right != "":
		var b := _text(right, 15, S.PANEL_SUBTLE)
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(b)
	return m


## A selectable row: flat button with the amber selection wash on focus.
func _row_button(text_left: String, cb: Callable, text_right := "", col: Color = S.PANEL_TEXT) -> Button:
	var b := Button.new()
	b.text = text_left + (("    " + text_right) if text_right != "" else "")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_stylebox_override("normal", S.row_box(false))
	b.add_theme_stylebox_override("hover", S.row_box(true))
	b.add_theme_stylebox_override("focus", S.row_box(true))
	b.add_theme_stylebox_override("pressed", S.row_box(true))
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(k, col)
	b.add_theme_font_size_override("font_size", 15)
	b.focus_entered.connect(func(): Audio.play(S.SND_SELECT))
	b.mouse_entered.connect(func(): b.grab_focus())
	b.pressed.connect(func():
		Audio.play(S.SND_CONFIRM)
		cb.call())
	return b


func _bar(frac: float, col: Color, label: String) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	m.add_child(v)
	v.add_child(_text(label, 13, S.PANEL_SUBTLE))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.max_value = 1.0
	bar.value = clampf(frac, 0.0, 1.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = S.BAR_BG
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	v.add_child(bar)
	return m


func _fill_status() -> void:
	var gs := GameState
	var who: String = str(gs.character.get("name", "Player"))
	_panel_body.add_child(_row_label(who, "Lv %d" % gs.level))
	if gs.title != "":
		_panel_body.add_child(_row_label(gs.title, "", S.PANEL_ACCENT))
	var mx: float = gs.max_hp()
	var f := gs.hp / maxf(mx, 1.0)
	_panel_body.add_child(_bar(f, S.hp_color(f), "HP  %d / %d" % [int(gs.hp), int(mx)]))
	var need := gs.xp_to_next()
	_panel_body.add_child(_bar(float(gs.xp) / maxf(need, 1), S.XP_FILL, "EXP  %d / %d" % [gs.xp, need]))
	for st in GameState.STAT_NAMES:
		_panel_body.add_child(_row_label(str(st).capitalize(), str(int(gs.stats.get(st, 0)))))
	if gs.stat_points > 0:
		_panel_body.add_child(_row_label("Unspent points", str(gs.stat_points), S.PANEL_ACCENT))
	_panel_body.add_child(_row_label("Class", gs.hidden_class if gs.hidden_class != "" else "None"))
	_panel_body.add_child(_row_label("Col", str(gs.money)))
	_panel_body.add_child(_row_button("Equipment and stats", func(): _leave_then(func(): hud.toggle_inventory()), "▸"))


func _fill_items() -> void:
	var gs := GameState
	var shown := 0
	for item in gs.inventory:
		if not (item is Dictionary) or shown >= 8:
			continue
		var rank := int(item.get("rank", 0))
		_panel_body.add_child(_row_label(str(item.get("name", "?")), Crafting.RANKS[clampi(rank, 0, 5)], Crafting.rank_color(rank).darkened(0.25)))
		shown += 1
	if gs.inventory.size() > shown:
		_panel_body.add_child(_row_label("…and %d more" % (gs.inventory.size() - shown), "", S.PANEL_SUBTLE))
	var mats := 0
	for id in gs.materials:
		mats += int(gs.materials[id])
	if shown == 0 and mats == 0:
		_panel_body.add_child(_row_label("Your pack is empty.", "", S.PANEL_SUBTLE))
	_panel_body.add_child(_row_label("Materials", str(mats)))
	_panel_body.add_child(_row_button("Open inventory", func(): _leave_then(func(): hud.toggle_inventory()), "▸"))


func _fill_skills() -> void:
	var player := get_tree().get_first_node_in_group("player")
	for i in Player.SKILLS.size():
		var sk: Dictionary = Player.SKILLS[i]
		var cd := 0.0
		if player and "skill_cd" in player:
			cd = float(player.skill_cd[i])
		_panel_body.add_child(_row_label("[%d]  %s" % [i + 1, sk["name"]], ("%.1fs" % cd) if cd > 0.0 else "Ready"))
	_panel_body.add_child(_row_label("Smithing", "Lv %d" % GameState.smithing_level))
	_panel_body.add_child(_row_label("Fishing", "Lv %d" % GameState.fishing_level))
	_panel_body.add_child(_row_label("Cooking", "Lv %d" % GameState.cooking_level))
	var unique := GameState.unique_skill
	_panel_body.add_child(_row_label("Unique skill", UniqueSkills.display_name(unique) if unique != "" else "None", S.PANEL_ACCENT if unique != "" else S.PANEL_SUBTLE))
	if unique != "":
		var arts := UniqueSkills.arts(unique)
		for i in arts.size():
			var ucd := 0.0
			if player and "unique_cd" in player:
				ucd = float(player.unique_cd[i])
			_panel_body.add_child(_row_label("[%d]  %s" % [i + 4, arts[i]["name"]], ("%.1fs" % ucd) if ucd > 0.0 else "Ready", S.PANEL_ACCENT))


func _fill_quests() -> void:
	var ids := QuestData.active_ids()
	if ids.is_empty():
		_panel_body.add_child(_row_label("No active quests.", "", S.PANEL_SUBTLE))
	for id in ids.slice(0, 6):
		_panel_body.add_child(_row_label(QuestData.title(id), QuestData.progress_text(id, GameState.quests[id])))
	_panel_body.add_child(_row_label("Completed", str(QuestData.completed_ids().size()), S.PANEL_SUBTLE))
	_panel_body.add_child(_row_button("Open quest log", func(): _leave_then(func(): hud.toggle_quests()), "▸"))


func _fill_messages() -> void:
	var lines: Array = hud.get("_chat_lines") if hud and "_chat_lines" in hud else []
	if lines.is_empty():
		_panel_body.add_child(_row_label("No messages yet.", "", S.PANEL_SUBTLE))
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]")
	for line in lines.slice(maxi(lines.size() - 6, 0)):
		var plain := re.sub(str(line), "", true)
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 16)
		m.add_theme_constant_override("margin_right", 16)
		var msg := _text(plain, 14)
		msg.custom_minimum_size = Vector2(S.PANEL_W - 32, 0)
		m.add_child(msg)
		_panel_body.add_child(m)
	_panel_body.add_child(_row_button("Write a message", func():
		hud._toggle_pause()
		hud.open_chat(), "▸"))


func _fill_logout() -> void:
	_panel_body.add_child(_row_label("Progress is saved on log out.", "", S.PANEL_SUBTLE))
	_panel_body.add_child(_row_button("Save now", func(): hud._save()))
	_panel_body.add_child(_row_button("Log out", _confirm_logout, "▸"))


func _confirm_logout() -> void:
	_clear(_sub_body)
	_sub_title.text = "Log Out"
	var q := _text("Are you sure you want to log out?", 15)
	q.custom_minimum_size = Vector2(S.SUB_PANEL_W - 32, 0)
	var qm := MarginContainer.new()
	qm.add_theme_constant_override("margin_left", 16)
	qm.add_theme_constant_override("margin_right", 16)
	qm.add_child(q)
	_sub_body.add_child(qm)
	var yes := _row_button("Yes", func(): hud._quit_to_menu())
	var no := _row_button("No", func(): back())
	_sub_body.add_child(yes)
	_sub_body.add_child(no)
	_sub.size = Vector2(S.SUB_PANEL_W, 0)
	_sub.reset_size()
	_slide_in(_sub, "sub")
	no.grab_focus()
