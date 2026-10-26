class_name HiddenClasses
extends RefCounted
## Floor 1 hidden classes beyond Forgeborn (GameState.HIDDEN_CLASSES holds
## the stat bonus and perk text; this file holds the rules).
##
## A hidden class is found, not bought: the server watches a hidden stat on
## the character ("hidden" in the record / save, never sent to clients) and,
## once the deed is done, an NPC who saw it offers a short quest that nobody
## is told about. The turn-in grants the class, which changes how you play:
##
##   Stillblade  (combat)  Eight clean parries in a row, no damage between
##                         them, and Quartermaster Dain at the Talven camp
##                         opens "The Unmoving Edge" (parry 10 more strikes).
##                         Guard recovers 1.6x faster. Two Sword Arts:
##                         Still Water (a counter, only in the 1.5 s after a
##                         parry) and Breaking Wave (builds posture on the
##                         target, staggering normal mobs outright).
##   Hearthwright (life)   Twelve dishes over four recipes, five fish landed
##                         and three harvests, and Innkeeper Rook (once his
##                         stew quest is done) opens "The Wandering Pot": a
##                         trail supper of Grilled Trout, Turnip Soup and
##                         Harvest Bread. Food buffs last 50% longer and are
##                         25% stronger, a Hearthwright cooks anywhere (no
##                         fire needed), and one art: Hearth Flare, a wide
##                         scatter of coals that leaves the caster glowing
##                         (a short regen buff).
##
## Casting an art goes through the validated attack path: the client sends
## the art's net kind to Enemy.net_hit and the server checks the caster's
## class (Net.srv_hidden_class) and, for Still Water, that the caster's last
## server-judged parry is recent. Classes are per character, not per realm.

const STILLBLADE := "Stillblade"
const HEARTHWRIGHT := "Hearthwright"

## Net "kind" of a class art = KIND_BASE + index into ARTS (all classes share
## one index space so the server can look an art up from the kind alone).
const KIND_BASE := 20
const ARTS := [
	{"id": "still_water", "class": STILLBLADE, "name": "Still Water", "mult": 2.4, "range": 2.8, "arc": 1.3,
		"cooldown": 6.0, "recovery": 0.4, "lunge": 6.0, "hits": 1, "after_parry": true,
		"desc": "A counter cut, only in the moment after a parry. Lunges and lands as a riposte on a staggered foe."},
	{"id": "breaking_wave", "class": STILLBLADE, "name": "Breaking Wave", "mult": 1.8, "range": 2.6, "arc": 1.1,
		"cooldown": 14.0, "recovery": 0.7, "lunge": 0.0, "hits": 1, "posture": 1,
		"desc": "A heavy pommel strike that breaks posture: staggers a normal mob outright, builds one count on a Guardian."},
	{"id": "hearth_flare", "class": HEARTHWRIGHT, "name": "Hearth Flare", "mult": 1.5, "range": 3.0, "arc": PI,
		"cooldown": 12.0, "recovery": 0.5, "lunge": 0.0, "hits": 1, "buff": "hearth_glow",
		"desc": "Scatters hot coals in a wide arc. Landing it leaves you glowing: +3 HP/s for 10 s."},
]
## Seconds after a server-judged parry in which Still Water may be cast
## (the client window; the server allows COUNTER_LATENCY on top).
const COUNTER_WINDOW := 1.5
const COUNTER_LATENCY := 0.35
## The Hearth Flare glow.
const HEARTH_GLOW := {"name": "Hearth Glow", "regen": 3.0, "atk": 0.0, "speed": 0.0, "dur": 10.0, "color": "ff9a3c"}

## Stillblade perks.
const GUARD_REGEN_MULT := 1.6
## Hearthwright perks: food buffs last longer and hit harder.
const FOOD_DURATION_MULT := 1.5
const FOOD_POWER_MULT := 1.25

## Unlock thresholds.
const STILL_STREAK := 8          # clean parries in a row (no damage taken between them)
const STILL_QUEST := "stillblade_rite"
const STILL_QUEST_GOAL := 10     # parries while the quest is open
const HEARTH_DISHES := 12
const HEARTH_RECIPES := 4
const HEARTH_FISH := 5
const HEARTH_HARVESTS := 3
const HEARTH_QUEST := "hearth_rite"
const HEARTH_SUPPER := {"grilled_trout": 1, "turnip_soup": 1, "harvest_bread": 1}
## Quest ids that never show in the log until an NPC opened them (QuestData
## marks them "hidden"; the log only lists started quests anyway).
const HIDDEN_QUESTS := [STILL_QUEST, HEARTH_QUEST]


static func is_art_kind(kind: int) -> bool:
	return kind >= KIND_BASE and kind < KIND_BASE + ARTS.size()


static func art_for_kind(kind: int) -> Dictionary:
	var i := kind - KIND_BASE
	return ARTS[i] if i >= 0 and i < ARTS.size() else {}


## The arts of a class, in cast-slot order (class art 1, class art 2).
static func arts_of(cls: String) -> Array:
	var out := []
	for a in ARTS:
		if a["class"] == cls:
			out.append(a)
	return out


## Net kind of a class's i-th art (-1 when it has none).
static func kind_of(cls: String, i: int) -> int:
	var n := 0
	for k in ARTS.size():
		if ARTS[k]["class"] == cls:
			if n == i:
				return KIND_BASE + k
			n += 1
	return -1


static func guard_regen_mult(cls: String) -> float:
	return GUARD_REGEN_MULT if cls == STILLBLADE else 1.0


## Applies the Hearthwright food perk to a buff dict (regen/atk/speed/dur).
static func food_buff(cls: String, b: Dictionary) -> Dictionary:
	var out := b.duplicate()  # always a copy: recipe buffs are const tables
	if cls != HEARTHWRIGHT:
		return out
	out["dur"] = float(b.get("dur", 0.0)) * FOOD_DURATION_MULT
	for k in ["regen", "atk", "speed"]:
		out[k] = float(b.get(k, 0.0)) * FOOD_POWER_MULT
	return out


static func cooks_anywhere(cls: String) -> bool:
	return cls == HEARTHWRIGHT


## The hidden-stat dictionary of GameState or a RecordState (created on demand).
static func stats_of(gs) -> Dictionary:
	if gs.has_method("is_record"):
		if not (gs.rec.get("hidden") is Dictionary):
			gs.rec["hidden"] = {}
		return gs.rec["hidden"]
	return gs.hidden_stats


## Records a hidden event for `gs` (GameState offline, the RecordState of the
## record on the server). Events: "parry", "hurt", "cook:<recipe>", "fish",
## "harvest". Returns true when something changed. Never grants a class by
## itself: an NPC does that at the quest turn-in.
static func note(gs, event: String) -> bool:
	var hs := stats_of(gs)
	match event:
		"parry":
			hs["clean_parries"] = int(hs.get("clean_parries", 0)) + 1
			hs["best_streak"] = maxi(int(hs.get("best_streak", 0)), int(hs["clean_parries"]))
			if int(hs["clean_parries"]) >= STILL_STREAK:
				hs["still_ready"] = true
			if gs.quests.has(STILL_QUEST) and not gs.quest_done(STILL_QUEST):
				gs.advance_quest(STILL_QUEST)
			return true
		"hurt":
			if int(hs.get("clean_parries", 0)) == 0:
				return false
			hs["clean_parries"] = 0
			return true
		"fish":
			hs["fish"] = int(hs.get("fish", 0)) + 1
			_check_hearth(hs)
			return true
		"harvest":
			hs["harvests"] = int(hs.get("harvests", 0)) + 1
			_check_hearth(hs)
			return true
	if event.begins_with("cook:"):
		var id := event.substr(5)
		hs["dishes"] = int(hs.get("dishes", 0)) + 1
		var recipes: Dictionary = hs.get("recipes", {}) if hs.get("recipes") is Dictionary else {}
		recipes[id] = true
		hs["recipes"] = recipes
		_check_hearth(hs)
		return true
	return false


static func _check_hearth(hs: Dictionary) -> void:
	var recipes: Dictionary = hs.get("recipes", {}) if hs.get("recipes") is Dictionary else {}
	if int(hs.get("dishes", 0)) >= HEARTH_DISHES and recipes.size() >= HEARTH_RECIPES \
			and int(hs.get("fish", 0)) >= HEARTH_FISH and int(hs.get("harvests", 0)) >= HEARTH_HARVESTS:
		hs["hearth_ready"] = true


static func still_ready(gs) -> bool:
	return bool(stats_of(gs).get("still_ready", false))


static func hearth_ready(gs) -> bool:
	return bool(stats_of(gs).get("hearth_ready", false))


## Everything the trail supper needs is in the pack.
static func has_supper(gs) -> bool:
	return gs.has_materials(HEARTH_SUPPER)


## Supper dishes carried, for the quest's progress (0..3).
static func supper_count(gs) -> int:
	var n := 0
	for id in HEARTH_SUPPER:
		if int(gs.materials.get(id, 0)) >= int(HEARTH_SUPPER[id]):
			n += 1
	return n
