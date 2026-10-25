extends Node3D
## Showcase for VRMCharacter: both placeholder bodies side by side, one idle and
## one running in place, with different tints. Used by the screenshot harness
## (`--scene vrm`) and handy for eyeballing retargeted clips.

var _chars: Array[VRMCharacter] = []
var _t := 0.0
var _frame := 0
var _extra_shot := ""


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.53, 0.75, 0.96)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.9)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 3.0
	disc.bottom_radius = 3.0
	disc.height = 0.08
	disc.radial_segments = 48
	ground.mesh = disc
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.7, 0.4)
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position.y = -0.04
	add_child(ground)

	var a := VRMCharacter.new()
	a.name = "Alicia"
	a.position = Vector3(-0.7, 0, 0)
	add_child(a)
	a.apply({"body": "alicia", "hair_color": "7fd1ff", "eye_color": "ff7ab6", "outfit_color": "ffd166", "height": 1.0})
	_chars.append(a)

	var g := VRMCharacter.new()
	g.name = "Godette"
	g.position = Vector3(0.7, 0, 0)
	add_child(g)
	g.apply({"body": "godette", "hair_color": "ff8c42", "eye_color": "4cc9f0", "outfit_color": "e63946", "height": 1.05})
	_chars.append(g)

	for ch in _chars:
		print(ch.describe())
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot" and i + 1 < args.size():
			_extra_shot = args[i + 1].get_basename() + "_b.png"

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.25, -3.6)
	cam.fov = 45
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.95, 0.0))
	cam.current = true


func _process(delta: float) -> void:
	_t += delta
	_frame += 1
	if _chars.size() < 2:
		return
	_chars[0].animate(delta, 0.0, true)
	_chars[1].animate(delta, 6.0, true)
	if _frame % 20 == 0:
		# Proof of motion for headless runs: hand height changes as the clips play.
		for ch in _chars:
			print("frame ", _frame, " ", ch.name, " LeftHand=", ch.skeleton.get_bone_global_pose(ch.bones["LeftHand"]).origin)
	# Fire a swing on the idle character late enough that the harness shot (frame ~45
	# after load) catches it mid-swing; the extra shot at frame 30 shows pure idle.
	if _frame == 38:
		_chars[0].play_attack(0)
	if _frame == 30 and _extra_shot != "":
		var img := get_viewport().get_texture().get_image()
		img.save_png(_extra_shot)
		print("Saved extra ", _extra_shot)
