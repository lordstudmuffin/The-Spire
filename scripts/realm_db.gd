class_name RealmDB
extends RefCounted
## Server-wide persistent "realm world DB": the claim registry for unique
## skills, limited items and limited quests, item serials, and realm-owned
## containers (stall stock, tills, guild storage) with escrow transactions.
##
## One RealmDB per realm. A realm is the group of floor servers that share one
## world DB; today realm = this server (Net opens it in host(), id from
## `--realm <id>`, default "server"). Offline / listen host use the realm
## "local" so single-player code can call the same API; remote clients have no
## realm at all (Net.realm == null): they only see the results of actions.
##
## Durability. Every mutation is a transaction: it is appended to the journal
## (<realm>.journal, one checksummed JSON line, flushed) BEFORE it is applied
## in memory, and a full snapshot (<realm>.json) is rewritten atomically (temp
## file + rename) every COMPACT_EVERY journal lines and on close(). Load reads
## the snapshot (a torn snapshot temp file is ignored) and replays journal
## lines with seq > snapshot seq; a torn or corrupt tail line ends the replay.
## A crash therefore never double-grants (the grant is on disk before anyone
## is told) and never loses an acknowledged grant.
##
## Escrow. transact() moves Col and items between a character record and
## realm containers. The container side lives here; the record side is applied
## to the record dict and must be saved by the caller (Net.save_record). Until
## the caller calls settle(seq) the transaction stays "pending", and
## reconcile_record() replays pending transactions onto a record whose
## `realm_seq` watermark is older, exactly once, so a crash between the
## journal write and the record save cannot duplicate or lose Col or items.
##
## Holder identity: holder_key(account_token, character_name) =
## sha256(token)[:16] + ":" + lowercase name (Net.srv_holder(peer)).
## Offline: "local:" + lowercase name.
##
## Not thread-safe by design (the server runs its action path on the main
## thread); a mutex guards commit() anyway so a future worker cannot tear it.
## Sizes: the realm file is small (claims, serials, containers), not records.

const VERSION := 1
const DIR := "user://realm_db"
const COMPACT_EVERY := 64
## Inactivity release (seconds since the holder was last seen), by claim kind.
const INACTIVE_RELEASE := {"skill": 14 * 86400, "item": 30 * 86400, "quest": 30 * 86400, "stall": 30 * 86400, "plot": 30 * 86400}
const INACTIVE_DEFAULT := 30 * 86400
## Default reservation timeout for limited quests (seconds of online time).
const RESERVE_DEFAULT_SECS := 2 * 3600
const MAX_CONTAINER_ITEMS := 200
const MAX_INVENTORY := 60
const LOG_KEEP := 200

var realm_id := "local"
var dir := DIR
## Injectable clock (unix seconds, float) so tests can jump time.
var clock: Callable = func() -> float: return Time.get_unix_time_from_system()
## Optional: called with a text for realm-wide announcements (Net.srv_announce).
var announce: Callable = Callable()
var data: Dictionary = {}
## Recent log lines (also printed), newest last.
var log: Array = []

var _journal: FileAccess = null
var _journal_lines := 0
var _mutex := Mutex.new()
var _closed := false


# --- Open / close ---------------------------------------------------------------

static func holder_key(token: String, name: String) -> String:
	if token == "":
		return "local:" + name.strip_edges().to_lower()
	return token.sha256_text().left(16) + ":" + name.strip_edges().to_lower()


## Holder key of a server record (Net record dict) or an offline name.
static func holder_of_record(rec: Dictionary) -> String:
	return holder_key(str(rec.get("token", "")), str(rec.get("name", rec.get("character", {}).get("name", "Nameless"))))


static func empty_data(id: String) -> Dictionary:
	return {"version": VERSION, "realm": id, "seq": 0, "claims": {}, "serials": {}, "containers": {}, "last_seen": {},
		"pending": {}, "serial_counter": 0}


## Opens (or creates) the realm `id` under `base_dir`. Never fails: a corrupt
## snapshot is logged and the journal replayed onto an empty realm.
static func open(id: String, base_dir := DIR) -> RealmDB:
	var db := RealmDB.new()
	db.realm_id = id
	db.dir = base_dir
	db._load()
	return db


func snapshot_path() -> String:
	return "%s/%s.json" % [dir, realm_id]


func journal_path() -> String:
	return "%s/%s.journal" % [dir, realm_id]


func _load() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	data = empty_data(realm_id)
	var path := snapshot_path()
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("realm", "") == realm_id and parsed.has("seq"):
			data = parsed
			for k in empty_data(realm_id):
				if not data.has(k):
					data[k] = empty_data(realm_id)[k]
			data["seq"] = int(data["seq"])
			data["serial_counter"] = int(data["serial_counter"])
		else:
			_log("corrupt snapshot %s ignored; rebuilding from the journal" % path)
	# A temp file left behind means a snapshot write was torn: ignore it.
	if FileAccess.file_exists(path + ".tmp"):
		DirAccess.remove_absolute(path + ".tmp")
	var replayed := 0
	var dropped := 0
	_journal_lines = 0
	if FileAccess.file_exists(journal_path()):
		var text := FileAccess.get_file_as_string(journal_path())
		for line in text.split("\n", false):
			var tx := _parse_line(line)
			if tx.is_empty():
				dropped += 1
				break  # a torn line ends the valid prefix of the journal
			_journal_lines += 1
			if int(tx["s"]) <= int(data["seq"]):
				continue  # already in the snapshot
			_apply(str(tx["op"]), tx["a"], float(tx.get("t", 0.0)))
			data["seq"] = int(tx["s"])
			replayed += 1
	if replayed > 0 or dropped > 0:
		_log("recovered realm '%s': %d journal entries replayed, %d torn dropped" % [realm_id, replayed, dropped])
	if dropped > 0 or _journal_lines >= COMPACT_EVERY:
		_compact()  # rewrites the snapshot and leaves a clean journal
	else:
		_open_journal(false)


func _open_journal(truncate: bool) -> void:
	if _journal != null:
		_journal.close()
		_journal = null
	var p := journal_path()
	if truncate or not FileAccess.file_exists(p):
		_journal = FileAccess.open(p, FileAccess.WRITE_READ)
		_journal_lines = 0
	else:
		_journal = FileAccess.open(p, FileAccess.READ_WRITE)
		if _journal != null:
			_journal.seek_end()
	if _journal == null:
		push_error("[realm] cannot open journal %s: %s" % [p, error_string(FileAccess.get_open_error())])


## Writes the snapshot atomically and truncates the journal. Called every
## COMPACT_EVERY transactions and on close(); safe to call any time.
func flush() -> void:
	_mutex.lock()
	_compact()
	_mutex.unlock()


func close() -> void:
	if _closed:
		return
	flush()
	if _journal != null:
		_journal.close()
		_journal = null
	_closed = true


func _compact() -> void:
	var path := snapshot_path()
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[realm] cannot write %s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.flush()
	f.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("[realm] cannot replace %s: %s" % [path, error_string(err)])
		return
	_open_journal(true)


static func _parse_line(line: String) -> Dictionary:
	# "<md5-8> <json>": the checksum catches a line cut short by a crash.
	var sp := line.find(" ")
	if sp != 8:
		return {}
	var body := line.substr(9)
	if body.md5_text().left(8) != line.left(8):
		return {}
	var tx = JSON.parse_string(body)
	if not (tx is Dictionary) or not tx.has("s") or not tx.has("op") or not tx.has("a"):
		return {}
	return tx


## The one write path: journal first (flushed), then apply in memory.
## Returns the transaction's sequence number, or -1 when the journal is
## unwritable (the mutation is then NOT applied: no durability, no grant).
func commit(op: String, args: Dictionary) -> int:
	_mutex.lock()
	if _journal == null:
		_open_journal(false)
	if _journal == null:
		_mutex.unlock()
		return -1
	var seq := int(data["seq"]) + 1
	var now := _now()
	var body := JSON.stringify({"s": seq, "op": op, "a": args, "t": now})
	var line := body.md5_text().left(8) + " " + body
	var pos_before := _journal.get_position()
	_journal.store_line(line)
	_journal.flush()
	if _journal.get_error() != OK or _journal.get_position() != pos_before + line.to_utf8_buffer().size() + 1:
		push_error("[realm] journal write failed (%s); '%s' refused" % [error_string(_journal.get_error()), op])
		_mutex.unlock()
		return -1
	_journal_lines += 1
	_apply(op, args, now)
	data["seq"] = seq
	if _journal_lines >= COMPACT_EVERY:
		_compact()
	_mutex.unlock()
	return seq


func _now() -> float:
	return float(clock.call())


func _log(text: String) -> void:
	print("[realm] " + text)
	log.append(text)
	if log.size() > LOG_KEEP:
		log.pop_front()


# --- Apply (shared by live commits and journal replay; must be deterministic) ---

func _apply(op: String, a: Dictionary, t: float) -> void:
	match op:
		"claim":
			var c := _claim_entry(str(a["id"]), int(a["cap"]), str(a.get("kind", "item")))
			c["holders"][str(a["holder"])] = {"since": t, "state": "held", "expires": 0.0, "online_left": -1.0}
			data["last_seen"][str(a["holder"])] = t
		"reserve":
			var c := _claim_entry(str(a["id"]), int(a["cap"]), str(a.get("kind", "quest")))
			var h := {"since": t, "state": "reserved", "expires": 0.0, "online_left": -1.0}
			if bool(a.get("online", false)):
				h["online_left"] = float(a["timeout"])
			else:
				h["expires"] = t + float(a["timeout"])
			c["holders"][str(a["holder"])] = h
			data["last_seen"][str(a["holder"])] = t
		"confirm":
			var c: Dictionary = data["claims"].get(str(a["id"]), {})
			if c.has("holders") and c["holders"].has(str(a["holder"])):
				var h: Dictionary = c["holders"][str(a["holder"])]
				h["state"] = "held"
				h["expires"] = 0.0
				h["online_left"] = -1.0
		"release":
			var c: Dictionary = data["claims"].get(str(a["id"]), {})
			if c.has("holders"):
				c["holders"].erase(str(a["holder"]))
				if c["holders"].is_empty() and not bool(c.get("keep", false)):
					data["claims"].erase(str(a["id"]))
		"touch":
			data["last_seen"][str(a["holder"])] = t
		"online":
			# Online-time reservations count down; a: {"holders": [..], "dt": s}
			for hk in a.get("holders", []):
				for id in data["claims"]:
					var hs: Dictionary = data["claims"][id]["holders"]
					if hs.has(str(hk)) and float(hs[str(hk)].get("online_left", -1.0)) >= 0.0:
						hs[str(hk)]["online_left"] = float(hs[str(hk)]["online_left"]) - float(a["dt"])
		"sweep":
			# a: {"released": [{"id", "holder"}]} decided by sweep() at commit time.
			for r in a.get("released", []):
				_apply("release", {"id": r["id"], "holder": r["holder"]}, t)
				for s in data["serials"].keys():
					if str(data["serials"][s].get("holder", "")) == str(r["holder"]) and str(data["serials"][s].get("limited_id", "")) == str(r["id"]):
						data["serials"].erase(s)
		"mint":
			data["serial_counter"] = int(data["serial_counter"]) + 1
			data["serials"][str(a["serial"])] = {"limited_id": str(a["id"]), "holder": str(a["holder"]), "item_id": str(a.get("item_id", "")),
				"minted": t, "bound": bool(a.get("bound", true))}
		"free_serial":
			data["serials"].erase(str(a["serial"]))
		"container":
			var id := str(a["id"])
			if a.get("remove", false):
				data["containers"].erase(id)
			elif not data["containers"].has(id):
				data["containers"][id] = {"owner": str(a.get("owner", "")), "kind": str(a.get("kind", "generic")), "col": 0, "items": [],
					"meta": a.get("meta", {}), "created": t}
			else:
				var c: Dictionary = data["containers"][id]
				if a.has("owner"):
					c["owner"] = str(a["owner"])
				if a.has("meta"):
					c["meta"] = a["meta"]
		"transact":
			# a: {"holder", "moves": [{"col", "from", "to"} | {"item": {...}, "from", "to"}], "delta": {...}}
			for m in a["moves"]:
				var from := str(m["from"])
				var to := str(m["to"])
				if m.has("col"):
					var n := int(m["col"])
					if from != "record":
						_cont(from)["col"] = int(_cont(from)["col"]) - n
					if to != "record":
						_cont(to)["col"] = int(_cont(to)["col"]) + n
				elif m.has("item"):
					var item: Dictionary = m["item"]
					if from != "record":
						var items: Array = _cont(from)["items"]
						var i := _find(items, str(item.get("id", "")))
						if i >= 0:
							items.remove_at(i)
					if to != "record":
						_cont(to)["items"].append(item.duplicate(true))
					if item.has("serial") and data["serials"].has(str(item["serial"])):
						data["serials"][str(item["serial"])]["holder"] = str(a["holder"]) if to == "record" else "container:" + to
			data["pending"][str(int(a["seq"]))] = {"holder": str(a["holder"]), "delta": a["delta"], "t": t}
		"settle":
			data["pending"].erase(str(int(a["seq"])))
		"release_all":
			var hk := str(a["holder"])
			for id in data["claims"].keys():
				data["claims"][id]["holders"].erase(hk)
				if data["claims"][id]["holders"].is_empty() and not bool(data["claims"][id].get("keep", false)):
					data["claims"].erase(id)
			for s in data["serials"].keys():
				if str(data["serials"][s].get("holder", "")) == hk:
					data["serials"].erase(s)
			for cid in data["containers"].keys():
				if str(data["containers"][cid].get("owner", "")) == hk:
					data["containers"][cid]["owner"] = ""
			data["last_seen"].erase(hk)
			for p in data["pending"].keys():
				if str(data["pending"][p].get("holder", "")) == hk:
					data["pending"].erase(p)
		"guild":
			# P8 guilds (scripts/life/guilds.gd): a top-level "guilds" key made on
			# first use. a: {"id", "g": the whole guild dict} or {"id", "remove": true}.
			if not (data.get("guilds") is Dictionary):
				data["guilds"] = {}
			if bool(a.get("remove", false)):
				data["guilds"].erase(str(a["id"]))
			elif a.get("g") is Dictionary:
				data["guilds"][str(a["id"])] = (a["g"] as Dictionary).duplicate(true)
		_:
			_log("unknown journal op '%s' ignored" % op)


func _claim_entry(id: String, cap: int, kind: String) -> Dictionary:
	if not data["claims"].has(id):
		data["claims"][id] = {"cap": cap, "kind": kind, "holders": {}}
	var c: Dictionary = data["claims"][id]
	c["cap"] = cap
	if kind != "":
		c["kind"] = kind
	return c


func _cont(id: String) -> Dictionary:
	if not data["containers"].has(id):
		data["containers"][id] = {"owner": "", "kind": "generic", "col": 0, "items": [], "meta": {}, "created": _now()}
	return data["containers"][id]


static func _find(items: Array, id: String) -> int:
	for i in items.size():
		if items[i] is Dictionary and str(items[i].get("id", "")) == id:
			return i
	return -1


# --- Claim registry ----------------------------------------------------------------

## Grants `holder` one of `cap` slots of `limited_id`, atomically and durably.
## Returns {"ok": bool, "holders": [...], "last": bool (this took the last
## slot), "already": bool (holder already held it), "error": why}.
## kind: "skill" | "item" | "quest" | "stall" | "plot" (sets the inactivity rule).
func claim(limited_id: String, cap: int, holder: String, kind := "item") -> Dictionary:
	_mutex.lock()
	var _r: Dictionary = _claim_impl(limited_id, cap, holder, kind)
	_mutex.unlock()
	return _r


func _claim_impl(limited_id: String, cap: int, holder: String, kind := "item") -> Dictionary:
	if _closed or limited_id == "" or holder == "":
		return {"ok": false, "error": "Bad claim.", "holders": holders(limited_id)}
	_expire(limited_id)
	var hs := holders(limited_id)
	if hs.has(holder):
		var st: String = data["claims"][limited_id]["holders"][holder].get("state", "held")
		if st == "held":
			return {"ok": true, "already": true, "last": false, "holders": hs}
		return confirm(limited_id, holder)
	if hs.size() >= maxi(cap, 1):
		return {"ok": false, "error": "All %d slot(s) are taken." % maxi(cap, 1), "holders": hs}
	var seq := commit("claim", {"id": limited_id, "cap": maxi(cap, 1), "holder": holder, "kind": kind})
	if seq < 0:
		return {"ok": false, "error": "The realm could not record the claim.", "holders": hs}
	hs = holders(limited_id)
	_log("claim '%s' -> %s (%d/%d)" % [limited_id, holder, hs.size(), maxi(cap, 1)])
	return {"ok": true, "already": false, "last": hs.size() >= maxi(cap, 1), "holders": hs, "seq": seq}


## Reserves a slot that frees itself after `timeout` seconds unless
## confirm() makes it permanent. online=true counts only time the holder is
## online (Net ticks it once a second); false counts wall time.
func reserve(limited_id: String, cap: int, holder: String, timeout := float(RESERVE_DEFAULT_SECS), online := true, kind := "quest") -> Dictionary:
	_mutex.lock()
	var _r: Dictionary = _reserve_impl(limited_id, cap, holder, timeout, online, kind)
	_mutex.unlock()
	return _r


func _reserve_impl(limited_id: String, cap: int, holder: String, timeout := float(RESERVE_DEFAULT_SECS), online := true, kind := "quest") -> Dictionary:
	if _closed or limited_id == "" or holder == "":
		return {"ok": false, "error": "Bad reservation.", "holders": holders(limited_id)}
	_expire(limited_id)
	var hs := holders(limited_id)
	if hs.has(holder):
		return {"ok": true, "already": true, "holders": hs}
	if hs.size() >= maxi(cap, 1):
		return {"ok": false, "error": "All %d slot(s) are taken." % maxi(cap, 1), "holders": hs}
	var seq := commit("reserve", {"id": limited_id, "cap": maxi(cap, 1), "holder": holder, "timeout": maxf(timeout, 1.0), "online": online, "kind": kind})
	if seq < 0:
		return {"ok": false, "error": "The realm could not record the reservation.", "holders": hs}
	hs = holders(limited_id)
	_log("reserve '%s' -> %s for %.0fs %s" % [limited_id, holder, timeout, "online" if online else "wall"])
	return {"ok": true, "already": false, "last": hs.size() >= maxi(cap, 1), "holders": hs, "seq": seq}


## Turns a reservation into a permanent claim. Fails when it already expired.
func confirm(limited_id: String, holder: String) -> Dictionary:
	_mutex.lock()
	var _r: Dictionary = _confirm_impl(limited_id, holder)
	_mutex.unlock()
	return _r


func _confirm_impl(limited_id: String, holder: String) -> Dictionary:
	_expire(limited_id)
	if not is_holder(limited_id, holder):
		return {"ok": false, "error": "The reservation has expired.", "holders": holders(limited_id)}
	if str(data["claims"][limited_id]["holders"][holder].get("state", "held")) == "held":
		return {"ok": true, "already": true, "holders": holders(limited_id)}
	var seq := commit("confirm", {"id": limited_id, "holder": holder})
	if seq < 0:
		return {"ok": false, "error": "The realm could not record the claim.", "holders": holders(limited_id)}
	_log("confirm '%s' -> %s" % [limited_id, holder])
	return {"ok": true, "already": false, "holders": holders(limited_id), "last": holders(limited_id).size() >= cap_of(limited_id), "seq": seq}


## Frees the holder's slot (and that holder's serials of the item). True when it held one.
func release(limited_id: String, holder: String) -> bool:
	_mutex.lock()
	var _r: bool = _release_impl(limited_id, holder)
	_mutex.unlock()
	return _r


func _release_impl(limited_id: String, holder: String) -> bool:
	if not is_holder(limited_id, holder):
		return false
	var freed: Array = []
	for s in data["serials"]:
		if str(data["serials"][s].get("holder", "")) == holder and str(data["serials"][s].get("limited_id", "")) == limited_id:
			freed.append(s)
	var ok := commit("release", {"id": limited_id, "holder": holder}) >= 0
	for s in freed:
		commit("free_serial", {"serial": s})
	if ok:
		_log("release '%s' from %s" % [limited_id, holder])
	return ok


## Current holders (held and reserved, expired reservations excluded).
func holders(limited_id: String) -> Array:
	var out: Array = []
	var c: Dictionary = data["claims"].get(limited_id, {})
	var now := _now()
	for hk in c.get("holders", {}):
		if not _expired(c["holders"][hk], now):
			out.append(hk)
	out.sort()
	return out


func is_holder(limited_id: String, holder: String) -> bool:
	var c: Dictionary = data["claims"].get(limited_id, {})
	return c.has("holders") and c["holders"].has(holder) and not _expired(c["holders"][holder], _now())


func cap_of(limited_id: String) -> int:
	return int(data["claims"].get(limited_id, {}).get("cap", 1))


func slots_left(limited_id: String, cap: int) -> int:
	return maxi(cap, 1) - holders(limited_id).size()


## Everything `holder` holds: [{"id", "kind", "state", "since"}].
func claims_of(holder: String) -> Array:
	var out: Array = []
	var now := _now()
	for id in data["claims"]:
		var hs: Dictionary = data["claims"][id]["holders"]
		if hs.has(holder) and not _expired(hs[holder], now):
			out.append({"id": id, "kind": data["claims"][id].get("kind", "item"), "state": hs[holder].get("state", "held"), "since": hs[holder].get("since", 0.0)})
	return out


static func _expired(h: Dictionary, now: float) -> bool:
	if str(h.get("state", "held")) != "reserved":
		return false
	if float(h.get("online_left", -1.0)) >= 0.0:
		return float(h["online_left"]) <= 0.0
	return float(h.get("expires", 0.0)) <= now


## Durably drops expired reservations of one id (lazy; sweep() does them all).
func _expire(limited_id: String) -> void:
	var c: Dictionary = data["claims"].get(limited_id, {})
	var now := _now()
	for hk in c.get("holders", {}).keys():
		if _expired(c["holders"][hk], now):
			commit("release", {"id": limited_id, "holder": hk})
			_log("reservation '%s' of %s expired" % [limited_id, hk])


## Marks the holder active now (connect, disconnect, periodic). Journaled at
## most once per hour per holder; the in-memory value is always exact.
func touch(holder: String) -> void:
	if holder == "":
		return
	var now := _now()
	var last := float(data["last_seen"].get(holder, 0.0))
	if now - last >= 3600.0:
		commit("touch", {"holder": holder})
	else:
		data["last_seen"][holder] = now


func last_seen(holder: String) -> float:
	return float(data["last_seen"].get(holder, 0.0))


## Online-time reservations: subtract `dt` seconds for these holders.
## Journaled in one entry; call once a second with everyone online.
func tick_online(online_holders: Array, dt: float) -> void:
	if online_holders.is_empty() or dt <= 0.0:
		return
	var any := false
	for hk in online_holders:
		for id in data["claims"]:
			var hs: Dictionary = data["claims"][id]["holders"]
			if hs.has(hk) and float(hs[hk].get("online_left", -1.0)) >= 0.0:
				any = true
	if any:
		commit("online", {"holders": online_holders, "dt": dt})


## Releases expired reservations and claims whose holder has been away longer
## than INACTIVE_RELEASE[kind]. Returns [{"id", "holder", "why"}].
func sweep() -> Array:
	var now := _now()
	var out: Array = []
	for id in data["claims"].keys():
		var c: Dictionary = data["claims"][id]
		var limit := int(INACTIVE_RELEASE.get(str(c.get("kind", "item")), INACTIVE_DEFAULT))
		for hk in c["holders"].keys():
			if _expired(c["holders"][hk], now):
				out.append({"id": id, "holder": hk, "why": "expired"})
			elif now - float(data["last_seen"].get(hk, float(c["holders"][hk].get("since", now)))) > limit:
				out.append({"id": id, "holder": hk, "why": "inactive"})
	if not out.is_empty():
		commit("sweep", {"released": out})
		for r in out:
			_log("sweep: '%s' released from %s (%s)" % [r["id"], r["holder"], r["why"]])
			if announce.is_valid() and r["why"] == "inactive":
				announce.call("A %s has returned to the realm: %s" % [str(data["claims"].get(r["id"], {}).get("kind", "item")), str(r["id"]).capitalize()])
	return out


## Character delete: frees every claim, serial, container ownership and
## pending transaction of the holder. Returns what was released.
func release_all(holder: String) -> Array:
	_mutex.lock()
	var _r: Array = _release_all_impl(holder)
	_mutex.unlock()
	return _r


func _release_all_impl(holder: String) -> Array:
	var had := claims_of(holder)
	if commit("release_all", {"holder": holder}) >= 0:
		_log("release_all %s: %d claim(s)" % [holder, had.size()])
	return had


# --- Item serials -----------------------------------------------------------------

## Mints a unique serial for a limited item and stamps the item dictionary:
## item.serial, item.limited_id, item.bound (default true: cannot leave the
## character through transact()). Returns the serial ("" when refused: the
## holder must already hold a claim on `limited_id`).
func bind_serial(limited_id: String, holder: String, item: Dictionary, bound := true) -> String:
	_mutex.lock()
	var _r: String = _bind_serial_impl(limited_id, holder, item, bound)
	_mutex.unlock()
	return _r


func _bind_serial_impl(limited_id: String, holder: String, item: Dictionary, bound := true) -> String:
	if not is_holder(limited_id, holder):
		return ""
	var serial := "%s-%s-%06d" % [realm_id, limited_id, int(data["serial_counter"]) + 1]
	if commit("mint", {"serial": serial, "id": limited_id, "holder": holder, "item_id": str(item.get("id", "")), "bound": bound}) < 0:
		return ""
	item["serial"] = serial
	item["limited_id"] = limited_id
	item["bound"] = bound
	return serial


func serial_info(serial: String) -> Dictionary:
	return data["serials"].get(serial, {})


func is_bound(item: Dictionary) -> bool:
	if bool(item.get("bound", false)):
		return true
	var s := str(item.get("serial", ""))
	return s != "" and bool(data["serials"].get(s, {}).get("bound", false))


## Checks every item with a serial or limited_id in the record (inventory,
## home storage, equipped) against the registry: unregistered serials, serials
## minted for another holder, items of a limited id with no serial, and second
## copies of a serial are removed. Serials registered to this holder that the
## record no longer carries are freed (and the item claim with them when none
## remain), so a grant whose record save was lost heals toward "not held".
## Returns the removed items' descriptions; writes to the log.
func verify_record(rec: Dictionary) -> Array:
	var holder := holder_of_record(rec)
	var removed: Array = []
	var seen := {}
	for list_key in ["inventory", "home_storage"]:
		if not (rec.get(list_key) is Array):
			continue
		var kept: Array = []
		for item in rec[list_key]:
			var why := _bad_item(item, holder, seen)
			if why == "":
				kept.append(item)
			else:
				removed.append("%s (%s)" % [str(item.get("name", item.get("id", "?"))), why])
		rec[list_key] = kept
	if rec.get("equipped") is Dictionary:
		for slot in rec["equipped"]:
			var it = rec["equipped"][slot]
			if it is Dictionary:
				var serial := str(it.get("serial", ""))
				if serial != "" and not seen.has(serial):
					# Equipped items mirror an inventory entry; one without is a stray copy.
					rec["equipped"][slot] = null
					removed.append("%s (equipped copy)" % str(it.get("name", "?")))
	# Serials this holder owns on paper but no longer carries.
	var orphaned: Array = []
	for s in data["serials"]:
		if str(data["serials"][s].get("holder", "")) == holder and not seen.has(s):
			orphaned.append(s)
	for s in orphaned:
		var lid := str(data["serials"][s].get("limited_id", ""))
		commit("free_serial", {"serial": s})
		_log("serial %s of %s freed: not in the record" % [s, holder])
		var still := false
		for s2 in data["serials"]:
			if str(data["serials"][s2].get("holder", "")) == holder and str(data["serials"][s2].get("limited_id", "")) == lid:
				still = true
		if not still and is_holder(lid, holder) and str(data["claims"][lid].get("kind", "item")) == "item":
			commit("release", {"id": lid, "holder": holder})
			_log("claim '%s' released from %s: no serial left" % [lid, holder])
	if not removed.is_empty():
		_log("record %s: removed %s" % [holder, ", ".join(removed)])
	return removed


func _bad_item(item, holder: String, seen: Dictionary) -> String:
	if not (item is Dictionary):
		return "not an item"
	var serial := str(item.get("serial", ""))
	var lid := str(item.get("limited_id", ""))
	if serial == "" and lid == "":
		return ""
	if serial == "":
		return "limited item without a serial"
	if seen.has(serial):
		return "duplicate serial"
	var reg: Dictionary = data["serials"].get(serial, {})
	if reg.is_empty():
		return "unregistered serial"
	if str(reg.get("holder", "")) != holder:
		return "serial belongs to another holder"
	if lid != "" and str(reg.get("limited_id", "")) != lid:
		return "serial of a different item"
	seen[serial] = true
	return ""


# --- Containers and escrow ----------------------------------------------------------

## Creates the container when missing; updates owner/meta when given.
func ensure_container(id: String, owner := "", kind := "generic", meta: Dictionary = {}) -> Dictionary:
	if id == "" or id == "record":
		return {}
	if not data["containers"].has(id):
		commit("container", {"id": id, "owner": owner, "kind": kind, "meta": meta})
	elif owner != str(data["containers"][id].get("owner", "")) or not meta.is_empty():
		var a := {"id": id, "owner": owner}
		if not meta.is_empty():
			a["meta"] = meta
		commit("container", a)
	return data["containers"][id]


func remove_container(id: String) -> bool:
	if not data["containers"].has(id):
		return false
	var c: Dictionary = data["containers"][id]
	if int(c.get("col", 0)) != 0 or not c.get("items", []).is_empty():
		return false  # drain it through transact() first
	return commit("container", {"id": id, "remove": true}) >= 0


func container(id: String) -> Dictionary:
	return data["containers"].get(id, {})


func containers_of(owner: String) -> Array:
	var out: Array = []
	for id in data["containers"]:
		if str(data["containers"][id].get("owner", "")) == owner:
			out.append(id)
	out.sort()
	return out


## One atomic, durable transaction between a character record (`rec`, may
## be empty when no record side is involved) and realm containers.
## moves: [{"col": n, "from": "record"|container_id, "to": "record"|container_id},
##         {"item": item_id, "from": ..., "to": ...}]
## Every move is validated first (enough Col, item present, bound items stay
## on the record, inventory and container caps); then the whole set is
## journaled and applied: containers here, the record in place with its
## `realm_seq` watermark. The caller saves the record and calls settle(seq)
## (Net.srv_transact does both). Returns {"ok", "seq", "error"}.
func transact(rec: Dictionary, moves: Array) -> Dictionary:
	_mutex.lock()
	var _r: Dictionary = _transact_impl(rec, moves)
	_mutex.unlock()
	return _r


func _transact_impl(rec: Dictionary, moves: Array) -> Dictionary:
	if _closed:
		return {"ok": false, "error": "The realm is closed."}
	var holder := holder_of_record(rec) if not rec.is_empty() else ""
	var col_delta := 0
	var remove_ids: Array = []
	var add_items: Array = []
	var resolved: Array = []
	# Simulated balances so several moves in one transaction add up.
	var cont_col := {}
	var cont_items := {}
	var rec_col := int(rec.get("money", 0)) if not rec.is_empty() else 0
	var rec_items: Array = (rec.get("inventory", []) as Array).duplicate() if not rec.is_empty() else []
	for m in moves:
		if not (m is Dictionary) or not m.has("from") or not m.has("to"):
			return {"ok": false, "error": "Malformed move."}
		var from := str(m["from"])
		var to := str(m["to"])
		if from == to or from == "" or to == "":
			return {"ok": false, "error": "A move needs two different sides."}
		if (from == "record" or to == "record") and rec.is_empty():
			return {"ok": false, "error": "No record for this move."}
		for side in [from, to]:
			if side != "record" and not cont_col.has(side):
				var c := container(side)
				if c.is_empty():
					return {"ok": false, "error": "No container '%s'." % side}
				cont_col[side] = int(c.get("col", 0))
				cont_items[side] = (c.get("items", []) as Array).duplicate()
		if m.has("col"):
			var n := int(m["col"])
			if n <= 0:
				return {"ok": false, "error": "Col amount must be positive."}
			if from == "record":
				if rec_col < n:
					return {"ok": false, "error": "Not enough Col."}
				rec_col -= n
				col_delta -= n
			else:
				if int(cont_col[from]) < n:
					return {"ok": false, "error": "'%s' has not enough Col." % from}
				cont_col[from] = int(cont_col[from]) - n
			if to == "record":
				rec_col += n
				col_delta += n
			else:
				cont_col[to] = int(cont_col[to]) + n
			resolved.append({"col": n, "from": from, "to": to})
		elif m.has("item"):
			var iid := str(m["item"])
			var item := {}
			if from == "record":
				var i := _find(rec_items, iid)
				if i < 0:
					return {"ok": false, "error": "You do not carry that item."}
				item = rec_items[i]
				if is_bound(item):
					return {"ok": false, "error": "That item is bound to you."}
				rec_items.remove_at(i)
				remove_ids.append(iid)
			else:
				var i := _find(cont_items[from], iid)
				if i < 0:
					return {"ok": false, "error": "'%s' does not hold that item." % from}
				item = cont_items[from][i]
				cont_items[from].remove_at(i)
			if to == "record":
				if rec_items.size() >= MAX_INVENTORY:
					return {"ok": false, "error": "Your inventory is full."}
				rec_items.append(item)
				add_items.append(item.duplicate(true))
			else:
				if cont_items[to].size() >= MAX_CONTAINER_ITEMS:
					return {"ok": false, "error": "'%s' is full." % to}
				cont_items[to].append(item)
			resolved.append({"item": item.duplicate(true), "from": from, "to": to})
		else:
			return {"ok": false, "error": "A move needs col or item."}
	if resolved.is_empty():
		return {"ok": false, "error": "Nothing to move."}
	var seq := int(data["seq"]) + 1
	var delta := {"col": col_delta, "remove": remove_ids, "add": add_items}
	if commit("transact", {"holder": holder, "moves": resolved, "delta": delta, "seq": seq}) < 0:
		return {"ok": false, "error": "The realm could not record the trade."}
	if not rec.is_empty():
		_apply_delta(rec, delta, seq)
	_log("transact #%d %s: %d move(s), col %+d" % [seq, holder, resolved.size(), col_delta])
	return {"ok": true, "seq": seq, "delta": delta}


func _apply_delta(rec: Dictionary, delta: Dictionary, seq: int) -> void:
	rec["money"] = maxi(int(rec.get("money", 0)) + int(delta.get("col", 0)), 0)
	if not (rec.get("inventory") is Array):
		rec["inventory"] = []
	for iid in delta.get("remove", []):
		var i := _find(rec["inventory"], str(iid))
		if i >= 0:
			rec["inventory"].remove_at(i)
		if rec.get("equipped") is Dictionary:
			for slot in rec["equipped"]:
				if rec["equipped"][slot] is Dictionary and str(rec["equipped"][slot].get("id", "")) == str(iid):
					rec["equipped"][slot] = null
	for item in delta.get("add", []):
		if _find(rec["inventory"], str(item.get("id", ""))) < 0:
			rec["inventory"].append(item.duplicate(true))
	rec["realm_seq"] = seq


## The record side of transaction `seq` is safely on disk; forget it.
func settle(seq: int) -> void:
	if data["pending"].has(str(seq)):
		commit("settle", {"seq": seq})


## Record load: replays pending transactions newer than the record's
## realm_seq watermark (a crash between journal and record save), then
## settles everything of this holder. Returns the number applied.
func reconcile_record(rec: Dictionary) -> int:
	var holder := holder_of_record(rec)
	var seqs: Array = []
	for k in data["pending"]:
		if str(data["pending"][k].get("holder", "")) == holder:
			seqs.append(int(k))
	seqs.sort()
	var applied := 0
	for s in seqs:
		if s > int(rec.get("realm_seq", 0)):
			_apply_delta(rec, data["pending"][str(s)]["delta"], s)
			applied += 1
			_log("reconciled transaction #%d onto %s" % [s, holder])
	for s in seqs:
		settle(s)
	return applied


func pending_count() -> int:
	return data["pending"].size()


# --- Introspection -----------------------------------------------------------------

## Snapshot of the registry for a Legends board or admin view.
func summary() -> Dictionary:
	var claims := {}
	for id in data["claims"]:
		claims[id] = {"cap": data["claims"][id]["cap"], "kind": data["claims"][id].get("kind", "item"), "holders": holders(id)}
	return {"realm": realm_id, "seq": data["seq"], "claims": claims, "serials": data["serials"].size(),
		"containers": data["containers"].keys(), "pending": data["pending"].size()}
