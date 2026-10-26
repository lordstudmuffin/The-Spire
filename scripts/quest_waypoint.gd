extends Node3D
## In-world waypoint for the tracked quest (Floor 1): a diamond and the
## distance hanging over where to go next, drawn through terrain and trees
## so it reads across the wide floor. While the objective is open it points
## at the objective (the south field, the wolf dens, the nearest ore vein, the
## next unlit waystone...); once it is done it points back to the giver.
## Quests with nothing to walk to (crafting, parry rites) show no marker.
## Client-only and purely visual: the tracker card stays the source of truth.

const OBJECTIVE_COLOR := Color("4fd2ff")
const TURN_IN_COLOR := Color("ffc94a")
const HIDE_WITHIN := 7.0     # m: close enough to see the place itself
const LIFT := 4.5            # m above the ground at the target
const POLL := 0.25

var world: Node3D
var _label: Label3D
var _poll := 0.0


static func build(w: Node3D) -> Node3D:
	var n := Node3D.new()
	n.set_script(load("res://scripts/quest_waypoint.gd"))
	n.name = "QuestWaypoint"
	w.add_child(n)
	n.world = w
	return n


func _ready() -> void:
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 30
	_label.outline_size = 9
	_label.outline_modulate = Color(0.04, 0.05, 0.12, 0.9)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.render_priority = 10
	_label.outline_render_priority = 9
	add_child(_label)
	visible = false


## Where the tracked quest wants the player now (world position), or null.
func target_for(id: String, q: Dictionary) -> Variant:
	var info := QuestData.info(id)
	if int(q.get("progress", 0)) >= int(q.get("goal", 1)):
		return _npc_pos(str(info["giver"]))
	var tower: Vector3 = world.TOWER_POS
	match id:
		"boar_trouble":
			return Vector3(0, 0, 120)
		"wolf_hunt", "wolf_pelts", "old_watch_whispers":
			return tower + Vector3(0, 0, 52)
		"floor_boss", "gravelmaw_bounty":
			return tower + Vector3(0, 0, 14)
		"pond_catch":
			return Vector3(WorldArt.POND.x, 0, WorldArt.POND.y)
		"grove_bloom":
			return world.GROVE
		"tavern_stew":
			return world.TALVEN
		"ore_delivery":
			return _nearest_in_group("ore_veins")
		"talven_waystones":
			var best: Variant = null
			var best_d := INF
			var me := _me()
			for i in world.BEACONS.size():
				if GameState.visited.has("waystone_%d" % i):
					continue
				var d := me.distance_to(world.BEACONS[i])
				if d < best_d:
					best_d = d
					best = world.BEACONS[i]
			return best
	return null


func _me() -> Vector3:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	return p.global_position if p else Vector3.ZERO


func _npc_pos(n: String) -> Variant:
	for npc in get_tree().get_nodes_in_group("npcs"):
		if str(npc.get("npc_name")) == n:
			return (npc as Node3D).global_position
	return null


func _nearest_in_group(g: String) -> Variant:
	var me := _me()
	var best: Variant = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(g):
		var d := me.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = (n as Node3D).global_position
	return best


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL
	var hud = world.get("hud")
	var id: String = str(hud.tracked_quest) if hud != null else ""
	if id == "" or not GameState.quests.has(id) or GameState.floor != 1:
		visible = false
		return
	var q: Dictionary = GameState.quests[id]
	var t = target_for(id, q)
	if not (t is Vector3):
		visible = false
		return
	var me := _me()
	var flat := Vector2(t.x - me.x, t.z - me.z).length()
	if flat < HIDE_WITHIN:
		visible = false
		return
	var ready := int(q.get("progress", 0)) >= int(q.get("goal", 1))
	var ground: float = WorldArt.height_at(Vector2(t.x, t.z)) if t.y < 1.0 else float(t.y)
	global_position = Vector3(t.x, ground + LIFT, t.z)
	_label.modulate = TURN_IN_COLOR if ready else OBJECTIVE_COLOR
	_label.text = "◆\n%d m" % int(round(flat))
	visible = true
