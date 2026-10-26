class_name Permadeath
extends RefCounted
## Permadeath climbers, as in Aincrad: one life. An account (an install's
## three save slots) holds at most MAX_NORMAL ordinary characters and
## MAX_PERMADEATH permadeath one, chosen in the creator and fixed for life
## (`character.permadeath`; online the server record's own `permadeath`
## flag wins, so a client can't flip it).
##
## When a permadeath character's HP reaches 0 it falls for good: the server
## (or the offline game) writes `fallen` = {t, cause, where, level, floor}
## into the record before anyone is told, frees its realm claims (limited
## items, unique skill, stall, plot) and guild seat, and the Monument of
## Climbers strikes its name. The record is never playable again; the slot
## stays as a memorial until deleted.
##
## Leaving does not dodge it: a permadeath character that disconnects within
## COMBAT_SECS of being hit stays in the world for LINGER_SECS (Net
## srv_lingering), and dying there counts.
##
## Boosts (the reward for the risk, like hardcore modes elsewhere): +15% EXP,
## +10% drop chance, +25% Last Attack fallback rewards, the "Undying" title
## line and its own column on the Monument. Penalties: no revive, Healing
## Crystals cost double with a 30 s cooldown, no Teleport Crystal in combat,
## gear wears 1.5x as fast, stall trading only with other permadeath
## characters, and duels are First Strike only.
##
## Works on GameState and on a server RecordState (both expose `character`).

const MAX_NORMAL := 2
const MAX_PERMADEATH := 1
const XP_BONUS := 0.15
const DROP_BONUS := 0.10
const LA_BONUS := 0.25
const WEAR_MULT := 1.5
const CRYSTAL_PRICE_MULT := 2
const HEAL_CRYSTAL_CD := 30.0
const COMBAT_SECS := 10.0
const LINGER_SECS := 20.0
## Seconds the fallen screen holds before the game returns to the menu.
const FALL_SCREEN := 9.0

## name (lower) -> msec of the last hit taken / the last Healing Crystal.
static var _last_hurt := {}
static var _last_heal := {}


static func is_on(gs) -> bool:
	var c = gs.character if gs != null else null
	return c is Dictionary and bool(c.get("permadeath", false))


## A raw record (server dict or Stalls.local_rec()).
static func rec_on(rec: Dictionary) -> bool:
	if rec.has("permadeath"):
		return bool(rec["permadeath"])
	var c = rec.get("character", {})
	return c is Dictionary and bool(c.get("permadeath", false))


static func is_fallen(gs) -> bool:
	var f = gs.get("fallen") if gs is Object else gs.get("fallen", {})
	return f is Dictionary and not f.is_empty()


static func _key(gs) -> String:
	var c = gs.character if gs is Object else gs.get("character", {})
	return str(c.get("name", "")).to_lower() if c is Dictionary else ""


static func xp_gain(gs, amount: int) -> int:
	if amount > 0 and is_on(gs):
		return int(round(amount * (1.0 + XP_BONUS)))
	return amount


static func drop_chance(gs, chance: float) -> float:
	return minf(chance * (1.0 + DROP_BONUS), 1.0) if is_on(gs) else chance


static func wear(gs, amount: float) -> float:
	return amount * WEAR_MULT if is_on(gs) else amount


static func crystal_price(gs, id: String, base: int) -> int:
	return base * CRYSTAL_PRICE_MULT if id == "heal_crystal" and is_on(gs) else base


static func note_hurt(gs) -> void:
	_last_hurt[_key(gs)] = Time.get_ticks_msec()


static func in_combat(gs) -> bool:
	var t = _last_hurt.get(_key(gs))
	return t != null and Time.get_ticks_msec() - int(t) < int(COMBAT_SECS * 1000.0)


## "" when this crystal may be crushed now, else the reason.
static func crystal_block(gs, id: String) -> String:
	if not is_on(gs):
		return ""
	if id == "teleport_crystal" and in_combat(gs):
		return "Permadeath: no Teleport Crystal while in combat."
	if id == "heal_crystal":
		var t = _last_heal.get(_key(gs))
		if t != null:
			var left := HEAL_CRYSTAL_CD - float(Time.get_ticks_msec() - int(t)) / 1000.0
			if left > 0.0:
				return "Permadeath: the next Healing Crystal in %d s." % int(ceil(left))
	return ""


static func note_crystal(gs, id: String) -> void:
	if id == "heal_crystal" and is_on(gs):
		_last_heal[_key(gs)] = Time.get_ticks_msec()


## The record of a fall.
static func make_fall(gs, cause: String, where: String) -> Dictionary:
	return {"t": int(Time.get_unix_time_from_system()), "cause": cause.left(48) if cause != "" else "a monster",
		"where": where.left(48), "level": int(gs.level), "floor": int(gs.floors_cleared) + 1}


## "Fell to Dire Wolf on Town of First Light at Lv 6, 26 Oct 2026".
static func fall_text(info: Dictionary) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(info.get("t", 0)))
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "Fell to %s in %s at Lv %d, %d %s %d" % [str(info.get("cause", "a monster")), str(info.get("where", "Aincrad")),
		int(info.get("level", 1)), int(d["day"]), months[clampi(int(d["month"]) - 1, 0, 11)], int(d["year"])]


## The title line under a permadeath climber's name.
static func title_for(level: int, floors: int) -> String:
	if floors >= 1:
		return "Undying Vanguard"
	if level >= 10:
		return "Undying Blade"
	return "Undying"


## Frees what a fallen character held in the realm (claims, stall, plot,
## serials) and its guild seat. `holder` is its realm holder key.
static func release(rdb, holder: String) -> Array:
	if rdb == null or holder == "":
		return []
	load("res://scripts/life/guilds.gd").forget_holder(rdb, holder)
	return rdb.release_all(holder)


## Which kinds a new character in `slot` may be: {"normal": bool,
## "permadeath": bool}, counting the other slots (SaveSystem.slot_info).
static func slot_kinds(infos: Array, slot: int) -> Dictionary:
	var normal := 0
	var pd := 0
	for i in infos.size():
		var info: Dictionary = infos[i]
		if i == slot or not bool(info.get("exists", false)) or bool(info.get("corrupt", false)):
			continue
		if bool(info.get("permadeath", false)):
			pd += 1
		else:
			normal += 1
	return {"normal": normal < MAX_NORMAL, "permadeath": pd < MAX_PERMADEATH}
