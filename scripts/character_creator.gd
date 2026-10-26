extends Control
## Character creator: name, class, look, height, and 5 bonus stat points,
## with a live rotating 3D preview on the right.

const STAT_MAX := 10
const CLASS_BLURB := {
	"Swordsman": "Balanced blade work.",
	"Scout": "Fast, nimble, hard to pin.",
	"Guardian": "Takes hits so others don't.",
	"Arcanist": "Spirit-charged Sword Arts.",
}

var _model: Node3D
var _stage: Node3D
var _back_btn: Button
var _body_chips := {}
var _hair_label: Control
var _hair_row: Control
var _points_label: Label
var _stat_labels := {}
var _stat_bars := {}
var _stat_minus := {}
var _stat_plus := {}
var _bonus := {}
var _name_edit: LineEdit
var _name_hint: Label
var _class_chips := {}
var _hair_chips: Array = []
var _swatch_rows := {}  # key -> {"buttons": [[btn, html]...], "picker": ColorPickerButton}
var _height_val: Label
var _preview_name: Label
var _preview_class: Label
## "Edit appearance" for an existing slot (SaveSystem.edit_slot >= 0): name,
## class and stats are locked, only the look changes, and saving returns to
## the title screen instead of entering the world.
var _edit := false
var _edit_slot := -1
## Life: "Standard" or "Permadeath" (Permadeath.slot_kinds decides what the
## slot may be: two standard climbers and one permadeath per account).
var _life_chips := {}
var _life_note: Label
var _life_terms: HBoxContainer
var _life_panel: PanelContainer
var _ring_mat: StandardMaterial3D
var _begin_btn: Button
var _pd_confirm := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.theme()
	for s in GameState.STAT_NAMES:
		_bonus[s] = 0
	_edit_slot = SaveSystem.edit_slot
	_edit = _edit_slot >= 0
	SaveSystem.edit_slot = -1

	var bg := TextureRect.new()
	bg.texture = UITheme.gradient_tex([Color("070b1c"), Color("0b1024"), Color("151c3a")], [0.0, 0.5, 1.0])
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(bg)

	var split := HBoxContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 0)
	add_child(split)

	# ---- Left column: form -------------------------------------------------
	var left := MarginContainer.new()
	left.custom_minimum_size = Vector2(740, 0)
	left.add_theme_constant_override("margin_left", 40)
	left.add_theme_constant_override("margin_right", 24)
	left.add_theme_constant_override("margin_top", 32)
	left.add_theme_constant_override("margin_bottom", 24)
	split.add_child(left)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	left.add_child(col)

	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	head.add_child(UITheme.kicker("Slot %d  ·  %s" % [_edit_slot + 1, GameState.class_title()] if _edit else "New climber"))
	head.add_child(UITheme.heading("Edit appearance" if _edit else "Create your character", 34))
	if _edit:
		head.add_child(UITheme.subtle("Looks only: name, class, level and stats stay as they are.", 14))
	col.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 14)
	scroll.add_child(form)

	# Identity card.
	var ident := UITheme.make_panel(form, "Identity")
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Enter a name"
	_name_edit.max_length = 16
	_name_edit.add_theme_font_size_override("font_size", 19)
	_name_edit.text_changed.connect(func(t):
		GameState.character["name"] = t.strip_edges()
		_name_hint.hide()
		_refresh_preview_caption())
	if _edit:
		_name_edit.text = str(GameState.character["name"])
		_name_edit.editable = false
	ident.add_child(_field("Name", _name_edit))
	_name_hint = UITheme.label("Please enter a name first.", 13, UITheme.ROSE)
	_name_hint.hide()
	ident.add_child(_name_hint)
	ident.add_child(_field_label("Starting class"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for o in GameState.ORIGINS:
		var b := _class_chip(o)
		b.disabled = _edit
		_class_chips[o] = b
		grid.add_child(b)
	ident.add_child(grid)
	_select_class(GameState.character["origin"])

	# Life card: one life or the usual climb (new characters only).
	if not _edit:
		var life := UITheme.make_panel(form, "Life")
		var kinds := SaveSystem.kinds_for(SaveSystem.current_slot)
		var lrow := HBoxContainer.new()
		lrow.add_theme_constant_override("separation", 8)
		for k in [["standard", "Standard", "Fall, wake in town. Some EXP and wear lost."],
				["permadeath", "Permadeath  ·  one life", "Fall once and the climb is over."]]:
			var key: String = k[0]
			var lb := _class_chip_base("%s\n%s" % [k[1], k[2]])
			lb.disabled = not bool(kinds["normal" if key == "standard" else "permadeath"])
			if lb.disabled:
				lb.tooltip_text = "This account's %s slot%s taken" % ["permadeath" if key == "permadeath" else "standard", " is" if key == "permadeath" else "s are"]
			lb.pressed.connect(func(): _select_life(key))
			lrow.add_child(lb)
			_life_chips[key] = lb
		life.add_child(lrow)
		_life_panel = life.get_parent()
		_life_note = UITheme.label("", 13, UITheme.PARCH)
		_life_note.autowrap_mode = TextServer.AUTOWRAP_WORD
		life.add_child(_life_note)
		# Permadeath terms: boosts and penalties side by side.
		_life_terms = HBoxContainer.new()
		_life_terms.add_theme_constant_override("separation", 14)
		for side in [["Boosts", UITheme.GOLD], ["Penalties", UITheme.ROSE]]:
			var tcol := VBoxContainer.new()
			tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tcol.add_theme_constant_override("separation", 3)
			tcol.add_child(UITheme.kicker(side[0], side[1]))
			_life_terms.add_child(tcol)
		life.add_child(_life_terms)
		_select_life("standard" if bool(kinds["normal"]) else "permadeath")

	# Appearance card.
	var look := UITheme.make_panel(form, "Appearance")
	look.add_child(_field_label("Body"))
	var body_row := HFlowContainer.new()
	body_row.add_theme_constant_override("h_separation", 8)
	body_row.add_theme_constant_override("v_separation", 8)
	for entry in [["alicia", "Alicia"], ["godette", "Godette"], ["seed", "Seed"], ["classic", "Classic"]]:
		var bb := UITheme.make_button(entry[1], "chip")
		var key: String = entry[0]
		bb.pressed.connect(func(): _select_body(key))
		body_row.add_child(bb)
		_body_chips[key] = bb
	look.add_child(body_row)
	_hair_label = _field_label("Hair style")
	look.add_child(_hair_label)
	var hair_row := HFlowContainer.new()
	_hair_row = hair_row
	hair_row.add_theme_constant_override("h_separation", 8)
	hair_row.add_theme_constant_override("v_separation", 8)
	for i in CharacterModel.HAIR_STYLES.size():
		var b := UITheme.make_button(CharacterModel.HAIR_STYLES[i], "chip")
		b.pressed.connect(func(): _select_hair(i))
		hair_row.add_child(b)
		_hair_chips.append(b)
	look.add_child(hair_row)
	_select_hair(int(GameState.character["hair_style"]))

	for entry in [["Hair color", "hair_color", UITheme.SWATCHES_HAIR], ["Eye color", "eye_color", UITheme.SWATCHES_EYE],
			["Skin tone", "skin_color", UITheme.SWATCHES_SKIN], ["Outfit color", "outfit_color", UITheme.SWATCHES_OUTFIT]]:
		look.add_child(_field_label(entry[0]))
		look.add_child(_swatch_row(entry[1], entry[2]))

	look.add_child(_field_label("Height"))
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 12)
	var height := HSlider.new()
	height.min_value = 0.85
	height.max_value = 1.15
	height.step = 0.01
	height.value = float(GameState.character.get("height", 1.0))
	height.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	height.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	height.custom_minimum_size = Vector2(0, 22)
	_height_val = UITheme.label("", 15, UITheme.CYAN, true)
	_height_val.custom_minimum_size = Vector2(52, 0)
	_height_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	height.value_changed.connect(func(v):
		_set_look("height", v)
		_height_val.text = "%d%%" % roundi(v * 100.0))
	_height_val.text = "%d%%" % roundi(height.value * 100.0)
	hrow.add_child(height)
	hrow.add_child(_height_val)
	look.add_child(hrow)

	# Stats card (locked in edit mode: points were spent long ago).
	var stats := UITheme.make_panel(form, "Stats")
	stats.get_parent().visible = not _edit
	var prow := HBoxContainer.new()
	prow.add_child(UITheme.subtle("Spend your bonus points. The class sets the base.", 14))
	_points_label = UITheme.label("", 14, UITheme.NAVY, true)
	var badge := PanelContainer.new()
	badge.theme_type_variation = "Pill"
	badge.add_theme_stylebox_override("panel", UITheme.box(UITheme.GOLD, Color(0, 0, 0, 0), 999, 0))
	badge.get_theme_stylebox("panel").content_margin_top = 3
	badge.get_theme_stylebox("panel").content_margin_bottom = 3
	badge.add_child(_points_label)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	prow.add_child(badge)
	stats.add_child(prow)
	for s in GameState.STAT_NAMES:
		stats.add_child(_stat_row(s))

	# Big call to action under the scroll area.
	var begin := UITheme.make_button("Save look" if _edit else "Enter the Spire", "primary")
	_begin_btn = begin
	begin.custom_minimum_size = Vector2(0, 56)
	begin.add_theme_font_size_override("font_size", 21)
	begin.pressed.connect(_begin)
	col.add_child(begin)
	var back := UITheme.make_button("Back to title", "ghost")
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	col.add_child(back)
	_back_btn = back

	# ---- Right column: 3D preview ------------------------------------------
	var right := MarginContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("margin_left", 16)
	right.add_theme_constant_override("margin_right", 40)
	right.add_theme_constant_override("margin_top", 32)
	right.add_theme_constant_override("margin_bottom", 24)
	split.add_child(right)
	var frame := PanelContainer.new()
	frame.theme_type_variation = "CardCyan"
	var fs := UITheme.card_box(UITheme.CYAN, 0.55)
	fs.set_content_margin_all(0)
	frame.add_theme_stylebox_override("panel", fs)
	frame.clip_contents = true
	right.add_child(frame)
	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(stack)
	var backdrop := TextureRect.new()
	backdrop.texture = UITheme.gradient_tex([Color("1b2546"), Color("2b2f6a"), Color("0b1024")], [0.0, 0.55, 1.0])
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stack.add_child(backdrop)
	var glow := TextureRect.new()
	glow.texture = UITheme.radial_dot(Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.35), 64, true)
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_top = -120
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stack.add_child(glow)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var stage := Node3D.new()
	vp.add_child(stage)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.05, 3.4)
	cam.rotation.x = -0.06
	cam.fov = 48
	stage.add_child(cam)
	var key := DirectionalLight3D.new()
	key.light_color = Color("fff1d8")
	key.light_energy = 1.3
	key.rotation = Vector3(-0.7, 0.6, 0)
	stage.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = UITheme.CYAN
	rim.light_energy = 2.5
	rim.omni_range = 6
	rim.position = Vector3(-1.6, 2.2, -1.6)
	stage.add_child(rim)
	var fill := OmniLight3D.new()
	fill.light_color = Color("f0c060")
	fill.light_energy = 0.8
	fill.omni_range = 6
	fill.position = Vector3(1.8, 0.6, 1.4)
	stage.add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.5, 0.7)
	e.ambient_light_energy = 0.9
	env.environment = e
	stage.add_child(env)
	# Floor disc + glowing ring.
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 1.05
	dm.bottom_radius = 1.15
	dm.height = 0.08
	disc.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color("121a33")
	dmat.roughness = 0.35
	dmat.metallic = 0.2
	disc.material_override = dmat
	disc.position.y = -0.04
	stage.add_child(disc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.10
	tm.outer_radius = 1.14
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = UITheme.GOLD
	rmat.emission_enabled = true
	rmat.emission = UITheme.GOLD
	rmat.emission_energy_multiplier = 0.9
	ring.material_override = rmat
	_ring_mat = rmat
	ring.position.y = 0.0
	stage.add_child(ring)
	_stage = stage
	_rebuild_model()
	_select_body(str(GameState.character.get("body", "alicia")), false)

	# Caption over the preview.
	var cap := VBoxContainer.new()
	cap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	cap.offset_left = 28
	cap.offset_top = -92
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(cap)
	cap.add_child(UITheme.kicker("Preview"))
	_preview_name = UITheme.heading("", 30, UITheme.PARCH)
	cap.add_child(_preview_name)
	_preview_class = UITheme.label("", 15, UITheme.CYAN, true)
	cap.add_child(_preview_class)
	var hint := UITheme.subtle("Rotating live preview", 13)
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.offset_left = -240
	hint.offset_right = -24
	hint.offset_top = 20
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(hint)

	_refresh_stats()
	_refresh_preview_caption()
	if not _life_chips.is_empty():
		# Re-apply now the Enter button and pedestal ring exist (--demo-permadeath: shots).
		_select_life("permadeath" if bool(GameState.character.get("permadeath", false)) or "--demo-permadeath" in OS.get_cmdline_user_args() else "standard")
	UITheme.fade_in(col, 0.05)
	UITheme.fade_in(frame, 0.2)
	_name_edit.grab_focus()


func _process(delta: float) -> void:
	if _model:
		_model.rotation.y += delta * 0.6
		if _model is VRMCharacter:
			_model.animate(delta, 0.0, true)


# --- Builders ---------------------------------------------------------------

func _field_label(text: String) -> Label:
	var l := UITheme.label(text.to_upper(), 12, UITheme.MUTED, true)
	l.add_theme_font_override("font", UITheme.spaced(UITheme.ui_bold(), 2))
	return l


func _field(label: String, control: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(_field_label(label))
	v.add_child(control)
	return v


func _class_chip(origin: String) -> Button:
	var b := _class_chip_base("%s\n%s" % [origin, CLASS_BLURB.get(origin, "")])
	var st: Dictionary = GameState.ORIGINS[origin]
	b.tooltip_text = "STR %d  AGI %d  END %d  SPI %d" % [st["strength"], st["agility"], st["endurance"], st["spirit"]]
	b.pressed.connect(func(): _select_class(origin))
	return b


## Two-line option card (class and Life choices).
func _class_chip_base(text: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = "Chip"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 58)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = text
	UITheme.hover_fx(b, 1.02)
	for st_name in ["normal", "hover", "pressed"]:
		var s: StyleBoxFlat = b.get_theme_stylebox(st_name).duplicate()
		s.set_corner_radius_all(10)
		b.add_theme_stylebox_override(st_name, s)
	return b


func _select_class(origin: String) -> void:
	for o in _class_chips:
		var b: Button = _class_chips[o]
		var on: bool = o == origin
		var s: StyleBoxFlat = UITheme.box(Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.16) if on else Color(1, 1, 1, 0.05),
			UITheme.CYAN if on else Color(1, 1, 1, 0.12), 10, 2 if on else 1)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_color_override("font_color", UITheme.PARCH if on else UITheme.MUTED)
	if not _edit:
		GameState.apply_origin(origin)  # resets the base stats; never in edit mode
	if _points_label:
		_refresh_stats()
	_refresh_preview_caption()


func _select_hair(i: int) -> void:
	for j in _hair_chips.size():
		UITheme.set_chip(_hair_chips[j], j == i)
	_set_look("hair_style", i)


func _swatch_row(key: String, presets: Array) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	var buttons := []
	var current: String = GameState.character[key]
	for html in presets:
		var c := Color(html)
		var b := UITheme.swatch(c)
		b.pressed.connect(func(): _pick_color(key, html))
		row.add_child(b)
		buttons.append([b, html])
	# Custom colour: a rainbow-ringed button that opens the ColorPickerButton's popup.
	var picker := ColorPickerButton.new()
	picker.color = Color(current)
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2.ZERO
	picker.visible = false
	picker.color_changed.connect(func(c): _pick_color(key, c.to_html(false)))
	row.add_child(picker)
	var custom := Button.new()
	custom.custom_minimum_size = Vector2(30, 30)
	custom.tooltip_text = "Custom colour"
	UITheme.style_custom_picker(custom)
	custom.pressed.connect(func():
		var pop := picker.get_popup()
		pop.popup(Rect2i(Vector2i(custom.global_position + Vector2(0, custom.size.y + 6)), Vector2i(0, 0))))
	row.add_child(custom)
	_swatch_rows[key] = {"buttons": buttons, "picker": picker}
	_mark_swatches(key, current)
	return row


func _mark_swatches(key: String, html: String) -> void:
	for pair in _swatch_rows[key]["buttons"]:
		UITheme.set_swatch_selected(pair[0], Color(pair[1]), pair[1] == html)
	var picker: ColorPickerButton = _swatch_rows[key]["picker"]
	if picker.color.to_html(false) != html:
		picker.set_block_signals(true)
		picker.color = Color(html)
		picker.set_block_signals(false)


func _pick_color(key: String, html: String) -> void:
	_set_look(key, html)
	_mark_swatches(key, html)


func _stat_row(s: String) -> VBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_l := UITheme.label(s.capitalize(), 16, UITheme.PARCH, true)
	name_l.custom_minimum_size = Vector2(104, 0)
	row.add_child(name_l)
	var bar := ProgressBar.new()
	bar.max_value = STAT_MAX
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("fill", UITheme.gradient_fill_box([UITheme.CYAN, UITheme.GOLD]))
	row.add_child(bar)
	_stat_bars[s] = bar
	var val := UITheme.label("0", 18, UITheme.GOLD, true)
	val.custom_minimum_size = Vector2(36, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	_stat_labels[s] = val
	var minus := UITheme.make_button("-", "round")
	minus.pressed.connect(func(): _adjust(s, -1))
	row.add_child(minus)
	_stat_minus[s] = minus
	var plus := UITheme.make_button("+", "round")
	plus.pressed.connect(func(): _adjust(s, 1))
	row.add_child(plus)
	_stat_plus[s] = plus
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(row)
	box.add_child(UITheme.subtle(GameState.STAT_INFO[s], 12))
	return box


# --- State ------------------------------------------------------------------

func _rebuild_model() -> void:
	var rot := _model.rotation.y if _model else 0.0
	if _model:
		_model.queue_free()
	if VRMCharacter.BODIES.has(str(GameState.character.get("body", ""))):
		_model = VRMCharacter.new()
	else:
		_model = CharacterModel.new()
	_stage.add_child(_model)
	_model.apply(GameState.character)
	_model.rotation.y = rot


func _select_body(key: String, rebuild := true) -> void:
	GameState.character["body"] = key
	for k in _body_chips:
		_body_chips[k].theme_type_variation = &"ChipOn" if k == key else &"Chip"
	# Hair styles only exist on the built-in body; VRM bodies bring their own hair.
	var classic := not VRMCharacter.BODIES.has(key)
	if _hair_label:
		_hair_label.visible = classic
	if _hair_row:
		_hair_row.visible = classic
	if rebuild:
		_rebuild_model()


func _set_look(key: String, value) -> void:
	GameState.character[key] = value
	if _model:
		_model.apply(GameState.character)


func _points_left() -> int:
	var used := 0
	for s in _bonus:
		used += _bonus[s]
	return GameState.CREATOR_POINTS - used


func _adjust(stat: String, d: int) -> void:
	if d > 0 and _points_left() == 0:
		return
	if d < 0 and _bonus[stat] == 0:
		return
	_bonus[stat] += d
	_refresh_stats()


func _refresh_stats() -> void:
	var left := _points_left()
	_points_label.text = "%d point%s left" % [left, "" if left == 1 else "s"]
	for s in GameState.STAT_NAMES:
		var total: int = GameState.stats[s] + _bonus[s]
		_stat_labels[s].text = str(total)
		if _stat_bars.has(s):
			var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(_stat_bars[s], "value", float(total), 0.2)
			_stat_minus[s].disabled = _bonus[s] == 0
			_stat_plus[s].disabled = left == 0


func _refresh_preview_caption() -> void:
	if _preview_name == null:
		return
	var n: String = GameState.character["name"]
	_preview_name.text = (n if n != "" and n != "Nameless" else "Nameless").to_upper()
	_preview_class.text = "%s  ·  Floor %d" % [GameState.class_title() if _edit else GameState.character["origin"], GameState.floor]


## B / Esc: leave the name field, or move focus to "Back to title" (the
## button still has to be pressed, so a creation is never lost by accident).
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	var f := get_viewport().gui_get_focus_owner()
	if f is LineEdit:
		f.release_focus()
	elif _back_btn and f != _back_btn:
		_back_btn.grab_focus()
	get_viewport().set_input_as_handled()


func _select_life(key: String) -> void:
	var pd := key == "permadeath"
	GameState.character["permadeath"] = pd
	_pd_confirm = false
	if _begin_btn:
		_begin_btn.text = "Enter the Spire  ·  one life" if pd else "Enter the Spire"
	var crimson := Color(0.86, 0.18, 0.24)
	for k in _life_chips:
		var b: Button = _life_chips[k]
		var on: bool = k == key
		var tint: Color = crimson if k == "permadeath" else UITheme.CYAN
		b.add_theme_stylebox_override("normal", UITheme.box(Color(tint, 0.16) if on else Color(1, 1, 1, 0.05), tint if on else Color(1, 1, 1, 0.12), 10, 2 if on else 1))
		b.add_theme_color_override("font_color", UITheme.PARCH if on else UITheme.MUTED)
	if _begin_btn and not _edit:
		_begin_btn.theme_type_variation = "DangerButton" if pd else "PrimaryButton"
	if _ring_mat:
		var rc: Color = crimson if pd else UITheme.GOLD
		_ring_mat.albedo_color = rc
		_ring_mat.emission = rc
	if _life_panel:
		var pb := UITheme.card_box(crimson if pd else UITheme.GOLD)
		if pd:
			pb.border_color = Color(crimson, 0.85)
			pb.border_width_top = 3
			pb.shadow_color = Color(crimson, 0.18)
			pb.shadow_size = 14
		_life_panel.add_theme_stylebox_override("panel", pb)
	if _life_note == null:
		return
	var kinds := SaveSystem.kinds_for(SaveSystem.current_slot)
	_life_terms.visible = pd
	if pd:
		_life_note.text = "One life, as in Aincrad. If this climber dies they are gone for good: the name is struck on the Monument of Climbers and the slot becomes a memorial. Leaving mid-fight does not save you: the body stays %d s." % int(Permadeath.LINGER_SECS)
		_life_note.add_theme_color_override("font_color", Color(0.95, 0.82, 0.84))
		_fill_terms(0, ["+%d%% EXP" % int(Permadeath.XP_BONUS * 100), "+%d%% drop chance" % int(Permadeath.DROP_BONUS * 100),
			"+%d%% Last Attack rewards" % int(Permadeath.LA_BONUS * 100), "The Undying title", "Permadeath column on the Monument"])
		_fill_terms(1, ["No revive", "Healing Crystals %dx price, %d s cooldown" % [Permadeath.CRYSTAL_PRICE_MULT, int(Permadeath.HEAL_CRYSTAL_CD)],
			"No Teleport Crystal in combat", "Gear wears %.1fx faster" % Permadeath.WEAR_MULT,
			"Stalls trade only with one-life climbers", "Duels are First Strike only"])
	else:
		_life_note.text = "Death costs some EXP and gear durability, and you return to town. Up to %d standard climbers per account%s." % [
			Permadeath.MAX_NORMAL, "" if bool(kinds["permadeath"]) else "; your permadeath slot is taken"]
		_life_note.add_theme_color_override("font_color", UITheme.PARCH)


## Bulleted lines under the Boosts (0) or Penalties (1) heading.
func _fill_terms(which: int, lines: Array) -> void:
	var col: VBoxContainer = _life_terms.get_child(which)
	for i in range(col.get_child_count() - 1, 0, -1):
		col.get_child(i).queue_free()
	var c: Color = UITheme.GOLD if which == 0 else UITheme.ROSE
	for t in lines:
		var l := UITheme.label("•  " + str(t), 13, c.lerp(UITheme.PARCH, 0.35))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		col.add_child(l)


func _begin() -> void:
	if _edit:
		SaveSystem.save_game(_edit_slot)
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	if GameState.character["name"] == "" or GameState.character["name"] == "Nameless":
		_name_edit.placeholder_text = "Please enter a name first"
		_name_hint.show()
		_name_edit.grab_focus()
		return
	if Permadeath.is_on(GameState) and not _pd_confirm:
		_pd_confirm = true
		_begin_btn.text = "Begin with one life?"
		Audio.play("ui_error")
		return
	for s in _bonus:
		GameState.stats[s] += _bonus[s]
	GameState.heal_full()
	SaveSystem.save_game()  # the slot new_game() picked
	LoadingScreen.open(GameState.floor)
	get_tree().change_scene_to_file("res://scenes/world.tscn")
