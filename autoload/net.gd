extends Node
## Networking entry point. Offline by default so single player keeps working.
## One server = one floor instance. Host from the menu, join by IP, or run a
## dedicated server with:  godot --headless -- --server [--port 4433]
##
## Online, the SERVER owns each character's record (user://server_db):
## level, XP, Col, stats, HP, materials, gear, quests, skills, buffs and the
## cottage. Every state-changing action a client takes (mining, crafting,
## fishing, cooking, shopping, quest talks, equipping...) is a request
## (request_action -> net_request_action) the server validates against the
## record and the world (Player.srv_position() vs the vein / NPC / spot), runs
## through the same gameplay code offline uses (Crafting, LifeData, the
## world's quest talks) on a RecordState view of the record, and answers
## with net_apply(kind, {patch, ...}): the client adopts the patch through
## GameState.apply_patch. Movement is policed in Player._server_movement_check.
## Clients send a character + secret token in the join handshake; the token
## must match the record created on first join or the join is refused.

signal connection_failed(reason: String)
signal server_disconnected
## Client: the server answered an action (or refused it: result has "error").
signal action_applied(kind: String, result: Dictionary)
## Everyone: the server announced something realm-wide (unique skill taken,
## last limited slot gone). HUD nodes in group "hud" with realm_announce(text)
## get it too.
signal realm_announced(text: String)

const RecordState := preload("res://scripts/record_state.gd")
## Realm world DB (docs/REALM_DB.md). Preloaded so a fresh checkout needs no
## class cache; use Net.RealmDBScript.holder_key(...) for the statics.
const RealmDBScript := preload("res://scripts/realm_db.gd")

const DEFAULT_PORT := 4433
const MAX_PLAYERS := 30
## The client builds its world before it sends its character; a cold load
## with VRM scenes can take 10-20 s, so give the handshake room.
const AUTH_TIMEOUT := 60.0
const DB_DIR := "user://server_db"
const RECORD_VERSION := 1
## How often the server flushes records and a client sends its snapshot.
const PERSIST_INTERVAL := 60.0
const SNAPSHOT_MIN_INTERVAL_MS := 20000
const MAX_INVENTORY := 60
const LEVEL_CAP := 100
## Per-kind minimum interval between two accepted action requests of a peer.
const RATE_ACTION_MS := {"craft": 400, "cook": 400, "eat": 250, "crystal": 500, "repair": 400, "buy": 400, "buy_home": 1000, "mine": 700, "herb": 400,
	"cast": 1500, "land": 800, "talk": 400, "store": 150, "place": 300, "rest": 2000, "spend_point": 100, "equip": 150,
	"unequip": 150, "enter_labyrinth": 1000, "duel": 400}
const RATE_ACTION_DEFAULT_MS := 250
## Slack added to every server-side range check (sync lag, srv_position lag).
const RANGE_SLACK := 2.5

## World geometry the server knows about, so movement checks can tell a
## legal teleport (pad, gate, respawn) from a cheat. The Floor 1 defaults
## below are replaced by what the live world scene exposes (_pads, TOWER_POS,
## ARENA_POS, LAB_LEVELS, FLOOR_RADIUS, GameState.spawn_point) in
## _refresh_geometry(), so a floor that moves its tower keeps working.
const FLOOR_RADIUS := 90.0
const TOWER_POS := Vector3(0, 0, -70)
const TOWER_REACH := 50.0  # terraces (30 m out, r 14) and bridges hang off the tower
const SAFE_DESTINATIONS: Array[Vector3] = [
	Vector3(0, 1, 6),          # town plaza: spawn, respawn, exit portal, "Descend to town" pads
	Vector3(30, 71, -61),      # Labyrinth gate -> Terrace 1 (LAB_LEVELS[0] + (0,1,9))
	Vector3(-30, 141, -61),    # Terrace 2 pads (LAB_LEVELS[1] + (0,1,9))
	Vector3(0, 223, -58),      # summit (ARENA_POS + (0,1,12))
]
const SAFE_DESTINATION_TOLERANCE := 3.0
static var _geo_dests: Array = []
static var _geo_tower := TOWER_POS
static var _geo_radius := FLOOR_RADIUS
static var _geo_scene_id := 0

var online := false
var dedicated := false
var port := DEFAULT_PORT
## Server only: characters received during the join handshake, by peer id.
var pending_characters := {}
## Client: secret that proves this install owns its name on a server. Lives
## in the save file (SaveSystem writes/reads "net_token").
var client_token := ""
## Client: why the last connection ended, when the server told us.
var last_error := ""
## Server only: live record per connected peer (see _new_record for keys).
var srv_records := {}
var _pending_records := {}
var _last_snapshot_ms := {}
var _reject_reason := ""
var _persist_timer: Timer
var _life_timer: Timer
## Server: per-peer cooldowns of world objects ("vein:3", "herb:7" -> until ms).
var _srv_cd := {}
## Server: one-shot log guards per peer ("snapshot", "report").
var _srv_warned := {}
## Client: last request time per kind (self rate limit so a held key cannot
## flood the server into dropping our real requests).
var _last_req_ms := {}
## Realm world DB: open on the server (host()) and lazily offline / on the
## listen host (realm "local"); always null on a remote client. Use
## get_realm() rather than reading this directly.
var realm = null
## Realm id of this server (`--realm <id>`; several floor servers that share a
## user:// folder and this id share one world DB). Offline uses "local".
var realm_id := "server"


func _ready() -> void:
	multiplayer.connection_failed.connect(func():
		_go_offline()
		connection_failed.emit("Could not reach the server."))
	multiplayer.server_disconnected.connect(func():
		_go_offline()
		server_disconnected.emit())
	multiplayer.peer_authentication_failed.connect(func(peer):
		pending_characters.erase(peer)
		_pending_records.erase(peer)
		if multiplayer.is_server():
			print("[net] peer %d failed the join handshake (timeout or dropped)" % peer)
		if not multiplayer.is_server() and peer == 1:
			# Deferred: the engine is still inside its poll of the peer we
			# are about to replace, so tearing it down here crashes.
			_on_join_refused.call_deferred()
		elif not multiplayer.is_server():
			print("[net] auth of peer %d failed (ignored on a client)" % peer))
	# With an auth_callback set, a client also sees the other clients as
	# pending peers; they never send anything, so admit them right away.
	multiplayer.peer_authenticating.connect(func(peer):
		if online and not multiplayer.is_server() and peer != 1:
			multiplayer.complete_auth(peer))
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
		elif args[i] == "--token" and i + 1 < args.size():
			client_token = args[i + 1].left(64)
		elif args[i] == "--realm" and i + 1 < args.size():
			realm_id = args[i + 1].validate_filename().left(32)
		elif args[i] == "--quit-after" and i + 1 < args.size():
			# Test hook: leave cleanly (snapshot + disconnect) after N seconds.
			get_tree().create_timer(float(args[i + 1])).timeout.connect(func():
				print("Quitting (--quit-after)")
				leave()
				get_tree().quit())
	dedicated = "--server" in args
	_persist_timer = Timer.new()
	_persist_timer.wait_time = PERSIST_INTERVAL
	_persist_timer.autostart = true
	_persist_timer.timeout.connect(_on_persist_tick)
	add_child(_persist_timer)
	_life_timer = Timer.new()
	_life_timer.wait_time = 1.0
	_life_timer.autostart = true
	_life_timer.timeout.connect(_on_life_tick)
	add_child(_life_timer)
	_party_setup()


func _on_join_refused() -> void:
	var why := _reject_reason if _reject_reason != "" else "The server did not accept the connection."
	last_error = why
	print("Join refused: %s" % why)
	_go_offline()
	connection_failed.emit(why)
	server_disconnected.emit()


func is_server() -> bool:
	return not online or multiplayer.is_server()


## True when this peer should run world simulation (mob AI, loot, boss).
func is_authority() -> bool:
	return not online or multiplayer.is_server()


func host(p := DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p, MAX_PLAYERS)
	if err != OK:
		connection_failed.emit("Could not open port %d (%s)." % [p, error_string(err)])
		return false
	multiplayer.multiplayer_peer = peer
	# Peers are only admitted (and sent the world's spawns) once their world
	# scene exists and has sent its character through send_auth().
	multiplayer.auth_callback = _on_auth
	multiplayer.auth_timeout = AUTH_TIMEOUT
	online = true
	port = p
	DirAccess.make_dir_recursive_absolute(DB_DIR)
	_open_realm(realm_id)
	return true


## Server: the client's handshake payload {"character": {...}, "token": "..."}.
func _on_auth(peer: int, data: PackedByteArray) -> void:
	var v = bytes_to_var(data)
	if typeof(v) != TYPE_DICTIONARY:
		_reject(peer, "Bad handshake (%s, %d bytes)." % [type_string(typeof(v)), data.size()])
		return
	var raw_char = v.get("character", v)
	var character := sanitize_character(raw_char if raw_char is Dictionary else {})
	var token := str(v.get("token", ""))
	if not _token_ok(token):
		_reject(peer, "Bad token.")
		return
	for other in srv_records:
		if srv_records[other]["name"].to_lower() == character["name"].to_lower():
			_reject(peer, "%s is already online here." % character["name"])
			return
	var rec := load_record(character["name"])
	if rec.is_empty():
		rec = _new_record(character, token, v.get("stats", {}))
		print("[db] new character '%s' (peer %d)" % [character["name"], peer])
	elif rec.get("token", "") != token:
		print("[db] token mismatch for '%s' from peer %d" % [character["name"], peer])
		_reject(peer, "The name '%s' belongs to another player on this server." % character["name"])
		return
	rec["character"] = character
	rec["last_peer"] = peer
	_realm_check_record(rec)
	pending_characters[peer] = character
	_pending_records[peer] = rec
	multiplayer.complete_auth(peer)


func _reject(peer: int, reason: String) -> void:
	print("[net] refusing peer %d: %s" % [peer, reason])
	# Tell the client why, then drop it a moment later so the reason is
	# delivered and processed before the disconnect arrives.
	multiplayer.send_auth(peer, var_to_bytes({"reject": reason}))
	get_tree().create_timer(0.5).timeout.connect(func():
		if online and multiplayer.multiplayer_peer and multiplayer.get_authenticating_peers().has(peer):
			multiplayer.multiplayer_peer.disconnect_peer(peer))


static func _token_ok(token: String) -> bool:
	if token.length() < 16 or token.length() > 64:
		return false
	for c in token:
		if not ("0123456789abcdefABCDEF".contains(c)):
			return false
	return true


## Never trust a client's character dictionary: whitelist keys and clamp values.
static func sanitize_character(c: Dictionary) -> Dictionary:
	var out := {}
	var hex := RegEx.create_from_string("^[0-9a-fA-F]{6}$")
	out["name"] = str(c.get("name", "Nameless")).strip_edges().left(16)
	if out["name"] == "":
		out["name"] = "Nameless"
	out["origin"] = str(c.get("origin", "Swordsman")).left(24)
	if not GameState.ORIGINS.has(out["origin"]):
		out["origin"] = "Swordsman"
	for key in ["hair_color", "skin_color", "eye_color", "outfit_color"]:
		var val := str(c.get(key, "888888"))
		out[key] = val if hex.search(val) else "888888"
	var body := str(c.get("body", "alicia")).left(16)
	out["body"] = body if VRMCharacter.BODIES.has(body) or body == "classic" else "alicia"
	out["hair_style"] = clampi(int(c.get("hair_style", 0)), 0, CharacterModel.HAIR_STYLES.size() - 1)
	out["height"] = clampf(float(c.get("height", 1.0)), 0.85, 1.15)
	return out


## Joining is a two-step handshake: on connect the server shows up as a
## pending peer (peer_authenticating), the client loads the world and sends its
## character with send_auth(), and the server admits it. Both sides need an
## auth_callback for the handshake to exist at all.
func join(ip: String, p := DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, p)
	if err != OK:
		connection_failed.emit("Bad address (%s)." % error_string(err))
		return false
	_reject_reason = ""
	last_error = ""
	ensure_token()
	multiplayer.auth_callback = func(_peer: int, data: PackedByteArray):
		var v = bytes_to_var(data)
		if v is Dictionary and v.has("reject"):
			_reject_reason = str(v["reject"]).left(120)
	multiplayer.auth_timeout = AUTH_TIMEOUT
	multiplayer.multiplayer_peer = peer
	online = true
	return true


## Makes sure this client has a secret token and that it is on disk.
## Test clients (--join --name X) derive theirs from the name so a bot can
## reconnect across runs; a real client gets random bytes saved in slot 0.
func ensure_token() -> void:
	if client_token != "":
		return
	var args := OS.get_cmdline_user_args()
	if "--join" in args:
		client_token = ("bot:" + str(GameState.character.get("name", "Bot"))).sha256_text().left(32)
		return
	client_token = Crypto.new().generate_random_bytes(16).hex_encode()
	SaveSystem.store_token(0)


## Called by the world scene on a client once it exists and can receive spawns.
func send_character(character: Dictionary) -> void:
	ensure_token()
	multiplayer.send_auth(1, var_to_bytes({
		"character": character, "token": client_token, "stats": GameState.stats}))
	multiplayer.complete_auth(1)


func leave() -> void:
	if online and not multiplayer.is_server():
		request_save()
	_go_offline()


func _go_offline() -> void:
	if online and multiplayer.multiplayer_peer and multiplayer.is_server():
		save_all_records()
	if realm != null:
		realm.close()  # compacts; the offline "local" realm reopens lazily
		realm = null
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	multiplayer.auth_callback = Callable()
	pending_characters.clear()
	_pending_records.clear()
	srv_records.clear()
	_last_snapshot_ms.clear()
	_srv_cd.clear()
	_srv_warned.clear()
	_last_req_ms.clear()
	online = false
	_party_reset()


# --- Server-side character records ------------------------------------------

static func record_path(name: String) -> String:
	return "%s/%s.json" % [DB_DIR, name.to_lower().sha256_text().left(24)]


static func load_record(name: String) -> Dictionary:
	var path := record_path(name)
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or str(data.get("token", "")) == "":
		push_warning("[db] corrupt record %s" % path)
		return {}
	data["level"] = clampi(int(data.get("level", 1)), 1, LEVEL_CAP)
	data["xp"] = maxi(int(data.get("xp", 0)), 0)
	fill_record_defaults(data)
	return data


## Fields a record must carry (older records on disk gain them on load).
static func record_defaults() -> Dictionary:
	var mats := {}
	for m in GameState.MATERIAL_NAMES:
		mats[m] = 0
	return {
		"money": 50, "stat_points": 0, "materials": mats, "inventory": [], "equipped": {"weapon": null, "armor": null},
		"quests": {}, "smithing_level": 1, "smithing_xp": 0, "items_crafted": 0, "hidden_class": "", "floors_cleared": 0,
		"weapon_atk": 0.0, "recipes_unlocked": [], "fishing_level": 1, "fishing_xp": 0, "cooking_level": 1, "cooking_xp": 0, "farming_level": 1, "farming_xp": 0,
		"fish_caught": 0, "home_owned": false, "home_storage": [], "home_furniture": ["", "", "", "", "", ""],
		"decor_owned": {}, "buffs": {}, "hp": 100.0, "title": "", "visited": [], "chests": {},
		"unique_skill": "", "hidden": {}, "duels": {"won": 0, "lost": 0}, "sword_prof": 0,
	}


static func fill_record_defaults(rec: Dictionary) -> void:
	var d := record_defaults()
	if not rec.has("sword_prof"):
		rec["sword_prof"] = GameState.prof_for_level(int(rec.get("level", 1)))
	for k in d:
		if not rec.has(k) or typeof(rec[k]) != typeof(d[k]):
			rec[k] = d[k]
	for m in d["materials"]:
		if not rec["materials"].has(m):
			rec["materials"][m] = 0
	while rec["home_furniture"].size() < GameState.HOME_SLOTS:
		rec["home_furniture"].append("")
	for slot in ["weapon", "armor"]:
		if not rec["equipped"].has(slot):
			rec["equipped"][slot] = null


## Atomic: the record is written to a temp file and renamed over the old
## one, so a crash mid-write leaves the previous record, never a torn one.
static func save_record(rec: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DB_DIR)
	rec["saved"] = int(Time.get_unix_time_from_system())
	var path := record_path(rec["name"])
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		push_error("[db] cannot write record for %s: %s" % [rec["name"], FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(rec, "\t"))
	f.flush()
	f.close()
	var err := DirAccess.rename_absolute(path + ".tmp", path)
	if err != OK:
		push_error("[db] cannot replace record for %s: %s" % [rec["name"], error_string(err)])
		return false
	return true


func _new_record(character: Dictionary, token: String, claimed_stats) -> Dictionary:
	var base: Dictionary = GameState.ORIGINS.get(character["origin"], GameState.ORIGINS["Swordsman"]).duplicate()
	var stats := base.duplicate()
	# First join: accept the creator's 5 bonus points if the claim adds up.
	if claimed_stats is Dictionary:
		var extra := 0
		var ok := true
		var claim := {}
		for s in GameState.STAT_NAMES:
			claim[s] = int(claimed_stats.get(s, base[s]))
			if claim[s] < base[s]:
				ok = false
			extra += claim[s] - base[s]
		if ok and extra <= GameState.CREATOR_POINTS:
			stats = claim
	var rec := record_defaults()
	rec.merge({
		"version": RECORD_VERSION,
		"name": character["name"],
		"token": token,
		"character": character,
		"level": 1,
		"xp": 0,
		"stats": stats,
		"created": int(Time.get_unix_time_from_system()),
	}, true)
	RecordState.new(rec).heal_full()
	return rec


## What the client adopts on join: the record minus server-only fields.
static func snapshot_for_client(rec: Dictionary) -> Dictionary:
	var snap := rec.duplicate(true)
	for k in ["token", "weapon_atk", "created", "saved", "last_peer", "position", "_fish", "hidden"]:
		snap.erase(k)
	# Buffs carry an absolute expiry on the server; the client counts down.
	var now := Time.get_unix_time_from_system()
	var buffs := {}
	for id in rec.get("buffs", {}):
		var b: Dictionary = rec["buffs"][id]
		var left := float(b.get("until", 0.0)) - now
		if left > 0.0:
			buffs[id] = {"name": b.get("name", id), "left": left, "regen": b.get("regen", 0.0), "atk": b.get("atk", 0.0),
				"speed": b.get("speed", 0.0), "color": b.get("color", "f0c060")}
	snap["buffs"] = buffs
	return snap


## The progress fields a client adopts after a server-side action
## (GameState.apply_patch): the join snapshot without looks.
static func patch_for_client(rec: Dictionary) -> Dictionary:
	var p := snapshot_for_client(rec)
	for k in ["character", "name", "version", "floor"]:
		p.erase(k)
	return p


func _on_peer_connected(peer: int) -> void:
	if not online or not multiplayer.is_server():
		return
	var rec: Dictionary = _pending_records.get(peer, {})
	_pending_records.erase(peer)
	if rec.is_empty():
		return
	srv_records[peer] = rec
	RecordState.new(rec).heal_full()  # the client heals on adopt too
	save_record(rec)
	net_adopt_snapshot.rpc_id(peer, snapshot_for_client(rec))
	print("[db] peer %d is '%s' Lv %d (%d xp)" % [peer, rec["name"], rec["level"], rec["xp"]])


func _on_peer_disconnected(peer: int) -> void:
	pending_characters.erase(peer)
	_pending_records.erase(peer)
	_last_snapshot_ms.erase(peer)
	if online and multiplayer.is_server():
		_srv_leave_party(peer, "disconnected from")
		srv_invites.erase(peer)
		srv_hp.erase(peer)
		_rate.erase(peer)
		_srv_cd.erase(peer)
		_srv_warned.erase(peer)
	if srv_records.has(peer):
		var rec: Dictionary = srv_records[peer]
		srv_records.erase(peer)
		save_record(rec)
		if realm != null:
			realm.touch(RealmDBScript.holder_of_record(rec))
		print("[db] saved '%s' Lv %d on disconnect" % [rec["name"], rec["level"]])


func save_all_records() -> void:
	for peer in srv_records:
		save_record(srv_records[peer])


func _on_persist_tick() -> void:
	if not online:
		return
	if multiplayer.is_server():
		save_all_records()
		if realm != null:
			for peer in srv_records:
				realm.touch(RealmDBScript.holder_of_record(srv_records[peer]))
			realm.sweep()
			realm.flush()
	else:
		request_save()


# --- Realm world DB (server / offline) --------------------------------------------

func _open_realm(id: String) -> void:
	if realm != null:
		realm.close()
	realm = RealmDBScript.open(id)
	realm.announce = srv_announce
	print("[realm] '%s' open (seq %d, %d claim(s), %d container(s))" % [id, realm.data["seq"], realm.data["claims"].size(), realm.data["containers"].size()])


## The realm DB for server-side and offline code; null on a remote client.
func get_realm():
	if remote_client():
		return null
	if realm == null:
		_open_realm(realm_id if online else "local")
	return realm


## Holder key of a connected peer's record ("" when unknown). Offline / host
## without a record: local_holder().
func srv_holder(peer: int) -> String:
	if srv_records.has(peer):
		return RealmDBScript.holder_of_record(srv_records[peer])
	if peer == 1 and (not online or (multiplayer.is_server() and not dedicated)):
		return local_holder()
	return ""


## Holder key of this install's character when it plays offline (or hosts).
func local_holder() -> String:
	return RealmDBScript.holder_key("", str(GameState.character.get("name", "Nameless")))


## Record load: replay pending escrow onto the record, then drop items whose
## serials the registry does not know (dupes, foreign copies).
func _realm_check_record(rec: Dictionary) -> void:
	var rdb = get_realm()
	if rdb == null:
		return
	var applied: int = rdb.reconcile_record(rec)
	var removed: Array = rdb.verify_record(rec)
	# Market stacks (scripts/life/stalls.gd) never stay packed on a record.
	if preload("res://scripts/life/stalls.gd").unpack_stacks(rec):
		applied += 1
	var holder: String = RealmDBScript.holder_of_record(rec)
	rdb.touch(holder)
	# A unique skill lost to inactivity (or taken while away) is gone for good.
	var us := str(rec.get("unique_skill", ""))
	if us != "" and not UniqueSkills.holds(rdb, us, holder):
		print("[realm] '%s' no longer holds %s" % [rec["name"], us])
		rec["unique_skill"] = ""
		removed.append(us)
	if applied > 0 or not removed.is_empty():
		print("[realm] record '%s': %d trade(s) reconciled, %d item(s) removed" % [rec["name"], applied, removed.size()])
		save_record(rec)


## Server: one escrow transaction for a connected peer (see RealmDB.transact):
## validates and journals the moves, saves the record, settles, and answers the
## client with the patch. Returns the RealmDB result.
func srv_transact(peer: int, moves: Array, reply_kind := "trade") -> Dictionary:
	if not srv_records.has(peer):
		return {"ok": false, "error": "No record."}
	var rdb = get_realm()
	if rdb == null:
		return {"ok": false, "error": "No realm."}
	var rec: Dictionary = srv_records[peer]
	var res: Dictionary = rdb.transact(rec, moves)
	if not res.get("ok", false):
		_send(peer, net_apply, [reply_kind, {"error": str(res.get("error", "Refused."))}])
		return res
	RecordState.new(rec)._sync_weapon()
	if save_record(rec):
		rdb.settle(int(res["seq"]))
	_srv_reply(peer, reply_kind, {"seq": res["seq"]})
	return res


## Server: a character is deleted; frees its claims, serials, containers and
## removes the record (token must match). Returns what the realm released.
func srv_delete_character(name: String, token: String) -> Dictionary:
	var rec := load_record(name)
	if rec.is_empty() or str(rec.get("token", "")) != token:
		return {"ok": false, "error": "No such character or wrong token."}
	for peer in srv_records.keys():
		if str(srv_records[peer]["name"]).to_lower() == name.to_lower():
			kick(peer, "Character deleted")
			srv_records.erase(peer)
	var released: Array = []
	var rdb = get_realm()
	if rdb != null:
		var holder: String = RealmDBScript.holder_of_record(rec)
		load("res://scripts/life/guilds.gd").forget_holder(rdb, holder)
		released = rdb.release_all(holder)
	DirAccess.remove_absolute(record_path(name))
	print("[db] deleted character '%s' (%d realm claim(s) freed)" % [name, released.size()])
	return {"ok": true, "released": released}


## Server / offline: tell everyone on the realm. Clients get net_realm_announce;
## the host and offline player get it directly.
## A hidden-stat event ("dodge", "kill") for the player with `peer`:
## offline the local GameState, on the server that peer's record. Clients do
## nothing (they never see or report hidden stats).
func note_hidden(peer: int, event: String) -> void:
	if not online or (multiplayer.is_server() and peer == multiplayer.get_unique_id() and not srv_records.has(peer)):
		GameState.note_hidden(event)
	elif multiplayer.is_server():
		srv_note_hidden(peer, event)


func srv_note_hidden(peer: int, event: String) -> void:
	if not srv_records.has(peer):
		return
	var rec: Dictionary = srv_records[peer]
	if not (rec.get("hidden") is Dictionary):
		rec["hidden"] = {}
	# Hidden-class deeds (HiddenClasses): a parry while the Stillblade quest
	# is open moves the quest, so the client gets a patch for that one.
	var quests_before := var_to_str(rec["quests"])
	HiddenClasses.note(RecordState.new(rec), event)
	if var_to_str(rec["quests"]) != quests_before:
		_srv_reply(peer, "quest", {})
	if not UniqueSkills.note(rec["hidden"], event, Time.get_ticks_msec() / 1000.0):
		return
	var id := UniqueSkills.try_grant(get_realm(), srv_holder(peer), int(rec.get("level", 1)), rec["hidden"], str(rec.get("unique_skill", "")))
	if id == "":
		return
	rec["unique_skill"] = id
	save_record(rec)
	print("[realm] '%s' awakened %s" % [rec["name"], id])
	srv_announce(UniqueSkills.announce_text(str(rec["name"]), id))
	if peer == multiplayer.get_unique_id():
		GameState.unique_skill = id
		GameState.unique_skill_changed.emit(id)
	else:
		_srv_reply(peer, "unique_skill", {"skill": id})


## Server / offline: the hidden class of the player with `peer` ("" none).
## Remote players come from their record; the host and offline play from
## GameState. Checked on every class art hit (Enemy.net_hit).
func srv_hidden_class(peer: int) -> String:
	if srv_records.has(peer):
		var hc := str(srv_records[peer].get("hidden_class", ""))
		return hc if GameState.HIDDEN_CLASSES.has(hc) else ""
	if not online or peer == multiplayer.get_unique_id():
		return GameState.hidden_class
	return ""


## Server / offline: a class art landed and grants its caster a buff
## (Hearth Flare's glow). Records get it with an expiry and a patch; the
## host and offline player get it on GameState.
func srv_class_buff(peer: int, id: String, data: Dictionary) -> void:
	if srv_records.has(peer):
		RecordState.new(srv_records[peer]).add_buff(id, float(data.get("dur", 0.0)), data)
		_srv_reply(peer, "buffs", {})
	elif not online or peer == multiplayer.get_unique_id():
		GameState.add_buff(id, float(data.get("dur", 0.0)), data)


## Server / offline: may the player with `peer` use unique skill `id` now?
func srv_holds_unique(peer: int, id: String) -> bool:
	if not online:
		var ok := GameState.unique_skill == id and UniqueSkills.holds(get_realm(), id, local_holder())
		if not ok and GameState.unique_skill == id:
			GameState.unique_skill = ""
			GameState.unique_skill_changed.emit("")
		return ok
	if not srv_records.has(peer):
		# The listen-server host plays from GameState.
		return peer == multiplayer.get_unique_id() and GameState.unique_skill == id \
			and UniqueSkills.holds(get_realm(), id, local_holder())
	return str(srv_records[peer].get("unique_skill", "")) == id and UniqueSkills.holds(get_realm(), id, srv_holder(peer))


func srv_announce(text: String) -> void:
	text = sanitize_text(text, 160)
	print("[realm] announce: %s" % text)
	if online and multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		for p in multiplayer.get_peers():
			net_realm_announce.rpc_id(p, text)
		if not dedicated:
			_deliver_announce(text)
	elif not online:
		_deliver_announce(text)


func _deliver_announce(text: String) -> void:
	realm_announced.emit(text)
	_system(text)
	if get_tree() != null:
		for n in get_tree().get_nodes_in_group("hud"):
			if n.has_method("realm_announce"):
				n.realm_announce(text)


@rpc("authority", "call_remote", "reliable")
func net_realm_announce(text: String) -> void:
	if not _from_server():
		return
	_deliver_announce(sanitize_text(text, 160))


## Client: push a snapshot of the client-held parts of the character
## (inventory, materials, quests...) to the server. Level/XP stay server-side.
func request_save() -> void:
	if online and not multiplayer.is_server() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		net_client_snapshot.rpc_id(1, GameState.to_dict())


static func xp_to_next(level: int) -> int:
	# Same curve as GameState.xp_to_next().
	return int(100 + 50 * (level - 1) + 25 * pow(level - 1, 1.6))


## Adds xp to a record and levels it with GameState's curve. Returns the
## number of levels gained.
static func level_record(rec: Dictionary, xp: int) -> int:
	rec["xp"] = int(rec["xp"]) + maxi(xp, 0)
	var before: int = rec["level"]
	while rec["level"] < LEVEL_CAP and rec["xp"] >= xp_to_next(rec["level"]):
		rec["xp"] -= xp_to_next(rec["level"])
		rec["level"] += 1
		rec["stat_points"] = int(rec.get("stat_points", 0)) + GameState.POINTS_PER_LEVEL
	return int(rec["level"]) - before


## Server: a mob died to `peer`. Mirrors GameState.add_xp on the record.
func srv_grant_reward(peer: int, xp: int, money: int) -> void:
	if not srv_records.has(peer):
		return
	var rec: Dictionary = srv_records[peer]
	rec["money"] = maxi(int(rec["money"]) + money, 0)
	if level_record(rec, xp) > 0:
		RecordState.new(rec).heal_full()
		print("[db] '%s' reached Lv %d" % [rec["name"], rec["level"]])
		save_record(rec)
		_send(peer, net_hp, [float(rec["hp"]), RecordState.new(rec).max_hp()])


func srv_level(peer: int) -> int:
	return int(srv_records[peer]["level"]) if srv_records.has(peer) else 1


## Highest a single stat can legitimately be at this level: best origin value
## plus the creator's points, the hidden class bonus and 3 points per level.
static func stat_cap(level: int) -> int:
	return 4 + GameState.CREATOR_POINTS + 3 + GameState.POINTS_PER_LEVEL * (level - 1)


## Highest attack any craftable weapon of this rank can roll (Crafting
## recipe base x RANK_MULT x the 1.15 roll ceiling).
static func weapon_atk_cap(rank: int) -> float:
	rank = clampi(rank, 0, Crafting.RANK_MULT.size() - 1)
	var base := 0.0
	for r in Crafting.RECIPES.values():
		if r["kind"] == "weapon":
			base = maxf(base, float(r["base"]))
	return ceilf(base * Crafting.RANK_MULT[rank] * 1.15)


## Same formula as GameState.attack_damage(), fed from the server record:
## stats, level and equipped weapon of the record, times the food buffs the
## server itself applied (eat / rest actions).
func srv_attack_for(peer: int) -> float:
	if not srv_records.has(peer):
		return 1.0
	var rec: Dictionary = srv_records[peer]
	var rs = RecordState.new(rec)
	var strength: int = clampi(int(rec["stats"].get("strength", 0)), 0, stat_cap(rec["level"]))
	return (8.0 + strength * 3.0 + float(rec["level"]) + rs.weapon_attack()) * (1.0 + rs.buff_value("atk"))


## Server: the owner reported its strength and equipped weapon
## (Player.net_report_stats). Stats and gear live on the record now, so the
## report is only compared with it and a mismatch logged once per peer.
func srv_set_reported(peer: int, strength: int, weapon_atk: float, _weapon_rank: int) -> void:
	if not srv_records.has(peer):
		return
	var rec: Dictionary = srv_records[peer]
	var have_str := int(rec["stats"].get("strength", 0))
	var have_w := RecordState.new(rec).weapon_attack()
	if (strength != have_str or absf(weapon_atk - have_w) > 0.5) and _warn_once(peer, "report"):
		print("[anticheat] peer %d (%s) reports strength %d / weapon %.0f, record has %d / %.0f; report ignored" % [
			peer, rec["name"], strength, weapon_atk, have_str, have_w])


func _warn_once(peer: int, key: String) -> bool:
	var w: Dictionary = _srv_warned.get(peer, {})
	if w.has(key):
		return false
	w[key] = true
	_srv_warned[peer] = w
	return true


## Server: a client snapshot arrived. Nothing in it is adopted any more: the
## record is the truth for every field it carries (actions mutate it on the
## server). The snapshot is audited against the record so a modified client
## claiming 99,999 Col or a stack of koi shows up in the log, and the record
## is persisted (the snapshot doubles as the client's "save now" request).
func srv_apply_snapshot(peer: int, snap: Dictionary) -> void:
	if not srv_records.has(peer):
		return
	var rec: Dictionary = srv_records[peer]
	var claims := []
	if snap.has("money") and int(snap["money"]) != int(rec["money"]):
		claims.append("%d col (record %d)" % [int(snap["money"]), int(rec["money"])])
	if snap.has("level") and int(snap["level"]) != int(rec["level"]):
		claims.append("Lv %d (record %d)" % [int(snap["level"]), int(rec["level"])])
	var raw_mats = snap.get("materials", {})
	if raw_mats is Dictionary:
		for m in raw_mats:
			if int(raw_mats[m]) > int(rec["materials"].get(m, 0)):
				claims.append("%d %s (record %d)" % [int(raw_mats[m]), m, int(rec["materials"].get(m, 0))])
	var raw_inv = snap.get("inventory", [])
	if raw_inv is Array and raw_inv.size() > rec["inventory"].size():
		claims.append("%d items (record %d)" % [raw_inv.size(), rec["inventory"].size()])
	if not claims.is_empty():
		print("[anticheat] peer %d (%s) snapshot claims %s; snapshot ignored, record kept" % [peer, rec["name"], ", ".join(claims)])


## Server: drop a peer with a reason it can show.
func kick(peer: int, reason: String) -> void:
	if not online or not multiplayer.is_server() or not multiplayer.get_peers().has(peer):
		return
	var who: String = srv_records[peer]["name"] if srv_records.has(peer) else "?"
	print("[anticheat] kicked peer %d (%s): %s" % [peer, who, reason])
	net_kicked.rpc_id(peer, reason)
	multiplayer.multiplayer_peer.disconnect_peer(peer)
	# The node lives until peer_disconnected; stop mobs and checks from
	# sending to a peer that is already going away.
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.get("peer_id")) == peer:
			p.remove_from_group("players")
			p.set_physics_process(false)


# --- Movement helpers (server) ------------------------------------------------

## Reads the live world's teleport targets and geometry once per scene,
## through get() so there is no compile-time dependency on world.gd.
func _refresh_geometry() -> void:
	var w := get_tree().current_scene
	if w == null or w.get_instance_id() == _geo_scene_id:
		return
	var dests: Array = []
	var pads = w.get("_pads")
	if pads is Array:
		for pad in pads:
			if pad is Dictionary and pad.get("dest") is Vector3:
				dests.append(pad["dest"])
	if dests.is_empty():
		return  # not a world scene (menu, smoke test): keep the defaults
	var lab = w.get("LAB_LEVELS")
	if lab is Array and lab.size() > 0 and lab[0] is Vector3:
		dests.append(lab[0] + Vector3(0, 1, 9))
	var arena = w.get("ARENA_POS")
	if arena is Vector3:
		dests.append(arena + Vector3(0, 1, 12))
	dests.append(Vector3(0, 1, 6))
	if GameState.has_method("spawn_point"):
		dests.append(GameState.call("spawn_point"))
	var tower = w.get("TOWER_POS")
	_geo_tower = tower if tower is Vector3 else TOWER_POS
	var radius = w.get("FLOOR_RADIUS")
	_geo_radius = float(radius) if radius != null else FLOOR_RADIUS
	_geo_dests = dests
	_geo_scene_id = w.get_instance_id()
	print("[anticheat] world geometry: %d teleport targets, tower %s, radius %.0f" % [dests.size(), str(_geo_tower), _geo_radius])


## True near a place the game itself teleports players to.
func is_safe_destination(pos: Vector3) -> bool:
	_refresh_geometry()
	var list: Array = _geo_dests if not _geo_dests.is_empty() else SAFE_DESTINATIONS
	for d in list:
		if pos.distance_to(d) <= SAFE_DESTINATION_TOLERANCE:
			return true
	return false


## True inside the playable volume: the island disc, or (high up) the tower
## with its terraces and summit. Falling below the island is allowed down to
## the respawn depth.
func in_world_bounds(pos: Vector3) -> bool:
	_refresh_geometry()
	if pos.y < -40.0 or pos.y > 250.0:
		return false
	if Vector2(pos.x, pos.z).length() > _geo_radius + 6.0:
		return false
	if pos.y > 30.0 and Vector2(pos.x - _geo_tower.x, pos.z - _geo_tower.z).length() > TOWER_REACH:
		return false
	return true


# --- RPCs ---------------------------------------------------------------------

## Server -> joining client: your character as this server knows it.
@rpc("authority", "call_remote", "reliable")
func net_adopt_snapshot(snap: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1 or multiplayer.is_server():
		return
	var keep_char: Dictionary = GameState.character.duplicate()
	GameState.from_dict(snap)
	# Looks come from our own creator; the record only sanitized them.
	GameState.character.merge(keep_char, true)
	GameState.character["name"] = str(snap.get("character", {}).get("name", keep_char.get("name", "")))
	GameState.has_position = false
	GameState.heal_full()
	GameState.stats_changed.emit()
	GameState.xp_changed.emit(GameState.xp, GameState.xp_to_next())
	GameState.money_changed.emit(GameState.money)
	GameState.inventory_changed.emit()
	GameState.quest_changed.emit()
	print("Adopted server character: %s Lv %d (%d xp, %d col)" % [GameState.character["name"], GameState.level, GameState.xp, GameState.money])


## Client -> server: periodic snapshot of the client-held parts of the character.
@rpc("any_peer", "call_remote", "reliable")
func net_client_snapshot(snap: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not srv_records.has(peer):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_snapshot_ms.get(peer, -SNAPSHOT_MIN_INTERVAL_MS)) < SNAPSHOT_MIN_INTERVAL_MS:
		return
	_last_snapshot_ms[peer] = now
	if var_to_bytes(snap).size() > 65536:
		kick(peer, "Oversized snapshot")
		return
	srv_apply_snapshot(peer, snap)
	save_record(srv_records[peer])


## Server -> client: you were dropped, and why.
@rpc("authority", "call_remote", "reliable")
func net_kicked(reason: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	last_error = reason.left(120)
	print("Kicked by server: %s" % last_error)


# --- Party & social (server-authoritative) -----------------------------------
## Parties live on the server only (srv_parties); clients get a description
## of their own party (net_party_update) and a 0.5 s relay of member
## name / level / hp% / position (net_party_state). Every request below is
## an any_peer rpc that resolves its sender itself, rate-limits it and
## answers through net_system; nothing a client sends changes XP, level or
## another player's state directly.

signal party_changed
signal party_invited(from_name: String)
signal chat_received(sender: String, text: String, channel: String)
signal who_received(list: Array)

const PARTY_MAX := 4
const PARTY_BONUS_PER_MEMBER := 0.10
const PARTY_SHARE_RANGE := 60.0
const PARTY_TICK := 0.5
const INVITE_TTL_MS := 30000
const RATE_INVITE_MS := 2000
const RATE_WHISPER_MS := 500
const RATE_WHO_MS := 5000
const RATE_PARTY_CHAT_MS := 500
const RATE_ROLL_MS := 2000
const RATE_HP_MS := 300
const RATE_PARTY_OP_MS := 500

## Server: party id -> {"leader": peer, "members": [peer, ...]}.
var srv_parties := {}
var srv_party_of := {}  # peer -> party id
var srv_invites := {}   # invited peer -> {"from": peer, "ms": int}
var srv_hp := {}        # peer -> hp percent (client-reported, cosmetic only)
var _srv_next_party_id := 1
var _rate := {}         # peer -> {key: last_ms}

## Client: my party as the server last described it:
## {"id": int, "leader": peer, "members": [{"peer": int, "name": String}]}, {} when solo.
var party := {}
## Client: latest relayed state per member peer: {"name", "level", "hp", "pos": Vector3}.
var party_state := {}
## Client: peer -> true for every member of my party (minimap, name tags).
var party_ids := {}
## Client: pending invite {"from": String, "ms": int} or {}.
var pending_invite := {}
## Client: last /who answer: [{"name", "level", "floor", "party": bool}].
var who_list := []
## Test hook (--bot --party): invite whoever is online and accept every invite.
var bot_party := false
var _party_timer: Timer
var _last_hp_sent := -1
var _bot_party_t := 0.0


func _party_setup() -> void:
	bot_party = "--party" in OS.get_cmdline_user_args()
	_party_timer = Timer.new()
	_party_timer.wait_time = PARTY_TICK
	_party_timer.autostart = true
	_party_timer.timeout.connect(_on_party_tick)
	add_child(_party_timer)


func _party_reset() -> void:
	srv_parties.clear()
	srv_party_of.clear()
	srv_invites.clear()
	srv_hp.clear()
	_rate.clear()
	who_list.clear()
	_last_hp_sent = -1
	if not party.is_empty() or not party_state.is_empty() or not pending_invite.is_empty():
		party = {}
		party_state = {}
		party_ids = {}
		pending_invite = {}
		party_changed.emit()


func in_party() -> bool:
	return not party.is_empty()


func party_size() -> int:
	return party.get("members", []).size() if not party.is_empty() else 0


func is_party_leader() -> bool:
	return not party.is_empty() and int(party.get("leader", 0)) == multiplayer.get_unique_id()


func my_name() -> String:
	return str(GameState.character.get("name", ""))


## Printable name: trimmed, 16 chars, no control characters or brackets
## (the chat log is BBCode).
static func sanitize_name(n: String) -> String:
	var out := ""
	for c in n.strip_edges().left(16):
		var code := c.unicode_at(0)
		if code >= 32 and code != 127 and c != "[" and c != "]":
			out += c
	return out.strip_edges()


static func sanitize_text(t: String, max_len := 200) -> String:
	var out := ""
	for c in t.strip_edges().left(max_len):
		var code := c.unicode_at(0)
		if code >= 32 and code != 127:
			out += c
	return out


## Reward split rule: the kill's XP and Col form a pool that grows 10 % per
## extra member in range, split evenly between them (floored, never below
## 1 when the base was positive). 100 xp: solo 100, duo 55 each, trio 40,
## full party 32. Drops and quest credit stay with the killer.
static func party_split(xp: int, money: int, n: int) -> Array:
	n = maxi(n, 1)
	var mult := 1.0 + PARTY_BONUS_PER_MEMBER * float(n - 1)
	var sx := int(floor(float(xp) * mult / float(n)))
	var sm := int(floor(float(money) * mult / float(n)))
	if xp > 0:
		sx = maxi(sx, 1)
	if money > 0:
		sm = maxi(sm, 1)
	return [sx, sm]


func _rate_ok(peer: int, key: String, interval_ms: int) -> bool:
	var now := Time.get_ticks_msec()
	var r: Dictionary = _rate.get(peer, {})
	if now - int(r.get(key, -1000000)) < interval_ms:
		return false
	r[key] = now
	_rate[peer] = r
	return true


# --- Server helpers -----------------------------------------------------------

## True for an admitted client, or for the listen-server host itself (peer 1
## has no record: its GameState is the record).
func _srv_is_online(peer: int) -> bool:
	if srv_records.has(peer):
		return true
	return peer == 1 and online and multiplayer.is_server() and not dedicated


func srv_name_of(peer: int) -> String:
	if srv_records.has(peer):
		return str(srv_records[peer]["name"])
	if peer == 1 and online and multiplayer.is_server() and not dedicated:
		return my_name()
	return ""


func srv_peer_by_name(name: String) -> int:
	var n := sanitize_name(name).to_lower()
	if n == "":
		return 0
	for peer in srv_records:
		if str(srv_records[peer]["name"]).to_lower() == n:
			return peer
	if not dedicated and online and multiplayer.is_server() and my_name().to_lower() == n:
		return 1
	return 0


func _srv_level_of(peer: int) -> int:
	if srv_records.has(peer):
		return int(srv_records[peer]["level"])
	return GameState.level if peer == 1 else 1


func _srv_player_node(peer: int) -> Node:
	if get_tree() == null:
		return null
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.get("peer_id")) == peer:
			return p
	return null


## Where the server believes `peer` stands, or null without a player node.
func _srv_player_pos(peer: int) -> Variant:
	var node := _srv_player_node(peer)
	if node == null:
		return null
	return node.srv_position() if node.has_method("srv_position") else node.global_position


## Server: run a server->client handler for `peer`: an rpc for a connected
## client, a direct call for the host itself. Silently skips anyone else
## (a peer that just dropped, or a fake record in the smoke test).
func _send(peer: int, fn: Callable, args: Array) -> void:
	if not online or not multiplayer.is_server():
		return
	if peer == 1:
		if not dedicated:
			fn.callv(args)
	elif multiplayer.get_peers().has(peer):
		Callable(self, "rpc_id").callv([peer, fn.get_method()] + args)


## True when a server->client rpc really came from the server (or is the
## host handling its own request locally).
func _from_server() -> bool:
	var s := multiplayer.get_remote_sender_id()
	return s == 1 or (s == 0 and multiplayer.is_server())


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return multiplayer.get_unique_id() if s == 0 else s


func _srv_party_members(peer: int) -> Array:
	var pid := int(srv_party_of.get(peer, 0))
	return srv_parties[pid]["members"].duplicate() if srv_parties.has(pid) else []


func _srv_party_desc(pid: int) -> Dictionary:
	var p: Dictionary = srv_parties[pid]
	var members := []
	for m in p["members"]:
		members.append({"peer": m, "name": srv_name_of(m)})
	return {"id": pid, "leader": p["leader"], "members": members}


func _srv_broadcast_party(pid: int, note := "") -> void:
	if not srv_parties.has(pid):
		return
	var desc := _srv_party_desc(pid)
	for m in srv_parties[pid]["members"]:
		_send(m, net_party_update, [desc])
		if note != "":
			_send(m, net_system, [note])


## Server: `from` invites `target`. Returns "" or the reason it failed.
func _srv_invite(from: int, target: int) -> String:
	if target == 0 or not _srv_is_online(target):
		return "No such player online."
	if target == from:
		return "You cannot invite yourself."
	if srv_party_of.has(target):
		return "%s is already in a party." % srv_name_of(target)
	var pid := int(srv_party_of.get(from, 0))
	if pid != 0:
		if int(srv_parties[pid]["leader"]) != from:
			return "Only the party leader can invite."
		if srv_parties[pid]["members"].size() >= PARTY_MAX:
			return "Your party is full (%d)." % PARTY_MAX
	var now := Time.get_ticks_msec()
	var inv: Dictionary = srv_invites.get(target, {})
	if not inv.is_empty() and now - int(inv["ms"]) < INVITE_TTL_MS and int(inv["from"]) != from:
		return "%s already has a pending invite." % srv_name_of(target)
	srv_invites[target] = {"from": from, "ms": now}
	print("[party] %s invited %s" % [srv_name_of(from), srv_name_of(target)])
	_send(target, net_party_invited, [srv_name_of(from)])
	_send(from, net_system, ["Invited %s to your party." % srv_name_of(target)])
	return ""


## Server: `peer` answers its pending invite.
func _srv_respond(peer: int, accept: bool) -> void:
	var inv: Dictionary = srv_invites.get(peer, {})
	srv_invites.erase(peer)
	if inv.is_empty():
		return
	var from := int(inv["from"])
	if Time.get_ticks_msec() - int(inv["ms"]) > INVITE_TTL_MS:
		_send(peer, net_system, ["That invite has expired."])
		return
	if not accept:
		_send(from, net_system, ["%s declined your invite." % srv_name_of(peer)])
		return
	if not _srv_is_online(from):
		_send(peer, net_system, ["%s is no longer online." % srv_name_of(from)])
		return
	if srv_party_of.has(peer):
		_send(peer, net_system, ["You are already in a party."])
		return
	var pid := int(srv_party_of.get(from, 0))
	if pid == 0:
		pid = _srv_next_party_id
		_srv_next_party_id += 1
		srv_parties[pid] = {"leader": from, "members": [from]}
		srv_party_of[from] = pid
	var p: Dictionary = srv_parties[pid]
	if p["members"].size() >= PARTY_MAX:
		_send(peer, net_system, ["That party is full."])
		return
	p["members"].append(peer)
	srv_party_of[peer] = pid
	print("[party] %s joined party %d (%d members, leader %s)" % [srv_name_of(peer), pid, p["members"].size(), srv_name_of(p["leader"])])
	_srv_broadcast_party(pid, "%s joined the party." % srv_name_of(peer))


## Server: `peer` leaves (or is removed from, or disconnects out of) its
## party. A party with one member left is disbanded; leadership passes to
## the oldest member when the leader goes.
func _srv_leave_party(peer: int, verb := "left") -> void:
	var pid := int(srv_party_of.get(peer, 0))
	if pid == 0 or not srv_parties.has(pid):
		srv_party_of.erase(peer)
		return
	srv_party_of.erase(peer)
	var p: Dictionary = srv_parties[pid]
	p["members"].erase(peer)
	_send(peer, net_party_update, [{}])
	print("[party] %s %s party %d (%d left)" % [srv_name_of(peer), verb, pid, p["members"].size()])
	if p["members"].size() <= 1:
		for m in p["members"]:
			srv_party_of.erase(m)
			_send(m, net_party_update, [{}])
			_send(m, net_system, ["The party was disbanded."])
		srv_parties.erase(pid)
		print("[party] party %d disbanded" % pid)
		return
	var note := "%s %s the party." % [srv_name_of(peer), verb]
	if int(p["leader"]) == peer:
		p["leader"] = p["members"][0]
		note += "  %s leads now." % srv_name_of(p["leader"])
	_srv_broadcast_party(pid, note)


## Server: a mob worth (xp, money) died at `pos` to `killer`. Every party
## member within PARTY_SHARE_RANGE (by the server's accepted position) gets
## party_split()'s share through srv_grant_reward. Returns {peer: [xp, money]}
## so the mob can tell each client its share (Enemy.net_reward_split).
func srv_reward_kill(killer: int, xp: int, money: int, pos: Vector3, drops: Dictionary = {}, quest := "") -> Dictionary:
	var sharers: Array = [killer]
	for m in _srv_party_members(killer):
		if m == killer or not _srv_is_online(m):
			continue
		var mp = _srv_player_pos(m)
		if mp is Vector3 and mp.distance_to(pos) <= PARTY_SHARE_RANGE:
			sharers.append(m)
	var share := party_split(xp, money, sharers.size())
	var out := {}
	for m in sharers:
		srv_grant_reward(m, share[0], share[1])
		out[m] = share
	if sharers.size() > 1:
		var names := []
		for m in sharers:
			names.append(srv_name_of(m))
		print("[party] kill by %s shared with %s: %d xp / %d col each (base %d/%d, +%d%% bonus)" % [
			srv_name_of(killer), ", ".join(names), share[0], share[1], xp, money, int(PARTY_BONUS_PER_MEMBER * 100.0 * (sharers.size() - 1))])
	# Drops and quest credit are rolled here, on the killer's record, and
	# sent as a patch (a client never books its own loot online).
	if srv_records.has(killer):
		var rs = RecordState.new(srv_records[killer])
		var got := {}
		for mat in drops:
			if GameState.MATERIAL_NAMES.has(mat) and randf() < float(drops[mat]):
				rs.add_material(mat)
				got[mat] = int(got.get(mat, 0)) + 1
		if quest != "":
			rs.advance_quest(quest)
		if not got.is_empty() or quest != "":
			_srv_reply(killer, "loot", {"drops": got, "quest": quest})
	return out


func _on_party_tick() -> void:
	if not online:
		return
	if multiplayer.is_server():
		for pid in srv_parties.keys():
			var p: Dictionary = srv_parties[pid]
			var states := []
			for m in p["members"]:
				var mp = _srv_player_pos(m)
				var pos: Vector3 = mp if mp is Vector3 else Vector3.ZERO
				var hp := int(srv_hp.get(m, 100))
				if m == 1 and not dedicated:
					hp = int(round(GameState.hp / maxf(GameState.max_hp(), 1.0) * 100.0))
				elif srv_records.has(m):
					var mrs = RecordState.new(srv_records[m])
					hp = int(round(float(mrs.hp) / maxf(mrs.max_hp(), 1.0) * 100.0))
				states.append({"peer": m, "name": srv_name_of(m), "level": _srv_level_of(m), "hp": hp, "pos": pos})
			for m in p["members"]:
				_send(m, net_party_state, [states])
	else:
		if bot_party:
			_bot_party_think()


## --bot --party: every 6 s while not yet in a party of two, ask who is
## online and invite the first other climber; invites are auto-accepted in
## net_party_invited. Two such bots pair up within ~10 s of each other.
func _bot_party_think() -> void:
	_bot_party_t += PARTY_TICK
	if party_size() >= 2 or _bot_party_t < 6.0:
		return
	_bot_party_t = 0.0
	if not pending_invite.is_empty():
		request_party_respond(true)
		return
	request_who()


# --- Client requests (also used by the listen-server host) --------------------

func _system(text: String) -> void:
	chat_received.emit("", text, "system")


func _request(fn: Callable, args: Array, offline_msg := "You are not online.") -> bool:
	if not online:
		if offline_msg != "":
			_system(offline_msg)
		return false
	if multiplayer.is_server():
		fn.callv(args)  # host: the rpc handler runs locally with sender 1
	else:
		Callable(self, "rpc_id").callv([1, fn.get_method()] + args)
	return true


func request_invite(name: String) -> void:
	_request(net_party_invite, [sanitize_name(name)])


func request_party_respond(accept: bool) -> void:
	pending_invite = {}
	party_changed.emit()
	_request(net_party_respond, [accept], "")


func request_party_leave() -> void:
	_request(net_party_leave, [], "You are not in a party.")


func request_party_kick(name: String) -> void:
	_request(net_party_kick, [sanitize_name(name)])


func request_whisper(name: String, text: String) -> void:
	_request(net_whisper, [sanitize_name(name), sanitize_text(text)])


func request_party_chat(text: String) -> void:
	_request(net_party_chat, [sanitize_text(text)], "You are not in a party.")


func request_who(quiet := false) -> void:
	if not online:
		who_list = [{"name": my_name(), "level": GameState.level, "floor": GameState.floor, "party": false}]
		who_received.emit(who_list)
		if not quiet:
			_system("Online: just you (offline).")
		return
	_request(net_who, [])


func request_roll(max_v := 100) -> void:
	if not online:
		_system("%s rolls %d (1-%d)" % [my_name(), randi_range(1, clampi(max_v, 2, 1000)), clampi(max_v, 2, 1000)])
		return
	_request(net_roll, [max_v])


# --- Client -> server rpcs ----------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func net_party_invite(target_name: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not _srv_is_online(peer) or not _rate_ok(peer, "invite", RATE_INVITE_MS):
		return
	var err := _srv_invite(peer, srv_peer_by_name(target_name))
	if err != "":
		_send(peer, net_system, [err])


@rpc("any_peer", "call_remote", "reliable")
func net_party_respond(accept: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not _srv_is_online(peer) or not _rate_ok(peer, "party_op", RATE_PARTY_OP_MS):
		return
	_srv_respond(peer, accept)


@rpc("any_peer", "call_remote", "reliable")
func net_party_leave() -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not _srv_is_online(peer) or not _rate_ok(peer, "party_op", RATE_PARTY_OP_MS):
		return
	if not srv_party_of.has(peer):
		_send(peer, net_system, ["You are not in a party."])
		return
	_srv_leave_party(peer)


@rpc("any_peer", "call_remote", "reliable")
func net_party_kick(target_name: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not _srv_is_online(peer) or not _rate_ok(peer, "party_op", RATE_PARTY_OP_MS):
		return
	var pid := int(srv_party_of.get(peer, 0))
	var target := srv_peer_by_name(target_name)
	if pid == 0 or int(srv_parties[pid]["leader"]) != peer:
		_send(peer, net_system, ["Only the party leader can remove members."])
		return
	if target == 0 or target == peer or int(srv_party_of.get(target, 0)) != pid:
		_send(peer, net_system, ["%s is not in your party." % sanitize_name(target_name)])
		return
	_send(target, net_system, ["You were removed from the party."])
	_srv_leave_party(target, "was removed from")


@rpc("any_peer", "call_remote", "reliable")
func net_whisper(target_name: String, text: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not _srv_is_online(peer) or not _rate_ok(peer, "whisper", RATE_WHISPER_MS):
		return
	text = sanitize_text(text)
	if text == "":
		return
	var target := srv_peer_by_name(target_name)
	if target == 0 or not _srv_is_online(target):
		_send(peer, net_system, ["%s is not online." % sanitize_name(target_name)])
		return
	if target == peer:
		_send(peer, net_system, ["You whisper to yourself. Nobody answers."])
		return
	_send(target, net_chat, ["whisper", srv_name_of(peer), text])
	_send(peer, net_chat, ["whisper_to", srv_name_of(target), text])


@rpc("any_peer", "call_remote", "reliable")
func net_party_chat(text: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not _srv_is_online(peer) or not _rate_ok(peer, "party_chat", RATE_PARTY_CHAT_MS):
		return
	text = sanitize_text(text)
	var members := _srv_party_members(peer)
	if members.is_empty():
		_send(peer, net_system, ["You are not in a party."])
		return
	if text == "":
		return
	for m in members:
		_send(m, net_chat, ["party", srv_name_of(peer), text])


# --- Guilds (P8, scripts/life/guilds.gd) -------------------------------------
## Client: lower-case character name -> guild tag, pushed by the server (the
## Guilds node rebuilds it from the realm every few seconds); offline and on
## the host the node writes it directly. Player name labels read guild_label().
var guild_tags := {}
const RATE_GUILD_CHAT_MS := 500


func guild_label(name: String) -> String:
	var t := str(guild_tags.get(name.to_lower(), ""))
	return name if t == "" else "%s  [%s]" % [name, t]


## Server: send the tag map to every client.
func broadcast_guild_tags(tags: Dictionary) -> void:
	if online and multiplayer.multiplayer_peer != null and multiplayer.is_server():
		net_guild_tags.rpc(tags)


@rpc("authority", "call_remote", "reliable")
func net_guild_tags(tags: Dictionary) -> void:
	if not _from_server():
		return
	var clean := {}
	for k in tags:
		if clean.size() >= MAX_PLAYERS * 2:
			break
		var t := ""
		for ch in str(tags[k]).to_upper():
			if ch >= "A" and ch <= "Z" and t.length() < 4:
				t += ch
		if t != "":
			clean[sanitize_name(str(k)).to_lower()] = t
	guild_tags = clean


func request_guild_chat(text: String) -> void:
	text = sanitize_text(text)
	if text == "":
		return
	if not online:
		var rdb = get_realm()
		var G = load("res://scripts/life/guilds.gd")
		if rdb == null or G.guild_of(rdb, local_holder()) == "":
			_system("You are not in a guild.")
		else:
			chat_received.emit(my_name(), text, "guild")
		return
	_request(net_guild_chat, [text], "You are not in a guild.")


@rpc("any_peer", "call_remote", "reliable")
func net_guild_chat(text: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not _rate_ok(peer, "guild_chat", RATE_GUILD_CHAT_MS):
		return
	text = sanitize_text(text)
	var rdb = get_realm()
	var holder := srv_holder(peer)
	var G = load("res://scripts/life/guilds.gd")
	var mates: Array = G.mates(rdb, holder) if rdb != null and holder != "" else []
	if mates.is_empty():
		_send(peer, net_system, ["You are not in a guild."])
		return
	if text == "":
		return
	var sender := srv_name_of(peer) if srv_records.has(peer) else my_name()
	for p in srv_records:
		if mates.has(RealmDBScript.holder_of_record(srv_records[p])):
			_send(p, net_chat, ["guild", sender, text])
	# Listen host: its own character has no record; it hears its guild too.
	if not dedicated and mates.has(local_holder()):
		chat_received.emit(sender, text, "guild")


@rpc("any_peer", "call_remote", "reliable")
func net_who() -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not _srv_is_online(peer) or not _rate_ok(peer, "who", RATE_WHO_MS):
		return
	var list := []
	var peers := srv_records.keys()
	if not dedicated:
		peers.push_front(1)
	for p in peers:
		if list.size() >= MAX_PLAYERS:
			break
		list.append({"name": srv_name_of(p), "level": _srv_level_of(p), "floor": GameState.floor, "party": srv_party_of.has(p)})
	_send(peer, net_who_answer, [list])


@rpc("any_peer", "call_remote", "reliable")
func net_roll(max_v: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not _srv_is_online(peer) or not _rate_ok(peer, "roll", RATE_ROLL_MS):
		return
	max_v = clampi(max_v, 2, 1000)
	var line := "%s rolls %d (1-%d)" % [srv_name_of(peer), randi_range(1, max_v), max_v]
	var audience := _srv_party_members(peer)
	if audience.is_empty():
		audience = srv_records.keys()
		if not dedicated:
			audience.append(1)
	for m in audience:
		_send(m, net_system, [line])


## Client -> server: my hp as a percentage. Kept for protocol compatibility;
## HP lives on the record now (srv_damage), so the report is ignored.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_hp_report(_pct: int) -> void:
	pass


# --- Server -> client rpcs ----------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func net_party_update(desc: Dictionary) -> void:
	if not _from_server():
		return
	party = {}
	party_ids = {}
	if desc.has("members") and desc["members"] is Array and not desc["members"].is_empty():
		var members := []
		for m in desc["members"]:
			if m is Dictionary:
				var pid := int(m.get("peer", 0))
				members.append({"peer": pid, "name": sanitize_name(str(m.get("name", "")))})
				party_ids[pid] = true
		party = {"id": int(desc.get("id", 0)), "leader": int(desc.get("leader", 0)), "members": members}
		for k in party_state.keys():
			if not party_ids.has(k):
				party_state.erase(k)
	else:
		party_state = {}
	party_changed.emit()


@rpc("authority", "call_remote", "reliable")
func net_party_invited(from_name: String) -> void:
	if not _from_server():
		return
	pending_invite = {"from": sanitize_name(from_name), "ms": Time.get_ticks_msec()}
	party_invited.emit(pending_invite["from"])
	party_changed.emit()
	if bot_party:
		request_party_respond(true)


@rpc("authority", "call_remote", "unreliable_ordered")
func net_party_state(states: Array) -> void:
	if not _from_server() or party.is_empty():
		return
	for s in states:
		if not (s is Dictionary):
			continue
		var pid := int(s.get("peer", 0))
		if not party_ids.has(pid):
			continue
		var pos = s.get("pos", Vector3.ZERO)
		party_state[pid] = {
			"name": sanitize_name(str(s.get("name", ""))),
			"level": clampi(int(s.get("level", 1)), 1, LEVEL_CAP),
			"hp": clampi(int(s.get("hp", 100)), 0, 100),
			"pos": pos if pos is Vector3 else Vector3.ZERO,
		}


@rpc("authority", "call_remote", "reliable")
func net_chat(channel: String, sender_name: String, text: String) -> void:
	if not _from_server():
		return
	if not (channel in ["party", "whisper", "whisper_to", "guild"]):
		return
	chat_received.emit(sanitize_name(sender_name), sanitize_text(text), channel)


@rpc("authority", "call_remote", "reliable")
func net_system(text: String) -> void:
	if not _from_server():
		return
	_system(sanitize_text(text))


@rpc("authority", "call_remote", "reliable")
func net_who_answer(list: Array) -> void:
	if not _from_server():
		return
	who_list = []
	for e in list:
		if e is Dictionary and who_list.size() < MAX_PLAYERS:
			who_list.append({"name": sanitize_name(str(e.get("name", ""))), "level": clampi(int(e.get("level", 1)), 1, LEVEL_CAP),
				"floor": clampi(int(e.get("floor", 1)), 1, 100), "party": bool(e.get("party", false))})
	who_received.emit(who_list)
	if bot_party and party_size() < 2:
		for e in who_list:
			if e["name"].to_lower() != my_name().to_lower() and not e["party"]:
				request_invite(e["name"])
				break


# --- Server-authoritative actions (mining, crafting, fishing, cooking, ...) ----
## Client: Net.request_action(kind, payload) -> server net_request_action ->
## _srv_action validates (record, rate limit, world range checks through
## world.srv_action, record sufficiency inside Crafting/LifeData/the quest
## talks run on a RecordState) -> net_apply(kind, {patch, ...}) back to the
## client, which adopts the patch (GameState.apply_patch) and emits
## action_applied for the world's UI feedback. Kinds:
##   mine {vein}, herb {i}, cast {spot}, land {spot}, cook {id}, eat {id},
##   craft {recipe}, buy {id}, buy_home, store {id, to_storage}, place {slot,
##   id}, rest, talk {npc}, enter_labyrinth, spend_point {stat}, equip {id},
##   unequip {kind}. HP: srv_damage / net_hp; loot: srv_reward_kill.

## True on a connected client that is not the server: the peer whose
## state-changing actions go through the server.
func remote_client() -> bool:
	return online and multiplayer.multiplayer_peer != null and not multiplayer.is_server()


## Client: ask the server to run `kind`. Returns false when offline (the
## caller then runs the local code path) or when self rate-limited.
func request_action(kind: String, payload: Dictionary = {}) -> bool:
	if not remote_client():
		return false
	var now := Time.get_ticks_msec()
	var min_ms := int(RATE_ACTION_MS.get(kind, RATE_ACTION_DEFAULT_MS))
	if now - int(_last_req_ms.get(kind, -100000)) < min_ms:
		return false
	_last_req_ms[kind] = now
	net_request_action.rpc_id(1, kind, payload)
	return true


## Client helpers for the inventory screen: stat points and gear go through
## the server online, straight to GameState offline / on the host.
func spend_point(stat: String) -> bool:
	if remote_client():
		return request_action("spend_point", {"stat": stat})
	return GameState.spend_point(stat)


func equip(item: Dictionary) -> void:
	if remote_client():
		request_action("equip", {"id": str(item.get("id", ""))})
	else:
		GameState.equip(item)


func unequip(kind: String) -> void:
	if remote_client():
		request_action("unequip", {"kind": kind})
	else:
		InventoryScreen.unequip(kind)


@rpc("any_peer", "call_remote", "reliable")
func net_request_action(kind: String, payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not srv_records.has(peer):
		return
	if not (payload is Dictionary) or var_to_bytes(payload).size() > 1024 or kind.length() > 24:
		kick(peer, "Malformed action request")
		return
	if not _rate_ok(peer, "act:" + kind, int(RATE_ACTION_MS.get(kind, RATE_ACTION_DEFAULT_MS))):
		if _rate_ok(peer, "act_warn", 5000):
			print("[life] peer %d (%s) floods '%s' requests; dropped" % [peer, srv_records[peer]["name"], kind])
		return
	_srv_action(peer, kind, payload)


## Server: run one action for `peer` and answer it. Returns the result (the
## smoke test calls this directly on fake records; _send skips fake peers).
func _srv_action(peer: int, kind: String, payload: Dictionary) -> Dictionary:
	if not srv_records.has(peer):
		return {"error": "No record."}
	var rec: Dictionary = srv_records[peer]
	var rs = RecordState.new(rec)
	var res: Dictionary
	match kind:
		"eat":
			var id := str(payload.get("id", ""))
			res = {"id": id} if LifeData.eat(id, rs) else {"error": "You have none of that."}
		"crystal":
			var id := str(payload.get("id", ""))
			var prev := float(rec["hp"])
			var err := LifeData.use_crystal(id, rs)
			res = {"error": err} if err != "" else {"id": id}
			if err == "" and id == "heal_crystal":
				_send(peer, net_hp, [float(rec["hp"]), rs.max_hp(), prev])
		"spend_point":
			var stat := str(payload.get("stat", ""))
			res = {"stat": stat} if rs.spend_point(stat) else {"error": "No stat points to spend."}
		"equip":
			var id := str(payload.get("id", ""))
			res = {"error": "No such item."}
			for it in rec["inventory"]:
				if str(it.get("id", "")) == id:
					rs.equip(it)
					res = {"id": id}
					rs.hp = minf(float(rs.hp), rs.max_hp())
		"unequip":
			var k := str(payload.get("kind", ""))
			res = {"kind": k} if rs.unequip(k) else {"error": "Nothing equipped there."}
		_:
			var w: Node = get_tree().current_scene if get_tree() else null
			if w == null or not w.has_method("srv_action"):
				res = {"error": "No world."}
			else:
				var pos = _srv_player_pos(peer)
				res = w.srv_action(peer, rs, kind, payload, pos if pos is Vector3 else Vector3(1e6, 0, 1e6))
	if res.has("error"):
		print("[life] refused peer %d (%s) %s %s: %s" % [peer, rec["name"], kind, str(payload), res["error"]])
		_send(peer, net_apply, [kind, {"error": str(res["error"])}])
		return res
	for ev in rs.events:
		if ev.has("class"):
			print("[db] '%s' unlocked %s" % [rec["name"], ev["class"]])
		elif ev.has("skill"):
			print("[db] '%s' %s Lv %d" % [rec["name"], ev["skill"], ev["level"]])
		elif ev.has("level"):
			print("[db] '%s' reached Lv %d" % [rec["name"], ev["level"]])
	save_record(rec)
	_srv_reply(peer, kind, res)
	return res


## Server: one landed swing for `peer` (Enemy.net_hit, once per swing).
func srv_add_prof(peer: int) -> void:
	if srv_records.has(peer):
		var rec: Dictionary = srv_records[peer]
		rec["sword_prof"] = mini(int(rec.get("sword_prof", 0)) + 1, GameState.PROF_CAP)


## Server: wear `peer`'s equipped gear; at the "low" / "broken" lines the
## client gets a "gear" event with the patch.
func srv_wear(peer: int, slot: String, amount: float) -> void:
	if not srv_records.has(peer):
		return
	var rs = RecordState.new(srv_records[peer])
	var ev := Durability.wear(rs, slot, amount)
	if ev != "":
		if slot == "weapon":
			rs._sync_weapon()
		else:
			rs.hp = minf(float(rs.hp), rs.max_hp())
		_srv_reply(peer, "gear", {"slot": slot, "state": ev})


func srv_sword_prof(peer: int) -> int:
	return int(srv_records[peer].get("sword_prof", 0)) if srv_records.has(peer) else 0


## Server: per-peer cooldown on a world object ("vein:3"). True when the
## object is free for this peer, which also starts the cooldown.
func srv_cooldown(peer: int, key: String, ms: int) -> bool:
	var now := Time.get_ticks_msec()
	var cd: Dictionary = _srv_cd.get(peer, {})
	if now < int(cd.get(key, -1)):
		return false
	cd[key] = now + ms
	_srv_cd[peer] = cd
	return true


## Server: send the record's progress fields plus `extra` to the client.
func _srv_reply(peer: int, kind: String, extra: Dictionary) -> void:
	if not srv_records.has(peer):
		return
	var out := extra.duplicate()
	out["patch"] = patch_for_client(srv_records[peer])
	_send(peer, net_apply, [kind, out])


## Server -> client: the outcome of an action (or of server-side events such
## as loot, a floor clear or a respawn). Adopt the patch, then let the world
## do the toasts and sounds.
@rpc("authority", "call_remote", "reliable")
func net_apply(kind: String, result: Dictionary) -> void:
	if not _from_server() or multiplayer.is_server():
		return
	if result.get("patch") is Dictionary:
		GameState.apply_patch(result["patch"])
	action_applied.emit(kind, result)


# --- Server-owned HP -------------------------------------------------------------

## Server: a mob hit `peer`. Armor soak, HP and death are decided on the
## record; the client is told the new HP (net_hp) and, on death, respawned
## (net_apply "respawn" with a full-heal patch). Returns true when lethal.
## Seconds after a death in which the server ignores hits on that player
## (covers Player.DEATH_SHATTER + Player.DEATH_TIME plus latency).
const DEATH_GRACE := 6.0
var _death_grace := {}  # peer -> msec until hits count again


func srv_damage(peer: int, amount: float) -> bool:
	if not srv_records.has(peer):
		return false
	var rec: Dictionary = srv_records[peer]
	# Death grace: the client plays its shatter for a moment before it moves
	# to the respawn point, so the corpse can't be hit again meanwhile.
	if Time.get_ticks_msec() < int(_death_grace.get(peer, 0)):
		return false
	var rs = RecordState.new(rec)
	var prev := float(rec["hp"])
	var died: bool = rs.take_damage(clampf(amount, 0.0, 1000.0))
	srv_wear(peer, "armor", Durability.WEAR_HIT)
	HiddenClasses.note(rs, "hurt")  # a hit ends a clean parry streak
	if died:
		print("[life] '%s' fell (%.0f damage at %.0f hp); respawned at full health" % [rec["name"], amount, prev])
		rs.heal_full()
		_death_grace[peer] = Time.get_ticks_msec() + int(DEATH_GRACE * 1000.0)
		_srv_reply(peer, "respawn", {"prev_hp": prev})
		return true
	_send(peer, net_hp, [float(rec["hp"]), rs.max_hp(), prev])
	return false


## Server -> owner: your HP as the server knows it.
@rpc("authority", "call_remote", "unreliable_ordered")
func net_hp(hp: float, max_hp: float, prev: float = -1.0) -> void:
	if not _from_server() or multiplayer.is_server():
		return
	var before := GameState.hp
	GameState.hp = clampf(hp, 0.0, maxf(GameState.max_hp(), max_hp))
	GameState.health_changed.emit(GameState.hp, GameState.max_hp())
	action_applied.emit("hp", {"hp": GameState.hp, "max": max_hp, "prev": prev if prev >= 0.0 else before})


## Server, once a second: buff expiry and food regeneration on every
## record (the client only animates its own copy of the buffs).
func _on_life_tick() -> void:
	if not online or not multiplayer.is_server():
		return
	var online_holders: Array = []
	for peer in srv_records:
		var rec: Dictionary = srv_records[peer]
		var rs = RecordState.new(rec)
		var expired: bool = rs.prune_buffs()
		if rs.regen_tick(_life_timer.wait_time):
			_send(peer, net_hp, [float(rec["hp"]), rs.max_hp()])
		if expired:
			_srv_reply(peer, "buffs", {})
		online_holders.append(RealmDBScript.holder_of_record(rec))
	if realm != null:
		realm.tick_online(online_holders, _life_timer.wait_time)  # limited-quest reservations


## Screenshot / test hook: pretend to be in a party of these members plus
## this player (client side only). names[0] leads; hp is a percent per member.
func debug_seed_party(names: Array, hp: Array, levels: Array = []) -> void:
	var members := [{"peer": multiplayer.get_unique_id(), "name": my_name()}]
	party_ids = {}
	party_state = {}
	for i in names.size():
		var pid := 9000 + i
		members.append({"peer": pid, "name": str(names[i])})
		party_ids[pid] = true
		party_state[pid] = {"name": str(names[i]), "level": int(levels[i]) if i < levels.size() else 1,
			"hp": int(hp[i]) if i < hp.size() else 100, "pos": Vector3(12.0 * (i + 1), 0.0, 6.0 - 7.0 * i)}
	party = {"id": 1, "leader": 9000, "members": members}
	party_changed.emit()
