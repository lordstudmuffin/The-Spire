class_name MeshMerge
extends RefCounted
## Bakes the static primitive parts of a procedurally built rig into one
## ArrayMesh per animated anchor (one surface per distinct material), so a
## 40-part mob or a 250-part CharacterModel becomes a handful of draw calls
## that look exactly the same (vertices and normals are transformed exactly,
## so the toon bands and the inverted-hull outlines do not move).
##
## Anchors are nodes carrying meta "merge_anchor": limb pivots that animate()
## rotates, breathing torsos, hair/outfit groups whose visibility toggles.
## Every MeshInstance3D is folded into the nearest anchor above it (or the
## root). A MeshInstance3D that has children or carries meta "merge_keep" is
## left as it is (its mesh children are still merged).

const META_ANCHOR := "merge_anchor"
const META_KEEP := "merge_keep"
const MERGED_NAME := "Merged"

## Off = rigs keep every primitive as its own MeshInstance3D (for before/after
## comparisons: `--no-merge` on the review and screenshot harnesses).
static var enabled := true

## Toon materials on merged surfaces are moved to the opaque twin of their
## shader (see shaders/toon_opaque.gdshader): the base shader writes ALPHA
## and so draws in the transparent queue, where the surfaces of one mesh
## paint in order without depth writes.
const OPAQUE_TWINS := {"res://shaders/toon.gdshader": "res://shaders/toon_opaque.gdshader"}
static var _twin_cache := {}


static func _opaque_shader(sh: Shader) -> Shader:
	if sh == null or not OPAQUE_TWINS.has(sh.resource_path):
		return sh
	var path: String = OPAQUE_TWINS[sh.resource_path]
	if not _twin_cache.has(path):
		_twin_cache[path] = load(path)
	return _twin_cache[path] if _twin_cache[path] != null else sh


static func mark(n: Node, keep := false) -> void:
	n.set_meta(META_KEEP if keep else META_ANCHOR, true)


## Merge under `root`. `by_instance` groups surfaces by material instance
## (CharacterModel re-tints shared materials); otherwise by look, so two
## separately created but identical toon materials share one surface.
## Returns the number of MeshInstance3D nodes removed.
static func merge(root: Node3D, by_instance := false) -> int:
	if not enabled:
		return 0
	var groups := {}   # anchor -> {key -> {"mat": Material, "parts": Array}}
	var anchors: Array[Node3D] = []
	var doomed: Array[MeshInstance3D] = []
	_collect(root, root, Transform3D.IDENTITY, groups, anchors, doomed, by_instance)
	for anchor in anchors:
		var g: Dictionary = groups[anchor]
		if g.is_empty():
			continue
		var am := ArrayMesh.new()
		var mats: Array = []
		for key in g:
			var entry: Dictionary = g[key]
			var arrays := _concat(entry["parts"])
			if arrays.is_empty():
				continue
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mats.append(entry["mat"])
		if am.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = MERGED_NAME
		mi.mesh = am
		for s in mats.size():
			var sm: Material = mats[s]
			if sm is ShaderMaterial:
				sm.shader = _opaque_shader(sm.shader)
			mi.set_surface_override_material(s, sm)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		anchor.add_child(mi)
	for mi in doomed:
		mi.get_parent().remove_child(mi)
		mi.free()
	_prune(root)
	return doomed.size()


static func _collect(n: Node, anchor: Node3D, xf: Transform3D, groups: Dictionary, anchors: Array[Node3D], doomed: Array[MeshInstance3D], by_instance: bool) -> void:
	if not groups.has(anchor):
		groups[anchor] = {}
		anchors.append(anchor)
	for c in n.get_children():
		if not (c is Node3D):
			continue
		var c3 := c as Node3D
		var child_anchor := anchor
		var child_xf := xf * c3.transform
		if c3.has_meta(META_ANCHOR):
			child_anchor = c3
			child_xf = Transform3D.IDENTITY
		if c3 is MeshInstance3D and not c3.has_meta(META_ANCHOR):
			var mi := c3 as MeshInstance3D
			var keep := mi.has_meta(META_KEEP) or mi.get_child_count() > 0 or mi.mesh == null
			if not keep:
				var g: Dictionary = groups[child_anchor]
				for s in mi.mesh.get_surface_count():
					var m: Material = mi.material_override
					if m == null:
						m = mi.get_surface_override_material(s)
					if m == null:
						m = mi.mesh.surface_get_material(s)
					var key := "none"
					if m != null:
						key = str(m.get_instance_id()) if (by_instance or not (m is ShaderMaterial)) else _signature(m)
					if not g.has(key):
						g[key] = {"mat": m, "parts": []}
					g[key]["parts"].append([mi.mesh, s, child_xf])
				doomed.append(mi)
				continue
		_collect(c3, child_anchor, child_xf, groups, anchors, doomed, by_instance)


## Look-alike key for a toon ShaderMaterial (albedo, glow, outline).
static func _signature(m: ShaderMaterial) -> String:
	var parts := PackedStringArray()
	parts.append(str(m.shader.get_instance_id()) if m.shader else "noshader")
	for p in ["albedo", "emission_color", "emission_strength", "bands", "shadow_level", "rim_strength"]:
		var v = m.get_shader_parameter(p)
		if v != null:
			parts.append("%s=%s" % [p, str(v)])
	var np := m.next_pass
	if np is ShaderMaterial:
		parts.append("np=%s/%s/%s" % [str(np.shader.get_instance_id()) if np.shader else "", str(np.get_shader_parameter("outline_width")), str(np.get_shader_parameter("outline_color"))])
	elif np != null:
		parts.append("np=" + str(np.get_instance_id()))
	return "|".join(parts)


## Concatenate [mesh, surface, transform] parts into one surface's arrays.
static func _concat(parts: Array) -> Array:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var has_uv := true
	for p in parts:
		var mesh: Mesh = p[0]
		var arr: Array = mesh.surface_get_arrays(p[1])
		if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
			continue
		var xf: Transform3D = p[2]
		var nbasis := xf.basis.inverse().transposed()
		var flip := xf.basis.determinant() < 0.0
		var base := verts.size()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm = arr[Mesh.ARRAY_NORMAL]
		var uv = arr[Mesh.ARRAY_TEX_UV]
		if uv == null:
			has_uv = false
		for i in v.size():
			verts.append(xf * v[i])
			if nrm != null:
				norms.append((nbasis * nrm[i]).normalized())
			else:
				norms.append(Vector3.UP)
			if has_uv and uv != null:
				uvs.append(uv[i])
		var ind = arr[Mesh.ARRAY_INDEX]
		if ind == null:
			for t in range(0, v.size() - 2, 3):
				if flip:
					idx.append(base + t)
					idx.append(base + t + 2)
					idx.append(base + t + 1)
				else:
					idx.append(base + t)
					idx.append(base + t + 1)
					idx.append(base + t + 2)
		else:
			var ii: PackedInt32Array = ind
			for t in range(0, ii.size() - 2, 3):
				if flip:
					idx.append(base + ii[t])
					idx.append(base + ii[t + 2])
					idx.append(base + ii[t + 1])
				else:
					idx.append(base + ii[t])
					idx.append(base + ii[t + 1])
					idx.append(base + ii[t + 2])
	if verts.is_empty():
		return []
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	if has_uv and uvs.size() == verts.size():
		out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_INDEX] = idx
	return out


## Drop auto-named plain Node3Ds that the merge left empty (the `_nd` pivots
## the primitive builders hang parts on). Named nodes and anchors stay.
static func _prune(n: Node) -> void:
	for c in n.get_children():
		_prune(c)
	for c in n.get_children():
		if c.get_class() == "Node3D" and c.get_child_count() == 0 and c.get_meta_list().is_empty() and String(c.name).begins_with("@"):
			n.remove_child(c)
			c.free()


## PackedScene.pack needs every descendant owned by the root.
static func own(root: Node) -> void:
	for c in root.find_children("*", "", true, false):
		c.owner = root


## Give an instantiated merged rig its own copies of its (toon) materials, so
## per-mob hit flashes and tints never leak to other mobs of the same kind.
## Shared next_pass outlines are kept shared (they carry no per-mob state).
static func localize_materials(root: Node) -> void:
	var dup := {}
	var nodes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		nodes.append(root)
	for mi in nodes:
		if mi.material_override != null:
			mi.material_override = _dup(mi.material_override, dup)
		for s in mi.get_surface_override_material_count():
			var m: Material = mi.get_surface_override_material(s)
			if m != null:
				mi.set_surface_override_material(s, _dup(m, dup))


static func _dup(m: Material, dup: Dictionary) -> Material:
	var id := m.get_instance_id()
	if not dup.has(id):
		dup[id] = m.duplicate()
	return dup[id]


## Every material an instance draws with (override + per-surface), once each.
static func materials_of(root: Node) -> Array:
	var seen := {}
	var out: Array = []
	var nodes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		nodes.append(root)
	for mi in nodes:
		var mats: Array = []
		if mi.material_override != null:
			mats.append(mi.material_override)
		for s in mi.get_surface_override_material_count():
			var m: Material = mi.get_surface_override_material(s)
			if m != null:
				mats.append(m)
		for m in mats:
			if not seen.has(m.get_instance_id()):
				seen[m.get_instance_id()] = true
				out.append(m)
	return out
