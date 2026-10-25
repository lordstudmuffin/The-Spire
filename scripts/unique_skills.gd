class_name UniqueSkills
extends RefCounted
## Unique skills: skill lines only ONE character in the realm can hold at a
## time (claim cap 1 in the realm DB, kind "skill": released after 14 days
## inactive or on character delete; see docs/REALM_DB.md).
##
## They are never bought or quested openly. The server watches a hidden stat
## per character and grants the skill to the first to cross its threshold
## while the skill is free. Twin Fang watches "reaction": dodging a mob's
## wind-up at the last moment and fast kill chains.
##
## The hidden stats live in the record / save under "hidden" and are never
## sent to clients. Casting a unique Sword Art is checked against the realm
## registry on the server (Enemy.net_hit -> Net.srv_holds_unique).

const TWIN_FANG := "twin_fang"

## Net "kind" of a unique Sword Art = KIND_BASE + index into its arts.
const KIND_BASE := 10

const SKILLS := {
	TWIN_FANG: {
		"name": "Twin Fang",
		"desc": "Fight with a blade in each hand. Granted to the swordsman with the fastest reactions in the realm.",
		"stat": "reaction",
		"threshold": 30,
		"min_level": 5,
		"arts": [
			{"name": "Crossing Gale", "mult": 3.0, "range": 2.6, "arc": 1.6, "cooldown": 9.0, "recovery": 0.55, "lunge": 0.0, "hits": 2},
			{"name": "Sixfold Rush", "mult": 5.4, "range": 2.6, "arc": 1.2, "cooldown": 18.0, "recovery": 1.1, "lunge": 7.0, "hits": 6},
			{"name": "Mirror Fang", "mult": 3.6, "range": 2.9, "arc": PI, "cooldown": 12.0, "recovery": 0.7, "lunge": 11.0, "hits": 3},
		],
	},
}

## Kill chain: CHAIN_LEN kills inside CHAIN_WINDOW seconds count as one
## reaction point. Dodges count at most once per DODGE_GAP seconds.
const CHAIN_WINDOW := 8.0
const CHAIN_LEN := 3
const DODGE_GAP := 1.5


static func is_unique(id: String) -> bool:
	return SKILLS.has(id)


static func display_name(id: String) -> String:
	return str(SKILLS[id]["name"]) if SKILLS.has(id) else ""


static func arts(id: String) -> Array:
	return SKILLS[id]["arts"] if SKILLS.has(id) else []


## The art behind a net kind, or {} (only the holder's own skill matters, so
## one skill's art table is enough while there is one unique skill).
static func art_for_kind(kind: int, id := TWIN_FANG) -> Dictionary:
	var a := arts(id)
	var i := kind - KIND_BASE
	return a[i] if i >= 0 and i < a.size() else {}


static func is_unique_kind(kind: int) -> bool:
	return kind >= KIND_BASE and kind < KIND_BASE + 10


## Records a hidden-stat event ("dodge" or "kill") on `hs` (the record's or
## save's "hidden" dict). `now` is seconds (any monotonic clock). Returns
## true when the reaction stat went up.
static func note(hs: Dictionary, event: String, now: float) -> bool:
	match event:
		"dodge", "parry":
			if now - float(hs.get("last_dodge", -1000.0)) < DODGE_GAP:
				return false
			hs["last_dodge"] = now
			hs["reaction"] = int(hs.get("reaction", 0)) + 1
			hs[event + "s" if event == "dodge" else "parries"] = int(hs.get(event + "s" if event == "dodge" else "parries", 0)) + 1
			return true
		"kill":
			var chain: Array = []
			for t in hs.get("chain", []):
				if now - float(t) <= CHAIN_WINDOW:
					chain.append(float(t))
			chain.append(now)
			if chain.size() >= CHAIN_LEN:
				hs["chain"] = []
				hs["reaction"] = int(hs.get("reaction", 0)) + 1
				hs["chains"] = int(hs.get("chains", 0)) + 1
				return true
			hs["chain"] = chain
	return false


## Tries to grant a free unique skill whose hidden stat this character has
## crossed. `realm` is a RealmDB; returns the skill id granted (or re-synced
## when the registry already lists this holder), else "".
static func try_grant(realm, holder: String, level: int, hs: Dictionary, current: String) -> String:
	if realm == null or current != "":
		return ""
	for id in SKILLS:
		var s: Dictionary = SKILLS[id]
		if level < int(s["min_level"]) or int(hs.get(s["stat"], 0)) < int(s["threshold"]):
			continue
		if realm.slots_left(id, 1) <= 0 and not realm.is_holder(id, holder):
			continue
		var r: Dictionary = realm.claim(id, 1, holder, "skill")
		if r.get("ok", false):
			return id
	return ""


## True when `holder` still holds `id` in the realm (cast and load checks).
static func holds(realm, id: String, holder: String) -> bool:
	return realm != null and id != "" and realm.is_holder(id, holder)


static func announce_text(who: String, id: String) -> String:
	return "%s has awakened the unique skill %s." % [who, display_name(id)]
