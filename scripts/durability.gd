class_name Durability
extends RefCounted
## Gear durability, as in Aincrad and Satisfy: every forged weapon and armor
## piece wears with use and has to be brought back to an anvil. A weapon
## loses WEAR_SWING per landed swing and WEAR_PARRY per parry; armor loses
## WEAR_HIT per blow taken. At 0 the piece is broken: it stays in the pack
## and can still be repaired, but adds no attack or defense until it is.
##
## Items carry "dur" (current, float) and "dur_max"; older items without them
## count as fully repaired (max_for). Works on GameState and on a server
## RecordState alike (both expose `equipped`, `inventory`, `money`,
## `smithing_level`), and keeps the equipped copy and the inventory copy in
## step (after a save round trip they are separate dictionaries).

const WEAR_SWING := 0.2
const WEAR_PARRY := 0.5
const WEAR_HIT := 0.25
const LOW := 0.2            # warn below 20%
## Col per point of durability restored, per rank step (Normal 1x, Rare 1.5x...).
const COL_PER_POINT := 0.5
const SMITH_DISCOUNT := 0.03  # per smithing level
const SMITH_DISCOUNT_CAP := 0.45


static func max_for(item: Dictionary) -> float:
	if item.has("dur_max"):
		return float(item["dur_max"])
	var rank := int(item.get("rank", 0))
	return (80.0 if str(item.get("kind", "")) == "weapon" else 100.0) + 30.0 * rank


static func cur(item: Dictionary) -> float:
	return clampf(float(item.get("dur", max_for(item))), 0.0, max_for(item))


static func is_broken(item) -> bool:
	return item is Dictionary and cur(item) <= 0.0


static func fraction(item: Dictionary) -> float:
	return cur(item) / maxf(max_for(item), 1.0)


## New gear from the anvil: full durability.
static func stamp(item: Dictionary) -> void:
	item["dur_max"] = max_for(item)
	item["dur"] = item["dur_max"]


## Wears the gear in `slot` by `amount`. Returns "broken" the moment it hits
## 0, "low" the moment it drops under LOW, otherwise "".
static func wear(gs, slot: String, amount: float) -> String:
	var it = gs.equipped.get(slot)
	if not (it is Dictionary):
		return ""
	var before := cur(it)
	if before <= 0.0:
		return ""
	var after := maxf(before - Permadeath.wear(gs, amount), 0.0)
	_set_dur(gs, it, after)
	var m := max_for(it)
	if after <= 0.0:
		return "broken"
	if before / m >= LOW and after / m < LOW:
		return "low"
	return ""


static func _set_dur(gs, item: Dictionary, value: float) -> void:
	var id := str(item.get("id", ""))
	item["dur"] = value
	item["dur_max"] = max_for(item)
	for it in gs.inventory:
		if it is Dictionary and str(it.get("id", "")) == id:
			it["dur"] = value
			it["dur_max"] = item["dur_max"]
	for slot in gs.equipped:
		var e = gs.equipped[slot]
		if e is Dictionary and str(e.get("id", "")) == id:
			e["dur"] = value
			e["dur_max"] = item["dur_max"]


## "Durability 54 / 80" (or BROKEN), for item details and the anvil.
static func text(item: Dictionary) -> String:
	if is_broken(item):
		return "BROKEN  ·  0 / %d" % int(max_for(item))
	return "Durability %d / %d" % [int(ceil(cur(item))), int(max_for(item))]


static func repair_cost(item: Dictionary, smithing_level := 1) -> int:
	var missing := max_for(item) - cur(item)
	if missing <= 0.01:
		return 0
	var mult := 1.0 + 0.5 * int(item.get("rank", 0))
	var disc := minf(SMITH_DISCOUNT * maxi(smithing_level - 1, 0), SMITH_DISCOUNT_CAP)
	return maxi(int(ceil(missing * COL_PER_POINT * mult * (1.0 - disc))), 1)


## Repairs the equipped piece in `slot` for Col. Returns "" on success or the
## reason. The caller checks the anvil range (world.srv_action "repair").
static func repair(gs, slot: String) -> String:
	var it = gs.equipped.get(slot)
	if not (it is Dictionary):
		return "Nothing equipped there."
	if gs == GameState and Net.remote_client():
		Net.request_action("repair", {"slot": slot})
		return "pending"
	var cost := repair_cost(it, int(gs.smithing_level))
	if cost == 0:
		return "%s is in perfect condition." % str(it.get("name", "That"))
	if int(gs.money) < cost:
		return "Not enough Col (%d needed)." % cost
	gs.add_money(-cost)
	_set_dur(gs, it, max_for(it))
	return ""
