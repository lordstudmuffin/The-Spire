extends SceneTree
## Headless size check for kit props (no window needed):
##   godot --headless --path . -s tools/prop_sizes.gd -- pack:name:scale ...
## Prints each prop's world-space size (x, y, z in metres) at that scale.

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split(":")
		if parts.size() < 3:
			continue
		var pack := parts[0]
		var pname := parts[1]
		var scl := float(parts[2])
		var root := Node3D.new()
		get_root().add_child(root)
		var n = AssetLib.prop(root, pack, pname, Vector3.ZERO, 0.0, scl, "none")
		if n == null:
			print("%-12s %-28s MISSING" % [pack, pname])
			continue
		var box := AABB()
		var first := true
		for mi in (n as Node).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			# Walk up to the prop root by hand (works whether or not it is in the tree).
			var xf := Transform3D.IDENTITY
			var p: Node = m
			while p != null and p != root:
				if p is Node3D:
					xf = (p as Node3D).transform * xf
				p = p.get_parent()
			var b: AABB = xf * m.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		print("%-12s %-28s %5.1f x %5.1f x %5.1f m" % [pack, pname, box.size.x, box.size.y, box.size.z])
		root.queue_free()
	quit()
