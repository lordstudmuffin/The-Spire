class_name QuestLog
extends VBoxContainer
## Quest log (key J): Active / Completed tabs, one card per quest with
## title, giver, objective progress bar and reward. Cards are pooled and
## refreshed in place. "Track" picks the quest the HUD widget follows.

signal track_requested(id: String)

var tracked := ""
var _tab := 0  # 0 active, 1 completed
var _tab_btns: Array = []
var _tab_counts: Array = []
var _scroll: ScrollContainer
var _list: VBoxContainer
var _cards: Array = []  # pooled card dictionaries
var _empty: Label
var _summary: Label
var _styles := {}


static func build() -> QuestLog:
	var q := QuestLog.new()
	q._build()
	return q


func _build() -> void:
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UITheme.kicker("Journal"))
	tv.add_child(UITheme.heading("Quest Log", 28))
	head.add_child(tv)
	for i in 2:
		var b := UITheme.make_button(["Active", "Completed"][i], "chip")
		b.size_flags_vertical = Control.SIZE_SHRINK_END
		b.pressed.connect(func(): set_tab(i))
		head.add_child(b)
		_tab_btns.append(b)
	add_child(head)
	add_child(UITheme.rule())
	_summary = UITheme.subtle("", 13)
	add_child(_summary)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(760, 430)
	_scroll.follow_focus = true
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)
	_empty = UITheme.subtle("", 15)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD
	_list.add_child(_empty)
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 8)
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	for pair in [["tabs", "Switch tab"], ["confirm", "Track quest"], ["back", "Close"]]:
		hint.add_child(UITheme.action_cap(pair[0]) if pair[0] != "tabs" else _tabs_cap())
		hint.add_child(UITheme.subtle(pair[1], 12))
		hint.add_child(UITheme.spacer(6))
	add_child(hint)


func _card_style(c: Color, done: bool) -> StyleBoxFlat:
	var key := "%s:%s" % [c.to_html(false), done]
	if _styles.has(key):
		return _styles[key]
	var s := UITheme.box(Color(1, 1, 1, 0.03 if done else 0.05), Color(c.r, c.g, c.b, 0.35), 10, 1)
	s.border_width_left = 4
	s.set_content_margin_all(14)
	s.content_margin_left = 18
	_styles[key] = s
	return s


func _make_card() -> Dictionary:
	var p := PanelContainer.new()
	_list.add_child(p)
	_list.move_child(p, _list.get_child_count() - 2)  # keep the empty label last
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	var icon := UIGlyph.make("scroll", UITheme.CYAN, 44, 1.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 3)
	h.add_child(v)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	var title := UITheme.heading("", 19, UITheme.PARCH)
	title_row.add_child(title)
	var status := UITheme.label("", 10, UITheme.NAVY, true)
	var status_pill := PanelContainer.new()
	var sps := UITheme.box(UITheme.GOLD, UITheme.GOLD, 999, 1)
	sps.content_margin_left = 8
	sps.content_margin_right = 8
	sps.content_margin_top = 1
	sps.content_margin_bottom = 1
	status_pill.add_theme_stylebox_override("panel", sps)
	status_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_pill.add_child(status)
	title_row.add_child(status_pill)
	v.add_child(title_row)
	var giver := UITheme.label("", 12, UITheme.CYAN, true)
	v.add_child(giver)
	var story := UITheme.subtle("", 13)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(story)
	v.add_child(UITheme.spacer(2))
	var obj := UITheme.label("", 14, UITheme.PARCH, true)
	obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(obj)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 10)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("fill", UITheme.gradient_fill_box([Color("2d8fd5"), UITheme.CYAN]))
	bar_row.add_child(bar)
	var prog := UITheme.label("", 12, UITheme.MUTED, true)
	prog.custom_minimum_size = Vector2(150, 0)
	prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_row.add_child(prog)
	v.add_child(bar_row)
	var rew_row := HBoxContainer.new()
	rew_row.add_theme_constant_override("separation", 6)
	rew_row.add_child(UIGlyph.make("star", UITheme.GOLD, 16))
	rew_row.add_child(UITheme.label("REWARD", 10, UITheme.MUTED, true))
	var reward := UITheme.label("", 12, UITheme.GOLD, true)
	rew_row.add_child(reward)
	v.add_child(rew_row)
	var track := UITheme.make_button("Track", "chip")
	track.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	track.custom_minimum_size = Vector2(96, 32)
	h.add_child(track)
	var d := {"panel": p, "icon": icon, "title": title, "status": status, "status_pill": status_pill, "giver": giver,
		"story": story, "obj": obj, "bar": bar, "prog": prog, "reward": reward, "track": track, "id": ""}
	track.pressed.connect(func():
		if d["id"] != "":
			track_requested.emit(d["id"]))
	_cards.append(d)
	return d


func set_tab(i: int) -> void:
	if _tab != i:
		Audio.play("ui_click")
	_tab = i
	refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.physical_keycode == KEY_Q or k.physical_keycode == KEY_LEFT and _focus_in_tabs():
		set_tab(0)
		get_viewport().set_input_as_handled()
	elif k.physical_keycode == KEY_E or k.physical_keycode == KEY_RIGHT and _focus_in_tabs():
		set_tab(1)
		get_viewport().set_input_as_handled()


## "Q / E" on the keyboard, "LB / RB" on a pad.
func _tabs_cap() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	var kb := UITheme.keycap("Q / E")
	var pad := UITheme.keycap("LB / RB")
	h.add_child(kb)
	h.add_child(pad)
	var refresh := func():
		kb.visible = not InputSetup.using_gamepad()
		pad.visible = InputSetup.using_gamepad()
	refresh.call()
	h.tree_entered.connect(func(): InputSetup.input_device_changed.connect(func(_d): if is_instance_valid(h): refresh.call()), CONNECT_ONE_SHOT)
	return h


## Gamepad: LB / RB switch tabs while the log is open.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventJoypadButton) or not event.pressed:
		return
	var bi := (event as InputEventJoypadButton).button_index
	if bi == JOY_BUTTON_LEFT_SHOULDER:
		set_tab(0)
		get_viewport().set_input_as_handled()
	elif bi == JOY_BUTTON_RIGHT_SHOULDER:
		set_tab(1)
		get_viewport().set_input_as_handled()


func _focus_in_tabs() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f != null and f in _tab_btns


func refresh() -> void:
	var active := QuestData.active_ids()
	var done := QuestData.completed_ids()
	_tab_btns[0].text = "Active  %d" % active.size()
	_tab_btns[1].text = "Completed  %d" % done.size()
	for i in 2:
		UITheme.set_chip(_tab_btns[i], i == _tab)
	var ids: Array = active if _tab == 0 else done
	_summary.text = ("%d quest%s in progress  ·  tracked quest shows on the HUD" % [active.size(), "" if active.size() == 1 else "s"]) if _tab == 0 else ("%d quest%s completed on Floor 1" % [done.size(), "" if done.size() == 1 else "s"])
	_empty.visible = ids.is_empty()
	_empty.text = "No active quests. Talk to Guide Mira in the plaza, Captain Rhys to the north or Elder Wren in Hollowbrook." if _tab == 0 else "Nothing completed yet. Finished quests are kept here."
	while _cards.size() < ids.size():
		_make_card()
	for i in _cards.size():
		var d: Dictionary = _cards[i]
		if i >= ids.size():
			d["panel"].hide()
			d["id"] = ""
			continue
		var id: String = ids[i]
		var q: Dictionary = GameState.quests[id]
		var info := QuestData.info(id)
		var is_done := bool(q.get("done", false))
		var ready := not is_done and int(q.get("progress", 0)) >= int(q.get("goal", 1))
		var c: Color = UITheme.GREEN if is_done else (UITheme.GOLD if ready else UITheme.CYAN)
		d["id"] = id
		d["panel"].show()
		d["panel"].add_theme_stylebox_override("panel", _card_style(c, is_done))
		d["icon"].set_glyph("star" if is_done else "scroll", c)
		d["title"].text = str(info["title"]).to_upper()
		d["title"].add_theme_color_override("font_color", UITheme.MUTED if is_done else UITheme.PARCH)
		d["status_pill"].visible = is_done or ready or id == tracked
		d["status"].text = "COMPLETE" if is_done else ("READY TO TURN IN" if ready else "TRACKED")
		var sps: StyleBoxFlat = d["status_pill"].get_theme_stylebox("panel")
		sps.bg_color = c
		sps.border_color = c
		d["giver"].text = "%s  ·  %s" % [info["giver"], info["where"]]
		d["story"].text = str(info["story"])
		d["obj"].text = str(info["objective"])
		d["bar"].max_value = maxi(int(q.get("goal", 1)), 1)
		d["bar"].value = int(q.get("goal", 1)) if is_done else int(q.get("progress", 0))
		d["bar"].add_theme_stylebox_override("fill", UITheme.gradient_fill_box([Color("2d8fd5"), UITheme.CYAN] if not (is_done or ready) else [UITheme.GOLD_DIM, c]))
		d["prog"].text = QuestData.progress_text(id, q)
		d["reward"].text = str(info["reward"])
		d["track"].visible = not is_done
		d["track"].text = "Tracked" if id == tracked else "Track"
		UITheme.set_chip(d["track"], id == tracked)


func focus_first() -> void:
	for d in _cards:
		if d["panel"].visible and d["track"].visible:
			d["track"].grab_focus()
			return
	_tab_btns[_tab].grab_focus()
