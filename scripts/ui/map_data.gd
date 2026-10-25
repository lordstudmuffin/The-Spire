class_name MapData
extends RefCounted
## Read-only world layout for the minimap and the full map. Pulls the
## constants the world builds from (island radius, town wall, villages,
## tower, pond) so the drawn map stays in step with scripts/world.gd
## without that file knowing the UI exists.

const WorldScript := preload("res://scripts/world.gd")

const TOWN_CENTER := Vector2(0, 15)
const TOWN_RADIUS := 36.0
const GATE_POS := Vector2(0, 15)
const SMITHY_POS := Vector2(16, 22)
const FOUNTAIN_POS := Vector2(0, 27)

## kind: "town" | "village" | "camp" | "tower" | "water" | "gate" | "smith" | "npc"
##       | "market" | "farm" | "board" (Hollowbrook life spots: stalls, plots, guild board)
const KIND_COLORS := {
	"town": Color("f0c060"),
	"village": Color("7bdc8a"),
	"camp": Color("ff8c42"),
	"tower": Color("c9ced8"),
	"water": Color("4cc9f0"),
	"gate": Color("4fc3ff"),
	"smith": Color("ff9a3c"),
	"npc": Color("f3eee4"),
	"market": Color("ffd166"),
	"farm": Color("a7d46f"),
	"board": Color("b9a6ff"),
}

static var _landmarks := {}  # floor -> Array


static func island_radius() -> float:
	return float(WorldScript.FLOOR_RADIUS)


## Live world node when one exists (its per-floor layout vars win).
static func _world() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		for n in (ml as SceneTree).root.get_children():
			if "TOWER_POS" in n and "hud" in n:
				return n
	return null


static func tower_pos() -> Vector2:
	var w := _world()
	if w != null:
		var t: Vector3 = w.TOWER_POS
		return Vector2(t.x, t.z)
	if current_floor() == 2:
		return Vector2(Floor2Art.TOWER.x, Floor2Art.TOWER.z)
	return Vector2(0, -70)


static func current_floor() -> int:
	return int(GameState.get("floor")) if "floor" in GameState else 1


static func pond_pos() -> Vector2:
	return WorldArt.POND


static func pond_radius() -> float:
	return WorldArt.POND_RADIUS


static func floor_name() -> String:
	return "Mirewood" if current_floor() == 2 else "Island of First Light"


## [{pos: Vector2 (world x,z), kind: String, label: String, radius: float}]
## Built once per floor; layouts are fixed (seeded) so this never changes.
static func landmarks() -> Array:
	var f := current_floor()
	if _landmarks.has(f):
		return _landmarks[f]
	var out := []
	if f == 2:
		out = [
			{"pos": Floor2Art.PLAZA, "kind": "town", "label": "Waygate Plaza", "radius": Floor2Art.PLAZA_RADIUS},
			{"pos": Vector2(Floor2Art.WAYGATE.x, Floor2Art.WAYGATE.z), "kind": "gate", "label": "Waygate", "radius": 4.0},
			{"pos": Vector2(Floor2Art.VILLAGE.x, Floor2Art.VILLAGE.z), "kind": "village", "label": "Thornwick", "radius": 14.0},
			{"pos": Vector2(Floor2Art.LAKE.x, Floor2Art.LAKE.z), "kind": "water", "label": "The Mere", "radius": Floor2Art.LAKE_RADIUS},
			{"pos": Vector2(Floor2Art.ISLE.x, Floor2Art.ISLE.z), "kind": "smith", "label": "Shrine Isle", "radius": Floor2Art.ISLE_RADIUS},
			{"pos": Vector2(Floor2Art.BARROW.x, Floor2Art.BARROW.z), "kind": "camp", "label": "Sunken Barrow", "radius": Floor2Art.BARROW_RADIUS},
			{"pos": tower_pos(), "kind": "tower", "label": "The Labyrinth", "radius": 12.0},
			{"pos": tower_pos() + Vector2(0, 14), "kind": "gate", "label": "Sealed Gate", "radius": 2.0},
		]
	else:
		var hb: Vector3 = WorldScript.HOLLOWBROOK
		var tv: Vector3 = WorldScript.TALVEN
		out = [
			{"pos": TOWN_CENTER, "kind": "town", "label": "Town of First Light", "radius": TOWN_RADIUS},
			{"pos": GATE_POS, "kind": "gate", "label": "Teleport Gate", "radius": 4.0},
			{"pos": SMITHY_POS, "kind": "smith", "label": "Haldor's Anvil", "radius": 2.0},
			{"pos": Vector2(hb.x, hb.z), "kind": "village", "label": "Hollowbrook", "radius": 16.0},
			{"pos": Vector2(tv.x, tv.z), "kind": "camp", "label": "Talven Camp", "radius": 9.0},
			{"pos": tower_pos(), "kind": "tower", "label": "The Labyrinth", "radius": 12.0},
			{"pos": tower_pos() + Vector2(0, 14), "kind": "gate", "label": "Sealed Gate", "radius": 2.0},
			{"pos": pond_pos(), "kind": "water", "label": "Mill Pond", "radius": pond_radius()},
		]
		var mk: Vector3 = load("res://scripts/life/stalls.gd").market_center(hb)
		var fm: Vector3 = load("res://scripts/life/farms.gd").field_center(hb)
		var bd: Vector3 = hb + load("res://scripts/life/guilds.gd").BOARD_OFFSET
		out.append({"pos": Vector2(mk.x, mk.z), "kind": "market", "label": "Market", "radius": 2.0, "area": 9.0})
		out.append({"pos": Vector2(fm.x, fm.z), "kind": "farm", "label": "Farm Plots", "radius": 2.0, "area": 10.0})
		out.append({"pos": Vector2(bd.x, bd.z), "kind": "board", "label": "Guild Board", "radius": 1.5})
	_landmarks[f] = out
	return out


static func kind_color(kind: String) -> Color:
	return KIND_COLORS.get(kind, Color.WHITE)


## Nearest named place to a world position, for the "you are here" line.
static func place_name(p: Vector2) -> String:
	var best := "The Fields"
	var best_d := INF
	for l in landmarks():
		if l["kind"] in ["gate", "smith", "board"]:
			continue
		var d: float = p.distance_to(l["pos"]) - float(l.get("area", l["radius"]))
		if d < 0.0 and d < best_d:
			best_d = d
			best = l["label"]
	if best == "The Fields" and p.length() > island_radius() - 6.0:
		best = "Island's Edge"
	return best
