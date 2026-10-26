extends Node
## The Monument of Climbers in the Town of First Light: a wall of every
## character the realm has seen, by level. Names glow while that player is
## in the realm, and those who cleared Floor 1 carry a mark. The art (the
## iron hall and the stone face) belongs to the visuals side: any Node3D in
## group "monument" with set_names(entries) gets the list. Reading it with E
## opens the full list as a panel.
##
## Authority (offline / the server) builds the list: on the server from the
## record files on disk (scanned once) plus the live records, offline from
## the one local character. The server sends it to every client (net_names)
## every PUSH_EVERY seconds and to each new peer as it joins.

const PUSH_EVERY := 20.0
const MAX_ENTRIES := 40
const READ_RANGE := 4.0
const SHOWN := 10            # lines in the reading panel

var world: Node3D
var entries: Array = []      # [{name, level, floors, online, permadeath, fallen, fall_text}]
## permadeath: a one-life climber; fallen: false, or its fall info once it fell
## (MonumentArt strikes the name through, as on Aincrad's Monument of Life);
## fall_text: Permadeath.fall_text() for the reading panel.
var _known := {}             # server: lower name -> entry
var _t := 0.0


static func build(w: Node3D) -> Node:
	var n := Node.new()
	n.set_script(load("res://scripts/monument.gd"))
	n.name = "Monument"
	w.add_child(n)
	n.world = w
	return n


func _ready() -> void:
	if Net.online and multiplayer.is_server():
		_scan_disk()
		multiplayer.peer_connected.connect(func(peer: int):
			# The record lands a moment after the connect (Net._on_peer_connected).
			get_tree().create_timer(1.0, false).timeout.connect(func():
				refresh()
				if multiplayer.get_peers().has(peer):
					net_names.rpc_id(peer, entries)))
	if Net.is_authority():
		refresh.call_deferred()


func _process(delta: float) -> void:
	if not Net.is_authority():
		return
	_t += delta
	if _t < PUSH_EVERY:
		return
	_t = 0.0
	refresh()
	if Net.online and multiplayer.is_server():
		net_names.rpc(entries)


## Server: every character record on disk, once (levels refresh from the
## live records as players come and go).
func _scan_disk() -> void:
	var d := DirAccess.open(Net.DB_DIR)
	if d == null:
		return
	for f in d.get_files():
		if not f.ends_with(".json") or _known.size() >= 500:
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(Net.DB_DIR + "/" + f))
		if typeof(data) == TYPE_DICTIONARY and str(data.get("name", "")) != "":
			_note(data, false)


func _note(rec: Dictionary, online: bool) -> void:
	var nm := str(rec.get("name", ""))
	_known[nm.to_lower()] = _entry(nm, int(rec.get("level", 1)), int(rec.get("floors_cleared", 0)), online, Permadeath.rec_on(rec), rec.get("fallen", {}))


static func _entry(nm: String, level: int, floors: int, online: bool, pd: bool, f) -> Dictionary:
	var dead: bool = f is Dictionary and not f.is_empty()
	return {"name": nm, "level": level, "floors": floors, "online": online and not dead, "permadeath": pd,
		"fallen": (f as Dictionary).duplicate() if dead else false, "fall_text": Permadeath.fall_text(f) if dead else ""}


## Rebuilds `entries` and hands them to the monument art.
func refresh() -> void:
	if Net.online and multiplayer.is_server():
		for k in _known:
			_known[k]["online"] = false
		for peer in Net.srv_records:
			_note(Net.srv_records[peer], true)
		entries = sorted(_known.values())
	elif not Net.online:
		entries = [_entry(str(GameState.character.get("name", "Nameless")), GameState.level, GameState.floors_cleared, true,
			Permadeath.is_on(GameState), GameState.fallen)]
	_show()


static func sorted(list: Array) -> Array:
	var out := list.duplicate(true)
	out.sort_custom(func(a, b):
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) > int(b["level"])
		if int(a["floors"]) != int(b["floors"]):
			return int(a["floors"]) > int(b["floors"])
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return out.slice(0, MAX_ENTRIES)


## Server -> client: the realm's list.
@rpc("authority", "call_remote", "reliable")
func net_names(list: Array) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var clean: Array = []
	for e in list.slice(0, MAX_ENTRIES):
		if e is Dictionary:
			var f = e.get("fallen", false)
			clean.append(_entry(str(e.get("name", "")).left(24), int(e.get("level", 1)), int(e.get("floors", 0)),
				bool(e.get("online", false)), bool(e.get("permadeath", false)), f if f is Dictionary else {}))
	entries = clean
	_show()


func _show() -> void:
	if is_inside_tree():
		get_tree().call_group("monument", "set_names", entries)


## The monument node the player can read, or null (nothing built yet / far).
func near(pos: Vector3) -> Node3D:
	for m in get_tree().get_nodes_in_group("monument"):
		if m is Node3D and pos.distance_to(m.global_position) < READ_RANGE:
			return m
	return null


## The panel text: one line per name.
func text() -> String:
	if entries.is_empty():
		return "The stone is blank. No climber has been carved here yet."
	var lines: Array = []
	for i in mini(entries.size(), SHOWN):
		var e: Dictionary = entries[i]
		var fallen := str(e.get("fall_text", ""))
		if fallen != "":
			lines.append("%d. † %s  ·  %s" % [i + 1, e["name"], fallen])
			continue
		lines.append("%d. %s  ·  Lv %d%s%s%s" % [i + 1, e["name"], int(e["level"]), "  ·  Undying" if bool(e.get("permadeath", false)) else "",
			"  ·  Floor 1 cleared" if int(e["floors"]) >= 1 else "", "  (in the realm)" if bool(e["online"]) else ""])
	if entries.size() > SHOWN:
		lines.append("...and %d more carved below." % (entries.size() - SHOWN))
	return "\n".join(lines)
