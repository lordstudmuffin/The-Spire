class_name PartyPanel
extends VBoxContainer
## Party frames under the player card: one card per other member with a
## level ring, origin glyph, name, leader mark, HP bar and distance, fed by
## Net.party / Net.party_state (server relay every 0.5 s). Also owns the
## invite prompt (Y / N or buttons). Cards are pooled; nothing is rebuilt
## per tick.

# Same green / yellow / red bands as the player gauge (PlayerStatus).
const HP_COLORS := [Color("4fb83a"), Color("7fd35a"), Color("9be86a")]

var _header: PanelContainer
var _count: Label
var _leave: Button
var _cards: Array = []  # [{"panel","ring","lv","glyph","name","lead","dist","bar","hp"}]
var _invite: PanelContainer
var _invite_from: Label
var _t := 0.0
var _styles := {}


static func build() -> PartyPanel:
	var p := PartyPanel.new()
	p._build()
	return p


func _build() -> void:
	add_theme_constant_override("separation", 6)
	custom_minimum_size = Vector2(300, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header = PanelContainer.new()
	var hs := UITheme.box(Color(UITheme.NAVY.r, UITheme.NAVY.g, UITheme.NAVY.b, 0.5), Color(UITheme.GREEN.r, UITheme.GREEN.g, UITheme.GREEN.b, 0.35), 4, 1)
	hs.content_margin_left = 12
	hs.content_margin_right = 8
	hs.content_margin_top = 4
	hs.content_margin_bottom = 4
	_header.add_theme_stylebox_override("panel", hs)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	_header.add_child(hb)
	var k := UITheme.kicker("Party", UITheme.GREEN)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(k)
	_count = UITheme.label("", 11, UITheme.MUTED, true)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_count)
	_leave = UITheme.make_button("Leave", "chip")
	_leave.custom_minimum_size = Vector2(0, 24)
	_leave.add_theme_font_size_override("font_size", 11)
	_leave.pressed.connect(func(): Net.request_party_leave())
	hb.add_child(_leave)
	_header.hide()
	add_child(_header)
	for i in Net.PARTY_MAX - 1:
		_cards.append(_make_card())
	_build_invite()


func _card_style(c: Color) -> StyleBoxFlat:
	var key := c.to_html(false)
	if _styles.has(key):
		return _styles[key]
	var s := UITheme.box(Color(UITheme.NAVY.r, UITheme.NAVY.g, UITheme.NAVY.b, 0.38), Color(c.r, c.g, c.b, 0.45), 4, 1)
	s.border_width_left = 3
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	_styles[key] = s
	return s


func _make_card() -> Dictionary:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _card_style(UITheme.GREEN))
	add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	# Level ring with the origin glyph inside.
	var ring := Control.new()
	ring.custom_minimum_size = Vector2(44, 44)
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ring.set_meta("stroke", UITheme.GREEN)
	ring.draw.connect(func():
		var c := ring.size * 0.5
		var r: float = minf(ring.size.x, ring.size.y) * 0.5 - 2.0
		var stroke: Color = ring.get_meta("stroke")
		ring.draw_circle(c, r, UITheme.NAVY2)
		ring.draw_arc(c, r, 0.0, TAU, 48, stroke, 2.5, true))
	ring.resized.connect(ring.queue_redraw)
	var glyph := UIGlyph.make("sword", UITheme.PARCH, 22)
	glyph.set_anchors_preset(Control.PRESET_CENTER)
	glyph.offset_left = -11
	glyph.offset_top = -11
	glyph.offset_right = 11
	glyph.offset_bottom = 11
	ring.add_child(glyph)
	var lv := UITheme.label("1", 10, UITheme.NAVY, true)
	var lv_pill := PanelContainer.new()
	var lps := UITheme.box(UITheme.GREEN, UITheme.GREEN, 999, 1)
	lps.content_margin_left = 5
	lps.content_margin_right = 5
	lps.content_margin_top = 0
	lps.content_margin_bottom = 0
	lv_pill.add_theme_stylebox_override("panel", lps)
	lv_pill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	lv_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lv_pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lv_pill.offset_right = 4
	lv_pill.offset_bottom = 2
	lv_pill.add_child(lv)
	ring.add_child(lv_pill)
	h.add_child(ring)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 3)
	h.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_l := UITheme.label("", 15, UITheme.PARCH, true)
	row.add_child(name_l)
	var lead := UIGlyph.make("star", UITheme.GOLD, 14)
	lead.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lead.tooltip_text = "Party leader"
	row.add_child(lead)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)
	var dist := UITheme.label("", 11, UITheme.MUTED, true)
	dist.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dist)
	v.add_child(row)
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 14)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 100
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := UITheme.box(Color(0.06, 0.08, 0.13, 0.62), Color(1, 1, 1, 0.9), 2)
	bg.set_content_margin_all(0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", UITheme.gradient_fill_box(HP_COLORS, 2))
	wrap.add_child(bar)
	var hp := UITheme.label("", 10, UITheme.PARCH, true)
	hp.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	hp.add_theme_constant_override("outline_size", 3)
	wrap.add_child(hp)
	v.add_child(wrap)
	p.hide()
	return {"panel": p, "ring": ring, "lv": lv, "glyph": glyph, "name": name_l, "lead": lead, "dist": dist, "bar": bar, "hp": hp, "peer": 0, "low": false}


func _build_invite() -> void:
	_invite = PanelContainer.new()
	var sb := UITheme.box(Color(UITheme.NAVY.r, UITheme.NAVY.g, UITheme.NAVY.b, 0.9), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.7), 12, 1, 10)
	sb.set_content_margin_all(12)
	_invite.add_theme_stylebox_override("panel", sb)
	add_child(_invite)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_invite.add_child(v)
	v.add_child(UITheme.kicker("Party invite", UITheme.GOLD))
	_invite_from = UITheme.heading("", 18, UITheme.PARCH)
	v.add_child(_invite_from)
	v.add_child(UITheme.subtle("Share XP and Col with the party (+10% per member).", 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var acc := UITheme.make_button("Accept", "primary")
	acc.custom_minimum_size = Vector2(110, 32)
	acc.pressed.connect(func(): _answer(true))
	row.add_child(acc)
	row.add_child(UITheme.action_cap("yes"))
	row.add_child(UITheme.spacer(6))
	var dec := UITheme.make_button("Decline", "ghost")
	dec.custom_minimum_size = Vector2(100, 32)
	dec.pressed.connect(func(): _answer(false))
	row.add_child(dec)
	row.add_child(UITheme.action_cap("no"))
	v.add_child(row)
	_invite.hide()


func _ready() -> void:
	Net.party_changed.connect(refresh)
	Net.party_invited.connect(_on_invited)
	refresh()


func _on_invited(from_name: String) -> void:
	_invite_from.text = "%s invites you" % from_name
	_invite.show()
	Audio.play("ui_open")
	_invite.modulate.a = 0.0
	create_tween().tween_property(_invite, "modulate:a", 1.0, 0.2)


func _answer(accept: bool) -> void:
	if not _invite.visible:
		return
	_invite.hide()
	Audio.play("ui_click" if accept else "ui_close")
	Net.request_party_respond(accept)


func _unhandled_key_input(event: InputEvent) -> void:
	if not _invite.visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.physical_keycode == KEY_Y:
		_answer(true)
		get_viewport().set_input_as_handled()
	elif k.physical_keycode == KEY_N:
		_answer(false)
		get_viewport().set_input_as_handled()


## Gamepad: A accepts and B declines an invite (only while one is showing
## and nothing else is open, so the buttons never double-fire).
func _unhandled_input(event: InputEvent) -> void:
	if not _invite.visible or not (event is InputEventJoypadButton) or not event.pressed:
		return
	var bi := (event as InputEventJoypadButton).button_index
	if bi == JOY_BUTTON_A:
		_answer(true)
		get_viewport().set_input_as_handled()
	elif bi == JOY_BUTTON_B:
		_answer(false)
		get_viewport().set_input_as_handled()


## Membership changed: rebind the pooled cards.
func refresh() -> void:
	if Net.pending_invite.is_empty() and _invite.visible:
		_invite.hide()
	var members: Array = Net.party.get("members", []) if Net.in_party() else []
	var me := multiplayer.get_unique_id()
	var others := []
	for m in members:
		if int(m["peer"]) != me:
			others.append(m)
	_header.visible = not members.is_empty()
	_count.text = "%d / %d" % [members.size(), Net.PARTY_MAX]
	for i in _cards.size():
		var d: Dictionary = _cards[i]
		if i >= others.size():
			d["panel"].hide()
			d["peer"] = 0
			continue
		d["peer"] = int(others[i]["peer"])
		d["name"].text = str(others[i]["name"])
		d["lead"].visible = int(Net.party.get("leader", 0)) == d["peer"]
		d["panel"].show()
	_tick(true)


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_tick(false)


## Live values: level, hp, distance, origin glyph from the player node.
func _tick(force: bool) -> void:
	if not _header.visible:
		return
	var me := get_tree().get_first_node_in_group("player") as Node3D
	var nodes := {}
	for p in get_tree().get_nodes_in_group("players"):
		nodes[int(p.get("peer_id"))] = p
	for d in _cards:
		if d["peer"] == 0:
			continue
		var st: Dictionary = Net.party_state.get(d["peer"], {})
		var node: Node = nodes.get(d["peer"])
		var hp := int(st.get("hp", 100))
		var lvl := int(st.get("level", 1))
		d["lv"].text = str(lvl)
		d["bar"].value = hp
		d["hp"].text = "%d%%" % hp
		var low := hp <= 30
		var band: Array = PlayerStatus.band_colors(hp / 100.0)
		if band != d.get("band", []) or force:
			d["low"] = low
			d["band"] = band
			d["bar"].add_theme_stylebox_override("fill", UITheme.gradient_fill_box(HP_COLORS if band == PlayerStatus.HP_GREEN else band, 2))
			var c: Color = UITheme.ROSE if low else UITheme.GREEN
			d["panel"].add_theme_stylebox_override("panel", _card_style(c))
			d["ring"].set_meta("stroke", c)
			d["ring"].queue_redraw()
		var pos: Vector3 = node.global_position if node != null else st.get("pos", Vector3.ZERO)
		if me != null and (node != null or st.has("pos")):
			var dist := me.global_position.distance_to(pos)
			d["dist"].text = "%d m" % int(dist) if dist < 1000.0 else "far"
			d["dist"].add_theme_color_override("font_color", UITheme.MUTED if dist <= Net.PARTY_SHARE_RANGE else UITheme.ROSE)
		else:
			d["dist"].text = ""
		if node != null and "appearance" in node:
			var origin := str(node.appearance.get("origin", "Swordsman"))
			d["glyph"].set_glyph(_origin_glyph(origin), UITheme.PARCH)


static func _origin_glyph(origin: String) -> String:
	match origin:
		"Guardian":
			return "shield"
		"Scout":
			return "arrow"
		"Arcanist":
			return "shard"
		_:
			return "sword"
