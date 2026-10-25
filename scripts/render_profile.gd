class_name RenderProfile
extends RefCounted
## Scalable graphics presets. Ultra is tuned for an RTX 5070-class GPU
## (FSR2 anti-aliasing, 16k directional shadows, 6-cascade SDFGI, SSIL, SSR,
## volumetric fog); Low runs on integrated GPUs and the Compatibility renderer.
## Everything renderer-side lives here; the Settings autoload owns the UI and
## persistence and calls apply() on the active viewport + world Environment.
##
## Usage: RenderProfile.apply("High", get_viewport(), world_env.environment)

const PRESETS := ["Low", "Medium", "High", "Ultra"]

## Last preset applied in this process (so a world built later can match).
static var current: String = ""

## One row per preset. Keys that only matter under Forward+ are skipped on
## other renderers by apply().
##   foliage:   share of grass / flower / undergrowth instances drawn
##              (MultiMesh.visible_instance_count, no rebuild).
##   prop_cull: multiplier on the distance at which small props and foliage
##              chunks stop drawing (GeometryInstance3D.visibility_range_end);
##              0 = never cull (Ultra keeps every tuft to the horizon).
const TABLE := {
	"Low": {
		"scale_mode": Viewport.SCALING_3D_MODE_FSR, "scale": 0.67, "fsr_sharpness": 0.2,
		"msaa": Viewport.MSAA_DISABLED, "fxaa": true, "taa": false, "debanding": true,
		"dir_shadow": 2048, "pos_shadow": 2048, "soft_shadow": RenderingServer.SHADOW_QUALITY_HARD,
		"lod_threshold": 4.0, "foliage": 0.4, "prop_cull": 0.6,
		"sdfgi": false, "ssao": false, "ssil": false, "ssr": false, "vol_fog": false,
		"glow": true, "glow_bicubic": false, "sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_DISABLED,
	},
	"Medium": {
		"scale_mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 1.0, "fsr_sharpness": 0.2,
		"msaa": Viewport.MSAA_DISABLED, "fxaa": false, "taa": true, "debanding": true,
		"dir_shadow": 4096, "pos_shadow": 4096, "soft_shadow": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		"lod_threshold": 2.0, "foliage": 0.7, "prop_cull": 0.8,
		"sdfgi": false, "ssao": true, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_LOW,
		"ssil": false, "ssr": false, "vol_fog": false,
		"glow": true, "glow_bicubic": false, "sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_LOW,
	},
	"High": {
		# FSR2 at native scale: temporal AA with sharpening. MSAA is off on
		# purpose: with MSAA 2x the Forward+ post stack (DOF/SSR on resolved
		# depth) smeared the whole frame in testing, and TAA/FSR2 already
		# cover edges, including the shader-drawn outlines MSAA never touched.
		"scale_mode": Viewport.SCALING_3D_MODE_FSR2, "scale": 1.0, "fsr_sharpness": 0.25,
		"msaa": Viewport.MSAA_DISABLED, "fxaa": false, "taa": false, "debanding": true,
		"dir_shadow": 8192, "pos_shadow": 8192, "soft_shadow": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		"lod_threshold": 1.0, "foliage": 1.0, "prop_cull": 1.0,
		"sdfgi": true, "sdfgi_cascades": 4, "sdfgi_rays": RenderingServer.ENV_SDFGI_RAY_COUNT_16,
		"ssao": true, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_HIGH,
		"ssil": true, "ssil_quality": RenderingServer.ENV_SSIL_QUALITY_MEDIUM,
		"ssr": true, "ssr_steps": 64,
		"vol_fog": true, "vol_fog_size": 96, "vol_fog_depth": 96, "vol_fog_filter": true,
		"glow": true, "glow_bicubic": true, "sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_MEDIUM,
	},
	"Ultra": {
		# FSR2 at native scale = temporal super-sampled anti-aliasing (DLAA-like).
		"scale_mode": Viewport.SCALING_3D_MODE_FSR2, "scale": 1.0, "fsr_sharpness": 0.15,
		"msaa": Viewport.MSAA_DISABLED, "fxaa": false, "taa": false, "debanding": true,
		"dir_shadow": 16384, "pos_shadow": 8192, "soft_shadow": RenderingServer.SHADOW_QUALITY_SOFT_ULTRA,
		"lod_threshold": 0.5, "foliage": 1.0, "prop_cull": 0.0,
		"sdfgi": true, "sdfgi_cascades": 6, "sdfgi_rays": RenderingServer.ENV_SDFGI_RAY_COUNT_64,
		"ssao": true, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_ULTRA,
		"ssil": true, "ssil_quality": RenderingServer.ENV_SSIL_QUALITY_ULTRA,
		"ssr": true, "ssr_steps": 128,
		"vol_fog": true, "vol_fog_size": 128, "vol_fog_depth": 128, "vol_fog_filter": true,
		"glow": true, "glow_bicubic": true, "sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_HIGH,
	},
}


static func is_forward_plus() -> bool:
	if RenderingServer.get_rendering_device() == null:
		return false
	return str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")) == "forward_plus"


static func is_compatibility() -> bool:
	return str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")) == "gl_compatibility" \
		or RenderingServer.get_rendering_device() == null


## Applies a preset to a viewport and an Environment. Either may be null.
static func apply(preset: String, viewport: Viewport, env: Environment) -> void:
	if not TABLE.has(preset):
		push_warning("RenderProfile: unknown preset '%s', using High" % preset)
		preset = "High"
	var t: Dictionary = TABLE[preset]
	var fp := is_forward_plus()
	var compat := is_compatibility()
	current = preset

	if viewport:
		# Upscaling / temporal AA. FSR/FSR2 need the RenderingDevice renderers.
		var mode: int = t["scale_mode"]
		if not fp and mode == Viewport.SCALING_3D_MODE_FSR2:
			mode = Viewport.SCALING_3D_MODE_BILINEAR
		if compat and mode == Viewport.SCALING_3D_MODE_FSR:
			mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_mode = mode
		viewport.scaling_3d_scale = t["scale"]
		viewport.fsr_sharpness = t["fsr_sharpness"]
		viewport.msaa_3d = t["msaa"]
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if t["fxaa"] else Viewport.SCREEN_SPACE_AA_DISABLED
		viewport.use_taa = t["taa"] and not compat
		viewport.use_debanding = t["debanding"]
		viewport.positional_shadow_atlas_size = t["pos_shadow"]
		viewport.positional_shadow_atlas_16_bits = preset != "Ultra"
		viewport.mesh_lod_threshold = t["lod_threshold"]

	# Global renderer state.
	RenderingServer.directional_shadow_atlas_set_size(t["dir_shadow"], preset != "Ultra")
	RenderingServer.directional_soft_shadow_filter_set_quality(t["soft_shadow"])
	RenderingServer.positional_soft_shadow_filter_set_quality(t["soft_shadow"])
	if fp:
		RenderingServer.sub_surface_scattering_set_quality(t["sss"])
		if t.get("ssao", false):
			RenderingServer.environment_set_ssao_quality(t["ssao_quality"], preset == "Medium", 1.2, 2 if preset == "Ultra" else 3, 50.0, 300.0)
		if t.get("ssil", false):
			RenderingServer.environment_set_ssil_quality(t["ssil_quality"], false, 1.2, 4, 50.0, 300.0)
		if t.get("sdfgi", false):
			RenderingServer.environment_set_sdfgi_ray_count(t["sdfgi_rays"])
			RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES if preset == "Ultra" else RenderingServer.ENV_SDFGI_CONVERGE_IN_10_FRAMES)
			RenderingServer.environment_set_sdfgi_frames_to_update_light(RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_1_FRAME if preset == "Ultra" else RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_2_FRAMES)
		if t.get("vol_fog", false):
			RenderingServer.environment_set_volumetric_fog_volume_size(t["vol_fog_size"], t["vol_fog_depth"])
			RenderingServer.environment_set_volumetric_fog_filter_active(t["vol_fog_filter"])
		RenderingServer.environment_set_ssr_roughness_quality(RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_HIGH if preset == "Ultra" else RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_MEDIUM)
	RenderingServer.environment_glow_set_use_bicubic_upscale(t["glow_bicubic"])

	_apply_ground_detail(preset == "Low")
	apply_scene_detail(preset)

	if env:
		# Forward+-only effects stay off elsewhere; glow and fog work everywhere.
		env.sdfgi_enabled = fp and t.get("sdfgi", false)
		if env.sdfgi_enabled:
			env.sdfgi_cascades = t["sdfgi_cascades"]
			env.sdfgi_use_occlusion = true
		env.ssao_enabled = fp and t.get("ssao", false)
		env.ssil_enabled = fp and t.get("ssil", false)
		env.ssr_enabled = fp and t.get("ssr", false)
		if env.ssr_enabled:
			env.ssr_max_steps = t["ssr_steps"]
		env.volumetric_fog_enabled = fp and t.get("vol_fog", false)
		env.glow_enabled = t["glow"]


## Low turns off the ground shader's PBR detail layer (six texture fetches per
## fragment); the strength WorldArt bound is kept in meta so it can come back.
static func _apply_ground_detail(off: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var ground := tree.root.find_child("Ground", true, false) as MeshInstance3D
	if ground == null:
		return
	var gm := ground.get_active_material(0) as ShaderMaterial
	if gm == null or gm.shader == null or not gm.shader.resource_path.get_file() in ["ground.gdshader", "ground_mire.gdshader"]:
		return
	if not gm.has_meta("detail_full"):
		gm.set_meta("detail_full", float(gm.get_shader_parameter("detail_strength")))
	gm.set_shader_parameter("detail_strength", 0.0 if off else float(gm.get_meta("detail_full")))


## Foliage density of a preset ("" = the one in use now).
static func foliage_density(preset := "") -> float:
	return float(TABLE.get(_preset_or_current(preset), TABLE["High"]).get("foliage", 1.0))


## Small-prop cull distance multiplier of a preset (0 = off).
static func prop_cull(preset := "") -> float:
	return float(TABLE.get(_preset_or_current(preset), TABLE["High"]).get("prop_cull", 1.0))


static func _preset_or_current(preset: String) -> String:
	if preset != "":
		return preset
	if current != "":
		return current
	var tree := Engine.get_main_loop() as SceneTree
	var settings: Node = tree.root.get_node_or_null("Settings") if tree and tree.root else null
	if settings and settings.has_method("effective_preset"):
		return str(settings.effective_preset())
	return "High"


## Scene-side knobs that need no rebuild: every MultiMesh in the
## "foliage_density" group (meta "full_count") shows preset * full instances,
## and every GeometryInstance3D in "lod_range" (meta "lod_base", metres)
## culls at base * prop_cull, fading over the last 12 %.
static func apply_scene_detail(preset: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var density := foliage_density(preset)
	for n in tree.get_nodes_in_group("foliage_density"):
		set_density(n, density)
	var cull := prop_cull(preset)
	for n in tree.get_nodes_in_group("lod_range"):
		set_lod(n, cull)


static func set_density(mmi: MultiMeshInstance3D, density: float) -> void:
	if mmi == null or mmi.multimesh == null:
		return
	var full := int(mmi.get_meta("full_count", mmi.multimesh.instance_count))
	mmi.multimesh.visible_instance_count = -1 if density >= 0.999 else clampi(int(round(full * density)), 0, full)


static func set_lod(gi: GeometryInstance3D, cull: float) -> void:
	if gi == null:
		return
	var base := float(gi.get_meta("lod_base", 0.0))
	if cull <= 0.0 or base <= 0.0:
		gi.visibility_range_end = 0.0
		gi.visibility_range_end_margin = 0.0
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		return
	gi.visibility_range_end = base * cull
	gi.visibility_range_end_margin = base * cull * 0.12
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Registers a MultiMesh for the density slider and applies the current value.
static func register_foliage(mmi: MultiMeshInstance3D) -> void:
	if mmi == null or mmi.multimesh == null:
		return
	mmi.set_meta("full_count", mmi.multimesh.instance_count)
	mmi.add_to_group("foliage_density")
	set_density(mmi, foliage_density())


## Registers a mesh for distance culling (base range in metres) and applies it.
static func register_lod(gi: GeometryInstance3D, base_range: float) -> void:
	if gi == null:
		return
	gi.set_meta("lod_base", base_range)
	gi.add_to_group("lod_range")
	set_lod(gi, prop_cull())


## Picks a sensible default for this machine from the renderer and GPU name.
static func recommended_preset() -> String:
	if is_compatibility():
		return "Low"
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	var vendor := RenderingServer.get_video_adapter_vendor().to_lower()
	var kind := RenderingServer.get_video_adapter_type()
	if kind == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or kind == RenderingDevice.DEVICE_TYPE_CPU or kind == RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
		return "Medium"
	# Current high-end desktop parts.
	for tag in ["rtx 50", "rtx 40", "rtx 30", "rx 7", "rx 9", "arc b"]:
		if gpu.contains(tag):
			return "Ultra"
	for tag in ["rtx", "gtx 16", "rx 6", "rx 5", "arc a", "radeon pro", "quadro"]:
		if gpu.contains(tag):
			return "High"
	if vendor.contains("intel") or gpu.contains("uhd") or gpu.contains("iris") or gpu.contains("adreno") or gpu.contains("mali") or gpu.contains("apple"):
		return "Medium"
	if kind == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return "High"
	return "Medium"


## Short human description for the settings UI.
static func describe(preset: String) -> String:
	match preset:
		"Low": return "Upscaled (FSR 67%), hard shadows, no global illumination, 40% foliage, near prop culling. Integrated GPUs and laptops."
		"Medium": return "Native resolution, 2x MSAA + TAA, soft shadows, ambient occlusion, 70% foliage. GTX 1060 / RX 580 class."
		"High": return "Global illumination (SDFGI), SSIL, reflections, volumetric fog, 8k shadows, full foliage. RTX 3060 / RX 6700 class."
		"Ultra": return "FSR2 temporal AA, 16k shadows, 6-cascade SDFGI, ultra SSIL/SSAO, dense volumetric fog, no distance culling. RTX 4070 / 5070 class."
	return ""
