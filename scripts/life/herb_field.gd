class_name HerbField
extends Node3D
## Gatherable wild herbs: one MultiMesh of leafy clumps plus one of pale
## flowers, so a floor's herbs cost two draw calls. Picking an instance
## scales it to nothing and regrows it after REGROW seconds. The world asks
## `nearest()` for the prompt and `pick()` on E, like the ore veins.

const REGROW := 45.0
const PICK_RANGE := 2.6

var positions: Array = []
var _leaves: MultiMeshInstance3D
var _flowers: MultiMeshInstance3D
var _up: Array = []  # bool per instance
var _xf_leaf: Array = []
var _xf_flower: Array = []


static func build(parent: Node3D, spots: Array, tint := Color("7fc46a")) -> HerbField:
	var f := HerbField.new()
	f.name = "Herbs"
	f.positions = spots.duplicate()
	parent.add_child(f)
	f._build(tint)
	return f


func _build(tint: Color) -> void:
	add_to_group("herb_fields")
	var leaf := SphereMesh.new()
	leaf.radius = 0.32
	leaf.height = 0.5
	leaf.radial_segments = 8
	leaf.rings = 4
	var flower := SphereMesh.new()
	flower.radius = 0.09
	flower.height = 0.18
	flower.radial_segments = 6
	flower.rings = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for p in positions:
		var rot := rng.randf() * TAU
		var s := rng.randf_range(0.85, 1.25)
		_xf_leaf.append(WorldArt.xf(p + Vector3(0, 0.12, 0), rot, Vector3(s * 1.3, s * 0.8, s * 1.1)))
		_xf_flower.append(WorldArt.xf(p + Vector3(cos(rot) * 0.18, 0.42 * s, sin(rot) * 0.18), rot, Vector3(s, s, s)))
		_up.append(true)
	_leaves = WorldArt.multimesh(self, leaf, _xf_leaf, [], "Leaves")
	_leaves.material_override = WorldArt.mat(tint, 0.02)
	_flowers = WorldArt.multimesh(self, flower, _xf_flower, [], "Flowers")
	_flowers.material_override = WorldArt.mat(Color("f3e9b0"), 0.0, Color("fff2b0"), 0.35)


## Index of the closest standing herb within range, or -1.
func nearest(from: Vector3, range := PICK_RANGE) -> int:
	var best := -1
	var best_d := range
	for i in positions.size():
		if not _up[i]:
			continue
		var d: float = from.distance_to(positions[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func is_up(i: int) -> bool:
	return i >= 0 and i < _up.size() and _up[i]


## Picks herb i: hides it and schedules the regrowth. Returns the herbs gained.
func pick(i: int) -> int:
	if not is_up(i):
		return 0
	_up[i] = false
	_set_scale(i, 0.0)
	get_tree().create_timer(REGROW, false).timeout.connect(func():
		if is_instance_valid(self):
			regrow(i))
	return 1 if randf() < 0.65 else 2


func regrow(i: int) -> void:
	if i < 0 or i >= _up.size():
		return
	_up[i] = true
	_set_scale(i, 1.0)


func _set_scale(i: int, k: float) -> void:
	var l: Transform3D = _xf_leaf[i]
	var f: Transform3D = _xf_flower[i]
	_leaves.multimesh.set_instance_transform(i, Transform3D(l.basis.scaled(Vector3(k, k, k)), l.origin))
	_flowers.multimesh.set_instance_transform(i, Transform3D(f.basis.scaled(Vector3(k, k, k)), f.origin))
