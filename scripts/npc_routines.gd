extends Node
## Day/night routines for Floor 1 villagers: at set hours an NPC walks to
## another spot (the tavern porch after dark, a night patrol round the camp)
## and walks back at dawn. Everything follows world.day_night.time_of_day,
## which the server syncs to every client, so the same NPC stands in the
## same place on every machine and the server's talk range checks
## (world._srv_npc_near reads the live node position) agree with what the
## player sees. Walks are short and through open ground.

const WALK := 1.6          # m/s
const ARRIVE := 0.15

## npc_name -> list of {from, to, path}. `path` is a list of points relative
## to the anchor (world var name); one point = stand there, several = walk
## the loop. Outside every slot the NPC is at its spawn position.
const ROUTINES := {
	"Trapper Vesna": {"anchor": "HOLLOWBROOK", "slots": [
		{"from": 19.0, "to": 24.0, "path": [Vector3(-4.0, 0, -4.6)]},
	], "bark": "Long day on the trails. Rook's stew is the only thing worth walking back for."},
	"Herbalist Hesper": {"anchor": "HOLLOWBROOK", "slots": [
		{"from": 5.5, "to": 8.5, "path": [Vector3(-13.6, 0, 10.4), Vector3(-12.0, 0, 11.6)]},
	], "bark": "Dew's still on the leaves. That's when the wild herb is sweetest."},
	"Old Watchman Bram": {"anchor": "TALVEN", "slots": [
		{"from": 20.0, "to": 24.0, "path": [Vector3(-3.6, 0, 3.2), Vector3(-5.0, 0, -2.0), Vector3(1.0, 0, -4.5), Vector3(-1.0, 0, 3.8)]},
		{"from": 0.0, "to": 5.0, "path": [Vector3(-3.6, 0, 3.2), Vector3(-5.0, 0, -2.0), Vector3(1.0, 0, -4.5), Vector3(-1.0, 0, 3.8)]},
	], "bark": "Night watch. The waystones hum louder after dark, have you noticed?"},
}

var world: Node3D
var _npcs := {}   # name -> {node, home, rot, routine, leg, anchor}


static func build(w: Node3D) -> Node:
	var n := Node.new()
	n.set_script(load("res://scripts/npc_routines.gd"))
	n.name = "NpcRoutines"
	w.add_child(n)
	n.setup(w)
	return n


func setup(w: Node3D) -> void:
	world = w
	for npc in w.get_children():
		if npc is NPC and ROUTINES.has(npc.npc_name):
			var r: Dictionary = ROUTINES[npc.npc_name]
			_npcs[npc.npc_name] = {"node": npc, "home": npc.position, "rot": npc.rotation.y, "routine": r,
				"leg": 0, "anchor": w.get(str(r["anchor"]))}


func hour() -> float:
	var dn = world.get("day_night") if world else null
	return float(dn.time_of_day) if dn != null else 12.0


static func slot_for(r: Dictionary, h: float) -> Dictionary:
	for s in r["slots"]:
		if h >= float(s["from"]) and h < float(s["to"]):
			return s
	return {}


## Where `name` should be heading right now (world-local position).
func goal_of(name: String) -> Vector3:
	var e: Dictionary = _npcs[name]
	var s := slot_for(e["routine"], hour())
	if s.is_empty():
		return e["home"]
	var path: Array = s["path"]
	var anchor: Vector3 = e["anchor"] if e["anchor"] is Vector3 else Vector3.ZERO
	return anchor + (path[int(e["leg"]) % path.size()] as Vector3)


## True while the NPC is away from home on a routine.
func is_out(name: String) -> bool:
	return _npcs.has(name) and not slot_for(_npcs[name]["routine"], hour()).is_empty()


func bark(name: String) -> String:
	return str(ROUTINES[name].get("bark", "")) if is_out(name) else ""


func _process(delta: float) -> void:
	for name in _npcs:
		_step(name, delta)


func _step(name: String, delta: float) -> void:
	var e: Dictionary = _npcs[name]
	var npc: NPC = e["node"]
	if not is_instance_valid(npc):
		return
	var goal := goal_of(name)
	var to := (goal - npc.position) * Vector3(1, 0, 1)
	var vrm = npc.get("_vrm")
	if to.length() <= ARRIVE:
		# Arrived: on a loop, head for the next point; at rest face the way
		# they normally face (home) or the walk direction (elsewhere).
		var s := slot_for(e["routine"], hour())
		if not s.is_empty() and (s["path"] as Array).size() > 1:
			e["leg"] = int(e["leg"]) + 1
		elif s.is_empty():
			npc.rotation.y = lerp_angle(npc.rotation.y, float(e["rot"]), minf(delta * 4.0, 1.0))
			e["leg"] = 0
		if vrm != null:
			vrm.animate(delta, 0.0, true)
		return
	var stepv := to.normalized() * minf(WALK * delta, to.length())
	npc.position += stepv
	npc.rotation.y = lerp_angle(npc.rotation.y, atan2(stepv.x, stepv.z), minf(delta * 6.0, 1.0))
	if vrm != null:
		vrm.animate(delta, WALK, true)


## Tests / screenshots: put every routine NPC where it belongs at once.
func settle() -> void:
	for name in _npcs:
		var e: Dictionary = _npcs[name]
		if is_instance_valid(e["node"]):
			e["node"].position = goal_of(name)
