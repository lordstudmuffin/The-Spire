extends Node
## JSON save slots in user:// (on Windows: %APPDATA%/Godot/app_userdata/Anime Life RPG).
##
## Three slots, `save_0.json` .. `save_2.json`; slot 0 is the pre-slot save
## file, so an old install keeps its character. Each file is GameState.to_dict()
## plus:
##   "net_token": the secret that ties this character to its name on
##                multiplayer servers (see Net); kept per slot,
##   "meta": {"format": 3, "playtime": seconds, "last_played": unix,
##            "created": unix, "slot": n}.
## Files without "meta" (format 2) are migrated in place on startup; their
## net_token is preserved. Playtime is counted here: the session clock is
## marked when a slot is loaded or created and folded into the file on save.
##
## `current_slot` is the slot in play. Callers that say `save_game(0)` (the
## old "default slot") save to it; -1 or no argument means the same. Slots
## 1 and 2 passed explicitly are honoured (the smoke test uses slot 2).
## Online as a client the character lives on the server, so saving asks the
## server to persist it and leaves the offline slot untouched.

signal saved(slot: int)

const SLOT_COUNT := 3
const FORMAT := 3

## Slot being played; what save_game(0) / save_game() writes to.
var current_slot := 0
## Set by the character select before opening the creator in "edit
## appearance" mode for that slot; the creator clears it.
var edit_slot := -1

var _playtime_base := 0.0        # seconds already in the active slot's file
var _session_mark := Time.get_ticks_msec()


func _ready() -> void:
	migrate()


func slot_path(slot: int) -> String:
	return "user://save_%d.json" % slot


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func _resolve(slot: int) -> int:
	return current_slot if slot <= 0 else clampi(slot, 0, SLOT_COUNT - 1)


func _read(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(slot_path(slot)))
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _write(slot: int, data: Dictionary) -> bool:
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("Save failed: %s" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


# --- Session / playtime ----------------------------------------------------------

## Seconds played on the active slot, including the running session.
func playtime() -> float:
	return _playtime_base + float(Time.get_ticks_msec() - _session_mark) / 1000.0


func _mark_session(base: float) -> void:
	_playtime_base = base
	_session_mark = Time.get_ticks_msec()


## Starts a fresh character in `slot` (does not write until save_game).
func new_game(slot: int) -> void:
	current_slot = clampi(slot, 0, SLOT_COUNT - 1)
	GameState.reset()
	Net.client_token = ""  # a new climber gets its own token on first join
	_mark_session(0.0)


## First slot without a save, or -1 when all three are taken.
func first_free_slot() -> int:
	for s in SLOT_COUNT:
		if not has_save(s):
			return s
	return -1


# --- Save / load -------------------------------------------------------------------

func save_game(slot := -1) -> bool:
	slot = _resolve(slot)
	if Net.online and not Net.is_server():
		Net.request_save()
		store_token(slot)
		saved.emit(slot)
		return true
	var d := GameState.to_dict()
	if Net.client_token != "":
		d["net_token"] = Net.client_token
	var now := int(Time.get_unix_time_from_system())
	var old_meta: Dictionary = _read(slot).get("meta", {}) if has_save(slot) else {}
	var total := playtime() if slot == current_slot else float(old_meta.get("playtime", 0.0))
	d["meta"] = {
		"format": FORMAT,
		"playtime": snappedf(total, 0.1),
		"last_played": now,
		"created": int(old_meta.get("created", now)),
		"slot": slot,
	}
	if not _write(slot, d):
		return false
	if slot == current_slot:
		_mark_session(total)
	saved.emit(slot)
	return true


func load_game(slot := -1) -> bool:
	slot = _resolve(slot)
	if not has_save(slot):
		return false
	var data := _read(slot)
	if data.is_empty():
		push_error("Save file %d is corrupt" % slot)
		return false
	var token := str(data.get("net_token", ""))
	Net.client_token = token  # per character; empty until its first join
	GameState.from_dict(data)
	current_slot = slot
	var meta = data.get("meta", {})
	_mark_session(float(meta.get("playtime", 0.0)) if meta is Dictionary else 0.0)
	return true


func delete_slot(slot: int) -> bool:
	slot = clampi(slot, 0, SLOT_COUNT - 1)
	if not has_save(slot):
		return false
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))
	if err != OK:
		push_error("Could not delete slot %d: %s" % [slot, error_string(err)])
		return false
	return true


## Writes only the multiplayer token into an existing save file, so a token
## created at join time survives even if the player never saves again.
func store_token(slot := -1) -> void:
	slot = _resolve(slot)
	if Net.client_token == "" or not has_save(slot):
		return
	var data := _read(slot)
	if data.is_empty() or str(data.get("net_token", "")) == Net.client_token:
		return
	data["net_token"] = Net.client_token
	_write(slot, data)


# --- Migration ---------------------------------------------------------------------

## Brings format-2 files (one slot, no meta) up to format 3 in place. The
## net_token and every gameplay field are left exactly as they were; playtime
## starts at 0 and last_played is the file's modification time.
func migrate() -> int:
	var n := 0
	for s in SLOT_COUNT:
		if not has_save(s):
			continue
		var data := _read(s)
		if data.is_empty():
			continue
		var meta = data.get("meta")
		if meta is Dictionary and int(meta.get("format", 0)) >= FORMAT:
			continue
		var mtime := int(FileAccess.get_modified_time(slot_path(s)))
		var old: Dictionary = meta if meta is Dictionary else {}
		data["meta"] = {
			"format": FORMAT,
			"playtime": float(old.get("playtime", 0.0)),
			"last_played": int(old.get("last_played", mtime)),
			"created": int(old.get("created", mtime)),
			"slot": s,
		}
		if _write(s, data):
			n += 1
	return n


# --- Slot cards --------------------------------------------------------------------

## Everything the character select shows for a slot. "exists" false = empty.
func slot_info(slot: int) -> Dictionary:
	var info := {"slot": slot, "exists": false, "corrupt": false, "name": "", "origin": "", "class": "",
		"level": 1, "floor": 1, "floor_name": "", "playtime": 0.0, "last_played": 0, "character": {}}
	if not has_save(slot):
		return info
	var data := _read(slot)
	if data.is_empty():
		info["exists"] = true
		info["corrupt"] = true
		return info
	var ch = data.get("character", {})
	if not (ch is Dictionary):
		ch = {}
	var meta = data.get("meta", {})
	if not (meta is Dictionary):
		meta = {}
	info["exists"] = true
	info["character"] = ch
	info["name"] = str(ch.get("name", "?"))
	info["origin"] = str(ch.get("origin", "Swordsman"))
	var hidden := str(data.get("hidden_class", ""))
	info["class"] = hidden if hidden != "" else info["origin"]
	info["level"] = int(data.get("level", 1))
	info["floor"] = int(data.get("floor", 1))
	info["floor_name"] = GameState.FLOOR_NAMES.get(info["floor"], "Floor %d" % info["floor"])
	info["playtime"] = float(meta.get("playtime", 0.0))
	info["last_played"] = int(meta.get("last_played", 0))
	return info


func slot_summary(slot: int) -> String:
	var info := slot_info(slot)
	if not info["exists"]:
		return "Empty"
	if info["corrupt"]:
		return "Corrupt"
	return "%s  ·  Lv %d %s" % [info["name"], info["level"], info["origin"]]


## Most recently played slot with a save, or -1.
func last_played_slot() -> int:
	var best := -1
	var best_t := -1
	for s in SLOT_COUNT:
		var info := slot_info(s)
		if info["exists"] and not info["corrupt"] and info["last_played"] > best_t:
			best = s
			best_t = info["last_played"]
	return best


static func format_playtime(seconds: float) -> String:
	var m := int(seconds / 60.0)
	if m < 1:
		return "under a minute"
	if m < 60:
		return "%d min" % m
	return "%dh %02dm" % [m / 60, m % 60]


static func format_last_played(unix: int) -> String:
	if unix <= 0:
		return "never"
	var age := int(Time.get_unix_time_from_system()) - unix
	if age < 90:
		return "just now"
	if age < 3600:
		return "%d min ago" % (age / 60)
	if age < 86400:
		return "%dh ago" % (age / 3600)
	if age < 86400 * 7:
		return "%dd ago" % (age / 86400)
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]
