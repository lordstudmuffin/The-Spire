extends Node
## Player settings: graphics preset, window, input (sensitivity, remaps) and audio (Music/SFX bus
## levels are applied by the Audio autoload, which listens to `changed`). Persisted to
## user://settings.json. Graphics presets are applied through RenderProfile
## (scripts/render_profile.gd) when it exists, else a built-in fallback.

signal changed

const PATH := "user://settings.json"
const PRESETS := ["Auto", "Low", "Medium", "High", "Ultra"]
const WINDOW_MODES := ["Windowed", "Fullscreen", "Borderless"]

var data := {
	"preset": "Auto",
	"window_mode": "Windowed",
	"vsync": true,
	"fov": 75.0,
	"mouse_sens": 1.0,
	"stick_sens": 1.0,
	"stick_deadzone": 0.2,
	"invert_y": false,
	"vibration": true,
	"bindings": {},  # action -> {"kb": [...], "pad": [...]} remaps, see autoload/input_setup.gd
	"master_volume": 1.0,
	"music_volume": 0.8,
	"sfx_volume": 1.0,
	"show_fps": false,
	"ignored": [],  # chat ignore list (lower-case names), see scripts/ui/social.gd
}
var _fps_label: Label


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	var v = JSON.parse_string(f.get_as_text())
	if v is Dictionary:
		for k in data:
			if v.has(k) and typeof(v[k]) == typeof(data[k]):
				data[k] = v[k]
	data["preset"] = data["preset"] if data["preset"] in PRESETS else "Auto"
	data["window_mode"] = data["window_mode"] if data["window_mode"] in WINDOW_MODES else "Windowed"
	data["fov"] = clampf(float(data["fov"]), 60.0, 110.0)
	data["mouse_sens"] = clampf(float(data["mouse_sens"]), 0.2, 3.0)
	data["stick_sens"] = clampf(float(data["stick_sens"]), 0.2, 3.0)
	data["stick_deadzone"] = clampf(float(data["stick_deadzone"]), 0.05, 0.6)
	data["master_volume"] = clampf(float(data["master_volume"]), 0.0, 1.0)
	data["music_volume"] = clampf(float(data["music_volume"]), 0.0, 1.0)
	data["sfx_volume"] = clampf(float(data["sfx_volume"]), 0.0, 1.0)


func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


func set_value(key: String, value) -> void:
	if not data.has(key) or data[key] == value:
		return
	data[key] = value
	_queue_save()
	match key:
		"preset":
			apply_graphics()
		"window_mode", "vsync":
			apply_window()
		"master_volume", "music_volume", "sfx_volume":
			apply_audio()
		"show_fps":
			_update_fps_label()
		"bindings", "stick_deadzone":
			apply_input()
	changed.emit()


func apply_all() -> void:
	apply_window()
	apply_audio()
	apply_graphics()
	apply_input()
	_update_fps_label()


## Saved remaps and the stick deadzone onto the InputMap (InputSetup autoload).
func apply_input() -> void:
	var im := get_node_or_null("/root/InputSetup")
	if im == null or not im.has_method("apply_bindings"):
		return
	im.deadzone = float(data["stick_deadzone"])
	im.apply_bindings(data["bindings"])


# --- Graphics ------------------------------------------------------------

## The preset actually in use ("Auto" resolved to a concrete one).
func effective_preset() -> String:
	if data["preset"] != "Auto":
		return data["preset"]
	var rp := _render_profile()
	if rp and rp.has_method("recommended_preset"):
		return rp.recommended_preset()
	return _fallback_recommended()


func _render_profile() -> Script:
	if FileAccess.file_exists("res://scripts/render_profile.gd"):
		var s = load("res://scripts/render_profile.gd")
		if s is Script:
			return s
	return null


## Name of the renderer in use, safe on Godot 4.3 (no get_current_rendering_method there).
static func rendering_method() -> String:
	var m := str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"))
	if RenderingServer.get_rendering_device() == null:
		return "gl_compatibility"
	return m if m != "" else "forward_plus"


static func is_forward_plus() -> bool:
	return rendering_method() == "forward_plus"


func _fallback_recommended() -> String:
	if not is_forward_plus():
		return "Low"
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	if gpu.contains("rtx 50") or gpu.contains("rtx 40") or gpu.contains("rx 7") or gpu.contains("rx 9"):
		return "Ultra"
	if gpu.contains("intel") or gpu.contains("iris") or gpu.contains("uhd") or gpu.contains("llvmpipe"):
		return "Medium"
	return "High"


## Applies the preset to the main viewport and the live world Environment.
func apply_graphics() -> void:
	var preset := effective_preset()
	var vp := get_viewport()
	var env := current_environment()
	var rp := _render_profile()
	if rp and rp.has_method("apply"):
		rp.apply(preset, vp, env)
		return
	_fallback_apply(preset, vp, env)


## The Environment of the active scene's WorldEnvironment, if any.
func current_environment() -> Environment:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var we := _find_world_env(scene)
	return we.environment if we else null


func _find_world_env(n: Node) -> WorldEnvironment:
	if n is WorldEnvironment:
		return n
	for c in n.get_children():
		var r := _find_world_env(c)
		if r:
			return r
	return null


func _fallback_apply(preset: String, vp: Viewport, env: Environment) -> void:
	var fp := is_forward_plus()
	var level := PRESETS.find(preset) - 1  # Low 0 .. Ultra 3
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][clampi(level, 0, 3)]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if level <= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_debanding = level >= 1
	if fp:
		vp.use_taa = level >= 2
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if level >= 2 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = [0.67, 0.85, 1.0, 1.0][clampi(level, 0, 3)]
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096, 8192][clampi(level, 0, 3)], true)
	vp.positional_shadow_atlas_size = [1024, 2048, 4096, 8192][clampi(level, 0, 3)]
	if env and fp:
		env.ssao_enabled = level >= 1
		env.ssil_enabled = level >= 3
		env.ssr_enabled = level >= 2
		env.sdfgi_enabled = level >= 2
		env.volumetric_fog_enabled = level >= 2
		env.glow_enabled = level >= 1


# --- Window / audio ------------------------------------------------------

func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	match data["window_mode"]:
		"Fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"Borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if data["vsync"] else DisplayServer.VSYNC_DISABLED)


func apply_audio() -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(float(data["master_volume"]), 0.0001)))


func _update_fps_label() -> void:
	if data["show_fps"] and _fps_label == null:
		var layer := CanvasLayer.new()
		layer.layer = 100
		_fps_label = Label.new()
		_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_fps_label.offset_left = -120
		_fps_label.offset_top = 8
		_fps_label.offset_right = -12
		_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_fps_label.add_theme_font_size_override("font_size", 14)
		layer.add_child(_fps_label)
		add_child(layer)
	elif not data["show_fps"] and _fps_label:
		_fps_label.get_parent().queue_free()
		_fps_label = null


func _process(_delta: float) -> void:
	if _fps_label:
		_fps_label.text = "%d FPS  ·  %s" % [Engine.get_frames_per_second(), effective_preset()]


var _save_pending := false


## Sliders call set_value on every tick; coalesce writes into one per frame.
func _queue_save() -> void:
	if _save_pending:
		return
	_save_pending = true
	(func():
		_save_pending = false
		save_settings()).call_deferred()
