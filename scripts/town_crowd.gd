extends Node3D
## Ambient townsfolk for the Town of First Light: a handful of villagers
## who stroll round the plaza between the gate, the stalls and the fountain,
## pause, and walk on. Purely cosmetic and local (no collider, no talk, not
## in the "npcs" group), so the server never builds them and quests, the
## minimap and the tests don't see them. Fewer are out after dark.

const PLAZA := Vector3(0, 0, 15)
const RING_MIN := 8.5
const RING_MAX := 12.0
const FOUNTAIN_ANGLE := PI / 2   # the fountain sits at +z from the plaza centre
const COUNT := 8
const LOOKS := [
	{"hair_color": "3b2a20", "outfit_color": "7a5c3e"}, {"hair_color": "d9b380", "outfit_color": "4f6d8f"},
	{"hair_color": "1e1e24", "outfit_color": "8f4a4a"}, {"hair_color": "a0522d", "outfit_color": "5f7a4a"},
	{"hair_color": "e8e4de", "outfit_color": "6b5a8a"}, {"hair_color": "5b3a29", "outfit_color": "b58a3c"},
	{"hair_color": "2b3d5c", "outfit_color": "4a6b6b"}, {"hair_color": "c96f3b", "outfit_color": "3e4a5c"},
]

var world: Node3D
var _folk: Array = []  # {node, vrm, angle, r, target, wait, speed}
var _rng := RandomNumberGenerator.new()


static func build(w: Node3D) -> Node3D:
	var n := Node3D.new()
	n.set_script(load("res://scripts/town_crowd.gd"))
	n.name = "TownCrowd"
	w.add_child(n)
	n.setup(w)
	return n


func setup(w: Node3D) -> void:
	world = w
	_rng.seed = 2207
	var bodies: Array = VRMCharacter.BODIES.keys()
	for i in COUNT:
		var look: Dictionary = (LOOKS[i % LOOKS.size()] as Dictionary).duplicate()
		look["body"] = bodies[i % bodies.size()]
		look["height"] = _rng.randf_range(0.93, 1.06)
		if look["body"] in NPC.UNTINTABLE:
			look.erase("hair_color")
			look.erase("outfit_color")
		var vrm := VRMCharacter.new()
		var holder := Node3D.new()
		holder.name = "Villager%d" % i
		add_child(holder)
		holder.add_child(vrm)
		vrm.apply(look)
		if vrm.instance == null:
			holder.queue_free()
			continue
		# Seed-san's backpack robot arm rests sideways; NPCs hide it too.
		for mi in vrm.instance.find_children("robo_arm", "MeshInstance3D", true, false):
			mi.visible = false
		var a := _free_angle(_rng.randf() * TAU)
		var r := _rng.randf_range(RING_MIN, RING_MAX)
		holder.position = PLAZA + Vector3(cos(a) * r, 0, sin(a) * r)
		_folk.append({"node": holder, "vrm": vrm, "angle": a, "r": r, "target": holder.position,
			"wait": _rng.randf_range(0.0, 4.0), "speed": _rng.randf_range(1.1, 1.5), "night_home": i % 2 == 1})


## Keep walkers off the fountain's side of the ring.
func _free_angle(a: float) -> float:
	var d := wrapf(a - FOUNTAIN_ANGLE, -PI, PI)
	if absf(d) < 0.5:
		a = FOUNTAIN_ANGLE + signf(d if d != 0.0 else 1.0) * 0.5
	return a


func _night() -> bool:
	var dn = world.get("day_night") if world else null
	var h := float(dn.time_of_day) if dn != null else 12.0
	return h >= 20.5 or h < 6.0


func _process(delta: float) -> void:
	var night := _night()
	for f in _folk:
		var n: Node3D = f["node"]
		if not is_instance_valid(n):
			continue
		n.visible = not (night and f["night_home"])
		if not n.visible:
			continue
		var vrm: VRMCharacter = f["vrm"]
		if float(f["wait"]) > 0.0:
			f["wait"] = float(f["wait"]) - delta
			vrm.animate(delta, 0.0, true)
			if float(f["wait"]) <= 0.0:
				# Next stop: a short way round the ring, so the walk never cuts
				# across the gate in the middle.
				f["angle"] = _free_angle(float(f["angle"]) + _rng.randf_range(-1.1, 1.1))
				f["r"] = _rng.randf_range(RING_MIN, RING_MAX)
				f["target"] = PLAZA + Vector3(cos(f["angle"]) * f["r"], 0, sin(f["angle"]) * f["r"])
			continue
		var to: Vector3 = (f["target"] as Vector3) - n.position
		to.y = 0.0
		if to.length() < 0.15:
			f["wait"] = _rng.randf_range(2.0, 7.0)
			continue
		var step := to.normalized() * minf(float(f["speed"]) * delta, to.length())
		n.position += step
		n.rotation.y = lerp_angle(n.rotation.y, atan2(step.x, step.z), minf(delta * 6.0, 1.0))
		vrm.animate(delta, float(f["speed"]), true)
