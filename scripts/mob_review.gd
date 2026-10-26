extends Node3D
## Review lineup for the merged mob rigs and the VRM NPC bodies, with a fixed
## camera so before/after shots can be compared pixel for pixel.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##       res://scenes/mob_review.tscn -- --shot /tmp/mobs.png [--no-merge] [--npcs] [--stats]
## --no-merge keeps every primitive as its own MeshInstance3D (the old rigs);
## --npcs lines up every named NPC instead, with a stand-in player in front of
## the third one so the head look-at shows; --stats prints mesh/node counts.

const MOBS := [
	{"name": "Field Boar", "color": "8c5940"},
	{"name": "Dire Wolf", "color": "59596b"},
	{"name": "Kobold Scout", "color": "6b7a3a"},
	{"name": "Kobold Sergeant", "color": "8a5a2b", "size": [1.3, 1.4, 1.5]},
	{"name": "Kobold Halberdier", "color": "667380", "size": [1.0, 1.6, 1.0]},
	{"name": "Floor Guardian: Vargash the Kobold Warlord", "color": "806b8c", "size": [3.0, 2.6, 3.6], "boss": true},
	{"name": "Mire Toad", "color": "5f7a3a", "size": [1.3, 0.9, 1.4]},
	{"name": "Thornback Stag", "color": "7a4a2a"},
	{"name": "Marsh Wisp", "color": "7fe8d0", "size": [0.7, 0.9, 0.7], "ranged": 11.0},
	{"name": "Floor Guardian: Mirelord, the Drowned Knight", "color": "3e5a60", "size": [2.4, 3.0, 2.4], "boss": true},
]
## --floor1: every Floor 1 mob as it spawns in world.gd, with a human-height
## NPC at the left as a scale reference.
const FLOOR1 := [
	{"name": "Meadow Slime", "color": "7fd36a", "size": [0.9, 0.7, 0.9], "model": {"pack": "creatures", "name": "Slime"}},
	{"name": "Field Boar", "color": "8c5940"},
	{"name": "Dire Wolf", "color": "59596b"},
	{"name": "Cliff Bat", "color": "4a3a52", "size": [0.8, 0.6, 0.8], "model": {"pack": "creatures", "name": "Bat", "lift": 1.3, "fit": 1.4}},
	{"name": "Tunnel Rat", "color": "6e6258", "size": [0.6, 0.5, 1.0], "model": {"pack": "creatures", "name": "Rat", "fit": 1.3}},
	{"name": "Kobold Scout", "color": "6b7a3a"},
	{"name": "Kobold Sergeant", "color": "8a5a2b", "size": [1.3, 1.4, 1.5]},
	{"name": "Kobold Halberdier", "color": "667380", "size": [1.0, 1.6, 1.0]},
	{"name": "Floor Guardian: Vargash the Kobold Warlord", "color": "806b8c", "size": [3.0, 2.6, 3.6], "boss": true},
]
const NPCS := [
	["Smith Haldor", {"hair_color": "6b3e26", "outfit_color": "4a4a4a", "hair_style": 0, "eye_color": "8d6e63", "height": 1.1}],
	["Guide Mira", {"hair_color": "f4a261", "outfit_color": "2a9d8f", "hair_style": 3, "eye_color": "264653"}],
	["Captain Rhys", {"hair_color": "c0c0c0", "outfit_color": "3a3a5a", "hair_style": 1, "eye_color": "e63946"}],
	["Old Tam", {"hair_color": "e8e4de", "outfit_color": "3a6b8a", "hair_style": 1, "eye_color": "5b3a29", "height": 0.93}],
	["Trader Pell", {"hair_color": "7a4a21", "outfit_color": "9b59b6", "hair_style": 4, "eye_color": "a0522d", "height": 1.02}],
	["Elder Wren", {"hair_color": "dddddd", "outfit_color": "6d597a", "hair_style": 2, "eye_color": "355070", "height": 0.95}],
	["Quartermaster Dain", {"hair_color": "2b2b2b", "outfit_color": "2f4858", "hair_style": 1, "eye_color": "f6ae2d"}],
	["Huntmaster Sable", {"hair_color": "3b2a1e", "outfit_color": "4a5a2e", "hair_style": 4, "eye_color": "8fb34a", "height": 1.05}],
	["Smith Orla", {"hair_color": "c84a2a", "outfit_color": "3a3a3a", "hair_style": 2, "eye_color": "5a7a9a", "height": 1.0}],
	["Keeper Ilsa", {"hair_color": "e8e8f0", "outfit_color": "2e6a62", "hair_style": 3, "eye_color": "5ee0b0", "height": 0.97}],
	["Waykeeper Bran", {"hair_color": "6b5a4a", "outfit_color": "5a4a7a", "hair_style": 1, "eye_color": "d9a441"}],
	["Fisher Maud", {"hair_color": "c4262e", "outfit_color": "2f4858", "hair_style": 3, "eye_color": "3cb371", "height": 0.98}],
]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := ""
	for i in args.size():
		if args[i] == "--shot" and i + 1 < args.size():
			out = args[i + 1]
	if "--no-merge" in args:
		MeshMerge.enabled = false
	GameState.reset()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.28)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.9)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(200, 2, 200)
	cs.shape = bs
	cs.position.y = -1
	floor_body.add_child(cs)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.72, 0.5)
	gm.roughness = 1.0
	ground.material_override = gm
	floor_body.add_child(ground)
	add_child(floor_body)

	var npcs := "--npcs" in args
	# --group 1|2: first / second half of the list, framed closer.
	var group := 0
	for i in args.size():
		if args[i] == "--group" and i + 1 < args.size():
			group = int(args[i + 1])
	var x := 0.0
	var subjects: Array[Node3D] = []
	if npcs:
		var list: Array = NPCS
		if group == 1:
			list = NPCS.slice(0, 6)
		elif group == 2:
			list = NPCS.slice(6)
		for spec in list:
			var n := NPC.new()
			n.npc_name = spec[0]
			n.appearance = spec[1]
			n.position = Vector3(x, 0, 0)
			n.rotation.y = PI  # face the camera (+Z)
			add_child(n)
			subjects.append(n)
			x += 1.9
		if "--no-props" in args:
			for n in subjects:
				for a in n.find_children("PropAttach", "", true, false):
					a.get_parent().remove_child(a)
					a.free()
		# Stand-in player in front of the third NPC: the heads should turn to it.
		var dummy := Node3D.new()
		dummy.add_to_group("players")
		dummy.position = Vector3(0.6, 0, 2.6)
		add_child(dummy)
	else:
		var mlist: Array = MOBS
		if "--floor1" in args:
			mlist = FLOOR1
			var ref := NPC.new()
			ref.npc_name = "Guide Mira"
			ref.appearance = NPCS[1][1]
			ref.position = Vector3(x, 0, 0)
			ref.rotation.y = PI
			add_child(ref)
			x += 1.4
		if group == 1:
			mlist = MOBS.slice(0, 5)
		elif group == 2:
			mlist = MOBS.slice(5)
		# --only NAME: just the mobs whose name contains NAME (closer camera).
		# --turn DEG: extra yaw so a profile lineup can be seen 3/4 on.
		var only := ""
		var turn := 0.0
		for i in args.size():
			if args[i] == "--only" and i + 1 < args.size():
				only = args[i + 1].to_lower()
			if args[i] == "--turn" and i + 1 < args.size():
				turn = deg_to_rad(float(args[i + 1]))
		for spec in mlist:
			if only != "" and not only in str(spec["name"]).to_lower():
				continue
			var d: Dictionary = spec.duplicate()
			var sz: Array = d.get("size", [0.9, 0.8, 1.3])
			x += sz[0] * 0.5 + 0.6
			d["pos"] = [x, 0.2, 0.0]
			var en := Enemy.from_data(d)
			add_child(en)
			en.rotation.y = PI + turn
			en.aggro_range = 0.0
			en.speed = 0.0
			en._wander_timer = 999.0
			subjects.append(en)
			x += sz[0] * 0.5 + 0.6
	var cam := Camera3D.new()
	var mid := x * 0.5
	var dist := x * 0.55 + 3.0
	cam.position = Vector3(mid, 2.4 if npcs else 2.6, dist)
	cam.fov = 55
	add_child(cam)
	cam.look_at(Vector3(mid, 1.0, 0.0))
	cam.current = true
	for i in 30:
		await get_tree().process_frame
	if "--stats" in args:
		var meshes := 0
		var nodes := 0
		var surfaces := 0
		for s in subjects:
			for n in s.find_children("*", "", true, false):
				nodes += 1
				if n is MeshInstance3D and n.mesh:
					meshes += 1
					surfaces += n.mesh.get_surface_count()
		print("DBG review %s meshes=%d surfaces=%d nodes=%d mem=%dKB" % ["npcs" if npcs else "mobs", meshes, surfaces, nodes, int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1024)])
		if not npcs:
			for s in subjects:
				var m := 0
				for n in s.find_children("*", "MeshInstance3D", true, false):
					if n.mesh:
						m += 1
				print("DBG   %-44s meshes=%d" % [s.display_name, m])
	if "--describe" in args and npcs:
		for s in subjects:
			if s._vrm != null:
				print("DBG ", s.npc_name, ": ", s._vrm.describe())
	if out != "":
		var img := get_viewport().get_texture().get_image()
		img.save_png(out)
		print("Saved ", out, " ", img.get_size())
		get_tree().quit()
