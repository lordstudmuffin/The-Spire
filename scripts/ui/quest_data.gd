class_name QuestData
extends RefCounted
## Display data for quests (titles, givers, objectives, rewards). Quest
## *state* lives in GameState.quests; the world starts/advances them. This
## only decorates ids for the quest log and the HUD tracker.

const QUESTS := {
	"boar_trouble": {
		"title": "Boar Trouble",
		"giver": "Guide Mira",
		"where": "Town of First Light",
		"objective": "Defeat Field Boars in the southern fields",
		"unit": "boars",
		"reward": "150 XP  ·  100 Col",
		"story": "Boars have been tearing up the fields outside town. Mira wants five of them gone before the harvest.",
	},
	"wolf_hunt": {
		"title": "Howls by the Spire",
		"giver": "Captain Rhys",
		"where": "Town of First Light",
		"objective": "Thin the Dire Wolf pack near the Labyrinth tower",
		"unit": "wolves",
		"reward": "400 XP  ·  250 Col",
		"story": "Dire wolves gather at the foot of the tower to the north. They hunt in groups; so should you.",
	},
	"forge_trial": {
		"title": "Trial of the Forge",
		"giver": "Smith Haldor",
		"where": "Haldor's Anvil",
		"objective": "Craft items at Haldor's anvil",
		"unit": "items",
		"reward": "Hidden class: Forgeborn",
		"story": "Haldor sees promise in your hammer work. Prove it at the anvil and he will share the forge-born secret.",
	},
	"ore_delivery": {
		"title": "Cold Forge",
		"giver": "Elder Wren",
		"where": "Hollowbrook",
		"objective": "Bring Iron Ore to Elder Wren in Hollowbrook",
		"unit": "ore",
		"reward": "120 XP  ·  80 Col  ·  2 Spirit Shards",
		"story": "Hollowbrook's forge went cold when the ore wagons stopped. Mine the veins in the fields and carry the ore west.",
	},
	"floor_boss": {
		"title": "The Floor Guardian",
		"giver": "The Sealed Gate",
		"where": "The Labyrinth",
		"objective": "Defeat the Floor Guardian atop the Labyrinth",
		"unit": "guardian",
		"reward": "Floor 1 cleared  ·  3 Spirit Shards",
		"story": "Climb the terraces, cross the summit and face Gravelmaw. Don't stand in the slam.",
	},
	"stag_hunt": {
		"title": "Horns of Thornwick",
		"giver": "Huntmaster Sable",
		"where": "Thornwick",
		"objective": "Bring down Thornback Stags on the east tracks",
		"unit": "stags",
		"reward": "900 XP  ·  500 Col",
		"story": "The woods have turned and the stags gore anyone on the tracks. Six of them fed to the fire and Thornwick eats this winter.",
	},
	"shrine_rite": {
		"title": "The Drowned Rite",
		"giver": "Keeper Ilsa",
		"where": "Shrine Isle",
		"objective": "Gather Wisp Essence from the Sunken Barrow for Keeper Ilsa",
		"unit": "essence",
		"reward": "700 XP  ·  300 Col  ·  Recipe: Drowned Plate",
		"story": "Wisps haunt the Barrow north-west of Thornwick. Their essence lets the shrine keeper teach the old drowned-steel smithing.",
	},
	"pond_catch": {
		"title": "Old Tam's Pond",
		"giver": "Old Tam",
		"where": "The pond east of town",
		"objective": "Catch fish at the pond or the stream (E at a fishing stake)",
		"unit": "fish",
		"reward": "150 XP  ·  80 Col",
		"story": "Tam's back is done for and the pond is thick with fish. Cast, wait for the bite, and press E when the marker swims through the green.",
	},
	"mere_catch": {
		"title": "Eels for Thornwick",
		"giver": "Fisher Maud",
		"where": "The Mere's north shore",
		"objective": "Catch Mire Eels in the Mere or off the shrine boardwalk",
		"unit": "eels",
		"reward": "600 XP  ·  300 Col",
		"story": "Mire eels fetch a price in Thornwick, pie or smoked. They fight: keep your eye on the green.",
	},
	"floor_boss_2": {
		"title": "The Drowned Knight",
		"giver": "The Sealed Gate",
		"where": "The Labyrinth",
		"objective": "Defeat Mirelord atop the second Labyrinth",
		"unit": "guardian",
		"reward": "Floor 2 cleared",
		"story": "Mirelord raises the drowned to fight beside him. Cut the wisps down fast, then the knight.",
	},
	# --- Limited quests (only 1-3 characters in the realm, LimitedContent).
	"lantern_below": {
		"title": "The Lantern Below",
		"giver": "Lamplighter Iselde",
		"where": "Labyrinth, first terrace",
		"objective": "Bring Spirit Shards to relight Iselde's lantern",
		"unit": "shards",
		"reward": "500 XP  ·  300 Col  ·  Veil of First Dawn (only one in the realm)",
		"story": "A lamplighter nobody remembers waits at the far corner of the first terrace. Only one traveller will ever carry her veil.",
	},
	"old_watch_whispers": {
		"title": "Whispers of the Old Watch",
		"giver": "Old Watchman Bram",
		"where": "Talven camp",
		"objective": "Bring wolf pelts so Bram can kindle a Wisplight blade",
		"unit": "pelts",
		"reward": "380 XP  ·  220 Col  ·  Wisplight Rapier (one of three)",
		"story": "The last watch-captains forged three blades at the waystones. Bram can kindle them again, but only three were ever made.",
	},
	# --- Hollowbrook chain (Floor 1): five quests, one leading to the next.
	"wolf_pelts": {
		"title": "Teeth on the North Slope",
		"giver": "Trapper Vesna",
		"where": "Hollowbrook",
		"objective": "Bring Dire Wolf pelts from below the tower to Trapper Vesna",
		"unit": "pelts",
		"reward": "260 XP  ·  160 Col  ·  2 Beast Hide",
		"story": "The dire wolves have come down off the tower slope and nobody sets a snare north of the gate. Vesna wants four pelts: proof, and winter boots.",
	},
	"field_herbs": {
		"title": "Fog-Root and Feverleaf",
		"giver": "Herbalist Hesper",
		"where": "Hollowbrook",
		"objective": "Gather Wild Herbs from the field clumps for Herbalist Hesper",
		"unit": "herbs",
		"reward": "220 XP  ·  140 Col  ·  2 Grilled Trout",
		"story": "Hesper's shelves are bare and the field hands come back bitten. Six fresh herbs from the open grass will see her through the week.",
	},
	"tavern_stew": {
		"title": "A Pot for the Tavern",
		"giver": "Innkeeper Rook",
		"where": "The Hollowbrook tavern",
		"objective": "Cook a Boar Stew at a fire and bring it to Innkeeper Rook",
		"unit": "pot",
		"reward": "300 XP  ·  180 Col  ·  Koi Sashimi",
		"story": "The tavern's cook walked out and the field hands want stew. One boar hide, two herbs, the Talven camp fire, and Rook will remember you.",
	},
	"talven_waystones": {
		"title": "Stones of the Old Watch",
		"giver": "Scout Fen",
		"where": "The Talven camp",
		"objective": "Wake the three waystones around the Talven fields",
		"unit": "stones",
		"reward": "340 XP  ·  200 Col  ·  2 Spirit Shards",
		"story": "The old watch set waystones around these fields long before the town. They went dark when the Guardian woke. Lay a hand on each and the line wakes.",
	},
	# --- Hidden-class quests (scripts/hidden_classes.gd). "hidden": never
	# listed or hinted at until the NPC opens them (the log only shows
	# started quests; this flag keeps any future "available" view honest).
	"stillblade_rite": {
		"title": "The Unmoving Edge",
		"giver": "Quartermaster Dain",
		"where": "The Talven camp",
		"objective": "Parry strikes the way Dain showed you",
		"unit": "parries",
		"reward": "Hidden class: Stillblade",
		"story": "Dain watched you turn eight blows without a scratch. The old camp drill has a name for that, and a last lesson: ten more, and the edge stops moving.",
		"hidden": true,
	},
	"hearth_rite": {
		"title": "The Wandering Pot",
		"giver": "Innkeeper Rook",
		"where": "The Hollowbrook tavern",
		"objective": "Bring Rook a trail supper: Grilled Trout, Turnip Soup and Harvest Bread",
		"unit": "dishes",
		"reward": "Hidden class: Hearthwright",
		"story": "Rook has heard about your fires from the fishers and the field hands. The cooks who walk the Spire with a pot on their back had a name once; prove you can feed a road and he will give it to you.",
		"hidden": true,
	},
	"gravelmaw_bounty": {
		"title": "The Town's Bounty",
		"giver": "Captain Rhys",
		"where": "Town of First Light",
		"objective": "Defeat Gravelmaw atop the Labyrinth and report to Captain Rhys",
		"unit": "guardian",
		"reward": "600 XP  ·  400 Col  ·  Rare Spirit Blade  ·  Title: Warden of Talven",
		"story": "The town has posted a bounty on the Floor Guardian. Climb the Labyrinth, bring Gravelmaw down, and the town names you one of its own.",
	},
}


static func info(id: String) -> Dictionary:
	if QUESTS.has(id):
		return QUESTS[id]
	return {"title": id.capitalize(), "giver": "Unknown", "where": "", "objective": id.capitalize(), "unit": "", "reward": "", "story": ""}


static func title(id: String) -> String:
	return info(id)["title"]


## "3 / 5 boars" or "Return to Guide Mira" when the goal is met.
static func progress_text(id: String, q: Dictionary) -> String:
	var p := int(q.get("progress", 0))
	var g := int(q.get("goal", 1))
	if q.get("done", false):
		return "Completed"
	if p >= g:
		return "Return to %s" % info(id)["giver"]
	var unit: String = info(id)["unit"]
	return "%d / %d%s" % [p, g, ("  " + unit) if unit != "" else ""]


static func active_ids() -> Array:
	var out := []
	for id in GameState.quests:
		if not GameState.quests[id].get("done", false):
			out.append(id)
	return out


static func completed_ids() -> Array:
	var out := []
	for id in GameState.quests:
		if GameState.quests[id].get("done", false):
			out.append(id)
	return out
