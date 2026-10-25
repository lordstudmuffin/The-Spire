class_name SettingsPanel
extends VBoxContainer
## Settings form shared by the title screen and the pause menu: Graphics,
## Audio and Controls tabs. Writes through Settings (autoload) immediately;
## `closed` fires on Back (or Esc / B). The Controls tab holds look
## sensitivity, invert-Y, vibration, the stick deadzone and a remap list
## with a keyboard/mouse column and a gamepad column (InputSetup autoload).

signal closed

const TABS := ["Graphics", "Audio", "Controls"]

var _tab := 0
var _tab_btns: Array = []
var _pages: Array = []
var _page: VBoxContainer  # the page rows are being added to
var _listen := {}  # while rebinding: {"action", "column", "button"}
var _remap_rows := {}  # action -> {"kb": Button, "pad": Button, "label": Label}
var _note: Label
var _reset_btn: Button


static func build() -> SettingsPanel:
	var p := SettingsPanel.new()
	p.add_theme_constant_override("separation", 10)
	p._build()
	return p


func _build() -> void:
	add_child(UITheme.kicker("Settings"))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	add_child(tabs)
	for i in TABS.size():
		var b := UITheme.make_button(TABS[i], "chip")
		b.custom_minimum_size = Vector2(0, 34)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): show_tab(i))
		tabs.add_child(b)
		_tab_btns.append(b)
	add_child(UITheme.rule())
	for i in TABS.size():
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 10)
		page.visible = i == 0
		add_child(page)
		_pages.append(page)

	# --- Graphics ---
	_page = _pages[0]
	_option_row("Quality preset", Settings.PRESETS, Settings.data["preset"], func(v): Settings.set_value("preset", v),
		"Auto picks by GPU. Ultra is tuned for RTX 4070/5070-class cards.")
	_option_row("Window", Settings.WINDOW_MODES, Settings.data["window_mode"], func(v): Settings.set_value("window_mode", v))
	_toggle_row("V-Sync", Settings.data["vsync"], func(v): Settings.set_value("vsync", v))
	_toggle_row("Show FPS", Settings.data["show_fps"], func(v): Settings.set_value("show_fps", v))
	_slider_row("Field of view", 60.0, 110.0, 1.0, Settings.data["fov"], func(v): Settings.set_value("fov", v), "%d°")
	var info := UITheme.subtle("Renderer: %s  ·  GPU: %s" % [Settings.rendering_method(), RenderingServer.get_video_adapter_name()], 12)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(info)

	# --- Audio ---
	_page = _pages[1]
	_slider_row("Master volume", 0.0, 1.0, 0.01, Settings.data["master_volume"], func(v): Settings.set_value("master_volume", v), "%d%%", 100.0)
	_slider_row("Music volume", 0.0, 1.0, 0.01, Settings.data["music_volume"], func(v): Settings.set_value("music_volume", v), "%d%%", 100.0)
	_slider_row("Effects volume", 0.0, 1.0, 0.01, Settings.data["sfx_volume"], func(v): Settings.set_value("sfx_volume", v), "%d%%", 100.0)

	# --- Controls ---
	_page = _pages[2]
	_build_controls()

	add_child(UITheme.spacer(2))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	add_child(foot)
	var back := UITheme.make_button("Back", "primary")
	back.custom_minimum_size = Vector2(0, 44)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func(): closed.emit())  # make_button already clicks
	foot.add_child(back)
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 6)
	hint.add_child(UITheme.action_cap("back"))
	hint.add_child(UITheme.subtle("close", 12))
	hint.add_child(UITheme.spacer(4))
	hint.add_child(UITheme.action_cap("map_zoom_out"))
	hint.add_child(UITheme.action_cap("map_zoom_in"))
	hint.add_child(UITheme.subtle("tabs", 12))
	foot.add_child(hint)
	show_tab(0, false)


func _build_controls() -> void:
	_slider_row("Mouse sensitivity", 0.2, 3.0, 0.05, Settings.data["mouse_sens"], func(v): Settings.set_value("mouse_sens", v), "%.2fx")
	_slider_row("Stick sensitivity", 0.2, 3.0, 0.05, Settings.data["stick_sens"], func(v): Settings.set_value("stick_sens", v), "%.2fx")
	_slider_row("Stick deadzone", 0.05, 0.6, 0.01, Settings.data["stick_deadzone"], func(v): Settings.set_value("stick_deadzone", v), "%d%%", 100.0)
	_toggle_row("Invert camera Y", Settings.data["invert_y"], func(v): Settings.set_value("invert_y", v))
	_toggle_row("Controller vibration", Settings.data["vibration"], func(v):
		Settings.set_value("vibration", v)
		if v:
			InputSetup.rumble(0.3, 0.5, 0.25))
	_page.add_child(UITheme.rule(UITheme.MUTED))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var hl := UITheme.kicker("Key bindings")
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	for col in [["Keyboard / mouse", 140], ["Gamepad", 120]]:
		var cl := UITheme.subtle(col[0], 12)
		cl.custom_minimum_size = Vector2(col[1], 0)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(cl)
	_page.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_page.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for entry in InputSetup.REMAPPABLE:
		var action: String = entry[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := Label.new()
		l.text = entry[1]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 15)
		row.add_child(l)
		var kb := _bind_button(action, "kb", 140)
		row.add_child(kb)
		var pad := _bind_button(action, "pad", 120)
		row.add_child(pad)
		list.add_child(row)
		_remap_rows[action] = {"kb": kb, "pad": pad, "label": l}
	_note = UITheme.subtle("Select a binding, then press a key, mouse button, gamepad button or stick direction. Esc cancels.", 12)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(_note)
	_reset_btn = UITheme.make_button("Reset to defaults", "ghost")
	_reset_btn.pressed.connect(func():
		_cancel_listen()
		InputSetup.reset_bindings()
		_note.text = "Bindings reset to defaults."
		_refresh_bindings())
	_page.add_child(_reset_btn)
	InputSetup.bindings_changed.connect(_refresh_bindings)
	tree_exiting.connect(func():
		if InputSetup.bindings_changed.is_connected(_refresh_bindings):
			InputSetup.bindings_changed.disconnect(_refresh_bindings))
	_refresh_bindings()


func _bind_button(action: String, column: String, width: int) -> Button:
	var b := UITheme.make_button("", "normal")
	b.custom_minimum_size = Vector2(width, 32)
	b.add_theme_font_size_override("font_size", 14)
	b.clip_text = true
	b.pressed.connect(func(): _start_listen(action, column, b))
	return b


func _refresh_bindings() -> void:
	for action in _remap_rows:
		var r: Dictionary = _remap_rows[action]
		for col in ["kb", "pad"]:
			var b: Button = r[col]
			if not _listen.is_empty() and _listen["button"] == b:
				continue
			var parts: Array = []
			for e in InputSetup.events(action, col):
				parts.append(InputSetup.event_text(e))
			b.text = "  ·  ".join(parts) if not parts.is_empty() else "—"
			b.tooltip_text = "Click to rebind"
		var custom: bool = not InputSetup.is_default(action)
		(r["label"] as Label).add_theme_color_override("font_color", UITheme.GOLD if custom else UITheme.PARCH)
	if _reset_btn:
		_reset_btn.disabled = Settings.data["bindings"].is_empty()


# --- Rebinding -------------------------------------------------------------

func _start_listen(action: String, column: String, b: Button) -> void:
	_cancel_listen()
	_listen = {"action": action, "column": column, "button": b}
	b.text = "Press a key…" if column == "kb" else "Press a button…"
	b.theme_type_variation = "PrimaryButton"
	_note.text = "Listening for %s… Esc cancels." % ("a key or mouse button" if column == "kb" else "a gamepad button or stick direction")


func _cancel_listen() -> void:
	if _listen.is_empty():
		return
	var b: Button = _listen["button"]
	b.theme_type_variation = ""
	_listen = {}
	_refresh_bindings()


## While listening, the next bindable press is captured before the GUI sees it.
func _input(event: InputEvent) -> void:
	if _listen.is_empty() or not is_visible_in_tree():
		return
	if event is InputEventMouseMotion:
		return
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_cancel_listen()
		_note.text = "Cancelled."
		get_viewport().set_input_as_handled()
		return
	var ev := InputSetup.bindable(event)
	if ev == null:
		# Releases (and small stick wobbles) are swallowed so nothing else reacts.
		if not (event is InputEventJoypadMotion):
			get_viewport().set_input_as_handled()
		return
	var column: String = _listen["column"]
	if (column == "pad") != InputSetup.is_pad_event(ev):
		get_viewport().set_input_as_handled()
		_note.text = "That is a %s input; this column takes %s." % ["gamepad" if InputSetup.is_pad_event(ev) else "keyboard / mouse", "gamepad buttons" if column == "pad" else "keys and mouse buttons"]
		return
	var action: String = _listen["action"]
	var b: Button = _listen["button"]
	_listen = {}
	b.theme_type_variation = ""
	var displaced := InputSetup.rebind(action, ev)
	Audio.play("ui_click")
	_note.text = "%s bound to %s." % [_action_name(action), InputSetup.event_text(ev)]
	if displaced != "":
		_note.text += "  %s lost that binding." % _action_name(displaced)
	_refresh_bindings()
	get_viewport().set_input_as_handled()
	b.grab_focus()


func _action_name(action: String) -> String:
	for e in InputSetup.REMAPPABLE:
		if e[0] == action:
			return e[1]
	return action


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		if not _listen.is_empty():
			_cancel_listen()
		else:
			closed.emit()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		var bi := (event as InputEventJoypadButton).button_index
		if bi == JOY_BUTTON_LEFT_SHOULDER or bi == JOY_BUTTON_RIGHT_SHOULDER:
			show_tab(wrapi(_tab + (1 if bi == JOY_BUTTON_RIGHT_SHOULDER else -1), 0, TABS.size()))
			_tab_btns[_tab].grab_focus()
			get_viewport().set_input_as_handled()


# --- Tabs ------------------------------------------------------------------

## Show one page by index or name ("Controls").
func show_tab(which, sound := true) -> void:
	var i: int = TABS.find(which) if which is String else int(which)
	i = clampi(i, 0, TABS.size() - 1)
	if sound and i != _tab:
		Audio.play("ui_click")
	_cancel_listen()
	_tab = i
	for j in TABS.size():
		UITheme.set_chip(_tab_btns[j], j == i)
		_pages[j].visible = j == i


## Put focus on the active tab chip (menus call this when they open).
func focus_first() -> void:
	_tab_btns[_tab].grab_focus()


# --- Row builders ------------------------------------------------------------

func _row(label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(170, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	_page.add_child(h)
	return h


func _option_row(label: String, options: Array, current: String, on_change: Callable, hint := "") -> void:
	var h := _row(label)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(190, 36)
	for o in options:
		ob.add_item(o)
	ob.selected = maxi(options.find(current), 0)
	ob.item_selected.connect(func(i): on_change.call(options[i]))
	h.add_child(ob)
	if hint != "":
		var s := UITheme.subtle(hint, 12)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_page.add_child(s)


func _toggle_row(label: String, current: bool, on_change: Callable) -> void:
	var h := _row(label)
	var cb := CheckButton.new()
	cb.button_pressed = current
	cb.toggled.connect(func(v):
		Audio.play("ui_toggle")
		on_change.call(v))
	h.add_child(cb)


func _slider_row(label: String, lo: float, hi: float, step: float, current: float, on_change: Callable, fmt := "%s", scale := 1.0) -> void:
	var h := _row(label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = current
	s.custom_minimum_size = Vector2(150, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.focus_ring(s)
	h.add_child(s)
	var v := Label.new()
	v.custom_minimum_size = Vector2(52, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var show := func(x: float): v.text = fmt % (int(round(x * scale)) if fmt.contains("d") else x * scale)
	show.call(current)
	s.value_changed.connect(func(x):
		show.call(x)
		on_change.call(x))
	s.drag_ended.connect(func(_changed): Audio.play("ui_tick"))
	h.add_child(v)
