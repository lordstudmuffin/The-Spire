extends Node3D
## Visual check for the imported packs: HDRI sky + RenderProfile, PBR ground,
## a modular Kenney cottage, nature props, a castle tower and a VRM body.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##       res://scenes/asset_showcase.tscn -- --shot out.png [--sky day|sunset|dusk|night]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := ""
	var sky := "day"
	for i in args.size():
		if args[i] == "--shot" and i + 1 < args.size():
			out = args[i + 1]
		if args[i] == "--sky" and i + 1 < args.size():
			sky = args[i + 1]
	_build(sky)
	if out != "":
		for i in 40:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(out)
		print("Saved ", out, " ", img.get_size())
		get_tree().quit()


func _build(sky: String) -> void:
	# Environment.
	var we := WorldEnvironment.new()
	var e := Environment.new()
	AssetLib.apply_sky(e, sky, 1.0, 20.0)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 4.0
	e.tonemap_exposure = 0.85 if sky == "day" else 1.1
	e.fog_enabled = true
	e.fog_density = 0.002
	e.fog_sky_affect = 0.0
	e.fog_light_color = Color("dfe8ff")
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_hdr_threshold = 1.3
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.1
	e.adjustment_contrast = 1.04
	we.environment = e
	add_child(we)
	RenderProfile.apply(RenderProfile.recommended_preset(), get_viewport(), e)

	var sun := DirectionalLight3D.new()
	sun.rotation = AssetLib.sun_rotation(sky)
	sun.light_energy = 1.3 if sky == "day" else 0.5
	sun.light_color = Color("fff2dc") if sky != "night" else Color("9fb4ff")
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.5
	add_child(sun)

	# Ground: PBR grass with a cobbled path.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	pm.subdivide_depth = 8
	pm.subdivide_width = 8
	ground.mesh = pm
	ground.material_override = AssetLib.pbr("aerial_grass_rock", 0.35, true, Color("b8e6a0"))
	add_child(ground)
	var path := MeshInstance3D.new()
	var ppm := PlaneMesh.new()
	ppm.size = Vector2(5, 60)
	path.mesh = ppm
	path.position = Vector3(0, 0.02, 10)
	path.material_override = AssetLib.pbr("cobblestone_floor_08", 0.6)
	add_child(path)

	# Buildings from the modular town kit.
	AssetLib.house(self, Vector3(-10, 0, -6), "home_A", "blue", 0.35)
	AssetLib.house(self, Vector3(9, 0, -9), "home_B", "red", -0.4)
	AssetLib.house(self, Vector3(18, 0, 2), "tavern", "green", -1.4)
	AssetLib.house(self, Vector3(-18, 0, 4), "blacksmith", "yellow", 1.2)
	AssetLib.house(self, Vector3(0, 0, -16), "church", "blue", 0.0)
	AssetLib.house(self, Vector3(-4, 0, 9), "well", "red", 0.0, 4.0)
	AssetLib.prop(self, "town", "fountain-round", Vector3(0, 0, -2), 0.0, 2.4)
	AssetLib.prop(self, "town", "lantern", Vector3(-3.5, 0, 3), 0.0, 2.4)
	AssetLib.prop(self, "town", "lantern", Vector3(3.5, 0, 3), 0.0, 2.4)
	AssetLib.prop(self, "town", "stall-red", Vector3(-6, 0, 6), 0.6, 2.4)
	AssetLib.prop(self, "town", "cart", Vector3(5, 0, 7), -0.8, 2.4)
	AssetLib.house(self, Vector3(-24, 0, -16), "windmill", "green", 0.5)
	# Castle tower + wall section for the Labyrinth look.
	AssetLib.prop(self, "castle", "tower-square", Vector3(0, 0, -30), 0.0, 4.0)
	AssetLib.prop(self, "castle", "wall", Vector3(-6, 0, -30), 0.0, 4.0)
	AssetLib.prop(self, "castle", "wall", Vector3(6, 0, -30), 0.0, 4.0)
	# Nature: trees and rocks as multimeshes, a few hero props.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var trees := []
	var trees2 := []
	var rocks := []
	var grass := []
	var flowers := []
	for i in 60:
		var a := rng.randf() * TAU
		var r := rng.randf_range(22, 55)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var s := rng.randf_range(2.6, 4.0)
		var xf := Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3.ONE * s), p)
		(trees if i % 2 == 0 else trees2).append(xf)
	for i in 40:
		var p := Vector3(rng.randf_range(-50, 50), 0, rng.randf_range(-50, 50))
		if p.length() < 12:
			continue
		rocks.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3.ONE * rng.randf_range(1.5, 3.0)), p))
	for i in 900:
		var p := Vector3(rng.randf_range(-55, 55), 0, rng.randf_range(-55, 55))
		if absf(p.x) < 3 and p.z > -20:
			continue
		var xf := Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3.ONE * rng.randf_range(1.8, 3.0)), p)
		(grass if i % 5 != 0 else flowers).append(xf)
	AssetLib.multi(self, "nature", "tree_oak", trees)
	AssetLib.multi(self, "nature", "tree_default", trees2)
	AssetLib.multi(self, "nature", "rock_largeA", rocks)
	AssetLib.multi(self, "nature", "grass_large", grass, true, false)
	AssetLib.multi(self, "nature", "flower_purpleA", flowers, true, false)
	AssetLib.prop(self, "nature", "tree_detailed", Vector3(-14, 0, 8), 0.0, 4.5, "trunk")
	AssetLib.prop(self, "nature", "log_stack", Vector3(-12, 0, 2), 0.3, 2.4)
	AssetLib.prop(self, "nature", "mushroom_redGroup", Vector3(-11, 0, 10), 0.0, 2.4, "none")
	AssetLib.prop(self, "survival", "campfire-pit", Vector3(10, 0, 12), 0.0, 2.4)
	AssetLib.prop(self, "survival", "tent", Vector3(14, 0, 14), -2.3, 2.4)
	AssetLib.prop(self, "graveyard", "lightpost-single", Vector3(-20, 0, -2), 0.0, 2.4)

	# A VRM body in front of the fountain (uses the project's VRMCharacter if present).
	var vrm_path := "res://assets/characters/extra/Seed-san.vrm"
	if ResourceLoader.exists(vrm_path):
		var ps: PackedScene = load(vrm_path)
		var body: Node3D = ps.instantiate()
		body.position = Vector3(1.2, 0, 6)
		body.rotation.y = PI
		add_child(body)

	# Camera.
	var cam := Camera3D.new()
	cam.position = Vector3(10, 7, 22)
	cam.fov = 60
	add_child(cam)
	cam.look_at(Vector3(0, 2.5, -2))
	cam.current = true
