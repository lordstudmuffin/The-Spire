class_name MobDress
extends RefCounted
## Turns a KayKit humanoid into one of Aincrad's Floor 1 kobolds: the human
## head is hidden and a furred kobold head is bolted to the head bone (long
## thin ears, a muzzle with fangs, glowing eyes), a big furred tail hangs
## from the hips and the hands get kobold arms. After the Ruin Kobolds of
## the first floor's Labyrinth (red demi-humans, long thin ears poking out of
## their helmets, a large tail) and their lord (a big kobold with a bone axe,
## a leather buckler and a curved blade carried at the waist). Original art
## built from primitives; the KayKit body keeps its rig and clips.
##
## Enemy._build_model calls apply(inst, spec["dress"]) once the model is
## fitted. Parts use the creature toon shader with their own materials, so
## the hit flash and the death dissolve treat them like the body.

const FUR := Color("b5482e")        # red-brown kobold fur
const FUR_DARK := Color("6e2618")
const FUR_LIGHT := Color("e09a6a")  # muzzle / belly
const IRON := Color("8d939e")
const LEATHER := Color("5a3a22")
const BONE := Color("e8dcc0")
const EYE := Color(1.0, 0.75, 0.2)
const EYE_LORD := Color(1.0, 0.35, 0.12)

static var _shader: Shader


## kind: "kobold" (scout: spear), "sergeant" (helmet, axe), "sentinel"
## (keeps the Knight's helmet, halberd), "lord" (bone axe, buckler, sheathed
## curved blade, fur mantle).
static func apply(inst: Node3D, kind: String) -> void:
	var sk: Skeleton3D = null
	for s in inst.find_children("*", "Skeleton3D", true, false):
		sk = s
		break
	if sk == null:
		return
	if kind == "greytusk":
		_greytusk(inst, sk)
		return
	var head_box := AABB()
	for mi in sk.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name).to_lower()
		if n.ends_with("_head") or n.ends_with("bearhat") or n.ends_with("helmetvisor") \
				or (kind != "sentinel" and n.ends_with("_helmet")) or n.ends_with("_cape"):
			if n.ends_with("_head"):
				head_box = (mi as MeshInstance3D).get_aabb()
			mi.visible = false
	var hb := sk.find_bone("head")
	if hb < 0:
		return
	var head_rest := sk.get_bone_global_rest(hb)
	if head_box.size == Vector3.ZERO:
		head_box = AABB(head_rest.origin + Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))
	# Head parts are authored in skeleton (model rest) space around the old
	# head's box, then moved into the head bone's space.
	var lord := kind == "lord"
	# Smaller than KayKit's chibi head (the lord's most of all), sitting on
	# the neck, so kobolds read as lean beasts and the lord as a brute.
	var r := minf(head_box.size.x, head_box.size.y) * 0.42 * (0.66 if lord else 0.82)
	var hc := Vector3(head_box.get_center().x, head_rest.origin.y + r * 1.05, head_box.get_center().z + r * 0.15)
	var to_bone := head_rest.affine_inverse()
	var fur := _mat(FUR)
	var fur_d := _mat(FUR_DARK)
	var fur_l := _mat(FUR_LIGHT)
	var iron := _mat(IRON)
	var leather := _mat(LEATHER)
	var bone := _mat(BONE)
	var eye := _mat(EYE_LORD if lord else EYE, EYE_LORD if lord else EYE, 2.2)
	var dark := _mat(Color(0.06, 0.04, 0.05))

	# A holder undoes the bone's rest transform, so parts below are placed in
	# skeleton (rest) space and still follow the bone as it animates.
	var head := _holder(_attach(sk, "head", "KoboldHead"), to_bone)
	var c := hc + Vector3(0, -r * 0.1, 0)
	# Skull, slightly long, with a brow ridge.
	_part(head, _sph(r), fur, c, Vector3.ZERO, Vector3(1.0, 0.92, 1.08))
	_part(head, _bx(r * 1.3, r * 0.22, r * 0.4), fur_d, c + Vector3(0, r * 0.32, r * 0.72), Vector3(-0.25, 0, 0))
	# Muzzle (models face +Z here: KayKit faces +Z in rest space).
	_part(head, _cap(r * 0.34, r * 1.5), fur_l, c + Vector3(0, -r * 0.3, r * 1.1), Vector3(PI / 2 + 0.12, 0, 0))
	_part(head, _cap(r * 0.3, r * 1.3), fur, c + Vector3(0, -r * 0.08, r * 1.05), Vector3(PI / 2 - 0.1, 0, 0))
	_part(head, _sph(r * 0.16), dark, c + Vector3(0, -r * 0.1, r * 1.72))
	for side: float in [-1.0, 1.0]:
		# Long thin ears, swept up and back.
		# Long jackal ears splayed out to the sides, flat like leaves.
		_part(head, _cone(r * 0.4, r * 2.0), fur, c + Vector3(side * r * 1.15, r * 0.8, -r * 0.15), Vector3(-0.2, 0, side * -1.0), Vector3(1, 1, 0.35))
		_part(head, _cone(r * 0.24, r * 1.5), fur_l, c + Vector3(side * r * 1.17, r * 0.76, -r * 0.05), Vector3(-0.2, 0, side * -1.0), Vector3(1, 1, 0.3))
		_part(head, _sph(r * 0.15), eye, c + Vector3(side * r * 0.36, r * 0.12, r * 0.82), Vector3.ZERO, Vector3(1.2, 0.7, 0.5))
		_part(head, _cone(r * 0.07, r * 0.32), bone, c + Vector3(side * r * 0.2, -r * 0.62, r * 1.45), Vector3(PI, 0, 0))
	if kind == "sergeant":
		# Open iron cap with a nose guard; the ears stick out through it.
		var cap := SphereMesh.new()
		cap.radius = r * 1.06
		cap.height = r * 1.06
		cap.is_hemisphere = true
		cap.radial_segments = 16
		cap.rings = 4
		_part(head, cap, iron, c + Vector3(0, r * 0.18, 0))
		_part(head, _bx(r * 0.16, r * 0.7, r * 0.12), iron, c + Vector3(0, r * 0.05, r * 1.02))
	if lord:
		# Mane of darker fur round the jaw and neck.
		for k in 7:
			var a := -PI * 0.8 + PI * 1.6 * k / 6.0
			_part(head, _cone(r * 0.32, r * 0.9), fur_d, c + Vector3(sin(a) * r * 0.85, -r * 0.55, cos(a) * r * 0.6 - r * 0.15), Vector3(PI + 0.5 * cos(a), 0, -0.6 * sin(a)))

	# Tail from the hips: a curve of tapering fur segments.
	var hip_rest := sk.get_bone_global_rest(sk.find_bone("hips"))
	var hips := _holder(_attach(sk, "hips", "KoboldTail"), hip_rest.affine_inverse())
	var body_h := head_box.end.y
	var tr := body_h * (0.085 if lord else 0.075)
	var p := hip_rest.origin + Vector3(0, -body_h * 0.02, -body_h * 0.08)
	var dirv := Vector3(0, -0.35, -1.0).normalized()
	for k in 5:
		var seg := body_h * 0.075
		var mid := p + dirv * seg * 0.5
		var m := _cap(tr * (1.0 - k * 0.15), seg * 1.35)
		var basis := Basis.looking_at(dirv, Vector3.UP) * Basis(Vector3.RIGHT, PI / 2)
		_part(hips, m, fur if k < 4 else fur_d, mid, basis.get_euler())
		p += dirv * seg
		dirv = (dirv + Vector3(0, 0.38, 0)).normalized()

	# Weapons on the hand slots.
	# In the idle clips KayKit's hand slots point +Y back along the body;
	# weapons are authored along +Y, so turn them half round to point ahead.
	var flip := Transform3D(Basis(Vector3.RIGHT, PI), Vector3.ZERO)
	var rh := _holder(_attach(sk, "handslot.r", "KoboldWeapon"), flip)
	var lh := _holder(_attach(sk, "handslot.l", "KoboldOffhand"), flip)
	var u := body_h  # model-space unit
	match kind:
		"kobold":
			_part(rh, _cy(u * 0.012, u * 0.014, u * 0.75), _mat(Color("7a5230")), Vector3(0, u * 0.12, 0))
			_part(rh, _cone(u * 0.03, u * 0.12), iron, Vector3(0, u * 0.55, 0))
			_part(lh, _cy(u * 0.12, u * 0.12, u * 0.02), leather, Vector3(0, 0, 0), Vector3(0, 0, PI / 2))
		"sergeant":
			_part(rh, _cy(u * 0.016, u * 0.018, u * 0.45), _mat(Color("7a5230")), Vector3(0, u * 0.1, 0))
			_part(rh, _bx(u * 0.02, u * 0.12, u * 0.14), iron, Vector3(0, u * 0.28, u * 0.06))
			_part(lh, _cy(u * 0.13, u * 0.13, u * 0.025), iron, Vector3.ZERO, Vector3(0, 0, PI / 2))
		"sentinel":
			# Halberd: long haft, axe blade, spike.
			_part(rh, _cy(u * 0.014, u * 0.016, u * 1.05), _mat(Color("5a3a22")), Vector3(0, u * 0.2, 0))
			_part(rh, _bx(u * 0.018, u * 0.16, u * 0.17), iron, Vector3(0, u * 0.62, u * 0.08))
			_part(rh, _cone(u * 0.025, u * 0.16), iron, Vector3(0, u * 0.78, 0))
		"lord":
			# Bone axe: a femur haft and a jagged blade of bone.
			_part(rh, _cy(u * 0.02, u * 0.024, u * 0.62), bone, Vector3(0, u * 0.14, 0))
			_part(rh, _sph(u * 0.04), bone, Vector3(0, u * 0.45, 0))
			_part(rh, _sph(u * 0.035), bone, Vector3(0, -u * 0.16, 0))
			var blade := CylinderMesh.new()
			blade.top_radius = u * 0.17
			blade.bottom_radius = u * 0.17
			blade.height = u * 0.03
			blade.radial_segments = 7
			blade.rings = 1
			_part(rh, blade, bone, Vector3(0, u * 0.36, u * 0.12), Vector3(PI / 2, 0, 0), Vector3(1, 1, 0.7))
			for k in 3:
				_part(rh, _cone(u * 0.03, u * 0.08), bone, Vector3(0, u * (0.27 + k * 0.08), u * 0.29), Vector3(PI / 2, 0, 0))
			# Leather buckler with iron boss.
			_part(lh, _cy(u * 0.11, u * 0.11, u * 0.025), leather, Vector3.ZERO, Vector3(0, 0, PI / 2))
			_part(lh, _sph(u * 0.03), iron, Vector3(-u * 0.015, 0, 0))
			# The curved blade, sheathed at the left hip (drawn on the last bar).
			var sheath := _holder(_attach(sk, "hips", "KoboldSheath"), hip_rest.affine_inverse())
			var sp := hip_rest.origin + Vector3(u * 0.13, -u * 0.02, u * 0.02)
			_part(sheath, _bx(u * 0.03, u * 0.62, u * 0.05), _mat(Color("2a1a14")), sp, Vector3(1.2, 0, 0.15))
			_part(sheath, _bx(u * 0.025, u * 0.14, u * 0.035), _mat(Color("c8a24a")), sp + Vector3(0, u * 0.3, -u * 0.2), Vector3(1.2, 0, 0.15))


## The lord's last-bar swap: axe and buckler gone, the curved longblade
## drawn from the hip (the scabbard stays, empty). Returns the blade's tip
## node for effects, or null when `root` wears no lord dress.
static func draw_blade(root: Node) -> Node3D:
	var wpn := root.find_child("KoboldWeapon", true, false)
	if wpn == null or wpn.get_child_count() == 0:
		return null
	var hold: Node3D = wpn.get_child(0)
	if hold.has_node("Longblade"):
		return hold.get_node("Longblade/Tip")
	for c in hold.get_children():
		(c as Node3D).visible = false
	var off := root.find_child("KoboldOffhand", true, false)
	if off:
		(off as Node3D).visible = false
	var sheath := root.find_child("KoboldSheath", true, false)
	if sheath and sheath.get_child_count() > 0 and sheath.get_child(0).get_child_count() > 1:
		(sheath.get_child(0).get_child(1) as Node3D).visible = false  # the hilt
	# Size the blade from the axe haft that was there (model-space units).
	var u := 2.4
	for c in hold.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh:
			u = ((c as MeshInstance3D).mesh as CylinderMesh).height / 0.62 * 1.0
			break
	var blade := Node3D.new()
	blade.name = "Longblade"
	hold.add_child(blade)
	var steel := _mat(Color("d8dde6"), Color(0.55, 0.65, 0.8), 0.25)
	_part(blade, _bx(u * 0.03, u * 0.14, u * 0.035), _mat(Color("2a1a14")), Vector3(0, -u * 0.02, 0))  # grip
	_part(blade, _bx(u * 0.1, u * 0.02, u * 0.05), _mat(Color("c8a24a")), Vector3(0, u * 0.06, 0))   # guard
	# A gentle curve: segments bending back along +Z as they rise.
	var p := Vector3(0, u * 0.07, 0)
	var ang := 0.0
	for k in 7:
		var seg := u * 0.1
		var dir := Vector3(0, cos(ang), sin(ang))
		_part(blade, _bx(u * 0.012, seg * 1.08, u * (0.05 - k * 0.004)), steel, p + dir * seg * 0.5, Vector3(-ang, 0, 0))
		p += dir * seg
		ang += 0.06
	var tip := Node3D.new()
	tip.name = "Tip"
	tip.position = p
	blade.add_child(tip)
	return tip


## Greytusk, the Old Boar (a named field elite on the boar's Pig model): long
## curving tusks, a shaggy grey mane down the spine, old pale scars on the
## flanks, a notched ear and one clouded eye. Parts are authored in a frame
## with Y up, -Z toward the snout and lengths in body lengths (L), then
## moved into the bone they ride on.
static func _greytusk(inst: Node3D, sk: Skeleton3D) -> void:
	var sk_xf := AssetLib._relative_xf(inst, sk)
	var at := func(bone: String) -> Transform3D:
		var b := sk.find_bone(bone)
		return sk_xf * sk.get_bone_global_rest(b) if b >= 0 else sk_xf
	if sk.find_bone("Head") < 0 or sk.find_bone("Hips") < 0:
		return
	var head: Transform3D = at.call("Head")
	var head_end: Transform3D = at.call("Head_end")
	var hips: Transform3D = at.call("Hips")
	var shoulders: Transform3D = at.call("Shoulders")
	var fwd := head_end.origin - hips.origin
	fwd.y = 0.0
	var L := maxf(fwd.length(), 0.001)
	fwd = fwd / L
	var right := fwd.cross(Vector3.UP).normalized()
	var basis := Basis(right, Vector3.UP, -fwd)
	var bone_frame := func(bone: String, origin: Vector3) -> Node3D:
		# Holder under the bone, whose local frame is (basis, origin) in
		# model space.
		var att := _attach(sk, bone, "Greytusk" + bone)
		var bone_model: Transform3D = at.call(bone)
		return _holder(att, bone_model.affine_inverse() * Transform3D(basis, origin))
	var bone := _mat(BONE.darkened(0.05))
	var mane := _mat(Color("8c8a86"))
	var mane_dark := _mat(Color("5e5b57"))
	var scar := _mat(Color("d9c2b0"))
	var milk := _mat(Color("cfd6dc"), Color("cfd6dc"), 0.25)
	# Tusks: three tapering segments each, sweeping out, up and back.
	var hf: Node3D = bone_frame.call("Head", head_end.origin)
	for side: float in [-1.0, 1.0]:
		var p := Vector3(side * 0.05 * L, -0.02 * L, 0.02 * L)
		var d := Vector3(side * 0.35, 0.25, -1.0).normalized()
		var r := 0.03 * L
		for k in 3:
			var seg := 0.08 * L
			var mid := p + d * seg * 0.5
			var mi := _part(hf, _cy(r * 0.7, r, seg), bone, mid)
			mi.basis = Basis(Quaternion(Vector3.UP, d))
			p += d * seg
			r *= 0.7
			d = (d + Vector3(side * 0.15, 0.55, 0.35)).normalized()
	# A clouded right eye and a notched left ear.
	_part(hf, _sph(0.022 * L), milk, Vector3(0.075 * L, 0.06 * L, 0.11 * L))
	# Mane: grey tufts from the neck to the hips, longest at the shoulders.
	var bf: Node3D = bone_frame.call("Body", shoulders.origin)
	var top := 0.25 * L
	for i in 9:
		var t := i / 8.0
		var z := lerpf(-0.14, 0.55, t) * L
		var hgt := lerpf(0.16, 0.06, t) * L
		var tilt := lerpf(0.5, 1.1, t)
		_part(bf, _cy(0.0, 0.05 * L * (1.0 - t * 0.4), hgt), mane if i % 2 == 0 else mane_dark,
			Vector3(0, top - t * 0.02 * L + hgt * 0.3, z), Vector3(tilt, 0, 0))
		for side: float in [-1.0, 1.0]:
			_part(bf, _cy(0.0, 0.035 * L, hgt * 0.8), mane_dark, Vector3(side * 0.05 * L, top - 0.02 * L, z + 0.02 * L), Vector3(tilt, 0, side * -0.5))
	# Scars: three pale slashes on each flank.
	for side: float in [-1.0, 1.0]:
		for k in 3:
			_part(bf, _bx(0.008 * L, 0.012 * L, 0.08 * L), scar, Vector3(side * 0.215 * L, 0.06 * L - k * 0.04 * L, 0.12 * L + k * 0.06 * L), Vector3(1.0, 0, 0))


static func _mat(c: Color, emission := Color.BLACK, strength := 0.0) -> ShaderMaterial:
	if _shader == null:
		_shader = load("res://shaders/toon_creature.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("emission_color", emission)
	m.set_shader_parameter("emission_strength", strength)
	return m


static func _attach(sk: Skeleton3D, bone: String, n: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.name = n
	ba.bone_name = bone
	sk.add_child(ba)
	return ba


static func _holder(parent: Node3D, xf: Transform3D) -> Node3D:
	var h := Node3D.new()
	h.transform = xf
	parent.add_child(h)
	return h


static func _part(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 7
	return s


static func _cap(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = 12
	c.rings = 3
	return c


static func _cone(r: float, h: float) -> CylinderMesh:
	return _cy(0.0, r, h)


static func _cy(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 10
	c.rings = 1
	return c


static func _bx(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b
