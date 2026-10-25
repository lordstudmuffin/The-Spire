class_name LifeData
## Data tables for the "live your life" layer: fish and fishing spots,
## cooking recipes and the buffs their food gives, gatherable herbs, the
## cottage and its decorations. State lives in GameState (materials for
## fish/herbs/food/rod, fishing_/cooking_ levels, home_*). Everything here is
## static so smoke_test.gd can roll the tables headless.

## Fish by id. rarity 0..3 sets the minigame difficulty (zone size, speed).
const FISH := {
	"minnow": {"name": "Minnow", "rarity": 0, "xp": 6, "color": "9fc4d8", "desc": "A quick little silver fish. Bait, or a snack if you're not picky."},
	"river_trout": {"name": "River Trout", "rarity": 1, "xp": 12, "color": "e0907a", "desc": "Firm and sweet. Grills well over a camp fire."},
	"mire_eel": {"name": "Mire Eel", "rarity": 2, "xp": 22, "color": "6f8f5a", "desc": "Slippery and stubborn. The Mirewood hunters bake them into pies."},
	"moonscale_koi": {"name": "Moonscale Koi", "rarity": 3, "xp": 60, "color": "ffd27a", "desc": "Its scales hold the light of the Spire's moon. Prized raw."},
}
const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Legendary"]
const RARITY_COLORS := ["cfcfcf", "4da6ff", "b04dff", "ffb84d"]

## Fishing spot kinds -> base roll weights. Floor 1 has the pond and the
## stream, Floor 2 the Mere's shore and the shrine boardwalk (koi water).
const SPOTS := {
	"pond": {"minnow": 55, "river_trout": 35, "mire_eel": 6, "moonscale_koi": 4},
	"stream": {"minnow": 38, "river_trout": 52, "mire_eel": 6, "moonscale_koi": 4},
	"mere": {"minnow": 25, "river_trout": 20, "mire_eel": 48, "moonscale_koi": 7},
	"boardwalk": {"minnow": 14, "river_trout": 20, "mire_eel": 44, "moonscale_koi": 22},
}
const SPOT_NAMES := {"pond": "the pond", "stream": "the stream", "mere": "the Mere", "boardwalk": "the shrine boardwalk"}

## Cooked food: what it costs, the skill xp, and the buff it grants.
## regen is HP per second, atk/speed are fractions, dur in seconds.
const RECIPES := {
	"grilled_trout": {"name": "Grilled Trout", "cost": {"river_trout": 1, "wild_herb": 1}, "xp": 15, "level": 1,
		"buff": {"regen": 2.0, "atk": 0.0, "speed": 0.0, "dur": 90.0}, "color": "e0907a",
		"desc": "Trout over the coals with a crushed herb. Mends wounds slowly."},
	"boar_stew": {"name": "Boar Stew", "cost": {"beast_hide": 1, "wild_herb": 2}, "xp": 20, "level": 1,
		"buff": {"regen": 0.0, "atk": 0.10, "speed": 0.0, "dur": 120.0}, "color": "c98a3a",
		"desc": "Boar trimmings stewed with wild herbs. Puts fire in the arm (+10% attack)."},
	"eel_pie": {"name": "Eel Pie", "cost": {"mire_eel": 1, "wild_herb": 2}, "xp": 30, "level": 2,
		"buff": {"regen": 0.0, "atk": 0.0, "speed": 0.15, "dur": 120.0}, "color": "8fb36a",
		"desc": "Thornwick's pie. Oily, filling, and it puts a spring in your step (+15% speed)."},
	"koi_sashimi": {"name": "Koi Sashimi", "cost": {"moonscale_koi": 1}, "xp": 60, "level": 3,
		"buff": {"regen": 3.0, "atk": 0.12, "speed": 0.12, "dur": 180.0}, "color": "ffd27a",
		"desc": "Moonscale Koi, sliced thin. Every blessing at once."},
	# Field crops (P8 farm plots, scripts/life/farms.gd).
	"turnip_soup": {"name": "Turnip Soup", "cost": {"turnip": 2, "wild_herb": 1}, "xp": 14, "level": 1,
		"buff": {"regen": 2.5, "atk": 0.0, "speed": 0.0, "dur": 120.0}, "color": "e9d8c4",
		"desc": "Hollowbrook turnips simmered soft with a herb. Warms you through and mends slowly."},
	"harvest_bread": {"name": "Harvest Bread", "cost": {"sunwheat": 3}, "xp": 18, "level": 1,
		"buff": {"regen": 1.0, "atk": 0.0, "speed": 0.08, "dur": 150.0}, "color": "e8b860",
		"desc": "A round loaf of sunwheat baked in the coals. Light on the feet (+8% speed)."},
	"melon_tart": {"name": "Honeymelon Tart", "cost": {"honeymelon": 1, "sunwheat": 2}, "xp": 28, "level": 2,
		"buff": {"regen": 1.5, "atk": 0.08, "speed": 0.06, "dur": 160.0}, "color": "f2a65a",
		"desc": "Sweet melon in a sunwheat crust. A little of everything (+8% attack, +6% speed)."},
}
## Farm crops (P8): the one table for seeds, growth and yields. Times are
## real seconds: `grow` = watered time until ripe (growth pauses while the
## soil is dry), `dry` = how long one watering keeps the soil wet, `wither`
## = seconds without water before an unripe crop dies. Seeds are bought at
## the field's seed cart; crops and seeds stack in GameState.materials.
const CROPS := {
	"turnip": {"name": "Turnip", "seed": "turnip_seeds", "seed_name": "Turnip Seeds", "seed_price": 6,
		"grow": 900.0, "dry": 600.0, "wither": 3 * 3600.0, "yield": [2, 3], "color": "e9d8c4",
		"desc": "A fat white root from the Hollowbrook fields. Soup, mostly.",
		"seed_desc": "A pouch of turnip seed. Ripens in about 15 minutes of wet soil."},
	"sunwheat": {"name": "Sunwheat", "seed": "sunwheat_seeds", "seed_name": "Sunwheat Seeds", "seed_price": 10,
		"grow": 1800.0, "dry": 900.0, "wither": 4 * 3600.0, "yield": [3, 4], "color": "e8c25a",
		"desc": "Golden grain that loves the floor's long afternoons. Bakes into bread.",
		"seed_desc": "Sunwheat seed. Ripens in about 30 minutes of wet soil."},
	"honeymelon": {"name": "Honeymelon", "seed": "honeymelon_seeds", "seed_name": "Honeymelon Seeds", "seed_price": 18,
		"grow": 3600.0, "dry": 1200.0, "wither": 6 * 3600.0, "yield": [1, 2], "color": "f2a65a",
		"desc": "A heavy, sweet melon. Worth the wait, and the tarts.",
		"seed_desc": "Honeymelon seed. Ripens in about an hour of wet soil."},
}
## Food ids are the recipe ids (they stack in GameState.materials).
const GATHER := {"wild_herb": {"name": "Wild Herb", "color": "8fd36a", "desc": "Grows in clumps on the open grass. Cooks love it."}}
const TOOLS := {"willow_rod": {"name": "Willow Rod", "color": "a9815a", "desc": "A limber willow pole, line and bone hook. Cast it at any fishing spot."}}

const HOME_PRICE := 300
const ROD_PRICE := 40
## Decorations the trader sells for the six cottage slots.
const DECOR := {
	"rug": {"name": "Woven Rug", "col": 60, "desc": "Hollowbrook wool, dyed red."},
	"bookshelf": {"name": "Bookshelf", "col": 120, "desc": "Three shelves of climbers' journals."},
	"plant": {"name": "Potted Fern", "col": 45, "desc": "Something green from the fields."},
	"lantern": {"name": "Brass Lantern", "col": 80, "desc": "Warm light for the long nights."},
	"trophy": {"name": "Gravelmaw Trophy", "col": 250, "requires_clear": 1, "desc": "A shard of the Floor 1 Guardian on a plinth. Only sold to those who felled it."},
}
const REST_BUFF := {"name": "Well Rested", "regen": 1.5, "atk": 0.05, "speed": 0.05, "dur": 240.0, "color": "4cc9f0"}


static func is_fish(id: String) -> bool:
	return FISH.has(id)


static func is_food(id: String) -> bool:
	return RECIPES.has(id)


## True for anything the inventory screen shows under Provisions instead of
## the smithing materials strip (fish, herbs, food, the rod).
static func is_life_item(id: String) -> bool:
	return FISH.has(id) or RECIPES.has(id) or GATHER.has(id) or TOOLS.has(id) or CROPS.has(id) or seed_crop(id) != ""


## The crop a seed id grows ("" when `id` is no seed).
static func seed_crop(id: String) -> String:
	for c in CROPS:
		if CROPS[c]["seed"] == id:
			return c
	return ""


static func item_color(id: String) -> Color:
	for t in [FISH, RECIPES, GATHER, TOOLS, CROPS]:
		if t.has(id):
			return Color(t[id]["color"])
	if seed_crop(id) != "":
		return Color("b89a6a")
	return Color("f0c060")


static func item_desc(id: String) -> String:
	for t in [FISH, RECIPES, GATHER, TOOLS, CROPS]:
		if t.has(id):
			return t[id]["desc"]
	if seed_crop(id) != "":
		return CROPS[seed_crop(id)]["seed_desc"]
	return ""


# --- Fishing -----------------------------------------------------------------

## Roll weights for a spot at a fishing skill: the skill pulls the table away
## from minnows and toward koi. Exposed so tests can check the shape.
static func fish_weights(spot: String, fishing_level: int) -> Dictionary:
	var base: Dictionary = SPOTS.get(spot, SPOTS["pond"])
	var l := float(maxi(fishing_level, 1) - 1)
	var w := {}
	for id in FISH:
		var v := float(base.get(id, 0))
		match id:
			"minnow":
				v = maxf(v - l * 1.6, 5.0)
			"moonscale_koi":
				v += l * 0.7
			_:
				v += l * 0.3
		w[id] = v
	return w


static func roll_fish(spot: String, fishing_level: int, rng: RandomNumberGenerator = null) -> String:
	var w := fish_weights(spot, fishing_level)
	var total := 0.0
	for id in w:
		total += w[id]
	var r := (rng.randf() if rng else randf()) * total
	for id in w:
		r -= w[id]
		if r <= 0.0:
			return id
	return "minnow"


## Minigame parameters by rarity: the green zone as a fraction of the bar
## and the marker's oscillation speed (cycles per second). Fishing skill
## widens the zone a little.
static func difficulty(fish_id: String, fishing_level := 1) -> Dictionary:
	var r := int(FISH.get(fish_id, FISH["minnow"])["rarity"])
	var zone := 0.34 - r * 0.065 + minf(fishing_level - 1, 10) * 0.008
	return {"zone": clampf(zone, 0.12, 0.4), "speed": 0.9 + r * 0.45, "window": 3.2 - r * 0.4}


static func rarity_color(fish_id: String) -> Color:
	return Color(RARITY_COLORS[int(FISH.get(fish_id, FISH["minnow"])["rarity"])])


## Every function below takes `gs`: GameState offline (and for the
## listen-server host), or the player's server-side record (Net.RecordState)
## when the server runs the action. An online client never books anything
## here: the request goes to the server, which answers with a state patch.
static func has_rod(gs = GameState) -> bool:
	return int(gs.materials.get("willow_rod", 0)) > 0


## Books a catch: material, fishing xp, quest progress. Returns {"skill_up"}.
static func land_fish(fish_id: String, gs = GameState) -> Dictionary:
	if not FISH.has(fish_id):
		return {"error": "No such fish."}
	gs.add_material(fish_id, 1)
	gs.fish_caught += 1
	gs.advance_quest("pond_catch")
	if fish_id == "mire_eel":
		gs.advance_quest("mere_catch")
	var up := gs.add_life_xp("fishing", int(FISH[fish_id]["xp"]))
	return {"skill_up": up, "fish": fish_id}


# --- Cooking -----------------------------------------------------------------

static func recipe_cost_text(id: String) -> String:
	var parts := []
	for m in RECIPES[id]["cost"]:
		parts.append("%d %s" % [RECIPES[id]["cost"][m], GameState.MATERIAL_NAMES.get(m, m)])
	return ", ".join(parts)


static func buff_text(b: Dictionary) -> String:
	var parts := []
	if float(b.get("regen", 0.0)) > 0.0:
		parts.append("+%.0f HP/s" % float(b["regen"]))
	if float(b.get("atk", 0.0)) > 0.0:
		parts.append("+%d%% ATK" % int(round(float(b["atk"]) * 100)))
	if float(b.get("speed", 0.0)) > 0.0:
		parts.append("+%d%% speed" % int(round(float(b["speed"]) * 100)))
	if b.has("dur"):
		parts.append("%d s" % int(b["dur"]))
	return "  ·  ".join(parts)


static func can_cook(id: String, gs = GameState) -> bool:
	var r: Dictionary = RECIPES[id]
	return gs.cooking_level >= int(r.get("level", 1)) and gs.has_materials(r["cost"])


## Cooks one portion. Returns {"name", "skill_up"} or {"error"}; an online
## client gets {"pending": true} and the result through Net.action_applied.
static func cook(id: String, gs = GameState) -> Dictionary:
	if not RECIPES.has(id):
		return {"error": "Unknown recipe."}
	if gs == GameState and Net.remote_client():
		Net.request_action("cook", {"id": id})
		return {"pending": true}
	var r: Dictionary = RECIPES[id]
	if gs.cooking_level < int(r.get("level", 1)):
		return {"error": "Needs Cooking Lv %d." % int(r["level"])}
	if not gs.has_materials(r["cost"]):
		return {"error": "Not enough ingredients."}
	gs.spend_materials(r["cost"])
	gs.add_material(id, 1)
	var up := gs.add_life_xp("cooking", int(r["xp"]))
	return {"name": r["name"], "skill_up": up, "id": id}


## Eats one portion of a cooked food: consumes it and applies its buff.
## Online the server eats it from the record (the buff then counts in the
## server's damage and regen); true here only means the request went out.
static func eat(id: String, gs = GameState) -> bool:
	if not RECIPES.has(id) or int(gs.materials.get(id, 0)) <= 0:
		return false
	if gs == GameState and Net.remote_client():
		return Net.request_action("eat", {"id": id})
	gs.spend_materials({id: 1})
	var r: Dictionary = RECIPES[id]
	var b: Dictionary = r["buff"].duplicate()
	b["name"] = r["name"]
	b["color"] = r["color"]
	gs.add_buff(id, float(b["dur"]), b)
	return true


# --- Home --------------------------------------------------------------------

static func decor_available(id: String, gs = GameState) -> bool:
	var d: Dictionary = DECOR[id]
	return gs.floors_cleared >= int(d.get("requires_clear", 0))


## Buys a decoration (or the rod). Returns "" on success or the reason;
## "pending" when an online client handed the purchase to the server.
static func buy(id: String, gs = GameState) -> String:
	if gs == GameState and Net.remote_client():
		Net.request_action("buy", {"id": id})
		return "pending"
	var price := 0
	if id == "willow_rod":
		price = ROD_PRICE
	elif DECOR.has(id):
		if not decor_available(id, gs):
			return "The trader will not part with that until you have cleared Floor %d." % int(DECOR[id]["requires_clear"])
		price = int(DECOR[id]["col"])
	else:
		return "Not for sale."
	if gs.money < price:
		return "Not enough Col (%d needed)." % price
	gs.add_money(-price)
	if id == "willow_rod":
		gs.add_material("willow_rod", 1)
	else:
		gs.add_decor(id, 1)
	return ""


## Sleeping in the cottage bed: full heal and the rest buff.
static func rest(gs = GameState) -> void:
	if gs == GameState and Net.remote_client():
		Net.request_action("rest")
		return
	gs.heal_full()
	var b := REST_BUFF.duplicate()
	gs.add_buff("rested", float(b["dur"]), b)
