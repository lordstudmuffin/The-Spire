class_name HUD
extends CanvasLayer

signal menus_closed
signal chat_open_changed(open: bool)

## Set by the world: called with the text to send to everyone.
var send_chat: Callable
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _chat_panel: PanelContainer
## Health/XP bars, level, money, tracked quest, minimap, boss bar, pickup
## feed, dialogue box, pause menu, toasts and the three screens (Inventory,
## Quest Log, Map). Built in code with UITheme; screens live in scripts/ui.

var _hp_bar: ProgressBar
var _hp_chip: ProgressBar
var _guard_bar: ProgressBar
var _hp_fills: Array = []
var _hp_band := 0
var _chip_tw: Tween
var _xp_bar: ProgressBar
var _hp_text: Label
var _xp_text: Label
var _info: Label
var _class_label: Label
var _level_label: Label
var _col_label: Label
var _floor_label: Label
var _quest_card: PanelContainer
var _quest_title: Label
var _quest_obj: Label
var _quest_bar: ProgressBar
var _quest_prog: Label
var _quest_more: Label
var _dialogue: PanelContainer
var _dialogue_text: Label
var _dialogue_speaker: Label
var _toast: Label
var _toast_kicker: Label
var _toast_sub: Label
var _toast_card: PanelContainer
var _pause_panel: PanelContainer
var _prompt: Label
var _prompt_card: PanelContainer
var _craft_panel: PanelContainer
var _skill_bar: HBoxContainer
var _skill_buttons: Array = []
var _skill_slots: Array = []  # [{"sweep": RadialSweep, "cd": Label, "name": Label, "card": PanelContainer}]
var _dash_slot := {}
var _craft_box: VBoxContainer
var _root: Control
## Life layer widgets (buffs, fishing minigame, cooking/shop/storage screens).
var life: LifeHUD
## Damage vignette (shaders/hit_vignette.gdshader): flashes when hp drops,
## pulses faintly below 25 % hp. Cosmetic only.
var _vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _vignette_tw: Tween
var _vignette_flash := 0.0
var _last_hp := -1.0

## Screens (built once, shown/hidden).
var _inv_panel: PanelContainer
var _inventory: InventoryScreen
var _quest_panel: PanelContainer
var _quest_log: QuestLog
var _map_panel: PanelContainer
var _map: Minimap
## Party frames (scripts/ui/party_panel.gd) under the player card and the
## Nearby / social panel (scripts/ui/social.gd, key O).
var _plate_card: PanelContainer
## What the player sees top left (scripts/ui/player_status.gd). The old card
## above is kept hidden: its labels and bars still hold the values.
var _status: PlayerStatus
var _party_panel: PartyPanel
var _nearby_panel: PanelContainer
var _social: Social
var _map_legend: Array = []  # [{"dist": Label, "pos": Vector2}]
var _map_place: Label
var _map_title: Label
var _minimap: Minimap
var _place_l: Label
var _place_t := 0.0
var tracked_quest := ""
var _last_quests := {}  # id -> done, for accept/complete toasts
var _last_mats := {}
var _last_inv := 0
var _suppress_feed := false

## Boss bar.
var _boss_card: PanelContainer
var _boss_name: Label
var _boss_lv: Label
var _boss_bar: ProgressBar
var _boss_hp: Label
var _boss: Node3D
var _boss_poll := 0.0
var _boss_tw: Tween

## Pickup feed and level-up banner.
var _feed: VBoxContainer
var _feed_pool: Array = []  # [{"node": PanelContainer, "label": Label, "glyph": UIGlyph, "tw": Tween}]
var _banner: Control
var _banner_lv: Label
var _banner_sub: Label
var _banner_rule_l: Control
var _banner_rule_r: Control
var _banner_tw: Tween


## Pie-shaped cooldown mask that sweeps clockwise from 12 o'clock.
class RadialSweep extends Control:
	var frac := 0.0
	var _pts := PackedVector2Array()
	const N := 36

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pts.resize(N + 2)

	func set_frac(f: float) -> void:
		if absf(f - frac) < 0.003 and not (f == 0.0 and frac != 0.0):
			return
		frac = f
		queue_redraw()

	func _draw() -> void:
		if frac <= 0.0:
			return
		var c := size * 0.5
		var r := size.length() * 0.75
		var sweep := TAU * clampf(frac, 0.0, 1.0)
		_pts[0] = c
		for i in N + 1:
			var a := -PI / 2 + sweep * float(i) / N
			_pts[i + 1] = c + Vector2(cos(a), sin(a)) * r
		draw_colored_polygon(_pts, Color(0.02, 0.03, 0.08, 0.74))
		# Leading edge so the sweep reads as motion.
		var a := -PI / 2 + sweep
		draw_line(c, c + Vector2(cos(a), sin(a)) * r, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.9), 2.0, true)


func _ready() -> void:
	var root := Control.new()
	_root = root
	add_to_group("hud")
	root.theme = UITheme.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_vignette(root)
	_build_player_plate(root)
	_build_minimap(root)
	_build_quest_tracker(root)
	_build_boss_bar(root)
	_build_prompt(root)
	_build_toast(root)
	_build_skill_bar(root)
	_build_hints(root)
	_build_feed(root)
	_build_chat(root)
	_build_dialogue(root)
	_build_level_banner(root)
	_build_party(root)

	_craft_panel = _modal(root, 640)
	_craft_box = _modal_box(_craft_panel)
	_build_screens(root)
	_build_pause(root)
	_ring = RingMenu.build(self)
	root.add_child(_ring)
	life = LifeHUD.attach(self, root)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var on_joy := func(id: int, connected: bool):
		toast("Controller %s" % ("connected" if connected else "disconnected"), Input.get_joy_name(id) if connected else "", "Input", UITheme.CYAN)
	Input.joy_connection_changed.connect(on_joy)
	tree_exiting.connect(func(): Input.joy_connection_changed.disconnect(on_joy))

	_snapshot_quests()
	_snapshot_inventory()
	GameState.health_changed.connect(func(_a, _b): _refresh())
	GameState.health_changed.connect(_on_health_for_vignette)
	_last_hp = GameState.hp
	GameState.xp_changed.connect(func(_a, _b): _refresh())
	GameState.money_changed.connect(func(_a): _refresh())
	GameState.stats_changed.connect(_refresh)
	GameState.quest_changed.connect(_on_quest_changed)
	GameState.inventory_changed.connect(_on_inventory_changed)
	GameState.class_unlocked.connect(func(c): toast("%s" % c, "Hidden class unlocked", "Class"))
	GameState.leveled_up.connect(_on_level_up)
	GameState.unique_skill_changed.connect(func(id):
		if id != "":
			toast(UniqueSkills.display_name(id), "Unique skill awakened  ·  Sword Arts on 4, 5, 6", "Only you hold this", UITheme.GOLD))
	SaveSystem.saved.connect(func(_s): toast("Game saved"))
	Net.chat_received.connect(add_chat)
	_refresh()


# --- Builders -----------------------------------------------------------------

func _build_player_plate(root: Control) -> void:
	var card := PanelContainer.new()
	card.position = Vector2(24, 24)
	var sb := UITheme.card_box(UITheme.GOLD, 0.72)
	sb.set_content_margin_all(14)
	sb.content_margin_right = 20
	card.add_theme_stylebox_override("panel", sb)
	root.add_child(card)
	_plate_card = card
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	card.add_child(h)

	# Level badge: gold disc with the level number.
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(64, 64)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.ring(badge, UITheme.NAVY2, UITheme.GOLD, 3.0)
	var lv_v := VBoxContainer.new()
	lv_v.set_anchors_preset(Control.PRESET_FULL_RECT)
	lv_v.alignment = BoxContainer.ALIGNMENT_CENTER
	lv_v.add_theme_constant_override("separation", -6)
	badge.add_child(lv_v)
	var lv_k := UITheme.label("LV", 10, UITheme.GOLD, true)
	lv_k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_v.add_child(lv_k)
	_level_label = Label.new()
	_level_label.theme_type_variation = "Heading"
	_level_label.add_theme_font_size_override("font_size", 26)
	_level_label.add_theme_color_override("font_color", UITheme.PARCH)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_v.add_child(_level_label)
	h.add_child(badge)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	h.add_child(v)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	_info = Label.new()
	_info.theme_type_variation = "Heading"
	_info.add_theme_font_size_override("font_size", 22)
	_info.add_theme_color_override("font_color", UITheme.PARCH)
	name_row.add_child(_info)
	_class_label = UITheme.label("", 13, UITheme.CYAN, true)
	_class_label.size_flags_vertical = Control.SIZE_SHRINK_END
	name_row.add_child(_class_label)
	v.add_child(name_row)

	# HP bar with gradient fill and numeric overlay.
	var hp_wrap := Control.new()
	hp_wrap.custom_minimum_size = Vector2(320, 22)
	# Delayed "chip" bar: on a hit the lost chunk stays pale for a moment,
	# then drains, so big hits read at a glance.
	_hp_chip = ProgressBar.new()
	_hp_chip.show_percentage = false
	_hp_chip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_chip.add_theme_stylebox_override("fill", UITheme.gradient_fill_box([Color(1, 1, 1, 0.85), Color(1, 0.92, 0.85, 0.85)]))
	hp_wrap.add_child(_hp_chip)
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	_hp_fills = [
		UITheme.gradient_fill_box([Color("3f9c2f"), Color("6fd34a"), Color("a8f07a")]),
		UITheme.gradient_fill_box([Color("b88a12"), Color("f2c230"), Color("ffe27a")]),
		UITheme.gradient_fill_box([Color("a3161c"), Color("e6392f"), Color("ff7a6b")]),
	]
	_hp_bar.add_theme_stylebox_override("fill", _hp_fills[0])
	hp_wrap.add_child(_hp_bar)
	_hp_text = UITheme.label("", 12, UITheme.PARCH, true)
	_hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_hp_text.add_theme_constant_override("outline_size", 4)
	hp_wrap.add_child(_hp_text)
	v.add_child(hp_wrap)
	# Guard bar (parry/guard): only shown while guarding or recovering.
	_guard_bar = ProgressBar.new()
	_guard_bar.show_percentage = false
	_guard_bar.custom_minimum_size = Vector2(320, 5)
	_guard_bar.max_value = Player.GUARD_MAX
	UITheme.style_guard_bar(_guard_bar)
	_guard_bar.visible = false
	v.add_child(_guard_bar)
	# Thin XP bar.
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 8)
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(0, 7)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var xbg: StyleBoxFlat = UITheme.box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.08), 4)
	xbg.set_content_margin_all(0)
	_xp_bar.add_theme_stylebox_override("background", xbg)
	_xp_bar.add_theme_stylebox_override("fill", UITheme.gradient_fill_box([Color("2d8fd5"), UITheme.CYAN]))
	xp_row.add_child(_xp_bar)
	_xp_text = UITheme.label("", 11, UITheme.MUTED, true)
	xp_row.add_child(_xp_text)
	v.add_child(xp_row)

	# Col + floor pills.
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 8)
	_col_label = UITheme.label("", 12, UITheme.GOLD, true)
	pills.add_child(_pill(_col_label, UITheme.GOLD))
	_floor_label = UITheme.label("", 12, UITheme.CYAN, true)
	pills.add_child(_pill(_floor_label, UITheme.CYAN))
	v.add_child(pills)
	_status = PlayerStatus.new()
	_status.position = Vector2(24, 18)
	root.add_child(_status)
	card.visible = false


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


const MINIMAP_PX := 176


func _build_minimap(root: Control) -> void:
	_minimap = Minimap.new()
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.offset_left = -24 - MINIMAP_PX
	_minimap.offset_right = -24
	_minimap.offset_top = 24
	_minimap.offset_bottom = 24 + MINIMAP_PX
	root.add_child(_minimap)
	# Place name under the disc.
	_place_l = UITheme.label("", 12, UITheme.PARCH, true)
	_place_l.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_place_l.offset_left = -24 - MINIMAP_PX - 40
	_place_l.offset_right = -24 + 40
	_place_l.offset_top = 24 + MINIMAP_PX + 4
	_place_l.offset_bottom = 24 + MINIMAP_PX + 26
	_place_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_place_l.add_theme_constant_override("outline_size", 5)
	_place_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_place_l)


func _build_quest_tracker(root: Control) -> void:
	_quest_card = PanelContainer.new()
	_quest_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_quest_card.offset_left = -24 - 300
	_quest_card.offset_right = -24
	_quest_card.offset_top = 24 + MINIMAP_PX + 30
	_quest_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var sb := UITheme.card_box(UITheme.CYAN, 0.6)
	sb.set_content_margin_all(12)
	sb.content_margin_left = 16
	sb.border_width_left = 3
	_quest_card.add_theme_stylebox_override("panel", sb)
	_quest_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_quest_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_quest_card.add_child(v)
	var kr := HBoxContainer.new()
	var k := UITheme.kicker("Tracked quest")
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kr.add_child(k)
	var cap := UITheme.action_cap("quest_log")
	cap.modulate.a = 0.7
	kr.add_child(cap)
	v.add_child(kr)
	_quest_title = UITheme.heading("", 16, UITheme.PARCH)
	_quest_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_quest_title)
	_quest_obj = UITheme.label("", 13, UITheme.MUTED)
	_quest_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_quest_obj)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 8)
	_quest_bar = ProgressBar.new()
	_quest_bar.show_percentage = false
	_quest_bar.custom_minimum_size = Vector2(0, 8)
	_quest_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_quest_bar.add_theme_stylebox_override("fill", UITheme.gradient_fill_box([Color("2d8fd5"), UITheme.CYAN]))
	br.add_child(_quest_bar)
	_quest_prog = UITheme.label("", 12, UITheme.CYAN, true)
	br.add_child(_quest_prog)
	v.add_child(br)
	_quest_more = UITheme.subtle("", 11)
	v.add_child(_quest_more)
	_quest_card.hide()


func _build_boss_bar(root: Control) -> void:
	_boss_card = PanelContainer.new()
	_boss_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	# 520 wide: clears the player status gauge at the top left.
	_boss_card.offset_left = -260
	_boss_card.offset_right = 260
	_boss_card.offset_top = 22
	_boss_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var sb := UITheme.box(Color(UITheme.NAVY.r, UITheme.NAVY.g, UITheme.NAVY.b, 0.78), Color(UITheme.ROSE.r, UITheme.ROSE.g, UITheme.ROSE.b, 0.6), 12, 1, 12)
	sb.set_content_margin_all(10)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	_boss_card.add_theme_stylebox_override("panel", sb)
	_boss_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_boss_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_boss_card.add_child(v)
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 10)
	var sk := UIGlyph.make("skull", UITheme.ROSE, 22)
	sk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nr.add_child(sk)
	var kk := UITheme.kicker("Floor Guardian", UITheme.ROSE)
	kk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nr.add_child(kk)
	_boss_name = UITheme.heading("", 20, UITheme.PARCH)
	_boss_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nr.add_child(_boss_name)
	_boss_lv = UITheme.label("", 12, UITheme.MUTED, true)
	_boss_lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nr.add_child(_boss_lv)
	v.add_child(nr)
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 18)
	_boss_bar = ProgressBar.new()
	_boss_bar.show_percentage = false
	_boss_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_boss_bar.add_theme_stylebox_override("fill", UITheme.gradient_fill_box([Color("7a0f2e"), UITheme.ROSE, Color("ff8fa3")]))
	wrap.add_child(_boss_bar)
	_boss_hp = UITheme.label("", 11, UITheme.PARCH, true)
	_boss_hp.set_anchors_preset(Control.PRESET_FULL_RECT)
	_boss_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boss_hp.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_boss_hp.add_theme_constant_override("outline_size", 4)
	wrap.add_child(_boss_hp)
	v.add_child(wrap)
	_boss_card.modulate.a = 0.0
	_boss_card.hide()


func _build_prompt(root: Control) -> void:
	_prompt_card = PanelContainer.new()
	_prompt_card.theme_type_variation = "Pill"
	_prompt_card.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_card.position.y += 70
	root.add_child(_prompt_card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_prompt_card.add_child(h)
	h.add_child(UITheme.action_cap("interact"))
	_prompt = UITheme.label("", 16, UITheme.PARCH, true)
	h.add_child(_prompt)
	_prompt_card.hide()
	_prompt_card.resized.connect(func(): _prompt_card.position = Vector2(root.size.x * 0.5 - _prompt_card.size.x * 0.5, root.size.y * 0.5 + 70))


func _build_toast(root: Control) -> void:
	_toast_card = PanelContainer.new()
	_toast_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	var sb := UITheme.box(Color(UITheme.NAVY.r, UITheme.NAVY.g, UITheme.NAVY.b, 0.78), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.7), 12, 1, 10)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_toast_card.add_theme_stylebox_override("panel", sb)
	_toast_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_toast_card.add_child(v)
	_toast_kicker = UITheme.kicker("", UITheme.GOLD)
	_toast_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_kicker.hide()
	v.add_child(_toast_kicker)
	_toast = Label.new()
	_toast.theme_type_variation = "Heading"
	_toast.add_theme_font_size_override("font_size", 24)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_toast)
	v.add_child(UITheme.rule())
	_toast_sub = UITheme.label("", 13, UITheme.MUTED, true)
	_toast_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_sub.hide()
	v.add_child(_toast_sub)
	_toast_card.modulate.a = 0.0
	_toast_card.resized.connect(func(): _toast_card.position = Vector2(root.size.x * 0.5 - _toast_card.size.x * 0.5, 120))


func _slot_card(key: String, name_text: String) -> Dictionary:
	var slot := PanelContainer.new()
	slot.theme_type_variation = "Slot"
	slot.custom_minimum_size = Vector2(84, 84)
	slot.clip_contents = true
	_skill_bar.add_child(slot)
	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.add_child(stack)
	# Faint inner gradient.
	var sheen := TextureRect.new()
	sheen.texture = UITheme.gradient_tex([Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.0)], [0.0, 1.0])
	sheen.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheen.stretch_mode = TextureRect.STRETCH_SCALE
	sheen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stack.add_child(sheen)
	# Radial cooldown sweep.
	var sweep := RadialSweep.new()
	sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(sweep)
	# Key badge.
	var kc := UITheme.action_cap(key)
	kc.position = Vector2(6, 6)
	stack.add_child(kc)
	# Name at the bottom.
	var name_l := UITheme.label(name_text, 11, UITheme.PARCH, true)
	name_l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_l.offset_top = -22
	name_l.offset_bottom = -6
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack.add_child(name_l)
	# Cooldown seconds, centred.
	var cd := Label.new()
	cd.theme_type_variation = "Heading"
	cd.add_theme_font_size_override("font_size", 22)
	cd.add_theme_color_override("font_color", UITheme.PARCH)
	cd.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd.offset_top = 4
	stack.add_child(cd)
	return {"sweep": sweep, "cd": cd, "name": name_l, "card": slot, "stack": stack}


var _unique_slots: Array = []
var _unique_spacer: Control
var _class_slots: Array = []
var _class_spacer: Control


## Hidden-class arts (R / C, or LT+X / LT+B): shown once a class with arts
## is held (Stillblade, Hearthwright), bordered in the class's colour.
func _update_class_slots(_cls := "") -> void:
	var cls: String = GameState.hidden_class
	var arts := HiddenClasses.arts_of(cls)
	_class_spacer.visible = not arts.is_empty()
	var tint: Color = Color(0.62, 0.92, 1.0) if cls == "Stillblade" else Color(1.0, 0.62, 0.22)
	for i in _class_slots.size():
		var on := i < arts.size()
		var cs: Dictionary = _class_slots[i]
		(cs["card"] as Control).visible = on
		if on:
			(cs["name"] as Label).text = arts[i]["name"]
			var sb: StyleBoxFlat = (cs["card"] as PanelContainer).get_theme_stylebox("panel").duplicate()
			sb.border_color = Color(tint, 0.8)
			(cs["card"] as PanelContainer).add_theme_stylebox_override("panel", sb)


func _update_unique_slots(id: String) -> void:
	var arts := UniqueSkills.arts(id)
	_unique_spacer.visible = not arts.is_empty()
	for i in _unique_slots.size():
		var on := i < arts.size()
		(_unique_slots[i]["card"] as Control).visible = on
		if on:
			(_unique_slots[i]["name"] as Label).text = arts[i]["name"]


func _build_skill_bar(root: Control) -> void:
	_skill_bar = HBoxContainer.new()
	_skill_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_skill_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_skill_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skill_bar.offset_bottom = -24
	_skill_bar.add_theme_constant_override("separation", 10)
	_skill_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_skill_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_skill_bar)

	# Basic attack hint.
	var atk := PanelContainer.new()
	atk.theme_type_variation = "Slot"
	var asb: StyleBoxFlat = UITheme.box(Color(UITheme.NAVY.r, UITheme.NAVY.g, UITheme.NAVY.b, 0.7), Color(1, 1, 1, 0.12), 12, 1)
	asb.set_content_margin_all(10)
	atk.add_theme_stylebox_override("panel", asb)
	atk.size_flags_vertical = Control.SIZE_SHRINK_END
	var av := VBoxContainer.new()
	av.alignment = BoxContainer.ALIGNMENT_CENTER
	av.add_theme_constant_override("separation", 4)
	var kc := UITheme.action_cap("attack")
	kc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	av.add_child(kc)
	var al := UITheme.label("Attack", 11, UITheme.MUTED, true)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.add_child(al)
	atk.add_child(av)
	_skill_bar.add_child(atk)
	# Dash (Q) with its own short cooldown.
	_dash_slot = _slot_card("dash", "Dash")
	(_dash_slot["card"] as Control).custom_minimum_size = Vector2(64, 84)
	var dsb: StyleBoxFlat = (_dash_slot["card"] as PanelContainer).get_theme_stylebox("panel").duplicate()
	dsb.border_color = Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.5)
	(_dash_slot["card"] as PanelContainer).add_theme_stylebox_override("panel", dsb)
	_skill_bar.add_child(UITheme.spacer(6))

	for i in Player.SKILLS.size():
		var slot := _slot_card("skill_%d" % (i + 1), Player.SKILLS[i]["name"])
		# Invisible Button kept for API/testing parity with the old bar.
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.modulate.a = 0.0
		(slot["stack"] as Control).add_child(b)
		# Locked until One-Handed Sword proficiency reaches the art's "prof".
		var lock := UITheme.LockOverlay.new()
		(slot["stack"] as Control).add_child(lock)
		(slot["stack"] as Control).move_child(lock, 2)  # under the key badge and name
		slot["lock"] = lock
		_skill_buttons.append(b)
		_skill_slots.append(slot)
	# Unique skill arts (keys 4-6): only shown while the realm lists you as
	# the holder (GameState.unique_skill).
	_unique_spacer = UITheme.spacer(6)
	_skill_bar.add_child(_unique_spacer)
	var arts := UniqueSkills.arts(UniqueSkills.TWIN_FANG)
	for i in arts.size():
		var us := _slot_card("skill_%d" % (i + 4), arts[i]["name"])
		var usb: StyleBoxFlat = (us["card"] as PanelContainer).get_theme_stylebox("panel").duplicate()
		usb.border_color = Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.75)
		(us["card"] as PanelContainer).add_theme_stylebox_override("panel", usb)
		_unique_slots.append(us)
	_update_unique_slots(GameState.unique_skill)
	GameState.unique_skill_changed.connect(_update_unique_slots)
	_class_spacer = UITheme.spacer(6)
	_skill_bar.add_child(_class_spacer)
	for i in 2:
		_class_slots.append(_slot_card("class_%d" % (i + 1), "Class Art"))
	_update_class_slots()
	GameState.class_unlocked.connect(_update_class_slots)


## Bottom-right key hints: the screens and their keys.
func _build_hints(root: Control) -> void:
	# A right-aligned column in the bottom-right corner: stays clear of the
	# skill bar however wide it grows (unique arts, long pad prompts).
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_right = -24
	col.offset_bottom = -24
	col.add_theme_constant_override("separation", 5)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.modulate.a = 0.85
	root.add_child(col)
	for pair in KEY_HINTS:
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_END
		h.add_theme_constant_override("separation", 8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(h)
		var l := UITheme.label(pair[1], 12, Color(0.92, 0.94, 1.0), true)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		l.add_theme_constant_override("outline_size", 4)
		h.add_child(l)
		h.add_child(UITheme.action_cap(pair[0]))


## Hint actions (InputMap names; the caps follow the device and remaps).
const KEY_HINTS := [["inventory", "Inventory"], ["quest_log", "Quests"], ["map", "Map"], ["chat", "Chat"], ["pause", "Menu"]]


## Bottom-left list of things you just picked up; entries slide in and fade.
func _build_feed(root: Control) -> void:
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_feed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_feed.offset_left = 24
	_feed.offset_right = 24 + 280
	_feed.offset_bottom = -250
	_feed.offset_top = -250 - 260
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.add_theme_constant_override("separation", 6)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)
	for i in 6:
		var p := PanelContainer.new()
		var sb := UITheme.box(Color(UITheme.NAVY.r, UITheme.NAVY.g, UITheme.NAVY.b, 0.7), Color(1, 1, 1, 0.1), 10, 1)
		sb.content_margin_left = 8
		sb.content_margin_right = 14
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var g := UIGlyph.make("ore", UITheme.MUTED, 24)
		h.add_child(g)
		var l := UITheme.label("", 13, UITheme.PARCH, true)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
		p.add_child(h)
		p.hide()
		_feed.add_child(p)
		_feed_pool.append({"node": p, "label": l, "glyph": g, "tw": null, "sb": sb})


const FEED_GLYPHS := {"iron_ore": ["ore", Color("b8bcc8")], "beast_hide": ["hide", Color("c98a3a")], "spirit_shard": ["shard", Color("4cc9f0")],
	"wisp_essence": ["shard", Color("5ee0b0")], "stag_horn": ["horn", Color("e8a432")]}


## Feed glyph for the life-layer stackables (fish, herbs, food, the rod).
func _life_glyph(m: String) -> Array:
	if LifeData.is_fish(m):
		return ["fish", LifeData.item_color(m)]
	if LifeData.is_food(m):
		return ["food", LifeData.item_color(m)]
	if LifeData.GATHER.has(m):
		return ["herb", LifeData.item_color(m)]
	if LifeData.TOOLS.has(m):
		return ["rod", LifeData.item_color(m)]
	return ["star", UITheme.GOLD]


func feed(text: String, glyph := "star", color := UITheme.GOLD) -> void:
	# Oldest (or hidden) entry is recycled and moved to the bottom.
	var e: Dictionary = _feed_pool[0]
	for cand in _feed_pool:
		if not cand["node"].visible:
			e = cand
			break
	_feed_pool.erase(e)
	_feed_pool.append(e)
	var node: PanelContainer = e["node"]
	_feed.move_child(node, _feed.get_child_count() - 1)
	(e["label"] as Label).text = text
	(e["glyph"] as UIGlyph).set_glyph(glyph, color)
	(e["sb"] as StyleBoxFlat).border_color = Color(color.r, color.g, color.b, 0.45)
	if e["tw"] != null and (e["tw"] as Tween).is_valid():
		(e["tw"] as Tween).kill()
	node.show()
	node.modulate.a = 0.0
	node.pivot_offset = Vector2(0, node.size.y * 0.5)
	node.scale = Vector2(0.9, 0.9)
	var tw := create_tween()
	e["tw"] = tw
	tw.set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, 0.2)
	tw.tween_property(node, "scale", Vector2.ONE, 0.25)
	tw.set_parallel(false)
	tw.tween_interval(3.2)
	tw.tween_property(node, "modulate:a", 0.0, 0.7)
	tw.tween_callback(node.hide)


func _build_level_banner(root: Control) -> void:
	_banner = Control.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -360
	_banner.offset_right = 360
	_banner.offset_top = 200
	_banner.offset_bottom = 380
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.pivot_offset = Vector2(360, 90)
	_banner.hide()
	root.add_child(_banner)
	var glow := TextureRect.new()
	glow.texture = UITheme.radial_dot(Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.35), 256, true)
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(glow)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(v)
	var k := UITheme.kicker("The Spire acknowledges you", UITheme.CYAN)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08, 0.9))
	k.add_theme_constant_override("outline_size", 6)
	v.add_child(k)
	var t := Label.new()
	t.theme_type_variation = "Heading"
	t.text = "LEVEL UP"
	t.add_theme_font_size_override("font_size", 58)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08, 0.9))
	t.add_theme_constant_override("outline_size", 10)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	t.add_theme_constant_override("shadow_offset_y", 4)
	v.add_child(t)
	var rules := HBoxContainer.new()
	rules.alignment = BoxContainer.ALIGNMENT_CENTER
	rules.add_theme_constant_override("separation", 14)
	_banner_rule_l = UITheme.rule()
	_banner_rule_l.flip_h = true
	_banner_rule_l.custom_minimum_size = Vector2(200, 2)
	_banner_rule_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rules.add_child(_banner_rule_l)
	_banner_lv = UITheme.label("", 18, UITheme.PARCH, true)
	_banner_lv.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_banner_lv.add_theme_constant_override("outline_size", 6)
	rules.add_child(_banner_lv)
	_banner_rule_r = UITheme.rule()
	_banner_rule_r.custom_minimum_size = Vector2(200, 2)
	_banner_rule_r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rules.add_child(_banner_rule_r)
	v.add_child(rules)
	_banner_sub = UITheme.label("", 14, UITheme.MUTED, true)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_banner_sub.add_theme_constant_override("outline_size", 5)
	v.add_child(_banner_sub)


func _on_level_up(level: int) -> void:
	_banner_lv.text = "LEVEL %d" % level
	_banner_sub.text = "+%d stat points  ·  open Inventory (I) to spend them" % GameState.POINTS_PER_LEVEL
	if _banner_tw and _banner_tw.is_valid():
		_banner_tw.kill()
	_banner.show()
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(0.7, 0.7)
	_banner_rule_l.custom_minimum_size.x = 0
	_banner_rule_r.custom_minimum_size.x = 0
	var tw := create_tween()
	_banner_tw = tw
	tw.set_parallel(true)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.25)
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_banner_rule_l, "custom_minimum_size:x", 200.0, 0.7).set_delay(0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_banner_rule_r, "custom_minimum_size:x", 200.0, 0.7).set_delay(0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(2.4)
	tw.set_parallel(true)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6)
	tw.tween_property(_banner, "scale", Vector2(1.06, 1.06), 0.6)
	tw.set_parallel(false)
	tw.tween_callback(_banner.hide)
	Audio.play("craft_success")


## Party frames sit under the player card and follow its height.
func _build_party(root: Control) -> void:
	_party_panel = PartyPanel.build()
	root.add_child(_party_panel)
	var place := func():
		_party_panel.position = Vector2(24, _status.position.y + _status.custom_minimum_size.y + 6)
	_plate_card.resized.connect(place)
	place.call()


func _build_chat(root: Control) -> void:
	_chat_panel = PanelContainer.new()
	_chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chat_panel.offset_left = 24
	_chat_panel.offset_right = 24 + 440
	_chat_panel.offset_bottom = -24
	_chat_panel.offset_top = -24
	var sb := UITheme.box(Color(UITheme.NAVY.r, UITheme.NAVY.g, UITheme.NAVY.b, 0.72), Color(1, 1, 1, 0.08), 12, 1)
	sb.set_content_margin_all(12)
	_chat_panel.add_theme_stylebox_override("panel", sb)
	_chat_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_chat_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_chat_panel.add_child(v)
	# BBCode so each channel has its colour and names are clickable (invite).
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.fit_content = true
	_chat_log.scroll_active = false
	_chat_log.autowrap_mode = TextServer.AUTOWRAP_WORD
	_chat_log.add_theme_font_size_override("normal_font_size", 14)
	_chat_log.add_theme_font_size_override("bold_font_size", 14)
	_chat_log.add_theme_font_override("bold_font", UITheme.ui_bold())
	_chat_log.add_theme_color_override("default_color", Color(UITheme.PARCH.r, UITheme.PARCH.g, UITheme.PARCH.b, 0.9))
	_chat_log.mouse_filter = Control.MOUSE_FILTER_STOP
	_chat_log.meta_underlined = false
	_chat_log.meta_clicked.connect(func(meta):
		var who := str(meta)
		if who != "" and who.to_lower() != Net.my_name().to_lower():
			Net.request_invite(who))
	v.add_child(_chat_log)
	_chat_input = LineEdit.new()
	_chat_input.custom_minimum_size = Vector2(0, 34)
	_chat_input.placeholder_text = "Say something...  (Enter to send, Esc to close)"
	_chat_input.max_length = 200
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_chat_input.hide()
	v.add_child(_chat_input)
	_chat_panel.hide()


func _build_dialogue(root: Control) -> void:
	_dialogue = PanelContainer.new()
	_dialogue.custom_minimum_size = Vector2(840, 0)
	var place_card := func():
		_dialogue.position = Vector2(root.size.x * 0.5 - _dialogue.size.x * 0.5, root.size.y - 136 - _dialogue.size.y)
	_dialogue.resized.connect(place_card)
	root.resized.connect(place_card)
	var sb := UITheme.card_box(UITheme.GOLD, 0.88)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 28
	sb.content_margin_bottom = 18
	_dialogue.add_theme_stylebox_override("panel", sb)
	root.add_child(_dialogue)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_dialogue.add_child(v)
	_dialogue_text = Label.new()
	_dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_dialogue_text.add_theme_font_size_override("font_size", 19)
	_dialogue_text.custom_minimum_size = Vector2(792, 64)
	_dialogue_text.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(_dialogue_text)
	var hint := UITheme.subtle("E  ·  continue", 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(hint)
	# Speaker name tab sitting on the top edge (sibling of the card so the
	# container does not stretch it).
	var tab := PanelContainer.new()
	var tsb := UITheme.box(UITheme.GOLD, Color(0, 0, 0, 0), 8, 0)
	tsb.content_margin_left = 16
	tsb.content_margin_right = 16
	tsb.content_margin_top = 4
	tsb.content_margin_bottom = 4
	tab.add_theme_stylebox_override("panel", tsb)
	_dialogue_speaker = UITheme.label("", 14, UITheme.NAVY, true)
	_dialogue_speaker.add_theme_font_override("font", UITheme.spaced(UITheme.ui_bold(), 1))
	tab.add_child(_dialogue_speaker)
	root.add_child(tab)
	var place := func():
		tab.position = _dialogue.position + Vector2(24, -tab.size.y * 0.5 - 2)
		tab.visible = _dialogue.visible
		tab.modulate = _dialogue.modulate
	_dialogue.item_rect_changed.connect(place)
	_dialogue.visibility_changed.connect(place)
	tab.resized.connect(place)
	_dialogue.set_meta("tab", tab)
	_dialogue.hide()


## Full-screen dim with a centred card. Toggling the returned panel toggles both.
func _modal(root: Control, width: int) -> PanelContainer:
	var dim := PanelContainer.new()
	dim.theme_type_variation = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.hide()
	root.add_child(dim)
	var center := CenterContainer.new()
	dim.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(width, 0)
	card.add_theme_stylebox_override("panel", UITheme.card_box(UITheme.GOLD, 0.96))
	center.add_child(card)
	dim.set_meta("card", card)
	return dim


func _modal_box(dim: PanelContainer) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	(dim.get_meta("card") as PanelContainer).add_child(v)
	return v


## Title strip shared by the three screens: kicker, heading, close hint.
func _screen_header(box: VBoxContainer, kicker: String, title: String, key: String, title_label: Label = null) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UITheme.kicker(kicker))
	tv.add_child(title_label if title_label != null else UITheme.heading(title, 28))
	h.add_child(tv)
	for action in [key, "back"]:
		var cap := UITheme.action_cap(action)
		cap.size_flags_vertical = Control.SIZE_SHRINK_END
		h.add_child(cap)
	var cl := UITheme.subtle("close", 12)
	cl.size_flags_vertical = Control.SIZE_SHRINK_END
	h.add_child(cl)
	box.add_child(h)
	box.add_child(UITheme.rule())


func _build_screens(root: Control) -> void:
	# Inventory & Equipment.
	_inv_panel = _modal(root, 0)
	var ib := _modal_box(_inv_panel)
	ib.add_theme_constant_override("separation", 12)
	_screen_header(ib, "Pack & gear", "Inventory", "inventory")
	_inventory = InventoryScreen.build()
	_inventory.item_toggled.connect(func(item, on):
		if on:
			toast(str(item["name"]), "Equipped", "", Crafting.rank_color(int(item.get("rank", 0)))))
	ib.add_child(_inventory)
	# Quest log.
	_quest_panel = _modal(root, 0)
	var qb := _modal_box(_quest_panel)
	_quest_log = QuestLog.build()
	_quest_log.track_requested.connect(func(id):
		tracked_quest = id
		Audio.play("ui_toggle")
		_refresh())
	qb.add_child(_quest_log)
	# Nearby / social (key O).
	_nearby_panel = _modal(root, 0)
	var nb := _modal_box(_nearby_panel)
	_social = Social.build()
	_social.whisper_requested.connect(func(who):
		close_screens()
		open_chat()
		_chat_input.text = "/w %s " % who
		_chat_input.caret_column = _chat_input.text.length())
	nb.add_child(_social)
	# Full map.
	_map_panel = _modal(root, 0)
	var mb := _modal_box(_map_panel)
	mb.add_theme_constant_override("separation", 12)
	_map_title = UITheme.heading("", 28)
	_screen_header(mb, "The Spire", "", "map", _map_title)
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override("separation", 20)
	mb.add_child(mh)
	_map = Minimap.new()
	_map.full = true
	_map.custom_minimum_size = Vector2(620, 620)
	mh.add_child(_map)
	var legend := VBoxContainer.new()
	legend.custom_minimum_size = Vector2(250, 0)
	legend.add_theme_constant_override("separation", 6)
	mh.add_child(legend)
	legend.add_child(UITheme.kicker("You are here"))
	_map_place = UITheme.heading("", 18, UITheme.PARCH)
	_map_place.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.add_child(_map_place)
	legend.add_child(UITheme.rule())
	legend.add_child(UITheme.kicker("Landmarks"))
	for l in MapData.landmarks():
		if l["kind"] == "gate" and l["label"] != "Sealed Gate":
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UIGlyph.make("dot", MapData.kind_color(l["kind"]), 14))
		var nl := UITheme.label(l["label"], 14, UITheme.PARCH, true)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nl)
		var dl := UITheme.label("", 12, UITheme.MUTED, true)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(dl)
		legend.add_child(row)
		_map_legend.append({"dist": dl, "pos": l["pos"]})
	legend.add_child(UITheme.spacer(4))
	legend.add_child(UITheme.rule())
	legend.add_child(UITheme.kicker("Markers"))
	for pair in [["Enemies", Color("ff6b6b")], ["Floor Guardian", UITheme.ROSE], ["Other climbers", UITheme.CYAN], ["Townsfolk", UITheme.PARCH], ["Iron veins", UITheme.GOLD]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UIGlyph.make("dot", pair[1], 14))
		row.add_child(UITheme.label(pair[0], 13, UITheme.MUTED, true))
		legend.add_child(row)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	legend.add_child(fill)
	for pair in [["map_zoom", "Minimap zoom"], ["map", "Toggle map"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UITheme.action_cap(pair[0]))
		row.add_child(UITheme.subtle(pair[1], 12))
		legend.add_child(row)


func _build_pause(root: Control) -> void:
	_pause_panel = _modal(root, 340)
	var pv := _modal_box(_pause_panel)
	pv.add_theme_constant_override("separation", 10)
	pv.add_child(UITheme.kicker("Game paused" if not Net.online else "Menu  ·  world keeps running"))
	pv.add_child(UITheme.heading("The Spire", 30))
	pv.add_child(UITheme.rule())
	pv.add_child(UITheme.spacer(4))
	var resume := UITheme.make_button("Resume", "primary")
	resume.custom_minimum_size = Vector2(0, 44)
	resume.pressed.connect(_toggle_pause)
	pv.add_child(resume)
	# Screens, each with its key cap on the right.
	for entry in [["Inventory", "inventory", toggle_inventory], ["Quest Log", "quest_log", toggle_quests], ["Map", "map", toggle_map]]:
		var b := UITheme.make_button(entry[0], "normal")
		b.custom_minimum_size = Vector2(0, 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var cap := UITheme.action_cap(entry[1])
		cap.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		cap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		cap.grow_vertical = Control.GROW_DIRECTION_BOTH
		cap.offset_right = -12
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cap)
		var fn: Callable = entry[2]
		b.pressed.connect(func():
			_toggle_pause()
			fn.call())
		pv.add_child(b)
	pv.add_child(UITheme.rule(UITheme.MUTED))
	for entry in [["Save", _save, "normal"], ["Settings", _open_settings, "normal"], ["Save & Quit to Menu", _quit_to_menu, "danger"]]:
		var b := UITheme.make_button(entry[0], entry[2])
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(entry[1])
		pv.add_child(b)
	var hint := UITheme.hint_label("%s resumes  ·  %s quick-saves", ["pause", "quick_save"], 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(hint)
	_pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS  # Online the tree is never paused.
	_pause_panel.set_meta("first", resume)


func _process(delta: float) -> void:
	_update_vignette()
	if _death_left > 0.0:
		_death_left -= delta
		_death_sub.text = "Returning to %s in %d" % [_death_where, maxi(ceili(_death_left), 1)]
	_poll_boss(delta)
	if _map_panel.visible:
		_update_map_legend()
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if "guard" in player:
		var show_guard: bool = player.blocking or player.guard < Player.GUARD_MAX - 0.5 or player.is_stunned()
		_guard_bar.visible = show_guard
		if show_guard:
			_guard_bar.value = player.guard
			_guard_bar.modulate = Color(1, 0.45, 0.4) if player.is_stunned() else Color.WHITE
		_status.set_guard(show_guard, player.guard, Player.GUARD_MAX, player.is_stunned())
	_place_t -= delta
	if _place_t <= 0.0:
		_place_t = 0.5
		var p: Vector3 = player.global_position
		_place_l.text = MapData.place_name(Vector2(p.x, p.z))
	for i in _skill_buttons.size():
		var cd: float = player.skill_cd[i]
		var b: Button = _skill_buttons[i]
		b.text = "[%d] %s" % [i + 1, Player.SKILLS[i]["name"]] if cd == 0.0 else "[%d] %.1fs" % [i + 1, cd]
		var slot: Dictionary = _skill_slots[i]
		var total: float = float(Player.SKILLS[i]["cooldown"])
		var frac: float = clamp(cd / max(total, 0.01), 0.0, 1.0)
		(slot["sweep"] as RadialSweep).set_frac(frac)
		(slot["cd"] as Label).text = "%.1f" % cd if cd > 0.0 else ""
		(slot["name"] as Label).modulate.a = 0.45 if cd > 0.0 else 1.0
		if slot.has("lock"):
			var need := int(Player.SKILLS[i].get("prof", 0))
			(slot["lock"] as UITheme.LockOverlay).set_state(GameState.sword_prof, need)
			if GameState.sword_prof < need:
				(slot["sweep"] as RadialSweep).set_frac(0.0)
				(slot["cd"] as Label).text = ""
				(slot["name"] as Label).modulate.a = 0.5
	if GameState.unique_skill != "" and "unique_cd" in player:
		var arts := UniqueSkills.arts(GameState.unique_skill)
		for i in mini(arts.size(), _unique_slots.size()):
			var ucd: float = player.unique_cd[i]
			var us: Dictionary = _unique_slots[i]
			(us["sweep"] as RadialSweep).set_frac(clampf(ucd / maxf(float(arts[i]["cooldown"]), 0.01), 0.0, 1.0))
			(us["cd"] as Label).text = "%.1f" % ucd if ucd > 0.0 else ""
			(us["name"] as Label).modulate.a = 0.45 if ucd > 0.0 else 1.0
	if GameState.hidden_class != "" and "class_cd" in player and not _class_slots.is_empty():
		var carts := HiddenClasses.arts_of(GameState.hidden_class)
		for i in mini(carts.size(), _class_slots.size()):
			var ccd: float = player.class_cd[i]
			var cs: Dictionary = _class_slots[i]
			(cs["sweep"] as RadialSweep).set_frac(clampf(ccd / maxf(float(carts[i]["cooldown"]), 0.01), 0.0, 1.0))
			(cs["cd"] as Label).text = "%.1f" % ccd if ccd > 0.0 else ""
			(cs["name"] as Label).modulate.a = 0.45 if ccd > 0.0 else 1.0
	if not _dash_slot.is_empty() and "_dash_cd" in player:
		var dcd: float = player._dash_cd
		(_dash_slot["sweep"] as RadialSweep).set_frac(clamp(dcd / Player.DASH_COOLDOWN, 0.0, 1.0))
		(_dash_slot["name"] as Label).modulate.a = 0.45 if dcd > 0.0 else 1.0


## Boss health bar: polls the enemies group four times a second (no world
## hooks needed) and follows the first living boss it finds.
func _poll_boss(delta: float) -> void:
	_boss_poll -= delta
	if _boss_poll <= 0.0:
		_boss_poll = 0.25
		var found: Node3D = null
		if _boss != null and is_instance_valid(_boss) and _boss.visible and _boss.is_inside_tree():
			found = _boss
		else:
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.visible and "is_boss" in e and e.is_boss:
					found = e
					break
		if found != _boss:
			_boss = found
			_set_boss_visible(_boss != null)
			if _boss != null:
				var bn := str(_boss.display_name)
				if ":" in bn:
					bn = bn.get_slice(":", 1).strip_edges()
				_boss_name.text = bn.to_upper()
				_boss_lv.text = "Lv %d" % int(_boss.mob_level)
				_boss_bar.max_value = maxf(float(_boss.max_hp), 1.0)
	if _boss != null and is_instance_valid(_boss) and _boss_card.visible:
		var hp: float = maxf(float(_boss.hp), 0.0)
		_boss_bar.value = hp
		_boss_hp.text = "%d / %d" % [ceili(hp), int(_boss.max_hp)]


func _set_boss_visible(on: bool) -> void:
	if _boss_tw and _boss_tw.is_valid():
		_boss_tw.kill()
	_boss_tw = create_tween()
	if on:
		_boss_card.show()
		_boss_card.position.y = 8
		_boss_tw.set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_boss_tw.tween_property(_boss_card, "modulate:a", 1.0, 0.35)
		_boss_tw.tween_property(_boss_card, "position:y", 22.0, 0.45)
	else:
		_boss_tw.tween_property(_boss_card, "modulate:a", 0.0, 0.6)
		_boss_tw.tween_callback(_boss_card.hide)


func _update_map_legend() -> void:
	var p := _map.player_pos
	_map_title.text = ("Floor %d  ·  %s" % [MapData.current_floor(), MapData.floor_name()]).to_upper()
	_map_place.text = MapData.place_name(p).to_upper()
	for e in _map_legend:
		(e["dist"] as Label).text = "%d m" % int(p.distance_to(e["pos"]))


## Full-screen damage vignette behind every other HUD element.
func _build_vignette(root: Control) -> void:
	if Audio.is_silent():
		return  # Headless: no renderer, no shader.
	var shader: Shader = load("res://shaders/hit_vignette.gdshader")
	if shader == null:
		return
	_vignette = ColorRect.new()
	_vignette.name = "HitVignette"
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.color = Color.WHITE
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = shader
	_vignette_mat.set_shader_parameter("strength", 0.0)
	_vignette.material = _vignette_mat
	_vignette.visible = false
	root.add_child(_vignette)
	root.move_child(_vignette, 0)


func _on_health_for_vignette(hp: float, max_hp: float) -> void:
	if _vignette_mat != null and _last_hp >= 0.0 and hp < _last_hp:
		var lost := (_last_hp - hp) / maxf(max_hp, 1.0)
		if _vignette_tw and _vignette_tw.is_valid():
			_vignette_tw.kill()
		_vignette_flash = clampf(0.55 + lost * 2.5, 0.55, 1.0)
		_vignette_tw = create_tween()
		_vignette_tw.tween_property(self, "_vignette_flash", 0.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_last_hp = hp


func _update_vignette() -> void:
	if _vignette_mat == null:
		return
	var frac := GameState.hp / maxf(GameState.max_hp(), 1.0)
	var pulse := 0.0
	if frac < 0.25:
		pulse = (0.2 + 0.12 * sin(Time.get_ticks_msec() * 0.006)) * (1.0 - frac / 0.25)
	var strength := maxf(_vignette_flash, pulse)
	# Heartbeat under 25% HP (not while dead or in a menu).
	_heart_t -= get_process_delta_time()
	if frac < 0.25 and GameState.hp > 0.0 and not _menu_paused and not (_death_overlay and _death_overlay.visible) and _heart_t <= 0.0:
		_heart_t = lerpf(0.75, 1.1, frac / 0.25)
		Audio.play("heartbeat", null, 0.0)
	_vignette.visible = strength > 0.003
	if _vignette.visible:
		_vignette_mat.set_shader_parameter("strength", strength)


const QUEST_NAMES := {
	"boar_trouble": "Boar Trouble: defeat Field Boars",
	"wolf_hunt": "Howls by the Spire: defeat Dire Wolves",
	"forge_trial": "Trial of the Forge: craft items at Haldor's anvil",
	"ore_delivery": "Cold Forge: bring Iron Ore to Elder Wren in Hollowbrook",
	"floor_boss": "Challenge the Floor Guardian atop the Labyrinth",
}


# --- Quest tracking + toasts ----------------------------------------------------

func _snapshot_quests() -> void:
	_last_quests = {}
	for id in GameState.quests:
		_last_quests[id] = bool(GameState.quests[id].get("done", false))


func _on_quest_changed() -> void:
	for id in GameState.quests:
		var done := bool(GameState.quests[id].get("done", false))
		var info := QuestData.info(id)
		if not _last_quests.has(id):
			toast(str(info["title"]), "%s  ·  %s" % [info["objective"], info["reward"]], "New quest")
			Audio.play("ui_open")
			if tracked_quest == "":
				tracked_quest = id
		elif done and not _last_quests[id]:
			toast(str(info["title"]), "Reward: %s" % info["reward"], "Quest complete", UITheme.GREEN)
			Audio.play("craft_success")
		elif not done and _last_quests.has(id) and int(GameState.quests[id].get("progress", 0)) >= int(GameState.quests[id].get("goal", 1)) and id == tracked_quest:
			pass  # the tracker shows "Return to ..." below
	_snapshot_quests()
	_refresh()


func _snapshot_inventory() -> void:
	_last_mats = GameState.materials.duplicate()
	_last_inv = GameState.inventory.size()


func _on_inventory_changed() -> void:
	if not _suppress_feed:
		for m in GameState.materials:
			var gain: int = int(GameState.materials[m]) - int(_last_mats.get(m, 0))
			if gain > 0:
				var g: Array = FEED_GLYPHS.get(m, _life_glyph(m))
				feed("+%d  %s" % [gain, GameState.MATERIAL_NAMES.get(m, m)], g[0], g[1])
		if GameState.inventory.size() > _last_inv:
			for i in range(_last_inv, GameState.inventory.size()):
				var item: Dictionary = GameState.inventory[i]
				feed("Obtained  %s" % item.get("name", "item"), "sword" if item.get("kind") == "weapon" else "shield", Crafting.rank_color(int(item.get("rank", 0))))
	_snapshot_inventory()
	_refresh()


## HP bar colour bands (green > 50% > yellow > 25% > red) and the chip drain.
func _update_hp_look() -> void:
	var mx := maxf(GameState.max_hp(), 1.0)
	var f := GameState.hp / mx
	var band := 0 if f > 0.5 else (1 if f > 0.25 else 2)
	if band != _hp_band:
		_hp_band = band
		_hp_bar.add_theme_stylebox_override("fill", _hp_fills[band])
	_hp_chip.max_value = mx
	if GameState.hp >= _hp_chip.value:
		if _chip_tw:
			_chip_tw.kill()
		_hp_chip.value = GameState.hp
	elif not (_chip_tw and _chip_tw.is_running()):
		_chip_tw = create_tween()
		_chip_tw.tween_interval(0.4)
		_chip_tw.tween_property(_hp_chip, "value", GameState.hp, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	else:
		# Already draining: retarget to the newest HP after the current drain.
		_chip_tw.kill()
		_chip_tw = create_tween()
		_chip_tw.tween_property(_hp_chip, "value", GameState.hp, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _refresh() -> void:
	_info.text = str(GameState.character["name"]).to_upper()
	_class_label.text = (GameState.class_title() + ("  ·  " + GameState.title if GameState.title != "" else "")).to_upper()
	_level_label.text = str(GameState.level)
	_col_label.text = "%d Col" % GameState.money
	_floor_label.text = "Floor %d" % GameState.floor
	_hp_bar.max_value = GameState.max_hp()
	_hp_bar.value = GameState.hp
	_update_hp_look()
	_hp_text.text = "%d / %d" % [ceili(GameState.hp), GameState.max_hp()]
	_xp_bar.max_value = GameState.xp_to_next()
	_xp_bar.value = GameState.xp
	_xp_text.text = "XP %d / %d" % [GameState.xp, GameState.xp_to_next()]
	_status.set_identity(_info.text, _class_label.text, GameState.level)
	_status.set_hp(GameState.hp, GameState.max_hp())
	_status.set_xp(GameState.xp, GameState.xp_to_next())
	_status.set_money_floor(GameState.money, GameState.floor)
	_status.set_crystals(int(GameState.materials.get("heal_crystal", 0)), int(GameState.materials.get("teleport_crystal", 0)))
	_refresh_tracker()
	if _inv_panel.visible:
		_inventory.refresh()
	if _quest_panel.visible:
		_quest_log.tracked = tracked_quest
		_quest_log.refresh()
	if _craft_panel.visible:
		_build_craft()
	if life:
		life.refresh()


func _refresh_tracker() -> void:
	var active := QuestData.active_ids()
	if tracked_quest == "" or not (tracked_quest in active):
		tracked_quest = active[0] if not active.is_empty() else ""
	_quest_card.visible = tracked_quest != ""
	_minimap.tracked_giver = ""
	if tracked_quest == "":
		return
	var q: Dictionary = GameState.quests[tracked_quest]
	var info := QuestData.info(tracked_quest)
	var ready := int(q.get("progress", 0)) >= int(q.get("goal", 1))
	_quest_title.text = str(info["title"]).to_upper()
	_quest_obj.text = str(info["objective"]) if not ready else "Return to %s  ·  %s" % [info["giver"], info["where"]]
	_quest_bar.max_value = maxi(int(q.get("goal", 1)), 1)
	_quest_bar.value = int(q.get("progress", 0))
	_quest_bar.add_theme_stylebox_override("fill", UITheme.gradient_fill_box([UITheme.GOLD_DIM, UITheme.GOLD] if ready else [Color("2d8fd5"), UITheme.CYAN]))
	_quest_prog.text = QuestData.progress_text(tracked_quest, q)
	_quest_prog.add_theme_color_override("font_color", UITheme.GOLD if ready else UITheme.CYAN)
	_quest_more.visible = active.size() > 1
	_quest_more.text = "+%d more  ·  J for the quest log" % (active.size() - 1)
	if ready:
		_minimap.tracked_giver = str(info["giver"])
		_map.tracked_giver = str(info["giver"])


func _section(parent: Node, title: String, right_text := "") -> void:
	var h := HBoxContainer.new()
	var k := UITheme.kicker(title)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(k)
	if right_text != "":
		h.add_child(UITheme.subtle(right_text, 13))
	parent.add_child(h)


func _build_craft() -> void:
	for c in _craft_box.get_children():
		c.queue_free()
	_section(_craft_box, "Haldor's anvil", "Esc to close")
	var title := UITheme.heading("Forge", 28)
	_craft_box.add_child(title)
	_craft_box.add_child(UITheme.rule())
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 8)
	info.add_child(_pill(UITheme.label("Smithing Lv %d  ·  %d/%d" % [GameState.smithing_level, GameState.smithing_xp, GameState.smithing_xp_to_next()], 12, UITheme.CYAN, true), UITheme.CYAN))
	info.add_child(_pill(UITheme.label("%d Col" % GameState.money, 12, UITheme.GOLD, true), UITheme.GOLD))
	for m in GameState.materials:
		info.add_child(_pill(UITheme.label("%s %d" % [GameState.MATERIAL_NAMES.get(m, m), GameState.materials[m]], 12, UITheme.PARCH, true), UITheme.MUTED))
	_craft_box.add_child(info)
	_craft_box.add_child(UITheme.spacer(4))
	for recipe_name in Crafting.RECIPES:
		var r: Dictionary = Crafting.RECIPES[recipe_name]
		var row := PanelContainer.new()
		row.theme_type_variation = "CardFlat"
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 2)
		var nr := HBoxContainer.new()
		nr.add_theme_constant_override("separation", 8)
		nr.add_child(UITheme.label(recipe_name, 16, UITheme.PARCH, true))
		var stat_txt: String = ("ATK %d" % r["base"]) if r["kind"] == "weapon" else (("DEF %d" % r["base"]) if r["kind"] == "armor" else "TOOL")
		nr.add_child(UITheme.label(stat_txt, 12, UITheme.CYAN, true))
		v.add_child(nr)
		v.add_child(UITheme.subtle(Crafting.cost_text(recipe_name), 13))
		h.add_child(v)
		var can: bool = GameState.has_materials(r["cost"]) and GameState.money >= r["col"]
		var b := UITheme.make_button("Forge", "primary" if can else "normal")
		b.custom_minimum_size = Vector2(96, 36)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = not can
		b.pressed.connect(func(): _do_craft(recipe_name))
		h.add_child(b)
		row.add_child(h)
		_craft_box.add_child(row)
	# Repairs: worn gear comes back to full here, for Col (smithing skill
	# lowers the price).
	var worn: Array = []
	for slot in ["weapon", "armor"]:
		var it = GameState.equipped.get(slot)
		if it is Dictionary and Durability.repair_cost(it, GameState.smithing_level) > 0:
			worn.append(slot)
	if not worn.is_empty():
		_craft_box.add_child(UITheme.spacer(4))
		_craft_box.add_child(UITheme.kicker("Repair"))
		for slot in worn:
			var it: Dictionary = GameState.equipped[slot]
			var cost := Durability.repair_cost(it, GameState.smithing_level)
			var row := PanelContainer.new()
			row.theme_type_variation = "CardFlat"
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 12)
			var v := VBoxContainer.new()
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_child(UITheme.label(str(it.get("name", "")), 16, Crafting.rank_color(int(it.get("rank", 0))), true))
			v.add_child(UITheme.subtle("%s  ·  %d Col" % [Durability.text(it), cost], 13))
			h.add_child(v)
			var b := UITheme.make_button("Repair", "primary" if GameState.money >= cost else "normal")
			b.custom_minimum_size = Vector2(96, 36)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.disabled = GameState.money < cost
			b.pressed.connect(func(): _do_repair(slot))
			h.add_child(b)
			row.add_child(h)
			_craft_box.add_child(row)
	var hint := UITheme.subtle("Ranks: Normal < Rare < Epic < Unique < Legendary < Myth. Higher smithing skill rolls higher.", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_craft_box.add_child(hint)


func _do_craft(recipe_name: String) -> void:
	_suppress_feed = true  # the forge toast already announces the item
	var item := Crafting.craft(recipe_name)
	_suppress_feed = false
	if item.has("pending"):
		return  # online: the server forges; the world toasts its answer
	if item.has("error"):
		Audio.play("craft_fail")
		toast(item["error"])
		return
	_forge_sfx(int(item["rank"]))
	var msg := "%s" % item["name"]
	var sub := "Smithing Lv %d" % GameState.smithing_level if item.get("skill_up", false) else ""
	toast(msg, sub, "Forged" if int(item["rank"]) < 3 else "Masterwork forged!", Crafting.rank_color(int(item["rank"])))
	_build_craft()


func _do_repair(slot: String) -> void:
	var err := Durability.repair(GameState, slot)
	if err == "pending":
		return  # online: the server repairs; the world toasts its answer
	if err != "":
		Audio.play("craft_fail")
		toast(err)
		return
	var w := get_tree().current_scene
	if w and w.has_method("repaired"):
		w.repaired(slot)
	else:
		_build_craft()


## Rebuilds the anvil panel when it is open (after a repair or a forge).
func refresh_craft() -> void:
	if _craft_panel and _craft_panel.visible:
		_build_craft()


## Hammer blows on the anvil, then the pot clang; a jingle for Epic and up.
func _forge_sfx(rank: int) -> void:
	for i in 3:
		get_tree().create_timer(0.11 * i, false).timeout.connect(func(): Audio.play("anvil", null, 0.12))
	get_tree().create_timer(0.42, false).timeout.connect(func():
		Audio.play("craft_pot")
		if rank >= 2:
			Audio.play("craft_success"))


func toggle_craft() -> bool:
	_craft_panel.visible = not _craft_panel.visible
	Audio.play("ui_open" if _craft_panel.visible else "ui_close")
	if _craft_panel.visible:
		_hide_screens()
		_build_craft()
		_pop_in(_craft_panel)
	return _craft_panel.visible


# --- Screens ------------------------------------------------------------------

func any_menu_open() -> bool:
	return _inv_panel.visible or _quest_panel.visible or _map_panel.visible or _craft_panel.visible or _nearby_panel.visible or (life != null and life.any_open())


func is_paused() -> bool:
	return _menu_paused


## Tab (world.gd) opens the character/inventory screen.
func toggle_stats() -> bool:
	return toggle_inventory()


func toggle_inventory() -> bool:
	return _toggle_screen(_inv_panel)


func toggle_quests() -> bool:
	return _toggle_screen(_quest_panel)


func toggle_map() -> bool:
	return _toggle_screen(_map_panel)


func toggle_nearby() -> bool:
	return _toggle_screen(_nearby_panel)


func _hide_screens() -> void:
	_inv_panel.hide()
	_quest_panel.hide()
	_map_panel.hide()
	_nearby_panel.hide()
	if life:
		life.hide_all()


func _toggle_screen(panel: PanelContainer) -> bool:
	if panel.visible:
		close_screens()
		return false
	if _menu_paused:
		return false
	_hide_screens()
	_craft_panel.hide()
	panel.show()
	if panel == _inv_panel:
		_inventory.refresh()
		_inventory.focus_first()
		Audio.play("book_open")
	elif panel == _quest_panel:
		_quest_log.tracked = tracked_quest
		_quest_log.refresh()
		_quest_log.focus_first()
		Audio.play("book_open")
	elif panel == _nearby_panel:
		_social.open()
		_social.focus_first()
		Audio.play("ui_open")
	else:
		_update_map_legend()
		Audio.play("ui_open")
	_pop_in(panel)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.input_enabled = false
	return true


## Hide every screen and hand control back to the player.
func close_screens() -> void:
	var was_open := any_menu_open()
	_hide_screens()
	_craft_panel.hide()
	if was_open:
		Audio.play("book_close")
	menus_closed.emit()
	if not _menu_paused and not _chat_input.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Fade the dim and scale the card up from 96%.
func _pop_in(dim: PanelContainer) -> void:
	var card: Control = dim.get_meta("card")
	dim.modulate.a = 0.0
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(0.96, 0.96)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(dim, "modulate:a", 1.0, 0.18)
	tw.tween_property(card, "scale", Vector2.ONE, 0.22)


var _menu_paused := false
## The ring menu (scripts/ui/ring_menu.gd) is the menu; the old pause modal
## is kept only as the parent of the settings modal.
var _ring: RingMenu


## Offline the whole game pauses. Online the world keeps running (other
## players can't wait), so only the menu opens and input is released.
var _settings_panel: PanelContainer
var _settings_form: SettingsPanel


func _open_settings() -> void:
	if _settings_panel == null:
		_settings_panel = _modal(_pause_panel.get_parent(), 560)
		_settings_panel.process_mode = Node.PROCESS_MODE_ALWAYS
		var box := _modal_box(_settings_panel)
		_settings_form = SettingsPanel.build()
		_settings_form.closed.connect(func():
			_settings_panel.hide()
			if _menu_paused:
				_ring.reshow())
		box.add_child(_settings_form)
	_pause_panel.hide()
	_settings_panel.show()
	_pop_in(_settings_panel)
	_settings_form.focus_first()
	Audio.play("ui_open")


func _toggle_pause() -> void:
	if _settings_panel and _settings_panel.visible:
		_settings_panel.hide()
	_menu_paused = not _menu_paused
	if not Net.online:
		get_tree().paused = _menu_paused
	_pause_panel.visible = false
	if _menu_paused:
		_hide_screens()
		_craft_panel.hide()
		_ring.open()
	else:
		_ring.close()
	# The quest card sits where the ring's panels slide out.
	create_tween().tween_property(_quest_card, "modulate:a", 0.0 if _menu_paused else 1.0, 0.15)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _menu_paused else Input.MOUSE_MODE_CAPTURED
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.input_enabled = not _menu_paused


func _save() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		GameState.position = player.global_position
	SaveSystem.save_game(0)


func _quit_to_menu() -> void:
	_save()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	Net.leave.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("chat") and not _chat_input.visible and not _menu_paused and not any_menu_open():
		open_chat()
		get_viewport().set_input_as_handled()
		return
	if _chat_input.visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			close_chat()
		return
	var menu_open := any_menu_open() or _menu_paused
	# On a pad the D-pad navigates an open screen; it only switches screens
	# from the world (the screen's own close button / B still work).
	var pad_nav := InputSetup.is_pad_event(event) and menu_open
	# Esc fires both "pause" and ui_cancel; B is only ui_cancel, so it closes
	# whatever is open without pausing from the world.
	if event.is_action_pressed("pause") or (menu_open and event.is_action_pressed("ui_cancel")):
		if any_menu_open():
			close_screens()
		else:
			_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_save") and not _menu_paused:
		_save()
	elif event.is_action_pressed("inventory") and not pad_nav:
		toggle_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quest_log") and not pad_nav:
		toggle_quests()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and not pad_nav:
		toggle_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("nearby") and not pad_nav:
		toggle_nearby()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map_zoom_in") and (not InputSetup.is_pad_event(event) or _map_panel.visible):
		_minimap.zoom(0.8)
		Audio.play("ui_tick")
	elif event.is_action_pressed("map_zoom_out") and (not InputSetup.is_pad_event(event) or _map_panel.visible):
		_minimap.zoom(1.25)
		Audio.play("ui_tick")


# --- Chat ----------------------------------------------------------------

var _chat_lines: Array = []
var _chat_hide_tween: Tween


## Guild chat channel colour (P8, "/g text").
const GUILD_CHAT_COLOR := Color("9be38b")


## One chat line. `channel`: say (white), party (cyan), guild (green),
## whisper / whisper_to (magenta), system (gold). Names are [url] links that invite.
func add_chat(sender_name: String, text: String, channel := "say") -> void:
	if channel != "system" and Social.is_ignored(sender_name):
		return
	var col: Color = Social.CHAT_COLORS.get(channel, GUILD_CHAT_COLOR if channel == "guild" else UITheme.PARCH)
	var hex := col.to_html(false)
	var who := _bb(sender_name)
	var body := _bb(text)
	var line := ""
	match channel:
		"system":
			line = "[color=#%s]%s[/color]" % [hex, body]
		"party":
			line = "[color=#%s][Party] [url=%s][b]%s[/b][/url]: %s[/color]" % [hex, who, who, body]
		"guild":
			line = "[color=#%s][Guild] [url=%s][b]%s[/b][/url]: %s[/color]" % [hex, who, who, body]
		"whisper":
			line = "[color=#%s][url=%s][b]%s[/b][/url] whispers: %s[/color]" % [hex, who, who, body]
		"whisper_to":
			line = "[color=#%s]To [url=%s][b]%s[/b][/url]: %s[/color]" % [hex, who, who, body]
		_:
			line = "[color=#%s][url=%s][b]%s[/b][/url]: %s[/color]" % [hex, who, who, body]
	_chat_lines.append(line)
	if _chat_lines.size() > 8:
		_chat_lines.pop_front()
	_chat_log.text = "\n".join(_chat_lines)
	Audio.play("chat")
	_show_chat_panel()
	if not _chat_input.visible:
		_schedule_chat_fade()


func _show_chat_panel() -> void:
	if _chat_hide_tween:
		_chat_hide_tween.kill()
	_chat_panel.show()
	var tw := create_tween()
	tw.tween_property(_chat_panel, "modulate:a", 1.0, 0.15)


func _schedule_chat_fade() -> void:
	if _chat_hide_tween:
		_chat_hide_tween.kill()
	_chat_hide_tween = create_tween()
	_chat_hide_tween.tween_interval(7.0)
	# Dim first so the log stays readable a moment longer, then fade out.
	_chat_hide_tween.tween_property(_chat_panel, "modulate:a", 0.55, 1.5)
	_chat_hide_tween.tween_property(_chat_panel, "modulate:a", 0.0, 1.2)
	_chat_hide_tween.tween_callback(_chat_panel.hide)


func open_chat() -> void:
	_show_chat_panel()
	_chat_input.show()
	_chat_input.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	chat_open_changed.emit(true)


func close_chat() -> void:
	_chat_input.text = ""
	_chat_input.hide()
	if _chat_lines.is_empty():
		_chat_panel.hide()
	else:
		_schedule_chat_fade()
	if not any_menu_open() and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	chat_open_changed.emit(false)


static func _bb(t: String) -> String:
	return t.replace("[", "[lb]")


func _on_chat_submitted(text: String) -> void:
	var t := text.strip_edges()
	if t != "" and preload("res://scripts/life/guilds.gd").chat_command(t, self, func(msg): add_chat("", msg, "system")):
		pass  # "/g text" guild chat and "/guild ..." (P8)
	elif t != "" and preload("res://scripts/duels.gd").chat_command(t, self, func(msg): add_chat("", msg, "system")):
		pass  # "/duel Name [mode]", "/duel accept|decline|yield" (scripts/duels.gd)
	elif t != "":
		Social.handle(t, send_chat if send_chat.is_valid() else func(_x): pass, func(msg): add_chat("", msg, "system"))
	close_chat()


## Chat helper for buttons: open the box with `text` already typed.
func chat_prefill(text: String) -> void:
	open_chat()
	_chat_input.text = text
	_chat_input.caret_column = text.length()


var _dialogue_serial := 0


func show_dialogue(speaker: String, text: String) -> void:
	_dialogue_speaker.text = speaker.to_upper()
	_dialogue_text.text = text
	_dialogue.reset_size()
	_dialogue.reset_size.call_deferred()
	if not _dialogue.visible:
		_dialogue.show()
		_dialogue.modulate.a = 0.0
		var tab: Control = _dialogue.get_meta("tab")
		tab.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_dialogue, "modulate:a", 1.0, 0.2)
		tw.tween_property(tab, "modulate:a", 1.0, 0.2)
	_dialogue_text.visible_ratio = 0.0
	var ttw := create_tween()
	ttw.tween_property(_dialogue_text, "visible_ratio", 1.0, clamp(text.length() * 0.018, 0.2, 1.4))
	_dialogue_serial += 1
	var mine := _dialogue_serial
	get_tree().create_timer(5.0, false).timeout.connect(func():
		if _dialogue_serial == mine:
			_dialogue.hide())


func set_prompt(text: String) -> void:
	# World passes "[E] Talk to X"; the key cap already shows E.
	var t := text.strip_edges()
	if t.begins_with("[E]"):
		t = t.substr(3).strip_edges()
	_prompt.text = t
	_prompt_card.visible = t != ""


var _toast_tween: Tween
var _heart_t := 0.0


# --- Death and realm notices -------------------------------------------------

var _death_overlay: ColorRect
var _death_label: Label
var _death_sub: Label
var _death_tw: Tween
var _death_left := 0.0
var _death_where := ""


## Grey-out with "You are dead" and a countdown; the player script respawns
## when it ends (see Player.death_sequence). Input is blocked meanwhile.
func show_death(seconds: float, where: String) -> void:
	if _death_overlay == null:
		_death_overlay = ColorRect.new()
		_death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_death_overlay.color = Color(0.08, 0.08, 0.1, 0.0)
		_death_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		_root.add_child(_death_overlay)
		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_CENTER)
		v.grow_horizontal = Control.GROW_DIRECTION_BOTH
		v.grow_vertical = Control.GROW_DIRECTION_BOTH
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		_death_overlay.add_child(v)
		_death_label = UITheme.heading("YOU ARE DEAD", 44, Color(0.95, 0.3, 0.28))
		_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(_death_label)
		_death_sub = UITheme.label("", 17, UITheme.PARCH)
		_death_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(_death_sub)
		UITheme.death_screen(_death_overlay, _death_label, _death_sub)
	_death_overlay.visible = true
	_death_overlay.color.a = 0.0
	_death_label.modulate.a = 0.0
	if _death_tw:
		_death_tw.kill()
	_death_tw = create_tween()
	_death_tw.tween_property(_death_overlay, "color:a", 0.62, 0.5).set_delay(0.35)
	_death_tw.parallel().tween_property(_death_label, "modulate:a", 1.0, 0.5).set_delay(0.6)
	_death_left = seconds
	_death_where = where
	_death_sub.text = "Returning to %s in %d" % [where, ceili(seconds)]
	close_screens()


func hide_death() -> void:
	if _death_overlay == null or not _death_overlay.visible:
		return
	if _death_tw:
		_death_tw.kill()
	_death_tw = create_tween()
	_death_tw.tween_property(_death_overlay, "color:a", 0.0, 0.4)
	_death_tw.parallel().tween_property(_death_label, "modulate:a", 0.0, 0.3)
	_death_tw.tween_callback(func(): _death_overlay.visible = false)


func is_dead_screen() -> bool:
	return _death_overlay != null and _death_overlay.visible


## Server-wide notice (unique skill granted, last limited slot taken...).
## Called by Net on every client through group "hud".
func realm_announce(text: String) -> void:
	Audio.play("realm_announce")
	RealmBanner.show_on(_root, text)


## Centre-top notice. `sub` is a smaller second line, `kicker` a small
## label above the title, `accent` tints the title and border.
func toast(text: String, sub := "", kicker := "", accent: Color = UITheme.GOLD) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", accent)
	_toast_sub.text = sub
	_toast_sub.visible = sub != ""
	_toast_kicker.text = kicker.to_upper()
	_toast_kicker.visible = kicker != ""
	_toast_kicker.add_theme_color_override("font_color", accent)
	(_toast_card.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color(accent.r, accent.g, accent.b, 0.7)
	_toast_card.reset_size()
	if _toast_tween:
		_toast_tween.kill()
	_toast_card.modulate.a = 0.0
	_toast_card.position.y = 108
	var tw := create_tween()
	_toast_tween = tw
	tw.set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_toast_card, "modulate:a", 1.0, 0.25)
	tw.tween_property(_toast_card, "position:y", 120.0, 0.3)
	tw.set_parallel(false)
	tw.tween_interval(2.0 if sub == "" else 2.8)
	tw.tween_property(_toast_card, "modulate:a", 0.0, 0.6)
