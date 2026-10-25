class_name CharacterModel
extends Node3D
## Anime-styled character built entirely from primitives with the toon shader.
## Proportions: ~1.8 m tall at height 1.0, feet at y = 0, facing -Z.
## Every part, hair style and outfit variant is built ONCE; apply() only
## re-tints shared materials and toggles visibility, so dragging a colour
## picker is cheap. Swap for an imported model later; keep apply() as the API.

const HAIR_STYLES := ["Short", "Spiky", "Long", "Twin Tails", "Ponytail", "Bob", "Messy"]
const ORIGINS := ["Swordsman", "Scout", "Guardian", "Arcanist"]

const OUTLINE_WIDTH := 0.018
const OUTLINE_THIN := 0.01

# Skeleton landmarks (metres, at height 1.0).
const HEAD_Y := 1.56
const HEAD_R := 0.235
const SHOULDER_Y := 1.27
const SHOULDER_X := 0.215
const HIP_Y := 0.9
const HIP_X := 0.1

var _parts := {}   # name -> Node3D
var _mats := {}    # role -> ShaderMaterial (shared by every part of that role)
var _hair_groups: Array[Node3D] = []
var _outfit_groups := {}  # origin -> Node3D
var _anim_t := 0.0
var _idle_t := 0.0
var _run_blend := 0.0
var _built := false


func _ready() -> void:
	if not _built:
		_build()


# ---------------------------------------------------------------- helpers --

func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 24
	m.rings = 12
	return m


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 16
	m.rings = 6
	return m


func _box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 20
	return m


func _cone(r: float, h: float) -> CylinderMesh:
	return _cyl(0.0, r, h)


func _node(parent: Node3D, part_name: String, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = part_name
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	_parts[part_name] = n
	return n


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, part_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if part_name != "":
		mi.name = part_name
		_parts[part_name] = mi
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func _mat(role: String, color: Color, width := OUTLINE_WIDTH, emission := Color.BLACK, strength := 0.0) -> ShaderMaterial:
	if _mats.has(role):
		return _mats[role]
	var m := ToonMaterial.part(color, width, emission, strength)
	_mats[role] = m
	return m


# ------------------------------------------------------------------ build --

func _build() -> void:
	_built = true
	# Shared materials; apply() re-tints these.
	var skin := _mat("skin", Color("f2d0b5"))
	var hair := _mat("hair", Color("1a1a2e"))
	var outfit := _mat("outfit", Color("e63946"))
	var outfit_dark := _mat("outfit_dark", Color("7a1c24"))
	var trim := _mat("trim", Color("f1e6c8"))
	var metal := _mat("metal", Color("8893a8"))
	var leather := _mat("leather", Color("4a3220"))
	var boots := _mat("boots", Color("2b1d14"))
	var white := _mat("white", Color(1, 1, 1), 0.0)
	var black := _mat("black", Color(0.08, 0.06, 0.1), 0.0)
	var iris := _mat("iris", Color("4cc9f0"), 0.0, Color("4cc9f0"), 0.25)
	var shine := _mat("shine", Color(1, 1, 1), 0.0, Color(1, 1, 1), 1.2)
	var mouth := _mat("mouth", Color("b3484f"), 0.0)
	var blush := _mat("blush", Color("f29aa0"), 0.0)

	var root := _node(self, "Root", Vector3.ZERO)
	var body := _node(root, "Body", Vector3.ZERO)   # breathing / bob target

	# -- Head ---------------------------------------------------------------
	var head := _node(body, "Head", Vector3(0, HEAD_Y, 0))
	_mi(head, _sphere(HEAD_R), skin, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.06, 0.98))
	# Jaw: a smaller sphere low and slightly forward gives the pointed anime chin.
	_mi(head, _sphere(HEAD_R * 0.78), skin, Vector3(0, -0.1, -0.015), Vector3.ZERO, Vector3(0.92, 0.82, 0.9))
	_mi(head, _sphere(0.05), skin, Vector3(0, -0.185, -0.04), Vector3.ZERO, Vector3(0.9, 0.7, 0.8))  # chin tip
	for side: float in [-1.0, 1.0]:
		_mi(head, _sphere(0.045), skin, Vector3(side * HEAD_R * 0.97, -0.02, 0.0), Vector3.ZERO, Vector3(0.45, 1.0, 0.75))  # ear
	# Face (camera-facing side is -Z).
	var fz := -HEAD_R * 0.86
	for side: float in [-1.0, 1.0]:
		var ex := side * 0.088
		var eye := _node(head, "Eye%s" % ("L" if side < 0 else "R"), Vector3(ex, -0.005, fz))
		_mi(eye, _sphere(0.062), white, Vector3.ZERO, Vector3(0, 0, side * -0.08), Vector3(0.95, 1.45, 0.32))
		_mi(eye, _sphere(0.046), iris, Vector3(0, -0.008, -0.012), Vector3.ZERO, Vector3(0.9, 1.35, 0.3))
		_mi(eye, _sphere(0.024), black, Vector3(0, -0.012, -0.024), Vector3.ZERO, Vector3(0.9, 1.4, 0.3))
		_mi(eye, _sphere(0.016), shine, Vector3(-0.018, 0.03, -0.032), Vector3.ZERO, Vector3(1, 1, 0.4))
		_mi(eye, _sphere(0.008), shine, Vector3(0.014, -0.028, -0.032), Vector3.ZERO, Vector3(1, 1, 0.4))
		# Upper lash line: a thin dark bar over the eye.
		_mi(eye, _box(0.12, 0.016, 0.012), black, Vector3(0, 0.085, -0.006), Vector3(0, 0, side * -0.12))
		# Eyebrow.
		_mi(head, _box(0.1, 0.016, 0.014), hair, Vector3(ex, 0.105, fz + 0.012), Vector3(0, 0, side * -0.18), Vector3.ONE, "Brow%s" % ("L" if side < 0 else "R"))
		# Blush.
		_mi(head, _sphere(0.03), blush, Vector3(side * 0.13, -0.075, fz + 0.045), Vector3.ZERO, Vector3(1.4, 0.7, 0.3))
	_mi(head, _sphere(0.014), skin, Vector3(0, -0.055, fz - 0.03), Vector3.ZERO, Vector3(0.8, 1.2, 0.8))  # nose
	_mi(head, _box(0.045, 0.012, 0.01), mouth, Vector3(0, -0.125, fz + 0.01))

	# -- Neck / torso ---------------------------------------------------------
	_mi(body, _cyl(0.05, 0.06, 0.16), skin, Vector3(0, 1.3, 0))
	var chest := _node(body, "Chest", Vector3(0, 1.1, 0))
	_mi(chest, _capsule(0.165, 0.46), outfit, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1.18, 1.0, 0.72))
	# Collar.
	_mi(chest, _cyl(0.09, 0.13, 0.07), trim, Vector3(0, 0.21, 0.0), Vector3.ZERO, Vector3(1.2, 1, 0.9))
	# Waist / belt.
	_mi(body, _cyl(0.15, 0.16, 0.1), outfit_dark, Vector3(0, 0.93, 0), Vector3.ZERO, Vector3(1.05, 1, 0.78))
	_mi(body, _cyl(0.162, 0.165, 0.05), leather, Vector3(0, 0.935, 0), Vector3.ZERO, Vector3(1.06, 1, 0.8))
	_mi(body, _box(0.07, 0.05, 0.03), metal, Vector3(0, 0.935, -0.135))  # buckle
	# Hips / shorts.
	_mi(body, _sphere(0.17), outfit_dark, Vector3(0, 0.86, 0), Vector3.ZERO, Vector3(1.05, 0.62, 0.8))

	# -- Arms -----------------------------------------------------------------
	for side: float in [-1.0, 1.0]:
		var tag := "L" if side < 0 else "R"
		var arm := _node(body, "Arm" + tag, Vector3(side * SHOULDER_X, SHOULDER_Y, 0), Vector3(0, 0, side * -0.14))
		_mi(arm, _sphere(0.072), outfit, Vector3(0, 0.01, 0), Vector3.ZERO, Vector3(1.0, 0.85, 1.0))  # shoulder
		_mi(arm, _capsule(0.055, 0.3), outfit, Vector3(0, -0.16, 0))
		_mi(arm, _capsule(0.048, 0.28), skin, Vector3(0, -0.42, 0))
		_mi(arm, _cyl(0.058, 0.052, 0.07), outfit_dark, Vector3(0, -0.31, 0))  # sleeve cuff
		var hand := _node(arm, "Hand" + tag, Vector3(0, -0.6, 0))
		_mi(hand, _sphere(0.052), skin, Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 1.1, 0.65))
		_mi(hand, _capsule(0.016, 0.06), skin, Vector3(side * -0.04, 0.0, -0.01), Vector3(0, 0, side * 0.5))  # thumb

	# -- Legs -----------------------------------------------------------------
	for side: float in [-1.0, 1.0]:
		var tag := "L" if side < 0 else "R"
		var leg := _node(body, "Leg" + tag, Vector3(side * HIP_X, HIP_Y, 0))
		_mi(leg, _capsule(0.082, 0.4), outfit_dark, Vector3(0, -0.2, 0), Vector3.ZERO, Vector3(1, 1, 0.95))
		_mi(leg, _capsule(0.068, 0.38), outfit_dark, Vector3(0, -0.5, 0))
		_mi(leg, _sphere(0.07), outfit_dark, Vector3(0, -0.38, -0.01), Vector3.ZERO, Vector3(1, 0.9, 1))  # knee
		# Boot: shaft + foot.
		_mi(leg, _cyl(0.078, 0.085, 0.2), boots, Vector3(0, -0.78, 0))
		_mi(leg, _cyl(0.088, 0.088, 0.03), leather, Vector3(0, -0.69, 0))  # boot cuff
		_mi(leg, _box(0.15, 0.085, 0.27), boots, Vector3(0, -0.857, -0.045))
		_mi(leg, _sphere(0.07), boots, Vector3(0, -0.86, -0.17), Vector3.ZERO, Vector3(1.0, 0.6, 0.9))  # rounded toe

	# -- Hair (all styles built, one visible) ---------------------------------
	for i in HAIR_STYLES.size():
		var g := _node(head, "Hair%d" % i, Vector3.ZERO)
		_build_hair(g, i, hair)
		g.visible = false
		_hair_groups.append(g)

	# -- Outfit variants (all built, one visible) ------------------------------
	for o in ORIGINS:
		var g := _node(body, "Outfit" + o, Vector3.ZERO)
		_build_outfit(g, o)
		g.visible = false
		_outfit_groups[o] = g

	# -- Merge: ~250 primitives become one mesh per animated pivot / toggled
	# group (surfaces keep the shared role materials, so apply() still re-tints).
	for pn in ["Body", "Chest", "ArmL", "ArmR", "LegL", "LegR"]:
		MeshMerge.mark(_parts[pn])
	for g in _hair_groups:
		MeshMerge.mark(g)
	for o in _outfit_groups:
		MeshMerge.mark(_outfit_groups[o])
	MeshMerge.merge(root, true)


## Hair is layered: a skull cap, a row of bangs (flattened spheres + cone tips),
## side locks over the ears, and a style-specific back.
func _build_hair(g: Node3D, style: int, hair: ShaderMaterial) -> void:
	var r := HEAD_R
	# Skull cap sitting slightly above the scalp.
	_mi(g, _sphere(r * 1.08), hair, Vector3(0, 0.035, 0.01), Vector3.ZERO, Vector3(1.0, 0.98, 1.0))
	# Bangs: overlapping clumps along the hairline, short tapered tips that
	# stop at the eyebrows so the eyes stay clear.
	var bang_count := 5 if style != 5 else 6
	for i in bang_count:
		var t := float(i) / float(bang_count - 1) - 0.5
		var a := t * 1.5
		var x := sin(a) * r * 0.95
		var z := -cos(a) * r * 0.95
		var y := 0.16 - absf(t) * 0.04
		_mi(g, _sphere(0.085), hair, Vector3(x, y, z), Vector3(0, -a, 0), Vector3(0.9, 1.05, 0.55))
		if style != 5 and style != 2:
			var tip_len := 0.09 + 0.03 * (1.0 - absf(t) * 2.0)
			_mi(g, _cone(0.038, tip_len), hair, Vector3(x * 1.03, y - 0.085 - tip_len * 0.35, z * 1.03), Vector3(PI + 0.22, -a, t * -0.7))
	# Side locks framing the face.
	for side: float in [-1.0, 1.0]:
		var lock_len := 0.3 if style in [2, 5, 3] else 0.2
		_mi(g, _capsule(0.05, lock_len), hair, Vector3(side * r * 0.98, 0.0 - lock_len * 0.2, -r * 0.35), Vector3(0.1, 0, side * 0.08), Vector3(0.8, 1, 1))
		_mi(g, _cone(0.045, 0.12), hair, Vector3(side * r * 0.98, -lock_len * 0.7 - 0.05, -r * 0.35), Vector3(PI, 0, side * 0.1))
	match style:
		0:  # Short: tidy back with a couple of flicks at the nape.
			_mi(g, _sphere(r * 0.9), hair, Vector3(0, -0.02, r * 0.35), Vector3.ZERO, Vector3(1.0, 1.0, 0.8))
			for i in 3:
				var a := (i - 1) * 0.6
				_mi(g, _cone(0.045, 0.14), hair, Vector3(sin(a) * r * 0.8, -0.12, cos(a) * r * 0.85), Vector3(PI - 0.6, -a, 0))
		1:  # Spiky: big upward/backward spikes all over the crown.
			for i in 9:
				var a := TAU * i / 9.0
				var tilt := 0.55 + 0.1 * (i % 2)
				var len := 0.3 + 0.08 * (i % 3)
				var pos := Vector3(cos(a) * r * 0.75, 0.2, sin(a) * r * 0.75 + 0.05)
				_mi(g, _cone(0.07, len), hair, pos + Vector3(cos(a), 0, sin(a)) * len * 0.3 + Vector3(0, len * 0.3, 0), Vector3(sin(a) * tilt, 0, -cos(a) * tilt))
			_mi(g, _cone(0.075, 0.38), hair, Vector3(0, 0.42, 0.04), Vector3(0.2, 0, 0))
		2:  # Long: flowing back and a thick curtain of strands past the shoulders.
			_mi(g, _sphere(r * 0.95), hair, Vector3(0, -0.05, r * 0.45), Vector3.ZERO, Vector3(1.05, 1.1, 0.8))
			for i in 7:
				var t := float(i) / 6.0 - 0.5
				var x := t * r * 1.7
				_mi(g, _capsule(0.06, 0.62), hair, Vector3(x, -0.4, r * 0.75 - absf(t) * 0.1), Vector3(0.12, 0, t * -0.3), Vector3(1, 1, 0.8))
				_mi(g, _cone(0.055, 0.16), hair, Vector3(x - t * 0.09, -0.78, r * 0.7 - absf(t) * 0.1), Vector3(PI + 0.12, 0, t * -0.3))
			# Swept bang tips for the Long style.
			for i in 5:
				var t := float(i) / 4.0 - 0.5
				var a := t * 1.5
				_mi(g, _cone(0.04, 0.13), hair, Vector3(sin(a) * r * 0.99, 0.03, -cos(a) * r * 0.99), Vector3(PI + 0.2, -a, t * -0.9))
		3:  # Twin tails: two high tails with ribbons, curling down.
			for side: float in [-1.0, 1.0]:
				var base := Vector3(side * r * 0.95, 0.14, r * 0.25)
				_mi(g, _sphere(0.085), hair, base, Vector3.ZERO, Vector3(1, 0.9, 1))
				_mi(g, _box(0.07, 0.09, 0.05), _mats["trim"], base + Vector3(side * 0.02, 0.0, 0), Vector3(0, 0, side * 0.3))
				_mi(g, _capsule(0.065, 0.55), hair, base + Vector3(side * 0.12, -0.32, 0.03), Vector3(0.1, 0, side * 0.22))
				_mi(g, _capsule(0.06, 0.3), hair, base + Vector3(side * 0.2, -0.7, 0.04), Vector3(0.0, 0, side * -0.25))
				_mi(g, _cone(0.05, 0.16), hair, base + Vector3(side * 0.16, -0.92, 0.05), Vector3(PI, 0, side * -0.3))
		4:  # Ponytail: hair tie high at the back, one thick tail swinging out.
			_mi(g, _sphere(r * 0.9), hair, Vector3(0, 0.0, r * 0.35), Vector3.ZERO, Vector3(1.0, 1.0, 0.8))
			var base := Vector3(0, 0.12, r * 0.95)
			_mi(g, _sphere(0.09), hair, base, Vector3.ZERO, Vector3(1, 0.9, 1))
			_mi(g, _cyl(0.07, 0.07, 0.05), _mats["trim"], base + Vector3(0, 0, 0.03), Vector3(PI / 2, 0, 0))
			_mi(g, _capsule(0.085, 0.55), hair, base + Vector3(0, -0.28, 0.14), Vector3(0.35, 0, 0))
			_mi(g, _capsule(0.065, 0.3), hair, base + Vector3(0, -0.66, 0.2), Vector3(-0.15, 0, 0))
			_mi(g, _cone(0.055, 0.18), hair, base + Vector3(0, -0.88, 0.17), Vector3(PI + 0.1, 0, 0))
		5:  # Bob: helmet-shaped, cut straight at the jaw line, blunt bangs.
			_mi(g, _sphere(r * 1.1), hair, Vector3(0, -0.04, 0.03), Vector3.ZERO, Vector3(1.05, 1.0, 1.0))
			_mi(g, _cyl(r * 1.12, r * 1.05, 0.2), hair, Vector3(0, -0.14, 0.03), Vector3.ZERO, Vector3(1.05, 1, 1.0))
			# Blunt fringe: a flat slab across the forehead.
			_mi(g, _cyl(r * 1.0, r * 1.02, 0.1), hair, Vector3(0, 0.0, -0.02), Vector3.ZERO, Vector3(1.0, 1, 0.98))
		6:  # Messy: tufts poking out at odd angles everywhere.
			_mi(g, _sphere(r * 0.9), hair, Vector3(0, -0.02, r * 0.35), Vector3.ZERO, Vector3(1.0, 1.0, 0.8))
			var seed := 7
			for i in 12:
				seed = (seed * 1103515245 + 12345) % 2147483648
				var a := TAU * i / 12.0 + float(seed % 100) / 300.0
				var el := 0.2 + float((seed / 100) % 100) / 120.0
				var len := 0.16 + float((seed / 1000) % 100) / 500.0
				var dir := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el))
				var pos := dir * r * 0.9 + Vector3(0, 0.03, 0.02) + dir * len * 0.35
				var rot := Vector3(0, 0, 0)
				# Point the cone along dir: cone's +Y is its tip.
				var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
				var mi := _mi(g, _cone(0.05, len), hair, pos, rot)
				mi.basis = basis * Basis(Vector3.RIGHT, PI / 2)


## Origin-specific gear layered over the base body.
func _build_outfit(g: Node3D, origin: String) -> void:
	var outfit: ShaderMaterial = _mats["outfit"]
	var dark: ShaderMaterial = _mats["outfit_dark"]
	var trim: ShaderMaterial = _mats["trim"]
	var metal: ShaderMaterial = _mats["metal"]
	var leather: ShaderMaterial = _mats["leather"]
	match origin:
		"Swordsman":
			# Light armour: breastplate, small pauldrons, a flowing half-cape.
			_mi(g, _capsule(0.17, 0.28), metal, Vector3(0, 1.15, -0.01), Vector3.ZERO, Vector3(1.1, 0.8, 0.62))
			_mi(g, _box(0.26, 0.035, 0.02), trim, Vector3(0, 1.05, -0.125), Vector3(0.15, 0, 0))
			_mi(g, _box(0.02, 0.16, 0.02), trim, Vector3(0, 1.16, -0.128))
			for side: float in [-1.0, 1.0]:
				_mi(g, _sphere(0.095), metal, Vector3(side * SHOULDER_X, SHOULDER_Y + 0.03, 0), Vector3(0, 0, side * -0.2), Vector3(1.0, 0.75, 1.0))
			_mi(g, _box(0.22, 0.62, 0.03), outfit, Vector3(0, 0.95, 0.16), Vector3(-0.12, 0, 0))
			_mi(g, _box(0.24, 0.05, 0.03), trim, Vector3(0, 1.25, 0.13), Vector3(-0.12, 0, 0))
			# Sword belt across the chest.
			_mi(g, _box(0.04, 0.42, 0.015), leather, Vector3(0.06, 1.12, -0.165), Vector3(0, 0, 0.55))
		"Scout":
			# Open hood (hemisphere, pole pointing back), scarf, short cloak, bracers.
			var hood := SphereMesh.new()
			hood.radius = HEAD_R * 1.3
			hood.height = HEAD_R * 1.3
			hood.is_hemisphere = true
			hood.radial_segments = 24
			hood.rings = 10
			_mi(g, hood, dark, Vector3(0, HEAD_Y + 0.01, 0.04), Vector3(PI / 2 - 0.35, 0, 0))
			var rim := TorusMesh.new()
			rim.inner_radius = HEAD_R * 1.22
			rim.outer_radius = HEAD_R * 1.36
			_mi(g, rim, dark, Vector3(0, HEAD_Y + 0.01, 0.04), Vector3(PI / 2 - 0.35, 0, 0))
			_mi(g, _cone(0.09, 0.2), dark, Vector3(0, HEAD_Y + 0.24, 0.16), Vector3(0.9, 0, 0))
			_mi(g, _cyl(0.16, 0.2, 0.45), dark, Vector3(0, 1.1, 0.06), Vector3(0.06, 0, 0), Vector3(1.25, 1, 0.9))  # cloak
			_mi(g, _cyl(0.1, 0.12, 0.07), outfit, Vector3(0, 1.33, -0.02), Vector3.ZERO, Vector3(1.2, 1, 1))  # scarf
			for side: float in [-1.0, 1.0]:
				_mi(g, _cyl(0.058, 0.06, 0.12), leather, Vector3(side * (SHOULDER_X + 0.06), SHOULDER_Y - 0.42, 0), Vector3(0, 0, side * -0.14))
			_mi(g, _box(0.1, 0.12, 0.06), leather, Vector3(-0.17, 0.9, 0.04))  # belt pouch
		"Guardian":
			# Plate: big pauldrons, full cuirass, tabard, gauntlets, greaves.
			_mi(g, _capsule(0.19, 0.42), metal, Vector3(0, 1.13, 0), Vector3.ZERO, Vector3(1.2, 1.0, 0.8))
			_mi(g, _box(0.34, 0.08, 0.06), trim, Vector3(0, 1.0, -0.14))
			for side: float in [-1.0, 1.0]:
				_mi(g, _sphere(0.13), metal, Vector3(side * (SHOULDER_X + 0.03), SHOULDER_Y + 0.05, 0), Vector3(0, 0, side * -0.25), Vector3(1.0, 0.8, 1.0))
				_mi(g, _sphere(0.1), outfit, Vector3(side * (SHOULDER_X + 0.03), SHOULDER_Y + 0.1, 0), Vector3(0, 0, side * -0.25), Vector3(0.8, 0.5, 0.8))
				_mi(g, _cyl(0.065, 0.07, 0.16), metal, Vector3(side * (SHOULDER_X + 0.065), SHOULDER_Y - 0.44, 0), Vector3(0, 0, side * -0.14))
				_mi(g, _cyl(0.085, 0.095, 0.3), metal, Vector3(side * HIP_X, 0.4, -0.01))
			_mi(g, _box(0.2, 0.5, 0.03), outfit, Vector3(0, 0.7, -0.13))  # tabard front
			_mi(g, _box(0.16, 0.14, 0.02), trim, Vector3(0, 0.78, -0.15))  # crest
		"Arcanist":
			# Robe skirt, wide sleeves, mantle, a floating focus crystal.
			_mi(g, _cyl(0.17, 0.36, 0.78), outfit, Vector3(0, 0.45, 0))
			_mi(g, _cyl(0.175, 0.3, 0.5), dark, Vector3(0, 0.62, -0.02), Vector3.ZERO, Vector3(0.35, 1, 1.02))  # front panel
			_mi(g, _cyl(0.18, 0.24, 0.14), dark, Vector3(0, 1.24, 0.0), Vector3.ZERO, Vector3(1.2, 1, 0.85))  # mantle
			_mi(g, _cyl(0.1, 0.17, 0.1), trim, Vector3(0, 1.33, 0), Vector3.ZERO, Vector3(1.1, 1, 1))  # tall collar
			for side: float in [-1.0, 1.0]:
				_mi(g, _cyl(0.06, 0.11, 0.25), outfit, Vector3(side * (SHOULDER_X + 0.07), SHOULDER_Y - 0.4, 0), Vector3(0, 0, side * -0.14))
			var crystal := _mi(g, _cyl(0.0, 0.04, 0.1), _mat("crystal", Color("8be9fd"), 0.0, Color("8be9fd"), 2.0), Vector3(0.28, 1.45, -0.1), Vector3.ZERO, Vector3.ONE, "Crystal")
			_mi(crystal, _cyl(0.04, 0.0, 0.1), _mats["crystal"], Vector3(0, -0.1, 0))


# ------------------------------------------------------------------ apply --

func apply(c: Dictionary) -> void:
	if not _built:
		_build()
	var skin := Color(c.get("skin_color", "f2d0b5"))
	var outfit := Color(c.get("outfit_color", "e63946"))
	var eyes := Color(c.get("eye_color", "4cc9f0"))
	var hair := Color(c.get("hair_color", "1a1a2e"))
	ToonMaterial.tint(_mats["skin"], skin)
	ToonMaterial.tint(_mats["hair"], hair)
	ToonMaterial.tint(_mats["outfit"], outfit)
	ToonMaterial.tint(_mats["outfit_dark"], outfit.darkened(0.45))
	ToonMaterial.tint(_mats["iris"], eyes, eyes, 0.25)
	ToonMaterial.tint(_mats["mouth"], skin.darkened(0.35).lerp(Color("c0392b"), 0.4))
	ToonMaterial.tint(_mats["blush"], skin.lerp(Color("ff8da1"), 0.45))
	var style := clampi(int(c.get("hair_style", 0)), 0, HAIR_STYLES.size() - 1)
	for i in _hair_groups.size():
		_hair_groups[i].visible = i == style
	var origin := str(c.get("origin", "Swordsman"))
	if not _outfit_groups.has(origin):
		origin = "Swordsman"
	for o in _outfit_groups:
		_outfit_groups[o].visible = o == origin
	var h: float = clampf(float(c.get("height", 1.0)), 0.85, 1.15)
	scale = Vector3(h, h, h)


## Attachment point for a held weapon (right hand, palm facing -Z).
func hand_r() -> Node3D:
	if not _built:
		_build()
	return _parts["HandR"]


# ---------------------------------------------------------------- animate --

## Cheap procedural locomotion: leg/arm swing scaled by speed, a bob, and an
## idle breath. Call every physics tick; speed is horizontal m/s. `attack`
## (0..1) raises the sword arm forward for the duration of a swing.
func animate(delta: float, speed: float, grounded: bool, attack := 0.0) -> void:
	if not _built:
		return
	var run := clampf(speed / 5.0, 0.0, 1.0)
	_run_blend = lerpf(_run_blend, run, minf(delta * 10.0, 1.0))
	_idle_t += delta
	_anim_t += delta * (6.0 + 8.0 * _run_blend)
	var swing := sin(_anim_t) * 0.75 * _run_blend
	var leg_l: Node3D = _parts["LegL"]
	var leg_r: Node3D = _parts["LegR"]
	var arm_l: Node3D = _parts["ArmL"]
	var arm_r: Node3D = _parts["ArmR"]
	var body: Node3D = _parts["Body"]
	var chest: Node3D = _parts["Chest"]
	if grounded:
		leg_l.rotation.x = swing
		leg_r.rotation.x = -swing
		arm_l.rotation.x = -swing * 0.8
		arm_r.rotation.x = lerpf(swing * 0.8, -1.25, attack)
		body.position.y = absf(sin(_anim_t)) * 0.045 * _run_blend
		body.rotation.x = 0.12 * _run_blend
	else:
		# Airborne: legs tuck, arms lift a little.
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.35, delta * 8.0)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, -0.2, delta * 8.0)
		arm_l.rotation.x = lerpf(arm_l.rotation.x, -0.5, delta * 8.0)
		arm_r.rotation.x = lerpf(arm_r.rotation.x, lerpf(-0.5, -1.25, attack), delta * 8.0)
		body.position.y = 0.0
		body.rotation.x = 0.0
	var breath := 1.0 + 0.015 * sin(_idle_t * 2.2) * (1.0 - _run_blend)
	chest.scale = Vector3(breath, 1.0, breath)
