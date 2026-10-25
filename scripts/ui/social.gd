class_name Social
extends VBoxContainer
## Social layer: slash commands typed into the chat box, the client-side
## ignore list (Settings "ignored") and the Nearby panel (key O) that lists
## everyone online with Invite / Whisper buttons. The server answers /who
## (Net.request_who) at most once per 5 s; the panel reuses the last answer.
##
## Commands: /invite Name · /w Name msg · /p msg · /who · /roll [N]
##           /leave · /kick Name · /ignore Name · /unignore Name · /help

signal whisper_requested(name: String)

const CHAT_COLORS := {
	"say": Color("f3eee4"),
	"party": UITheme.CYAN,
	"whisper": Color("ff7ad9"),
	"whisper_to": Color("ff7ad9"),
	"system": UITheme.GOLD,
}
const HELP := "Commands: /invite Name, /w Name msg, /p msg, /who, /roll [N], /leave, /kick Name, /ignore Name, /unignore Name"

var _rows: Array = []  # pooled [{"panel","name","meta","tag","invite","whisper"}]
var _list: VBoxContainer
var _summary: Label
var _empty: Label
var _ignored: Label
var _t := 0.0


# --- Commands -----------------------------------------------------------------

## "/w Kyle hi there" -> {"cmd": "w", "target": "Kyle", "text": "hi there"}.
## Plain text (no leading slash) -> {"cmd": "say", "text": ...}. Unknown
## commands come back as {"cmd": "?", "text": "<name>"}.
static func parse_command(raw: String) -> Dictionary:
	var t := raw.strip_edges()
	if not t.begins_with("/"):
		return {"cmd": "say", "target": "", "text": t}
	var sp := t.find(" ")
	var cmd := (t.substr(1, sp - 1) if sp > 0 else t.substr(1)).to_lower()
	var rest := t.substr(sp + 1).strip_edges() if sp > 0 else ""
	match cmd:
		"whisper", "tell", "msg":
			cmd = "w"
		"party":
			cmd = "p"
		"inv":
			cmd = "invite"
		"mute":
			cmd = "ignore"
		"unmute":
			cmd = "unignore"
	var out := {"cmd": cmd, "target": "", "text": rest}
	match cmd:
		"w", "invite", "kick", "ignore", "unignore":
			var sp2 := rest.find(" ")
			out["target"] = Net.sanitize_name(rest.substr(0, sp2) if sp2 > 0 else rest)
			out["text"] = rest.substr(sp2 + 1).strip_edges() if sp2 > 0 else ""
		"p", "who", "roll", "leave", "help":
			pass
		_:
			out = {"cmd": "?", "target": "", "text": cmd}
	return out


## Runs a chat line: commands go to Net / the ignore list, anything else is
## handed back through `say` (the HUD's send_chat). `system` prints a line.
static func handle(raw: String, say: Callable, system: Callable) -> void:
	var c := parse_command(raw)
	match c["cmd"]:
		"say":
			if c["text"] != "":
				say.call(c["text"])
		"w":
			if c["target"] == "" or c["text"] == "":
				system.call("Usage: /w Name message")
			else:
				Net.request_whisper(c["target"], c["text"])
		"p":
			if c["text"] == "":
				system.call("Usage: /p message")
			else:
				Net.request_party_chat(c["text"])
		"invite":
			if c["target"] == "":
				system.call("Usage: /invite Name")
			else:
				Net.request_invite(c["target"])
		"kick":
			if c["target"] == "":
				system.call("Usage: /kick Name")
			else:
				Net.request_party_kick(c["target"])
		"leave":
			Net.request_party_leave()
		"who":
			Net.request_who()
		"roll":
			Net.request_roll(int(c["text"]) if c["text"].is_valid_int() else 100)
		"ignore":
			if c["target"] == "":
				system.call("Ignoring: %s" % (", ".join(ignored()) if not ignored().is_empty() else "nobody"))
			else:
				ignore(c["target"])
				system.call("Ignoring %s. /unignore %s to undo." % [c["target"], c["target"]])
		"unignore":
			unignore(c["target"])
			system.call("No longer ignoring %s." % c["target"])
		"help":
			system.call(HELP)
		_:
			system.call("Unknown command /%s.  %s" % [c["text"], HELP])


# --- Ignore list (client side, persisted by Settings) -------------------------

static func ignored() -> Array:
	var v = Settings.data.get("ignored", [])
	return v if v is Array else []


static func is_ignored(name: String) -> bool:
	var n := name.strip_edges().to_lower()
	return n != "" and n in ignored()


static func ignore(name: String) -> void:
	var n := Net.sanitize_name(name).to_lower()
	if n == "" or n == Net.my_name().to_lower():
		return
	var list := ignored().duplicate()
	if not (n in list):
		list.append(n)
		while list.size() > 64:
			list.pop_front()
		Settings.set_value("ignored", list)


static func unignore(name: String) -> void:
	var n := name.strip_edges().to_lower()
	var list := ignored().duplicate()
	if n in list:
		list.erase(n)
		Settings.set_value("ignored", list)


# --- Nearby panel -------------------------------------------------------------

static func build() -> Social:
	var s := Social.new()
	s._build()
	return s


func _build() -> void:
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UITheme.kicker("Climbers online"))
	tv.add_child(UITheme.heading("Nearby", 28))
	head.add_child(tv)
	var refresh_b := UITheme.make_button("Refresh", "chip")
	refresh_b.size_flags_vertical = Control.SIZE_SHRINK_END
	refresh_b.pressed.connect(func(): Net.request_who())
	head.add_child(refresh_b)
	for action in ["nearby", "back"]:
		var cap := UITheme.action_cap(action)
		cap.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(cap)
	var cl := UITheme.subtle("close", 12)
	cl.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(cl)
	add_child(head)
	add_child(UITheme.rule())
	_summary = UITheme.subtle("", 13)
	add_child(_summary)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(620, 380)
	scroll.follow_focus = true
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_empty = UITheme.subtle("Nobody else is on this floor right now.", 15)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD
	_list.add_child(_empty)
	_ignored = UITheme.subtle("", 12)
	add_child(_ignored)
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 8)
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	for pair in [["/w Name", "Whisper"], ["/p", "Party chat"], ["/invite Name", "Invite"], ["/ignore Name", "Mute"], ["/roll", "Dice"]]:
		hint.add_child(UITheme.keycap(pair[0]))
		hint.add_child(UITheme.subtle(pair[1], 12))
		hint.add_child(UITheme.spacer(4))
	add_child(hint)


func _ready() -> void:
	Net.who_received.connect(_on_who)
	Net.party_changed.connect(refresh)


func _on_who(_list: Array) -> void:
	refresh()


func _make_row() -> Dictionary:
	var p := PanelContainer.new()
	p.theme_type_variation = "CardFlat"
	_list.add_child(p)
	_list.move_child(p, _list.get_child_count() - 2)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var icon := UIGlyph.make("sword", UITheme.CYAN, 34, 1.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_l := UITheme.heading("", 18, UITheme.PARCH)
	row.add_child(name_l)
	var tag := UITheme.label("", 10, UITheme.NAVY, true)
	var tag_pill := PanelContainer.new()
	var tps := UITheme.box(UITheme.GREEN, UITheme.GREEN, 999, 1)
	tps.content_margin_left = 8
	tps.content_margin_right = 8
	tps.content_margin_top = 1
	tps.content_margin_bottom = 1
	tag_pill.add_theme_stylebox_override("panel", tps)
	tag_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag_pill.add_child(tag)
	row.add_child(tag_pill)
	v.add_child(row)
	var meta := UITheme.label("", 12, UITheme.CYAN, true)
	v.add_child(meta)
	var invite := UITheme.make_button("Invite", "primary")
	invite.custom_minimum_size = Vector2(96, 34)
	invite.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(invite)
	var whisper := UITheme.make_button("Whisper", "normal")
	whisper.custom_minimum_size = Vector2(96, 34)
	whisper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(whisper)
	var d := {"panel": p, "icon": icon, "name": name_l, "meta": meta, "tag": tag, "tag_pill": tag_pill, "invite": invite, "whisper": whisper, "who": ""}
	invite.pressed.connect(func():
		if d["who"] != "":
			Net.request_invite(d["who"]))
	whisper.pressed.connect(func():
		if d["who"] != "":
			whisper_requested.emit(d["who"])
		)
	_rows.append(d)
	return d


## Called when the panel opens: show the cached list now, ask for a fresh one.
func open() -> void:
	refresh()
	Net.request_who(true)


func refresh() -> void:
	var me := Net.my_name().to_lower()
	var list: Array = Net.who_list.duplicate()
	if list.is_empty():
		list = [{"name": Net.my_name(), "level": GameState.level, "floor": GameState.floor, "party": Net.in_party()}]
	var others := []
	for e in list:
		if str(e["name"]).to_lower() != me:
			others.append(e)
	var party_names := []
	for m in Net.party.get("members", []):
		party_names.append(str(m["name"]).to_lower())
	_summary.text = "%d climber%s on Floor %d%s" % [list.size(), "" if list.size() == 1 else "s", GameState.floor,
		"  ·  your party: %d / %d" % [Net.party_size(), Net.PARTY_MAX] if Net.in_party() else "  ·  click Invite to form a party"]
	_empty.visible = others.is_empty()
	var can_invite := not Net.in_party() or (Net.is_party_leader() and Net.party_size() < Net.PARTY_MAX)
	while _rows.size() < others.size():
		_make_row()
	for i in _rows.size():
		var d: Dictionary = _rows[i]
		if i >= others.size():
			d["panel"].hide()
			d["who"] = ""
			continue
		var e: Dictionary = others[i]
		var n := str(e["name"])
		var mine: bool = n.to_lower() in party_names
		var muted := is_ignored(n)
		d["who"] = n
		d["panel"].show()
		d["name"].text = n
		d["name"].add_theme_color_override("font_color", UITheme.MUTED if muted else UITheme.PARCH)
		d["meta"].text = "Lv %d  ·  Floor %d%s" % [int(e["level"]), int(e["floor"]), "  ·  ignored" if muted else ""]
		d["icon"].set_glyph("sword", UITheme.GREEN if mine else UITheme.CYAN)
		d["tag_pill"].visible = mine or bool(e.get("party", false))
		d["tag"].text = "YOUR PARTY" if mine else "IN A PARTY"
		var tps: StyleBoxFlat = d["tag_pill"].get_theme_stylebox("panel")
		tps.bg_color = UITheme.GREEN if mine else UITheme.MUTED
		tps.border_color = tps.bg_color
		d["invite"].visible = not mine
		d["invite"].disabled = not can_invite or bool(e.get("party", false)) or not Net.online
		d["whisper"].disabled = not Net.online
	var ig := ignored()
	_ignored.text = "Ignoring: %s" % ", ".join(ig) if not ig.is_empty() else "Ignore list empty  ·  /ignore Name"


func focus_first() -> void:
	for d in _rows:
		if d["panel"].visible and not d["invite"].disabled:
			d["invite"].grab_focus()
			return
