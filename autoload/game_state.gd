extends Node
## Holds the player's character: appearance, stats, level, gear and progress.
## Everything here is plain data so SaveSystem can serialize it as JSON.

signal xp_changed(xp: int, xp_to_next: int)
## Equipped gear crossed a durability line: state is "low" or "broken".
signal gear_state(slot: String, state: String)
signal leveled_up(level: int)
signal stats_changed
signal health_changed(hp: float, max_hp: float)
signal money_changed(money: int)
signal quest_changed
signal inventory_changed
signal class_unlocked(class_name_: String)
## Life layer (fishing, cooking, home): see scripts/life/life_data.gd.
signal buffs_changed
signal home_changed
signal life_skill_up(skill: String, level: int)
signal unique_skill_changed(id: String)

# Starting classes. Hidden classes unlock later through quests.
const ORIGINS := {
	"Swordsman": {"strength": 3, "agility": 2, "endurance": 2, "spirit": 1},
	"Scout": {"strength": 1, "agility": 4, "endurance": 1, "spirit": 2},
	"Guardian": {"strength": 2, "agility": 1, "endurance": 4, "spirit": 1},
	"Arcanist": {"strength": 1, "agility": 2, "endurance": 1, "spirit": 4},
}
# Hidden classes: name -> stat bonus and perk text. Unlocked by secret quests.
const HIDDEN_CLASSES := {
	"Forgeborn": {"bonus": {"strength": 3, "endurance": 2}, "perk": "Crafted gear rolls one rank higher more often."},
	# Rules, arts and unlock deeds: scripts/hidden_classes.gd.
	"Stillblade": {"bonus": {"agility": 2, "endurance": 2, "strength": 1}, "perk": "Guard recovers faster. Still Water counters right after a parry; Breaking Wave staggers."},
	"Hearthwright": {"bonus": {"endurance": 2, "spirit": 2, "agility": 1}, "perk": "Food lasts longer and works harder. Cook anywhere. Hearth Flare scatters coals and leaves you glowing."},
}
const STAT_NAMES := ["strength", "agility", "endurance", "spirit"]
const POINTS_PER_LEVEL := 3
const CREATOR_POINTS := 5
const MATERIAL_NAMES := {"iron_ore": "Iron Ore", "beast_hide": "Beast Hide", "spirit_shard": "Spirit Shard",
	"stag_horn": "Stag Horn", "wisp_essence": "Wisp Essence", "wolf_pelt": "Wolf Pelt",
	# Life layer: fish, gatherables, tools and cooked food are stackable
	# materials too (LifeData groups them; the inventory screen shows them
	# under Provisions, not in the smithing materials strip).
	"minnow": "Minnow", "river_trout": "River Trout", "mire_eel": "Mire Eel", "moonscale_koi": "Moonscale Koi",
	"wild_herb": "Wild Herb", "willow_rod": "Willow Rod",
	"grilled_trout": "Grilled Trout", "boar_stew": "Boar Stew", "eel_pie": "Eel Pie", "koi_sashimi": "Koi Sashimi",
	# Farm plots (P8): seeds, crops and the dishes they cook into.
	"turnip_seeds": "Turnip Seeds", "sunwheat_seeds": "Sunwheat Seeds", "honeymelon_seeds": "Honeymelon Seeds",
	"turnip": "Turnip", "sunwheat": "Sunwheat", "honeymelon": "Honeymelon",
	"turnip_soup": "Turnip Soup", "harvest_bread": "Harvest Bread", "melon_tart": "Honeymelon Tart",
	# Labyrinth: opens the terraces' locked vaults (LabyrinthFeatures).
	"terrace_key": "Terrace Key",
	# One-use crystals (LifeData.CRYSTALS).
	"heal_crystal": "Healing Crystal", "teleport_crystal": "Teleport Crystal",
	# Snaptrap Grove: the flowering vine's crown (Hesper's grove_bloom errand).
	"snaptrap_bloom": "Snaptrap Bloom"}
## Floor layout data the world and the player need before the scene exists:
## where a character arrives on each floor (also the respawn point).
const FLOOR_SPAWNS := {1: Vector3(0, 1, 6), 2: Vector3(0, 1, 37)}
const FLOOR_NAMES := {1: "Town of First Light", 2: "Mirewood"}

var character := {}
var level := 1
var xp := 0
var stat_points := 0
var stats := {}
var money := 0
var hp := 100.0
var position := Vector3.ZERO
var has_position := false
var quests := {}  # quest_id -> {"progress": int, "goal": int, "done": bool}
var materials := {}  # material id -> count
var inventory: Array = []  # crafted/looted items (see Crafting.make_item)
var equipped := {"weapon": null, "armor": null}
var smithing_level := 1
var smithing_xp := 0
var items_crafted := 0
var hidden_class := ""
## One-holder-per-realm skill this character holds ("" none; UniqueSkills).
var unique_skill := ""
## Hidden stats that unique skills watch (never shown, never sent to clients).
var hidden_stats := {}
var floors_cleared := 0
## One-Handed Sword proficiency, 0..PROF_CAP: rises by one per landed swing
## and unlocks the later Sword Arts (Player.SKILLS "prof").
var sword_prof := 0
const PROF_CAP := 1000
## Which floor of the Spire this character is on (1-based). Offline it is
## saved with the character; online it follows the server (one server = one
## floor). A dedicated server reads it from `--floor N`.
var floor := 1
## Recipe ids unlocked by quests (see Crafting.RECIPES "unlock").
var recipes_unlocked: Array = []
## --- Life layer -------------------------------------------------------------
## Fishing and cooking level like smithing; the cottage in Hollowbrook with
## its storage chest (items moved out of the pack), six furniture slots
## (decoration ids or "") and the decorations bought from the trader.
var fishing_level := 1
var fishing_xp := 0
var cooking_level := 1
var cooking_xp := 0
var farming_level := 1
var farming_xp := 0
var fish_caught := 0
var home_owned := false
var home_storage: Array = []
var home_furniture: Array = ["", "", "", "", "", ""]
var decor_owned := {}  # decoration id -> count (unplaced + placed)
## Active food/rest buffs: id -> {"name", "left" (s), "regen" (hp/s), "atk" (fraction), "speed" (fraction)}.
var buffs := {}
const HOME_SLOTS := 6
## Title earned from a quest chain (shown beside the class in the HUD).
var title := ""
## Location ids visited for visit-objective quests ("waystone_0" ...).
var visited: Array = []
## Labyrinth chests this character opened: {chest_id: unix seconds}.
var chests: Dictionary = {}
## Duel record (scripts/duels.gd): {"won": n, "lost": n}.
var duels: Dictionary = {"won": 0, "lost": 0}
## Permadeath only: how this character fell ({} while alive; Permadeath).
var fallen: Dictionary = {}


func _ready() -> void:
	reset()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--floor" and i + 1 < args.size():
			floor = clampi(int(args[i + 1]), 1, 2)


func reset() -> void:
	character = {
		"name": "Nameless",
		"origin": "Swordsman",
		"hair_color": "1a1a2e",
		"skin_color": "f2d0b5",
		"eye_color": "4cc9f0",
		"outfit_color": "e63946",
		"hair_style": 0,
		"body": "alicia",
		"height": 1.0,
	}
	level = 1
	xp = 0
	stat_points = 0
	money = 50
	stats = ORIGINS["Swordsman"].duplicate()
	quests = {}
	materials = {"iron_ore": 0, "beast_hide": 0, "spirit_shard": 0, "stag_horn": 0, "wisp_essence": 0, "wolf_pelt": 0}
	inventory = []
	equipped = {"weapon": null, "armor": null}
	smithing_level = 1
	smithing_xp = 0
	items_crafted = 0
	hidden_class = ""
	unique_skill = ""
	hidden_stats = {}
	floors_cleared = 0
	sword_prof = 0
	floor = 1
	recipes_unlocked = []
	fishing_level = 1
	fishing_xp = 0
	cooking_level = 1
	cooking_xp = 0
	farming_level = 1
	farming_xp = 0
	fish_caught = 0
	home_owned = false
	home_storage = []
	home_furniture = ["", "", "", "", "", ""]
	decor_owned = {}
	buffs = {}
	title = ""
	visited = []
	chests = {}
	duels = {"won": 0, "lost": 0}
	fallen = {}
	has_position = false
	hp = max_hp()


func apply_origin(origin: String) -> void:
	character["origin"] = origin
	stats = ORIGINS[origin].duplicate()


func class_title() -> String:
	return hidden_class if hidden_class != "" else character["origin"]


## Offline: a hidden-stat event for the local character. Online the server
## does this on the record (Net.note_hidden picks the right side).
func note_hidden(event: String) -> void:
	HiddenClasses.note(self, event)  # hidden-class deeds (parry streaks, dishes, catches)
	if not UniqueSkills.note(hidden_stats, event, Time.get_ticks_msec() / 1000.0):
		return
	var realm = Net.get_realm()
	var id := UniqueSkills.try_grant(realm, Net.local_holder(), level, hidden_stats, unique_skill)
	if id != "":
		unique_skill = id
		unique_skill_changed.emit(id)
		Net.srv_announce(UniqueSkills.announce_text(str(character.get("name", "Someone")), id))


func unlock_hidden_class(cls: String) -> void:
	if hidden_class == cls or not HIDDEN_CLASSES.has(cls):
		return
	hidden_class = cls
	for s in HIDDEN_CLASSES[cls]["bonus"]:
		stats[s] += HIDDEN_CLASSES[cls]["bonus"][s]
	stats_changed.emit()
	heal_full()
	class_unlocked.emit(cls)


## Proficiency credited to a character that predates the stat.
static func prof_for_level(lv: int) -> int:
	return clampi((lv - 1) * 60, 0, PROF_CAP)


## One landed swing: +n proficiency. Returns the name of a Sword Art this
## just unlocked, or "".
func add_sword_prof(n := 1) -> String:
	var before := sword_prof
	sword_prof = mini(sword_prof + n, PROF_CAP)
	for sk in Player.SKILLS:
		if before < int(sk["prof"]) and sword_prof >= int(sk["prof"]):
			return str(sk["name"])
	return ""


## Where the player arrives (and respawns) on the current floor.
func spawn_point() -> Vector3:
	return FLOOR_SPAWNS.get(floor, FLOOR_SPAWNS[1])


func floor_name() -> String:
	return FLOOR_NAMES.get(floor, "Floor %d" % floor)


## Client auth relay: the server announces its floor during the join
## handshake ({"floor": n} via send_auth). Returns a Callable bound here (an
## autoload, so it outlives the menu) that forwards every packet to `prev`
## (Net's own callback) and, on the floor packet, sets `floor` and calls
## `on_floor` if that target still exists.
func auth_floor_relay(prev: Callable, on_floor: Callable) -> Callable:
	return Callable(self, "_auth_relay").bind(prev, on_floor)


func _auth_relay(peer: int, data: PackedByteArray, prev: Callable, on_floor: Callable) -> void:
	if prev.is_valid():
		prev.call(peer, data)
	var v = bytes_to_var(data)
	if typeof(v) == TYPE_DICTIONARY and v.has("floor"):
		floor = clampi(int(v["floor"]), 1, 2)
		if on_floor.is_valid():
			on_floor.call()


func unlock_recipe(id: String) -> void:
	if not recipes_unlocked.has(id):
		recipes_unlocked.append(id)
		inventory_changed.emit()


func recipe_unlocked(id: String) -> bool:
	return recipes_unlocked.has(id)


func xp_to_next() -> int:
	# Gentle curve: 100, 175, 270, 385 ...
	return int(100 + 50 * (level - 1) + 25 * pow(level - 1, 1.6))


func add_xp(amount: int) -> void:
	amount = Permadeath.xp_gain(self, amount)
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		stat_points += POINTS_PER_LEVEL
		hp = max_hp()
		leveled_up.emit(level)
		health_changed.emit(hp, max_hp())
	xp_changed.emit(xp, xp_to_next())


func spend_point(stat: String) -> bool:
	if stat_points <= 0 or not stats.has(stat):
		return false
	stat_points -= 1
	stats[stat] += 1
	stats_changed.emit()
	health_changed.emit(hp, max_hp())
	return true


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)


# --- Materials, items, gear ---------------------------------------------

func add_material(id: String, amount := 1) -> void:
	materials[id] = materials.get(id, 0) + amount
	inventory_changed.emit()


func has_materials(cost: Dictionary) -> bool:
	for id in cost:
		if materials.get(id, 0) < cost[id]:
			return false
	return true


func spend_materials(cost: Dictionary) -> void:
	for id in cost:
		materials[id] -= cost[id]
	inventory_changed.emit()


func add_item(item: Dictionary) -> void:
	inventory.append(item)
	inventory_changed.emit()


func equip(item: Dictionary) -> void:
	equipped[item["kind"]] = item
	stats_changed.emit()
	health_changed.emit(hp, max_hp())
	inventory_changed.emit()


func smithing_xp_to_next() -> int:
	return 40 + 30 * (smithing_level - 1)


func add_smithing_xp(amount: int) -> bool:
	smithing_xp += amount
	var leveled := false
	while smithing_xp >= smithing_xp_to_next():
		smithing_xp -= smithing_xp_to_next()
		smithing_level += 1
		leveled = true
	inventory_changed.emit()
	return leveled


# --- Life skills (fishing, cooking) --------------------------------------

func life_xp_to_next(level: int) -> int:
	return 30 + 25 * (level - 1)


## Adds xp to "fishing" or "cooking". Returns true on a level-up.
func add_life_xp(skill: String, amount: int) -> bool:
	var leveled := false
	if skill == "fishing":
		fishing_xp += amount
		while fishing_xp >= life_xp_to_next(fishing_level):
			fishing_xp -= life_xp_to_next(fishing_level)
			fishing_level += 1
			leveled = true
		if leveled:
			life_skill_up.emit("fishing", fishing_level)
	elif skill == "cooking":
		cooking_xp += amount
		while cooking_xp >= life_xp_to_next(cooking_level):
			cooking_xp -= life_xp_to_next(cooking_level)
			cooking_level += 1
			leveled = true
		if leveled:
			life_skill_up.emit("cooking", cooking_level)
	elif skill == "farming":
		farming_xp += amount
		while farming_xp >= life_xp_to_next(farming_level) and farming_level < 99:
			farming_xp -= life_xp_to_next(farming_level)
			farming_level += 1
			leveled = true
		if leveled:
			life_skill_up.emit("farming", farming_level)
	inventory_changed.emit()
	return leveled


## Starts (or refreshes) a timed buff. `data` carries regen/atk/speed/name.
func add_buff(id: String, seconds: float, data: Dictionary) -> void:
	var b := {"name": str(data.get("name", id.capitalize())), "left": seconds,
		"regen": float(data.get("regen", 0.0)), "atk": float(data.get("atk", 0.0)), "speed": float(data.get("speed", 0.0)),
		"color": str(data.get("color", "f0c060"))}
	buffs[id] = b
	buffs_changed.emit()


func has_buff(id: String) -> bool:
	return buffs.has(id)


## Sum of one buff field ("regen", "atk" or "speed") over the active buffs.
func buff_value(kind: String) -> float:
	var v := 0.0
	for id in buffs:
		v += float(buffs[id].get(kind, 0.0))
	return v


## Ticks buff timers and HP regeneration. Called from _process, and by tests
## directly with a fixed delta.
func tick_buffs(delta: float) -> void:
	if buffs.is_empty():
		return
	var expired := []
	for id in buffs:
		buffs[id]["left"] = float(buffs[id]["left"]) - delta
		if buffs[id]["left"] <= 0.0:
			expired.append(id)
	var regen := buff_value("regen")
	if regen > 0.0 and hp > 0.0 and hp < max_hp():
		hp = minf(hp + regen * delta, max_hp())
		health_changed.emit(hp, max_hp())
	for id in expired:
		buffs.erase(id)
	if not expired.is_empty():
		buffs_changed.emit()


func _process(delta: float) -> void:
	tick_buffs(delta)


# --- Home ------------------------------------------------------------------

func buy_home(price: int) -> bool:
	if home_owned or money < price:
		return false
	add_money(-price)
	home_owned = true
	home_changed.emit()
	return true


## Moves an item (by id) from the pack into the cottage chest or back.
func store_item(item_id: String, to_storage: bool) -> bool:
	var from: Array = inventory if to_storage else home_storage
	var to: Array = home_storage if to_storage else inventory
	for i in from.size():
		if str(from[i].get("id", "")) == item_id:
			var item: Dictionary = from[i]
			if to_storage:
				for slot in equipped:
					if equipped[slot] != null and equipped[slot].get("id") == item_id:
						equipped[slot] = null
						stats_changed.emit()
						hp = minf(hp, max_hp())
			from.remove_at(i)
			to.append(item)
			inventory_changed.emit()
			home_changed.emit()
			return true
	return false


func add_decor(id: String, amount := 1) -> void:
	decor_owned[id] = int(decor_owned.get(id, 0)) + amount
	home_changed.emit()


## Decorations bought but not standing in a slot.
func decor_free(id: String) -> int:
	var placed := 0
	for f in home_furniture:
		if f == id:
			placed += 1
	return int(decor_owned.get(id, 0)) - placed


## Puts decoration `id` ("" clears) in furniture slot `slot`.
func place_furniture(slot: int, id: String) -> bool:
	if slot < 0 or slot >= HOME_SLOTS:
		return false
	if id != "" and decor_free(id) <= 0:
		return false
	home_furniture[slot] = id
	home_changed.emit()
	return true


# --- Derived stats -------------------------------------------------------

## A broken piece (Durability) adds nothing until it is repaired.
func weapon_attack() -> float:
	return equipped["weapon"]["atk"] if equipped["weapon"] != null and not Durability.is_broken(equipped["weapon"]) else 0.0


func armor_defense() -> float:
	return equipped["armor"]["def"] if equipped["armor"] != null and not Durability.is_broken(equipped["armor"]) else 0.0


## Wears equipped gear (Durability.wear). Offline / host announce the
## "low" and "broken" moments through gear_state; an online client only
## mirrors the wear (the server sends its own "gear" event).
func wear_gear(slot: String, amount: float) -> void:
	var ev := Durability.wear(self, slot, amount)
	if ev != "" and not Net.remote_client():
		gear_state.emit(slot, ev)
		if slot == "armor" and ev == "broken":
			hp = minf(hp, max_hp())
			health_changed.emit(hp, max_hp())


func max_hp() -> float:
	return 80.0 + stats.get("endurance", 0) * 12.0 + level * 5.0 + armor_defense() * 4.0


func attack_damage() -> float:
	return (8.0 + stats.get("strength", 0) * 3.0 + level + weapon_attack()) * (1.0 + buff_value("atk"))


func move_speed() -> float:
	return (5.0 + stats.get("agility", 0) * 0.25) * (1.0 + buff_value("speed"))


func take_damage(amount: float) -> void:
	# Armor soaks half its defense value per hit; every hit does at least 1.
	var dmg: float = max(amount - armor_defense() * 0.5, 1.0)
	Permadeath.note_hurt(self)
	hp = max(hp - dmg, 0.0)
	wear_gear("armor", Durability.WEAR_HIT)
	health_changed.emit(hp, max_hp())


func heal_full() -> void:
	hp = max_hp()
	health_changed.emit(hp, max_hp())


# --- Quests --------------------------------------------------------------

func start_quest(id: String, goal: int) -> void:
	if not quests.has(id):
		quests[id] = {"progress": 0, "goal": goal, "done": false}
		quest_changed.emit()


func advance_quest(id: String, amount := 1) -> void:
	if quests.has(id) and not quests[id]["done"]:
		quests[id]["progress"] = min(quests[id]["progress"] + amount, quests[id]["goal"])
		quest_changed.emit()


func quest_ready(id: String) -> bool:
	return quests.has(id) and not quests[id]["done"] and quests[id]["progress"] >= quests[id]["goal"]


func quest_done(id: String) -> bool:
	return quests.has(id) and quests[id]["done"]


func complete_quest(id: String) -> void:
	if quests.has(id):
		quests[id]["done"] = true
		quest_changed.emit()


## Visit-objective quests: progress mirrors how many "<prefix>_N" ids are in
## `visited` (world._light_beacon, RecordState.visit online).
const VISIT_QUESTS := {"talven_waystones": "waystone_"}


static func visited_count(list: Array, prefix: String) -> int:
	var n := 0
	for v in list:
		if str(v).begins_with(prefix):
			n += 1
	return n


static func _parse_duels(raw) -> Dictionary:
	var out := {"won": 0, "lost": 0}
	if raw is Dictionary:
		out["won"] = maxi(int(raw.get("won", 0)), 0)
		out["lost"] = maxi(int(raw.get("lost", 0)), 0)
	return out


static func _parse_chests(raw) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for k in raw:
			if k is String and k.length() <= 24 and out.size() < 32:
				out[k] = float(raw[k])
	return out


## Records a visited location. Returns true when it was new.
func visit(id: String) -> bool:
	if visited.has(id):
		return false
	visited.append(id)
	sync_visit_quests()
	return true


func sync_visit_quests() -> void:
	var changed := false
	for q in VISIT_QUESTS:
		if quests.has(q) and not quests[q]["done"]:
			var have: int = min(visited_count(visited, VISIT_QUESTS[q]), int(quests[q]["goal"]))
			if int(quests[q]["progress"]) != have:
				quests[q]["progress"] = have
				changed = true
	if changed:
		quest_changed.emit()


# --- Serialization -------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": 2,
		"character": character,
		"level": level,
		"xp": xp,
		"stat_points": stat_points,
		"stats": stats,
		"money": money,
		"hp": hp,
		"position": [position.x, position.y, position.z],
		"quests": quests,
		"materials": materials,
		"inventory": inventory,
		"equipped": equipped,
		"smithing_level": smithing_level,
		"smithing_xp": smithing_xp,
		"items_crafted": items_crafted,
		"hidden_class": hidden_class,
		"unique_skill": unique_skill,
		"hidden": hidden_stats,
		"floors_cleared": floors_cleared,
		"sword_prof": sword_prof,
		"floor": floor,
		"recipes_unlocked": recipes_unlocked,
		"fishing_level": fishing_level,
		"fishing_xp": fishing_xp,
		"cooking_level": cooking_level,
		"cooking_xp": cooking_xp,
		"farming_level": farming_level,
		"farming_xp": farming_xp,
		"fish_caught": fish_caught,
		"home_owned": home_owned,
		"home_storage": home_storage,
		"home_furniture": home_furniture,
		"decor_owned": decor_owned,
		"buffs": buffs,
		"title": title,
		"visited": visited,
		"chests": chests,
		"duels": duels,
		"fallen": fallen,
	}


## Online: the server answered an action with the record's progress fields
## (Net.patch_for_client). Adopt them and emit the same signals the local
## code path would have, so HUD, feed, quest log and buffs follow. Looks,
## floor and position are never part of a patch.
func apply_patch(d: Dictionary) -> void:
	var prev_level := level
	var prev_class := hidden_class
	var prev_fish := fishing_level
	var prev_cook := cooking_level
	var prev_farm := farming_level
	var prev_hp := hp
	level = clampi(int(d.get("level", level)), 1, 100)
	xp = maxi(int(d.get("xp", xp)), 0)
	stat_points = maxi(int(d.get("stat_points", stat_points)), 0)
	var raw_stats = d.get("stats", {})
	if raw_stats is Dictionary:
		for s in STAT_NAMES:
			stats[s] = int(raw_stats.get(s, stats.get(s, 0)))
	money = maxi(int(d.get("money", money)), 0)
	var raw_quests = d.get("quests")
	if raw_quests is Dictionary:
		quests = {}
		for id in raw_quests:
			var q = raw_quests[id]
			if q is Dictionary:
				quests[str(id)] = {"progress": int(q.get("progress", 0)), "goal": int(q.get("goal", 1)), "done": bool(q.get("done", false))}
	var raw_mats = d.get("materials")
	if raw_mats is Dictionary:
		for m in raw_mats:
			if MATERIAL_NAMES.has(m):
				materials[m] = int(raw_mats[m])
	if d.get("inventory") is Array:
		inventory = _parse_items(d["inventory"], 60, "")
	if d.has("equipped"):
		equipped = {"weapon": null, "armor": null}
		var eq = d["equipped"]
		if eq is Dictionary:
			for slot in ["weapon", "armor"]:
				var it = eq.get(slot)
				if it is Dictionary and it.has("id"):
					for inv_item in inventory:
						if inv_item["id"] == it["id"]:
							equipped[slot] = inv_item
	smithing_level = clampi(int(d.get("smithing_level", smithing_level)), 1, 99)
	smithing_xp = maxi(int(d.get("smithing_xp", smithing_xp)), 0)
	items_crafted = maxi(int(d.get("items_crafted", items_crafted)), 0)
	var hc := str(d.get("hidden_class", hidden_class))
	hidden_class = hc if HIDDEN_CLASSES.has(hc) else ""
	var prev_unique := unique_skill
	var us := str(d.get("unique_skill", unique_skill))
	unique_skill = us if UniqueSkills.is_unique(us) else ""
	floors_cleared = maxi(int(d.get("floors_cleared", floors_cleared)), 0)
	sword_prof = clampi(int(d.get("sword_prof", sword_prof)), 0, PROF_CAP)
	if d.get("recipes_unlocked") is Array:
		recipes_unlocked = []
		for r in d["recipes_unlocked"]:
			if r is String:
				recipes_unlocked.append(r)
	fishing_level = clampi(int(d.get("fishing_level", fishing_level)), 1, 99)
	fishing_xp = maxi(int(d.get("fishing_xp", fishing_xp)), 0)
	cooking_level = clampi(int(d.get("cooking_level", cooking_level)), 1, 99)
	cooking_xp = maxi(int(d.get("cooking_xp", cooking_xp)), 0)
	farming_level = clampi(int(d.get("farming_level", farming_level)), 1, 99)
	farming_xp = maxi(int(d.get("farming_xp", farming_xp)), 0)
	fish_caught = maxi(int(d.get("fish_caught", fish_caught)), 0)
	home_owned = bool(d.get("home_owned", home_owned))
	if d.get("home_storage") is Array:
		home_storage = _parse_items(d["home_storage"], 60, "s")
	var raw_furn = d.get("home_furniture")
	if raw_furn is Array:
		home_furniture = ["", "", "", "", "", ""]
		for i in mini(raw_furn.size(), HOME_SLOTS):
			home_furniture[i] = str(raw_furn[i]).left(24)
	var raw_decor = d.get("decor_owned")
	if raw_decor is Dictionary:
		decor_owned = {}
		for k in raw_decor:
			decor_owned[str(k).left(24)] = clampi(int(raw_decor[k]), 0, 99)
	if d.get("buffs") is Dictionary:
		buffs = _parse_buffs(d["buffs"])
	if d.has("title"):
		title = str(d["title"]).left(32)
	if d.get("visited") is Array:
		visited = _parse_visited(d["visited"])
	if d.get("chests") is Dictionary:
		chests = _parse_chests(d["chests"])
	if d.get("duels") is Dictionary:
		duels = _parse_duels(d["duels"])
	hp = clampf(float(d.get("hp", hp)), 0.0, max_hp())
	stats_changed.emit()
	xp_changed.emit(xp, xp_to_next())
	money_changed.emit(money)
	inventory_changed.emit()
	quest_changed.emit()
	buffs_changed.emit()
	home_changed.emit()
	if level > prev_level:
		leveled_up.emit(level)
	if hidden_class != "" and hidden_class != prev_class:
		class_unlocked.emit(hidden_class)
	if unique_skill != prev_unique:
		unique_skill_changed.emit(unique_skill)
	if fishing_level > prev_fish:
		life_skill_up.emit("fishing", fishing_level)
	if cooking_level > prev_cook:
		life_skill_up.emit("cooking", cooking_level)
	if farming_level > prev_farm:
		life_skill_up.emit("farming", farming_level)
	if hp != prev_hp or level != prev_level:
		health_changed.emit(hp, max_hp())


## Whitelists a list of gear dictionaries (save file, server patch).
func _parse_items(raw: Array, cap: int, id_suffix: String) -> Array:
	var out: Array = []
	for item in raw:
		if item is Dictionary and item.has("name") and item.get("kind") in ["weapon", "armor"] and out.size() < cap:
			item["rank"] = clampi(int(item.get("rank", 0)), 0, 5)
			item["atk"] = int(item.get("atk", 0))
			item["def"] = int(item.get("def", 0))
			if not item.has("id"):
				item["id"] = "%s_%s%d" % [item["name"], id_suffix, out.size()]
			out.append(item)
	return out


func _parse_visited(raw: Array) -> Array:
	var out: Array = []
	for v in raw:
		if v is String and v.length() <= 32 and out.size() < 200 and not out.has(v):
			out.append(v)
	return out


func _parse_buffs(raw: Dictionary) -> Dictionary:
	var out := {}
	for k in raw:
		var b = raw[k]
		if b is Dictionary and float(b.get("left", 0.0)) > 0.0:
			out[str(k).left(32)] = {"name": str(b.get("name", k)).left(32), "left": minf(float(b.get("left", 0.0)), 3600.0),
				"regen": clampf(float(b.get("regen", 0.0)), 0.0, 50.0), "atk": clampf(float(b.get("atk", 0.0)), 0.0, 1.0),
				"speed": clampf(float(b.get("speed", 0.0)), 0.0, 1.0), "color": str(b.get("color", "f0c060")).left(8)}
	return out


func from_dict(d: Dictionary) -> void:
	reset()
	var raw_char = d.get("character", {})
	if raw_char is Dictionary:
		character.merge(raw_char, true)
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	stat_points = int(d.get("stat_points", 0))
	var raw_stats = d.get("stats", {})
	if raw_stats is Dictionary:
		for s in STAT_NAMES:
			stats[s] = int(raw_stats.get(s, stats[s]))
	money = int(d.get("money", 0))
	var p = d.get("position")
	if p is Array and p.size() == 3:
		position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		has_position = true
	var raw_quests = d.get("quests", {})
	quests = {}
	if raw_quests is Dictionary:
		for id in raw_quests:
			var q = raw_quests[id]
			if q is Dictionary:
				quests[id] = {"progress": int(q.get("progress", 0)), "goal": int(q.get("goal", 1)), "done": bool(q.get("done", false))}
	var raw_mats = d.get("materials", {})
	if raw_mats is Dictionary:
		for m in raw_mats:
			if MATERIAL_NAMES.has(m):
				materials[m] = int(raw_mats[m])
	inventory = []
	var raw_inv = d.get("inventory", [])
	if raw_inv is Array:
		inventory = _parse_items(raw_inv, 1000000, "")
	var eq = d.get("equipped", {})
	equipped = {"weapon": null, "armor": null}
	if eq is Dictionary:
		for slot in ["weapon", "armor"]:
			var it = eq.get(slot)
			if it is Dictionary and it.has("id"):
				# Re-point at the inventory copy so "Equipped" matches by id.
				for inv_item in inventory:
					if inv_item["id"] == it["id"]:
						equipped[slot] = inv_item
	smithing_level = int(d.get("smithing_level", 1))
	smithing_xp = int(d.get("smithing_xp", 0))
	items_crafted = int(d.get("items_crafted", 0))
	hidden_class = str(d.get("hidden_class", ""))
	if not HIDDEN_CLASSES.has(hidden_class):
		hidden_class = ""
	unique_skill = str(d.get("unique_skill", ""))
	if not UniqueSkills.is_unique(unique_skill):
		unique_skill = ""
	hidden_stats = d.get("hidden", {}).duplicate(true) if d.get("hidden") is Dictionary else {}
	floors_cleared = int(d.get("floors_cleared", 0))
	# Saves from before proficiency existed: credit the levels already earned.
	sword_prof = clampi(int(d.get("sword_prof", prof_for_level(int(d.get("level", 1))))), 0, PROF_CAP)
	floor = clampi(int(d.get("floor", 1)), 1, 2)
	recipes_unlocked = []
	var raw_rec = d.get("recipes_unlocked", [])
	if raw_rec is Array:
		for r in raw_rec:
			if r is String:
				recipes_unlocked.append(r)
	fishing_level = clampi(int(d.get("fishing_level", 1)), 1, 99)
	fishing_xp = maxi(int(d.get("fishing_xp", 0)), 0)
	cooking_level = clampi(int(d.get("cooking_level", 1)), 1, 99)
	cooking_xp = maxi(int(d.get("cooking_xp", 0)), 0)
	farming_level = clampi(int(d.get("farming_level", 1)), 1, 99)
	farming_xp = maxi(int(d.get("farming_xp", 0)), 0)
	fish_caught = maxi(int(d.get("fish_caught", 0)), 0)
	home_owned = bool(d.get("home_owned", false))
	home_storage = []
	var raw_store = d.get("home_storage", [])
	if raw_store is Array:
		home_storage = _parse_items(raw_store, 60, "s")
	home_furniture = ["", "", "", "", "", ""]
	var raw_furn = d.get("home_furniture", [])
	if raw_furn is Array:
		for i in mini(raw_furn.size(), HOME_SLOTS):
			home_furniture[i] = str(raw_furn[i]).left(24)
	decor_owned = {}
	var raw_decor = d.get("decor_owned", {})
	if raw_decor is Dictionary:
		for k in raw_decor:
			decor_owned[str(k).left(24)] = clampi(int(raw_decor[k]), 0, 99)
	buffs = {}
	var raw_buffs = d.get("buffs", {})
	if raw_buffs is Dictionary:
		buffs = _parse_buffs(raw_buffs)
	title = str(d.get("title", "")).left(32)
	visited = []
	var raw_visited = d.get("visited", [])
	if raw_visited is Array:
		visited = _parse_visited(raw_visited)
	chests = _parse_chests(d.get("chests", {}))
	duels = _parse_duels(d.get("duels", {}))
	fallen = d["fallen"].duplicate() if d.get("fallen") is Dictionary else {}
	hp = float(d.get("hp", max_hp()))
