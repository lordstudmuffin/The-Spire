class_name Crafting
## Blacksmithing: recipes, rank rolls and item creation.
## Ranks follow the Normal -> Myth ladder; higher smithing skill and the
## Forgeborn hidden class shift the odds upward.

const RANKS := ["Normal", "Rare", "Epic", "Unique", "Legendary", "Myth"]
const RANK_COLORS := ["cfcfcf", "4da6ff", "b04dff", "ffb84d", "ff6b35", "ff2d75"]
const RANK_MULT := [1.0, 1.3, 1.7, 2.2, 3.0, 4.0]

const RECIPES := {
	"Iron Sword": {"kind": "weapon", "cost": {"iron_ore": 3}, "col": 20, "base": 6, "xp": 20},
	"Hide Armor": {"kind": "armor", "cost": {"beast_hide": 3}, "col": 15, "base": 4, "xp": 20},
	"Spirit Blade": {"kind": "weapon", "cost": {"iron_ore": 4, "spirit_shard": 2}, "col": 60, "base": 12, "xp": 45},
	"Warden Plate": {"kind": "armor", "cost": {"iron_ore": 3, "beast_hide": 3, "spirit_shard": 1}, "col": 50, "base": 8, "xp": 45},
	# Floor 2 (Mirewood) recipes. "unlock" names a GameState recipe flag a
	# quest grants (the Shrine rite teaches Drowned Plate).
	"Mirewood Blade": {"kind": "weapon", "cost": {"iron_ore": 4, "stag_horn": 2, "spirit_shard": 1}, "col": 120, "base": 18, "xp": 70},
	"Drowned Plate": {"kind": "armor", "cost": {"iron_ore": 4, "beast_hide": 3, "wisp_essence": 2}, "col": 110, "base": 13, "xp": 70, "unlock": "shrine_rite"},
	# Tools land in GameState.materials (stackable), not the gear list.
	"Willow Rod": {"kind": "tool", "material": "willow_rod", "cost": {"iron_ore": 1, "beast_hide": 1}, "col": 10, "base": 0, "xp": 8},
}


## False when a recipe still needs its quest unlock. `gs` is GameState or,
## on the server, the player's record (Net.RecordState).
static func recipe_known(recipe_name: String, gs = GameState) -> bool:
	var r: Dictionary = RECIPES[recipe_name]
	return not r.has("unlock") or gs.recipe_unlocked(r["unlock"])


static func rank_color(rank: int) -> Color:
	return Color(RANK_COLORS[rank])


## Weighted roll. At skill 1 almost everything is Normal/Rare; by skill 8
## Legendary shows up for real. Forgeborn adds a chance of a free bump.
static func roll_rank(smithing_level: int, forgeborn := false) -> int:
	var l := float(smithing_level)
	var weights := [
		max(60.0 - l * 6.0, 8.0),  # Normal
		25.0 + l * 2.0,            # Rare
		8.0 + l * 2.5,             # Epic
		2.0 + l * 1.5,             # Unique
		0.3 + l * 0.6,             # Legendary
		0.02 + l * 0.08,           # Myth
	]
	var total := 0.0
	for w in weights:
		total += w
	var r := randf() * total
	var rank := 0
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			rank = i
			break
	if forgeborn and rank < RANKS.size() - 1 and randf() < 0.25:
		rank += 1
	return rank


static var _serial := 0


static func make_item(recipe_name: String, rank: int, crafter: String) -> Dictionary:
	var r: Dictionary = RECIPES[recipe_name]
	var value := int(round(r["base"] * RANK_MULT[rank] * randf_range(0.9, 1.15)))
	_serial += 1
	var item := {
		"id": "%s_%d_%d" % [recipe_name.to_lower().replace(" ", "_"), Time.get_ticks_msec(), _serial],
		"name": "%s %s" % [RANKS[rank], recipe_name],
		"kind": r["kind"],
		"rank": rank,
		"atk": value if r["kind"] == "weapon" else 0,
		"def": value if r["kind"] == "armor" else 0,
		"crafted_by": crafter,
	}
	return item


static func cost_text(recipe_name: String) -> String:
	var r: Dictionary = RECIPES[recipe_name]
	var parts := []
	for m in r["cost"]:
		parts.append("%d %s" % [r["cost"][m], GameState.MATERIAL_NAMES[m]])
	parts.append("%d Col" % r["col"])
	return ", ".join(parts)


## Attempts a craft. Returns the item, or an empty dict with a reason.
## `gs` is GameState (offline, listen-server host) or the server-side record
## of the crafter. An online client never crafts here: the request goes to
## the server (Net.request_action), which crafts against the record and
## answers with the item and a state patch; this returns {"pending": true}.
static func craft(recipe_name: String, gs = GameState) -> Dictionary:
	if not RECIPES.has(recipe_name):
		return {"error": "Unknown recipe."}
	if gs == GameState and Net.remote_client():
		Net.request_action("craft", {"recipe": recipe_name})
		return {"pending": true}
	var r: Dictionary = RECIPES[recipe_name]
	if not recipe_known(recipe_name, gs):
		return {"error": "You do not know this recipe yet. (The Mirewood shrine keeper teaches it.)"}
	if not gs.has_materials(r["cost"]):
		return {"error": "Not enough materials."}
	if gs.money < r["col"]:
		return {"error": "Not enough Col."}
	if r["kind"] != "tool" and gs.inventory.size() >= Net.MAX_INVENTORY:
		return {"error": "Your pack is full (%d pieces). Store some in the cottage chest." % Net.MAX_INVENTORY}
	gs.spend_materials(r["cost"])
	gs.add_money(-r["col"])
	if r["kind"] == "tool":
		gs.add_material(r["material"], 1)
		return {"name": recipe_name, "kind": "tool", "rank": 0, "skill_up": gs.add_smithing_xp(r["xp"])}
	var rank := roll_rank(gs.smithing_level, gs.hidden_class == "Forgeborn")
	var item := make_item(recipe_name, rank, gs.character["name"])
	gs.add_item(item)
	gs.items_crafted += 1
	gs.advance_quest("forge_trial")
	# Return a copy with the skill-up flag so the saved item stays clean.
	var result := item.duplicate()
	result["skill_up"] = gs.add_smithing_xp(r["xp"])
	return result
