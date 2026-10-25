extends Control
## Title screen: layered night sky, the Spire silhouette, title block on the
## left and the menu card on the right. Also hosts the dedicated-server and
## --join test entry points (no UI is built for those).

const VERSION := "v0.1  ·  vertical slice"

var _status: Label
var _buttons: Array = []
var _entered_world := false


## Joining: the server runs one floor, and tells us which during the auth
## handshake (world.gd on the server sends {"floor": n} the moment the peer
## shows up). We set GameState.floor from it and only then load the world, so
## the right floor is built before our character is sent. If a server never
## says (older build), fall back to the saved floor a few seconds in.
func _enter_world_when_floor_known() -> void:
	_entered_world = false
	# Net.join installed its own auth callback (reject reasons); wrap it in a
	# relay that lives on GameState, so it stays valid after this menu is freed.
	multiplayer.auth_callback = GameState.auth_floor_relay(multiplayer.auth_callback, _go_world)
	multiplayer.peer_authenticating.connect(func(_peer):
		print("Client connected as peer %d" % multiplayer.get_unique_id())
		# Building the floor blocks this process for a while; keep ENet from
		# timing the server out meanwhile (mirrors the server-side setting).
		var ep := multiplayer.multiplayer_peer
		if ep is ENetMultiplayerPeer and ep.get_peer(1):
			ep.get_peer(1).set_timeout(32, 20000, 40000)
		get_tree().create_timer(4.0).timeout.connect(_go_world), CONNECT_ONE_SHOT)


func _go_world() -> void:
	if _entered_world or not Net.online:
		return
	_entered_world = true
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Net.dedicated:
		# Headless floor server: no character, straight into the world.
		if Net.host(Net.port):
			print("Dedicated server listening on port %d" % Net.port)
			get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")
		else:
			get_tree().quit(1)
		return
	# Test hook: godot -- --join 127.0.0.1 --name Bot  (auto-creates a character and joins)
	var args := OS.get_cmdline_user_args()
	var join_at := args.find("--join")
	if join_at != -1 and join_at + 1 < args.size():
		GameState.reset()
		var name_at := args.find("--name")
		GameState.character["name"] = args[name_at + 1] if name_at != -1 and name_at + 1 < args.size() else "Bot"
		if Net.join(args[join_at + 1], Net.port):
			_enter_world_when_floor_known()
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.theme()
	# Screenshot hooks: --demo-slots fills the three cards with made-up
	# climbers (nothing is written), --slots opens the character select.
	if "--demo-slots" in args:
		var now := int(Time.get_unix_time_from_system())
		_demo_infos = {
			0: {"slot": 0, "exists": true, "corrupt": false, "name": "Kaede", "origin": "Swordsman", "class": "Forgeborn", "level": 7, "floor": 1,
				"floor_name": "Town of First Light", "playtime": 5820.0, "last_played": now - 3600 * 5,
				"character": {"name": "Kaede", "origin": "Swordsman", "hair_color": "c4262e", "skin_color": "f2d0b5", "eye_color": "f0c060", "outfit_color": "e63946", "hair_style": 2, "body": "alicia", "height": 1.0}},
			1: {"slot": 1, "exists": true, "corrupt": false, "name": "Orrin", "origin": "Guardian", "class": "Guardian", "level": 12, "floor": 2,
				"floor_name": "Mirewood", "playtime": 14100.0, "last_played": now - 86400 * 2,
				"character": {"name": "Orrin", "origin": "Guardian", "hair_color": "3b2418", "skin_color": "a06a44", "eye_color": "3cb371", "outfit_color": "2d6cdf", "hair_style": 1, "body": "classic", "height": 1.12}},
		}
	_build_backdrop()
	_build_title()
	_build_menu()
	_build_footer()
	if "--slots" in args:
		_open_slots("play")


# --- Backdrop -----------------------------------------------------------------

func _build_backdrop() -> void:
	var sky := TextureRect.new()
	sky.texture = UITheme.gradient_tex(
		[Color("05081a"), Color("0b1024"), Color("1a1f4a"), Color("3a2d5e"), Color("7a4a66")],
		[0.0, 0.35, 0.65, 0.86, 1.0])
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)

	# Stars: small twinkling dots.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var star_tex := UITheme.radial_dot(Color(1, 1, 1, 1), 8, true)
	for i in 110:
		var s := TextureRect.new()
		s.texture = star_tex
		var px := rng.randf_range(2.0, 6.0)
		s.custom_minimum_size = Vector2(px, px)
		s.stretch_mode = TextureRect.STRETCH_SCALE
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.anchor_left = rng.randf()
		s.anchor_right = s.anchor_left
		s.anchor_top = rng.randf_range(0.0, 0.62)
		s.anchor_bottom = s.anchor_top
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.modulate = Color(1, 1, 1, rng.randf_range(0.25, 0.9))
		add_child(s)
		var tw := s.create_tween().set_loops()
		tw.tween_property(s, "modulate:a", rng.randf_range(0.1, 0.35), rng.randf_range(0.8, 2.4)).set_delay(rng.randf_range(0.0, 2.0))
		tw.tween_property(s, "modulate:a", rng.randf_range(0.6, 1.0), rng.randf_range(0.8, 2.4))

	# Moon with a soft halo.
	var halo := TextureRect.new()
	halo.texture = UITheme.radial_dot(Color(0.8, 0.9, 1.0, 0.35), 64, true)
	halo.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	halo.offset_left = -520
	halo.offset_right = -120
	halo.offset_top = -80
	halo.offset_bottom = 320
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(halo)
	var moon := TextureRect.new()
	moon.texture = UITheme.radial_dot(Color("f6f1e3"), 64)
	moon.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	moon.offset_left = -365
	moon.offset_right = -275
	moon.offset_top = 75
	moon.offset_bottom = 165
	moon.stretch_mode = TextureRect.STRETCH_SCALE
	moon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(moon)

	# Drifting clouds (soft radial blobs stretched wide).
	var cloud_tex := UITheme.radial_dot(Color(0.55, 0.5, 0.8, 0.22), 64, true)
	for i in 6:
		var c := TextureRect.new()
		c.texture = cloud_tex
		c.stretch_mode = TextureRect.STRETCH_SCALE
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w := rng.randf_range(420, 780)
		var h := rng.randf_range(70, 130)
		c.anchor_top = rng.randf_range(0.42, 0.78)
		c.anchor_bottom = c.anchor_top
		c.anchor_left = rng.randf_range(-0.2, 0.9)
		c.anchor_right = c.anchor_left
		c.offset_right = w
		c.offset_bottom = h
		add_child(c)
		var tw := c.create_tween().set_loops()
		var drift := rng.randf_range(40, 110)
		tw.tween_property(c, "offset_left", drift, rng.randf_range(14, 26)).from(0.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(c, "offset_right", w + drift, rng.randf_range(14, 26)).from(w).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(c, "offset_left", 0.0, rng.randf_range(14, 26)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(c, "offset_right", w, rng.randf_range(14, 26)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# The Spire: layered silhouettes anchored to the bottom-centre.
	var tower := Control.new()
	tower.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tower.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tower)
	tower.draw.connect(_draw_tower.bind(tower))
	resized.connect(tower.queue_redraw)

	# Vignette to pull focus inwards.
	var vig := TextureRect.new()
	vig.texture = UITheme.radial_dot(Color(0, 0, 0, 0), 64)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.55)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	vig.texture = gt
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.offset_left = -200
	vig.offset_right = 200
	vig.offset_top = -120
	vig.offset_bottom = 120
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)


func _draw_tower(c: Control) -> void:
	var w := size.x
	var h := size.y
	var base_y := 0.0  # control sits at the bottom edge; draw upwards (negative y)
	var cx := w * 0.52
	# Far hills.
	var far := Color("151c3a")
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(-10, base_y), Vector2(-10, -h * 0.14), Vector2(w * 0.12, -h * 0.22), Vector2(w * 0.3, -h * 0.15),
		Vector2(w * 0.5, -h * 0.24), Vector2(w * 0.72, -h * 0.17), Vector2(w * 0.9, -h * 0.25), Vector2(w + 10, -h * 0.16), Vector2(w + 10, base_y)]), far)
	# Tower tiers, widest at the base, narrowing to the spire.
	var col := Color("0a0e22")
	var tiers := [[0.115, 0.0, 0.22], [0.09, 0.22, 0.40], [0.07, 0.40, 0.55], [0.05, 0.55, 0.67], [0.033, 0.67, 0.76]]
	for t in tiers:
		var hw: float = w * t[0]
		var y0: float = -h * t[1]
		var y1: float = -h * t[2]
		c.draw_colored_polygon(PackedVector2Array([
			Vector2(cx - hw, y0), Vector2(cx - hw * 0.92, y1), Vector2(cx + hw * 0.92, y1), Vector2(cx + hw, y0)]), col)
		# Ledge lip on each tier.
		c.draw_rect(Rect2(cx - hw * 1.06, y1 - 6, hw * 2.12, 10), col)
		# Lit windows.
		var rng := RandomNumberGenerator.new()
		rng.seed = int(t[1] * 1000)
		for i in int(hw / 5):
			var wx := cx - hw * 0.8 + rng.randf() * hw * 1.6
			var wy := y1 + 14 + rng.randf() * (y0 - y1 - 28)
			var a := rng.randf_range(0.25, 0.8)
			c.draw_rect(Rect2(wx, wy, 3, 5), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, a))
	# Spire tip and beacon.
	c.draw_colored_polygon(PackedVector2Array([Vector2(cx - w * 0.015, -h * 0.76), Vector2(cx, -h * 0.88), Vector2(cx + w * 0.015, -h * 0.76)]), col)
	c.draw_circle(Vector2(cx, -h * 0.87), 16, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.2))
	c.draw_circle(Vector2(cx, -h * 0.87), 5, UITheme.CYAN)
	# Near hills.
	var near := Color("070a18")
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(-10, base_y), Vector2(-10, -h * 0.07), Vector2(w * 0.2, -h * 0.12), Vector2(w * 0.42, -h * 0.06),
		Vector2(w * 0.66, -h * 0.11), Vector2(w * 0.85, -h * 0.05), Vector2(w + 10, -h * 0.1), Vector2(w + 10, base_y)]), near)


# --- Title block ---------------------------------------------------------------

func _build_title() -> void:
	var block := VBoxContainer.new()
	block.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	block.offset_left = 112
	block.offset_top = -200
	block.add_theme_constant_override("separation", 6)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(block)

	var kick := UITheme.kicker("Anime Life RPG  ·  Floor One")
	block.add_child(kick)
	var title := Label.new()
	title.text = "THE SPIRE"
	title.theme_type_variation = "Title"
	block.add_child(title)
	var rule := UITheme.rule()
	rule.custom_minimum_size = Vector2(420, 2)
	block.add_child(rule)
	var sub := Label.new()
	sub.text = "Climb the Spire.  Live your story."
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", UITheme.PARCH)
	block.add_child(sub)
	var blurb := UITheme.subtle("A hundred floors above the Town of First Light, something is waiting.\nForge your blade, master the Sword Arts and find out what.", 15)
	blurb.custom_minimum_size = Vector2(460, 0)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
	block.add_child(blurb)
	UITheme.enter(block, Vector2(-60, 0), 0.1, 0.8)

	# Slow golden shimmer across the title.
	var tw := title.create_tween().set_loops()
	tw.tween_property(title, "self_modulate", Color(1.08, 1.04, 0.96), 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(title, "self_modulate", Color(1, 1, 1), 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# --- Menu card -----------------------------------------------------------------

func _build_menu() -> void:
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	card.offset_left = -112 - 400
	card.offset_right = -112
	card.offset_top = -236
	card.custom_minimum_size = Vector2(400, 0)
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)

	v.add_child(UITheme.kicker("Main menu", UITheme.GOLD))
	v.add_child(UITheme.spacer(2))
	var saves := _save_count()
	var has_save := saves > 0
	_online_slot = _last_played()

	var new_btn := UITheme.make_button("New Game", "primary")
	new_btn.custom_minimum_size = Vector2(0, 48)
	new_btn.pressed.connect(_new_game)
	v.add_child(new_btn)

	var cont := UITheme.make_button("Continue", "normal")
	cont.custom_minimum_size = Vector2(0, 48)
	cont.disabled = not has_save
	cont.pressed.connect(func(): _open_slots("play"))
	v.add_child(cont)
	var slot_text := "No saved climb yet"
	if has_save:
		var li := _info(_online_slot)
		slot_text = "%d of %d slots  ·  last: %s, Lv %d %s" % [saves, SaveSystem.SLOT_COUNT, li["name"], li["level"], li["class"]]
	var slot := UITheme.subtle(slot_text, 13)
	slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(slot)

	v.add_child(UITheme.spacer(4))
	# Online section in its own flat card.
	var online := PanelContainer.new()
	online.theme_type_variation = "CardFlat"
	v.add_child(online)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 8)
	online.add_child(ov)
	var oh := HBoxContainer.new()
	oh.add_child(UITheme.kicker("Online"))
	var osub := UITheme.subtle("same character, shared floor", 12)
	osub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	osub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	oh.add_child(osub)
	ov.add_child(oh)
	# Which climber goes online.
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 8)
	_online_label = UITheme.subtle("", 13)
	_online_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_online_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_online_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.add_child(_online_label)
	var change := UITheme.make_button("Change", "ghost")
	change.disabled = saves < 2
	change.pressed.connect(func(): _open_slots("pick"))
	who.add_child(change)
	ov.add_child(who)
	_refresh_online_label()

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_color_override("font_color", UITheme.ROSE)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	var host_btn := UITheme.make_button("Host a floor server  ·  port %d" % Net.DEFAULT_PORT, "normal")
	host_btn.disabled = not has_save
	host_btn.pressed.connect(func():
		if SaveSystem.load_game(_online_slot) and Net.host():
			LoadingScreen.open(GameState.floor, "Hosting")
			get_tree().change_scene_to_file("res://scenes/world.tscn"))
	ov.add_child(host_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var ip := LineEdit.new()
	ip.placeholder_text = "Server IP"
	ip.text = "127.0.0.1"
	ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ip)
	var join_btn := UITheme.make_button("Join", "normal")
	join_btn.disabled = not has_save
	join_btn.pressed.connect(func():
		if SaveSystem.load_game(_online_slot) and Net.join(ip.text.strip_edges()):
			_status.add_theme_color_override("font_color", UITheme.CYAN)
			_status.text = "Connecting..."
			LoadingScreen.connecting()
			_enter_world_when_floor_known())
	row.add_child(join_btn)
	ov.add_child(row)
	var on_fail := func(reason):
		LoadingScreen.close()
		_status.show()
		_status.add_theme_color_override("font_color", UITheme.ROSE)
		_status.text = reason
	Net.connection_failed.connect(on_fail)
	tree_exiting.connect(func(): Net.connection_failed.disconnect(on_fail))
	ov.add_child(_status)
	if not has_save:
		_status.add_theme_color_override("font_color", UITheme.MUTED)
		_status.text = "Create a character first to play online."
	else:
		_status.hide()
		join_btn.pressed.connect(func(): _status.show())

	v.add_child(UITheme.spacer(4))
	var settings_btn := UITheme.make_button("Settings", "normal")
	settings_btn.pressed.connect(_open_settings)
	v.add_child(settings_btn)
	_settings_btn = settings_btn
	_new_btn = new_btn
	var quit := UITheme.make_button("Quit", "ghost")
	quit.pressed.connect(func(): get_tree().quit())
	v.add_child(quit)

	UITheme.enter(card, Vector2(60, 0), 0.3, 0.8)
	new_btn.grab_focus()


# --- Save slots / character select ----------------------------------------------

var _online_slot := 0
var _online_label: Label
var _settings_btn: Button
var _new_btn: Button
var _slots_dim: PanelContainer
## --demo-slots: three made-up climbers for screenshots (nothing is written).
var _demo_infos := {}


func _info(slot: int) -> Dictionary:
	if _demo_infos.has(slot):
		return _demo_infos[slot]
	return SaveSystem.slot_info(slot)


func _save_count() -> int:
	var n := 0
	for s in SaveSystem.SLOT_COUNT:
		if _info(s)["exists"]:
			n += 1
	return n


func _last_played() -> int:
	var best := 0
	var best_t := -1
	for s in SaveSystem.SLOT_COUNT:
		var i := _info(s)
		if i["exists"] and not i["corrupt"] and int(i["last_played"]) > best_t:
			best = s
			best_t = int(i["last_played"])
	return best


func _refresh_online_label() -> void:
	if _online_label == null:
		return
	var i := _info(_online_slot)
	_online_label.text = ("as %s  ·  Lv %d %s" % [i["name"], i["level"], i["class"]]) if i["exists"] else "No climber yet"


func _new_game() -> void:
	var free := SaveSystem.first_free_slot()
	if free < 0:
		_open_slots("new")
		return
	SaveSystem.new_game(free)
	get_tree().change_scene_to_file("res://scenes/character_creator.tscn")


func _play_slot(slot: int) -> void:
	if SaveSystem.load_game(slot):
		LoadingScreen.open(GameState.floor)
		get_tree().change_scene_to_file("res://scenes/world.tscn")


func _edit_slot(slot: int) -> void:
	if SaveSystem.load_game(slot):
		SaveSystem.edit_slot = slot
		get_tree().change_scene_to_file("res://scenes/character_creator.tscn")


func _start_in_slot(slot: int) -> void:
	SaveSystem.new_game(slot)
	get_tree().change_scene_to_file("res://scenes/character_creator.tscn")


## Character select. mode: "play" (Continue), "pick" (who goes online),
## "new" (all slots taken: choose one to overwrite).
func _open_slots(mode: String) -> void:
	if _slots_dim:
		_slots_dim.queue_free()
	_slots_dim = PanelContainer.new()
	_slots_dim.theme_type_variation = "Dim"
	_slots_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_slots_dim)
	var center := CenterContainer.new()
	_slots_dim.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(1180, 0)
	center.add_child(card)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	card.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)
	var head := HBoxContainer.new()
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", 2)
	hv.add_child(UITheme.kicker({"play": "Continue", "pick": "Online", "new": "New Game"}[mode], UITheme.GOLD))
	hv.add_child(UITheme.heading({"play": "Choose your climber", "pick": "Who goes online?", "new": "Every slot is taken"}[mode], 30))
	hv.add_child(UITheme.subtle({"play": "Three save slots. Delete asks twice; Edit look changes only appearance.",
		"pick": "The server keeps its own record per name; this picks the character and its token.",
		"new": "Pick a slot to start over in. The climber in it is lost."}[mode], 14))
	head.add_child(hv)
	var close := UITheme.make_button("Close", "ghost")
	close.pressed.connect(_close_slots)
	head.add_child(close)
	v.add_child(head)
	v.add_child(UITheme.rule())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	for s in SaveSystem.SLOT_COUNT:
		var sc := _slot_card(s, mode)
		sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sc)
		UITheme.fade_in(sc, 0.06 * s, 0.35)  # containers own position: fade only
	UITheme.fade_in(_slots_dim, 0.0, 0.2)
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 8)
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	hint.add_child(UITheme.action_cap("back"))
	hint.add_child(UITheme.subtle("close", 12))
	v.add_child(hint)
	if UITheme.focus_first_in(row) == null:
		close.grab_focus()


func _close_slots() -> void:
	if _slots_dim:
		_slots_dim.queue_free()
		_slots_dim = null
		if _new_btn:
			_new_btn.grab_focus()


func _slot_card(slot: int, mode: String) -> PanelContainer:
	var info := _info(slot)
	var card := PanelContainer.new()
	card.theme_type_variation = "CardFlat"
	card.custom_minimum_size = Vector2(340, 430)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var top := HBoxContainer.new()
	top.add_child(UITheme.kicker("Slot %d" % (slot + 1)))
	var when := UITheme.subtle(SaveSystem.format_last_played(int(info["last_played"])) if info["exists"] and not info["corrupt"] else "", 12)
	when.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(when)
	v.add_child(top)

	var portrait := SlotPortrait.new()
	portrait.custom_minimum_size = Vector2(0, 150)
	portrait.character = info["character"] if info["exists"] and not info["corrupt"] else {}
	portrait.ring = UITheme.GOLD if info["exists"] else Color(1, 1, 1, 0.12)
	v.add_child(portrait)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	if not info["exists"]:
		v.add_child(UITheme.heading("Empty", 24, UITheme.MUTED))
		v.add_child(UITheme.subtle("A fresh climb starts at Floor 1.", 13))
		v.add_child(UITheme.spacer(2))
		var filler := Control.new()
		filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(filler)
		if mode != "pick":
			var nb := UITheme.make_button("New climber", "primary" if mode == "new" else "normal")
			nb.pressed.connect(func(): _start_in_slot(slot))
			actions.add_child(nb)
		v.add_child(actions)
		return card
	if info["corrupt"]:
		v.add_child(UITheme.heading("Unreadable", 24, UITheme.ROSE))
		v.add_child(UITheme.subtle("This file could not be parsed.", 13))
		var filler2 := Control.new()
		filler2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(filler2)
		_delete_row(actions, slot, "this file")
		v.add_child(actions)
		return card

	v.add_child(UITheme.heading(str(info["name"]), 26, UITheme.PARCH))
	v.add_child(UITheme.label("%s  ·  Lv %d" % [info["class"], int(info["level"])], 15, UITheme.CYAN, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 2)
	for pair in [["Floor", "%d  ·  %s" % [int(info["floor"]), info["floor_name"]]], ["Played", SaveSystem.format_playtime(float(info["playtime"]))],
			["Body", str(info["character"].get("body", "classic")).capitalize()]]:
		var k := UITheme.subtle(pair[0], 12)
		k.custom_minimum_size = Vector2(56, 0)
		grid.add_child(k)
		grid.add_child(UITheme.label(pair[1], 13, UITheme.PARCH))
	v.add_child(grid)
	var filler3 := Control.new()
	filler3.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(filler3)
	match mode:
		"play":
			var play := UITheme.make_button("Play", "primary")
			play.pressed.connect(func(): _play_slot(slot))
			actions.add_child(play)
			var two := HBoxContainer.new()
			two.add_theme_constant_override("separation", 6)
			var edit := UITheme.make_button("Edit look", "normal")
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.pressed.connect(func(): _edit_slot(slot))
			two.add_child(edit)
			actions.add_child(two)
			_delete_row(two, slot, str(info["name"]))
		"pick":
			var pick := UITheme.make_button("Select" if slot != _online_slot else "Selected", "primary" if slot != _online_slot else "normal")
			pick.disabled = slot == _online_slot
			pick.pressed.connect(func():
				_online_slot = slot
				_refresh_online_label()
				_close_slots())
			actions.add_child(pick)
		"new":
			var over := UITheme.make_button("Start over here", "danger")
			over.pressed.connect(func(): _confirm(actions, over, "Lose %s?" % info["name"], func(): _start_in_slot(slot)))
			actions.add_child(over)
	v.add_child(actions)
	return card


func _delete_row(into: Control, slot: int, what: String) -> void:
	var del := UITheme.make_button("Delete", "ghost")
	del.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del.pressed.connect(func(): _confirm(into, del, "Delete %s?" % what, func():
		SaveSystem.delete_slot(slot)
		_open_slots("play")
		_online_slot = _last_played()
		_refresh_online_label()))
	into.add_child(del)


## Swaps `button` for an inline "question? [Yes] [Keep]" pair.
func _confirm(into: Control, button: Button, question: String, on_yes: Callable) -> void:
	var idx := button.get_index()
	button.hide()
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var q := UITheme.label(question, 13, UITheme.ROSE, true)
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q.autowrap_mode = TextServer.AUTOWRAP_OFF
	q.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(q)
	var yes := UITheme.make_button("Yes", "danger")
	yes.pressed.connect(on_yes)
	box.add_child(yes)
	var keep := UITheme.make_button("Keep", "ghost")
	keep.pressed.connect(func():
		box.queue_free()
		button.show())
	box.add_child(keep)
	into.add_child(box)
	into.move_child(box, idx)


## 2D portrait drawn from the saved cosmetics: hair, skin, eyes, outfit, with
## a class-coloured ring. Cheap enough for three cards (no SubViewport).
class SlotPortrait extends Control:
	var character := {}
	var ring := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _col(key: String, fallback: String) -> Color:
		var v = character.get(key, fallback)
		return Color(str(v)) if str(v).is_valid_html_color() else Color(fallback)

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.46
		draw_circle(c, r, Color(UITheme.NAVY.r, UITheme.NAVY.g, UITheme.NAVY.b, 0.85))
		draw_arc(c, r, 0.0, TAU, 64, ring, 2.5, true)
		if character.is_empty():
			draw_arc(c, r * 0.42, 0.0, TAU, 32, Color(1, 1, 1, 0.1), 2.0, true)
			draw_circle(c - Vector2(0, r * 0.1), r * 0.26, Color(1, 1, 1, 0.06))
			return
		var skin := _col("skin_color", "f2d0b5")
		var hair := _col("hair_color", "1a1a2e")
		var eyes := _col("eye_color", "4cc9f0")
		var outfit := _col("outfit_color", "e63946")
		var h := float(character.get("height", 1.0))
		var head_r := r * 0.3 * lerpf(1.04, 0.96, clampf((h - 0.85) / 0.3, 0.0, 1.0))
		var head_c := c + Vector2(0, -r * 0.18)
		# Shoulders / outfit.
		var body := Rect2(c.x - r * 0.46, head_c.y + head_r * 0.85, r * 0.92, r * 0.6)
		draw_rect(body, outfit.darkened(0.15))
		draw_rect(Rect2(body.position + Vector2(r * 0.33, 0), Vector2(r * 0.26, r * 0.6)), outfit.lightened(0.15))
		# Neck, head.
		draw_rect(Rect2(head_c.x - head_r * 0.28, head_c.y + head_r * 0.6, head_r * 0.56, head_r * 0.5), skin.darkened(0.12))
		draw_circle(head_c, head_r, skin)
		# Hair: cap, fringe and side locks; the style index nudges the fringe.
		var style := int(character.get("hair_style", 0))
		draw_arc(head_c, head_r * 0.98, PI + 0.15, TAU - 0.15, 24, hair, head_r * 0.42, true)
		var fringe := head_r * (0.55 + 0.1 * (style % 3))
		draw_circle(head_c + Vector2(-head_r * 0.55, -head_r * 0.25), fringe * 0.55, hair)
		draw_circle(head_c + Vector2(head_r * 0.5, -head_r * 0.3), fringe * 0.5, hair)
		if style % 2 == 1 or str(character.get("body", "")) != "classic":
			draw_rect(Rect2(head_c.x - head_r * 1.05, head_c.y - head_r * 0.2, head_r * 0.28, head_r * 1.1), hair)
			draw_rect(Rect2(head_c.x + head_r * 0.77, head_c.y - head_r * 0.2, head_r * 0.28, head_r * 1.1), hair)
		# Eyes.
		for sx in [-1.0, 1.0]:
			var e := head_c + Vector2(sx * head_r * 0.36, head_r * 0.12)
			draw_rect(Rect2(e - Vector2(head_r * 0.11, head_r * 0.16), Vector2(head_r * 0.22, head_r * 0.32)), Color(1, 1, 1, 0.95))
			draw_circle(e + Vector2(0, head_r * 0.03), head_r * 0.1, eyes)
			draw_circle(e + Vector2(head_r * 0.03, -head_r * 0.03), head_r * 0.035, Color.WHITE)
		# Mouth.
		draw_arc(head_c + Vector2(0, head_r * 0.45), head_r * 0.16, 0.3, PI - 0.3, 8, skin.darkened(0.45), 1.5, true)


# --- Footer --------------------------------------------------------------------

func _build_footer() -> void:
	var left := HBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left.offset_left = 32
	left.offset_top = -44
	left.add_theme_constant_override("separation", 10)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	for pair in [["move", "Move"], ["jump", "Jump"], ["attack", "Attack"], ["skills", "Sword Arts"], ["inventory", "Inventory"], ["quest_log", "Quests"], ["map", "Map"], ["chat", "Chat"]]:
		left.add_child(UITheme.action_cap(pair[0]))
		var l := UITheme.subtle(pair[1], 13)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		left.add_child(l)
		left.add_child(UITheme.spacer(6))
	UITheme.enter(left, Vector2(0, 20), 0.6)

	var ver := UITheme.subtle(VERSION, 13)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -300
	ver.offset_right = -32
	ver.offset_top = -40
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)
	UITheme.enter(ver, Vector2(0, 20), 0.7)


var _settings_dim: PanelContainer
var _settings_form: SettingsPanel


func _open_settings() -> void:
	if _settings_dim:
		_settings_dim.show()
		_settings_form.focus_first()
		return
	_settings_dim = PanelContainer.new()
	_settings_dim.theme_type_variation = "Dim"
	_settings_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_settings_dim)
	var center := CenterContainer.new()
	_settings_dim.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 0)
	center.add_child(card)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	card.add_child(margin)
	_settings_form = SettingsPanel.build()
	_settings_form.closed.connect(func():
		_settings_dim.hide()
		if _settings_btn:
			_settings_btn.grab_focus())
	margin.add_child(_settings_form)
	_settings_form.focus_first()


## B / Esc backs out of the slot picker and settings (gamepad navigation).
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _slots_dim:
		_close_slots()
		get_viewport().set_input_as_handled()
	elif _settings_dim and _settings_dim.visible:
		_settings_form.closed.emit()
		get_viewport().set_input_as_handled()
