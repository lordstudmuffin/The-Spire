class_name LimitedContent
extends RefCounted
## Floor 1 limited items and quests: only 1-3 characters in the realm can
## ever hold each one (realm DB claims, see docs/REALM_DB.md). Items carry a
## realm serial, are bound to the character (no trading or stall listing)
## and are checked against the registry on every record load.
##
## Every helper takes `gs`: GameState offline / for the host, or a
## RecordState on the server, like the world's talk handlers.

const ITEMS := {
	# Last Attack bonus: whoever lands the killing blow on the Floor Guardian
	# first. One in the whole realm, ever.
	"la_floor1": {"name": "Mantle of the First Floor", "kind": "armor", "rank": 4, "def": 26, "cap": 1,
		"desc": "Last Attack bonus. Woven from the Guardian's shadow."},
	# Last Attack bonuses on Floor 1's elites: the first three to land the
	# killing blow on each (World.SERGEANT_LA / GREYTUSK_LA).
	"la_sergeant": {"name": "Sergeant's Cleaver", "kind": "weapon", "rank": 2, "atk": 19, "cap": 3,
		"desc": "Last Attack bonus. The Kobold Sergeant's notched cleaver."},
	"la_greytusk": {"name": "Greytusk Hide Vest", "kind": "armor", "rank": 2, "def": 16, "cap": 3,
		"desc": "Last Attack bonus. Cut from the old boar's scarred hide."},
	# Reward of "The Lantern Below" (one holder).
	"veil_first_dawn": {"name": "Veil of First Dawn", "kind": "armor", "rank": 4, "def": 24, "cap": 1,
		"desc": "Iselde's lantern-cloth. It keeps the first light of the floor."},
	# Reward of "Whispers of the Old Watch" (three holders).
	"wisplight_rapier": {"name": "Wisplight Rapier", "kind": "weapon", "rank": 3, "atk": 26, "cap": 3,
		"desc": "A watch-captain's blade, kindled at the waystones."},
}

## Limited quests: `cap` slots, reserved on accept for `timeout` seconds of
## online time; finishing confirms the slot and pays `reward` (an ITEMS id).
const QUESTS := {
	"lantern_below": {"cap": 1, "timeout": 7200.0, "reward": "veil_first_dawn", "mat": "spirit_shard", "need": 6, "xp": 500, "col": 300},
	"old_watch_whispers": {"cap": 3, "timeout": 7200.0, "reward": "wisplight_rapier", "mat": "wolf_pelt", "need": 5, "xp": 380, "col": 220},
}


static func _realm():
	return Net.get_realm()


static func holder_for(gs) -> String:
	if gs == GameState:
		return Net.local_holder()
	return gs.holder()


static func make_item(id: String) -> Dictionary:
	var d: Dictionary = ITEMS[id]
	return {
		"id": "%s_%d" % [id, Time.get_ticks_msec()],
		"name": d["name"],
		"kind": d["kind"],
		"rank": int(d["rank"]),
		"atk": int(d.get("atk", 0)),
		"def": int(d.get("def", 0)),
		"crafted_by": "",
		"limited": true,
	}


## Slots still free for a limited item or quest id.
static func slots_left(id: String) -> int:
	var cap := int(ITEMS[id]["cap"]) if ITEMS.has(id) else int(QUESTS[id]["cap"]) if QUESTS.has(id) else 0
	var r = _realm()
	return r.slots_left(id, cap) if r != null else 0


## Grants one copy of limited item `id` to `gs` (claim + serial + bound).
## Returns the realm result ({ok, already, last, error}); announces when the
## final copy is taken.
static func grant_item(gs, id: String) -> Dictionary:
	if not ITEMS.has(id):
		return {"ok": false, "error": "Unknown item."}
	var cap := int(ITEMS[id]["cap"])
	var item := make_item(id)
	var res: Dictionary
	if gs == GameState:
		var r = _realm()
		if r == null:
			return {"ok": false, "error": "No realm."}
		res = r.claim(id, cap, holder_for(gs), "item")
		if not res.get("ok", false):
			return res
		if res.get("already", false):
			return res  # Already holds one: never a second copy.
		if r.bind_serial(id, holder_for(gs), item, true) == "":
			return {"ok": false, "error": "The realm could not mint the item."}
		GameState.add_item(item)
	else:
		if _realm() != null and _realm().is_holder(id, holder_for(gs)):
			return {"ok": true, "already": true}
		res = gs.grant_limited_item(id, cap, item, true)
	if res.get("ok", false) and res.get("last", false):
		var who := str(gs.character.get("name", "Someone")) if gs.character is Dictionary else "Someone"
		Net.srv_announce("%s claimed the last %s in the realm." % [who, ITEMS[id]["name"]])
	return res


## Accept a limited quest: reserve a slot. {ok} or {ok: false, error}.
static func reserve_quest(gs, qid: String) -> Dictionary:
	var q: Dictionary = QUESTS[qid]
	var r = _realm()
	if r == null:
		return {"ok": false, "error": "No realm."}
	return r.reserve(qid, int(q["cap"]), holder_for(gs), float(q["timeout"]), true, "quest")


## True while `gs` still holds (reserved or confirmed) a slot of `qid`.
static func holds_quest(gs, qid: String) -> bool:
	var r = _realm()
	return r != null and r.is_holder(qid, holder_for(gs))


static func confirm_quest(gs, qid: String) -> Dictionary:
	var r = _realm()
	if r == null:
		return {"ok": false, "error": "No realm."}
	return r.confirm(qid, holder_for(gs))


static func is_bound(item) -> bool:
	return item is Dictionary and bool(item.get("bound", false))
