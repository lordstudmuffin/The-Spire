extends RefCounted
## Server-side view of one character record (Net.srv_records[peer]) that
## speaks the same API as GameState: `gs.money`, `gs.materials`,
## `gs.add_material()`, `gs.start_quest()` ... so the gameplay code in
## Crafting, LifeData and the world's quest talks runs unchanged against a
## record (online, on the server) or against GameState (offline). Every
## mutation writes straight into the record dictionary; Net sends the
## result to the client as a patch (Net.patch_for_client) which the client
## applies through GameState.apply_patch, so signals and UI follow.
##
## Loaded by Net as `Net.RecordState` (preload, no class_name so a fresh
## checkout needs no re-import).

## Gather quests whose progress mirrors what you carry (world._track_ore_quest).
const GATHER_QUESTS := [["ore_delivery", "iron_ore"], ["shrine_rite", "wisp_essence"], ["wolf_pelts", "wolf_pelt"],
	["field_herbs", "wild_herb"], ["tavern_stew", "boar_stew"], ["lantern_below", "spirit_shard"], ["old_watch_whispers", "wolf_pelt"]]
const FIELDS := ["character", "level", "xp", "stat_points", "stats", "money", "hp", "quests", "materials", "inventory", "equipped",
	"smithing_level", "smithing_xp", "items_crafted", "hidden_class", "floors_cleared", "recipes_unlocked",
	"fishing_level", "fishing_xp", "cooking_level", "cooking_xp", "farming_level", "farming_xp", "fish_caught", "home_owned", "home_storage",
	"home_furniture", "decor_owned", "buffs", "title", "visited", "chests", "unique_skill", "hidden", "sword_prof"]

var rec: Dictionary
## Set by callers that want to know what happened (level-ups, class unlocks).
var events: Array = []


func _init(record: Dictionary) -> void:
	rec = record


func _get(property: StringName) -> Variant:
	if FIELDS.has(String(property)):
		return rec.get(String(property))
	return null


func _set(property: StringName, value: Variant) -> bool:
	if FIELDS.has(String(property)):
		rec[String(property)] = value
		return true
	return false


func is_record() -> bool:
	return true


# --- XP, Col, stats ---------------------------------------------------------

func xp_to_next() -> int:
	return Net.xp_to_next(int(rec["level"]))


func add_xp(amount: int) -> void:
	var before: int = int(rec["level"])
	Net.level_record(rec, amount)
	if int(rec["level"]) != before:
		events.append({"level": rec["level"]})
		rec["hp"] = max_hp()


func add_money(amount: int) -> void:
	rec["money"] = maxi(int(rec["money"]) + amount, 0)


func spend_point(stat: String) -> bool:
	if int(rec.get("stat_points", 0)) <= 0 or not rec["stats"].has(stat):
		return false
	rec["stat_points"] = int(rec["stat_points"]) - 1
	rec["stats"][stat] = int(rec["stats"][stat]) + 1
	return true


func class_title() -> String:
	return str(rec.get("hidden_class", "")) if str(rec.get("hidden_class", "")) != "" else str(rec["character"].get("origin", ""))


## A hidden-class deed on the record (LifeData.cook / land_fish, Farms
## harvest). Combat deeds come through Net.srv_note_hidden instead.
func note_hidden(event: String) -> void:
	HiddenClasses.note(self, event)


func unlock_hidden_class(cls: String) -> void:
	if str(rec.get("hidden_class", "")) == cls or not GameState.HIDDEN_CLASSES.has(cls):
		return
	rec["hidden_class"] = cls
	for s in GameState.HIDDEN_CLASSES[cls]["bonus"]:
		rec["stats"][s] = int(rec["stats"].get(s, 0)) + int(GameState.HIDDEN_CLASSES[cls]["bonus"][s])
	events.append({"class": cls})
	heal_full()


# --- Materials, items, gear ---------------------------------------------------

func add_material(id: String, amount := 1) -> void:
	rec["materials"][id] = int(rec["materials"].get(id, 0)) + amount
	_sync_gather_quests()


func has_materials(cost: Dictionary) -> bool:
	for id in cost:
		if int(rec["materials"].get(id, 0)) < int(cost[id]):
			return false
	return true


func spend_materials(cost: Dictionary) -> void:
	for id in cost:
		rec["materials"][id] = int(rec["materials"].get(id, 0)) - int(cost[id])
	_sync_gather_quests()


func add_item(item: Dictionary) -> void:
	rec["inventory"].append(item)


# --- Realm world DB (docs/REALM_DB.md) ---------------------------------------------

## Holder key of this record in the realm registry (account token + name).
func holder() -> String:
	return Net.RealmDBScript.holder_of_record(rec)


## The realm DB (null only on a remote client, where no RecordState exists).
func realm():
	return Net.get_realm()


func find_item(id: String) -> Dictionary:
	var i := _find_item(rec["inventory"], id)
	return rec["inventory"][i] if i >= 0 else {}


## True for a limited item bound to its holder (cannot be traded or dropped).
func item_bound(id: String) -> bool:
	var it := find_item(id)
	if it.is_empty():
		return false
	var rdb = realm()
	return bool(it.get("bound", false)) or (rdb != null and rdb.is_bound(it))


## Removes an item from the inventory (unequipping it first). False when absent.
func remove_item(id: String) -> bool:
	var i := _find_item(rec["inventory"], id)
	if i < 0:
		return false
	for slot in rec["equipped"]:
		if rec["equipped"][slot] != null and str(rec["equipped"][slot].get("id", "")) == id:
			rec["equipped"][slot] = null
	rec["inventory"].remove_at(i)
	_sync_weapon()
	rec["hp"] = minf(float(rec["hp"]), max_hp())
	return true


## Grants a limited item: claims a slot of `limited_id` (cap holders realm-wide),
## mints its serial and adds the item. Returns the claim result ({"ok", "last",
## "error", ...}); the item carries serial / limited_id / bound on success.
func grant_limited_item(limited_id: String, cap: int, item: Dictionary, bound := true) -> Dictionary:
	var rdb = realm()
	if rdb == null:
		return {"ok": false, "error": "No realm."}
	var res: Dictionary = rdb.claim(limited_id, cap, holder(), "item")
	if not res.get("ok", false):
		return res
	if rdb.bind_serial(limited_id, holder(), item, bound) == "":
		return {"ok": false, "error": "The realm could not mint the item."}
	add_item(item)
	return res


func _find_item(list: Array, id: String) -> int:
	for i in list.size():
		if str(list[i].get("id", "")) == id:
			return i
	return -1


func equip(item: Dictionary) -> void:
	var i := _find_item(rec["inventory"], str(item.get("id", "")))
	if i < 0:
		return
	var it: Dictionary = rec["inventory"][i]
	rec["equipped"][it["kind"]] = it
	_sync_weapon()


func unequip(kind: String) -> bool:
	if not rec["equipped"].has(kind) or rec["equipped"][kind] == null:
		return false
	rec["equipped"][kind] = null
	_sync_weapon()
	rec["hp"] = minf(float(rec["hp"]), max_hp())
	return true


func _sync_weapon() -> void:
	var w = rec["equipped"].get("weapon")
	rec["weapon_atk"] = float(w["atk"]) if w is Dictionary and not Durability.is_broken(w) else 0.0


func weapon_attack() -> float:
	var w = rec["equipped"].get("weapon")
	return float(w["atk"]) if w is Dictionary and not Durability.is_broken(w) else 0.0


func armor_defense() -> float:
	var a = rec["equipped"].get("armor")
	return float(a["def"]) if a is Dictionary and not Durability.is_broken(a) else 0.0


func smithing_xp_to_next() -> int:
	return 40 + 30 * (int(rec["smithing_level"]) - 1)


func add_smithing_xp(amount: int) -> bool:
	rec["smithing_xp"] = int(rec["smithing_xp"]) + amount
	var leveled := false
	while int(rec["smithing_xp"]) >= smithing_xp_to_next() and int(rec["smithing_level"]) < 99:
		rec["smithing_xp"] = int(rec["smithing_xp"]) - smithing_xp_to_next()
		rec["smithing_level"] = int(rec["smithing_level"]) + 1
		leveled = true
	return leveled


# --- Life skills, buffs ---------------------------------------------------------

func life_xp_to_next(level: int) -> int:
	return 30 + 25 * (level - 1)


func add_life_xp(skill: String, amount: int) -> bool:
	var lk := skill + "_level"
	var xk := skill + "_xp"
	if not rec.has(lk):
		return false
	rec[xk] = int(rec[xk]) + amount
	var leveled := false
	while int(rec[xk]) >= life_xp_to_next(int(rec[lk])) and int(rec[lk]) < 99:
		rec[xk] = int(rec[xk]) - life_xp_to_next(int(rec[lk]))
		rec[lk] = int(rec[lk]) + 1
		leveled = true
	if leveled:
		events.append({"skill": skill, "level": rec[lk]})
	return leveled


## Buffs on a record carry an absolute expiry (unix seconds) so they survive
## a save and tick on the server's clock.
func add_buff(id: String, seconds: float, data: Dictionary) -> void:
	rec["buffs"][id] = {"name": str(data.get("name", id.capitalize())), "until": Time.get_unix_time_from_system() + seconds,
		"regen": float(data.get("regen", 0.0)), "atk": float(data.get("atk", 0.0)), "speed": float(data.get("speed", 0.0)),
		"color": str(data.get("color", "f0c060"))}


func has_buff(id: String) -> bool:
	prune_buffs()
	return rec["buffs"].has(id)


## Drops expired buffs. Returns true when something expired.
func prune_buffs() -> bool:
	var now := Time.get_unix_time_from_system()
	var gone := []
	for id in rec["buffs"]:
		if float(rec["buffs"][id].get("until", 0.0)) <= now:
			gone.append(id)
	for id in gone:
		rec["buffs"].erase(id)
	return not gone.is_empty()


func buff_value(kind: String) -> float:
	prune_buffs()
	var v := 0.0
	for id in rec["buffs"]:
		v += float(rec["buffs"][id].get(kind, 0.0))
	return v


# --- HP ------------------------------------------------------------------------

func max_hp() -> float:
	return 80.0 + int(rec["stats"].get("endurance", 0)) * 12.0 + int(rec["level"]) * 5.0 + armor_defense() * 4.0


func attack_damage() -> float:
	return (8.0 + int(rec["stats"].get("strength", 0)) * 3.0 + int(rec["level"]) + weapon_attack()) * (1.0 + buff_value("atk"))


## Same soak rule as GameState.take_damage. Returns true when it was lethal.
func take_damage(amount: float) -> bool:
	var dmg: float = max(amount - armor_defense() * 0.5, 1.0)
	rec["hp"] = max(float(rec["hp"]) - dmg, 0.0)
	return float(rec["hp"]) <= 0.0


func heal_full() -> void:
	rec["hp"] = max_hp()


## One second of buff regeneration. Returns true when hp changed.
func regen_tick(delta: float) -> bool:
	var regen := buff_value("regen")
	var hp := float(rec["hp"])
	if regen > 0.0 and hp > 0.0 and hp < max_hp():
		rec["hp"] = minf(hp + regen * delta, max_hp())
		return true
	return false


# --- Quests --------------------------------------------------------------------

func start_quest(id: String, goal: int) -> void:
	if not rec["quests"].has(id):
		rec["quests"][id] = {"progress": 0, "goal": goal, "done": false}


func advance_quest(id: String, amount := 1) -> void:
	if rec["quests"].has(id) and not rec["quests"][id]["done"]:
		rec["quests"][id]["progress"] = mini(int(rec["quests"][id]["progress"]) + amount, int(rec["quests"][id]["goal"]))


func quest_ready(id: String) -> bool:
	return rec["quests"].has(id) and not rec["quests"][id]["done"] and int(rec["quests"][id]["progress"]) >= int(rec["quests"][id]["goal"])


func quest_done(id: String) -> bool:
	return rec["quests"].has(id) and bool(rec["quests"][id]["done"])


func complete_quest(id: String) -> void:
	if rec["quests"].has(id):
		rec["quests"][id]["done"] = true


func unlock_recipe(id: String) -> void:
	if not rec["recipes_unlocked"].has(id):
		rec["recipes_unlocked"].append(id)


func recipe_unlocked(id: String) -> bool:
	return rec["recipes_unlocked"].has(id)


func _sync_gather_quests() -> void:
	for pair in GATHER_QUESTS:
		if rec["quests"].has(pair[0]) and not rec["quests"][pair[0]]["done"]:
			var q: Dictionary = rec["quests"][pair[0]]
			q["progress"] = mini(int(rec["materials"].get(pair[1], 0)), int(q["goal"]))


## Visit-objective quests (GameState.VISIT_QUESTS): records a location id
## on the record and mirrors the count into the quest. True when new.
func visit(id: String) -> bool:
	if rec["visited"].has(id):
		return false
	rec["visited"].append(id)
	sync_visit_quests()
	return true


func sync_visit_quests() -> void:
	for q in GameState.VISIT_QUESTS:
		if rec["quests"].has(q) and not rec["quests"][q]["done"]:
			rec["quests"][q]["progress"] = mini(GameState.visited_count(rec["visited"], GameState.VISIT_QUESTS[q]), int(rec["quests"][q]["goal"]))


# --- Home ---------------------------------------------------------------------

func buy_home(price: int) -> bool:
	if bool(rec["home_owned"]) or int(rec["money"]) < price:
		return false
	add_money(-price)
	rec["home_owned"] = true
	return true


func store_item(item_id: String, to_storage: bool) -> bool:
	var from: Array = rec["inventory"] if to_storage else rec["home_storage"]
	var to: Array = rec["home_storage"] if to_storage else rec["inventory"]
	var i := _find_item(from, item_id)
	if i < 0:
		return false
	if to_storage:
		for slot in rec["equipped"]:
			if rec["equipped"][slot] != null and str(rec["equipped"][slot].get("id", "")) == item_id:
				rec["equipped"][slot] = null
		_sync_weapon()
		rec["hp"] = minf(float(rec["hp"]), max_hp())
	var item: Dictionary = from[i]
	from.remove_at(i)
	to.append(item)
	return true


func add_decor(id: String, amount := 1) -> void:
	rec["decor_owned"][id] = int(rec["decor_owned"].get(id, 0)) + amount


func decor_free(id: String) -> int:
	var placed := 0
	for f in rec["home_furniture"]:
		if f == id:
			placed += 1
	return int(rec["decor_owned"].get(id, 0)) - placed


func place_furniture(slot: int, id: String) -> bool:
	if slot < 0 or slot >= GameState.HOME_SLOTS:
		return false
	if id != "" and decor_free(id) <= 0:
		return false
	rec["home_furniture"][slot] = id
	return true
