class_name DayNight
extends Node
## Day/night cycle: drives the sun, sky colours, fog, ambient and lantern
## lights. The server owns the clock online; clients get it on join and every
## SYNC_INTERVAL seconds, and run it locally in between.

const DAY_LENGTH_SEC := 20.0 * 60.0  # one full day
const SYNC_INTERVAL := 30.0
const START_HOUR := 9.5

var time_of_day := START_HOUR  # 0..24
var paused := false

var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _sky_sm: ShaderMaterial  # shaders/sky_spire.gdshader (WorldArt.build_environment)
var _sync_t := 0.0
var _last_night := -1.0

# Palette.
const DAY_TOP := Color("3d8be0")
const DAY_HORIZON := Color("ffd9b8")
const DUSK_TOP := Color("4a3a7a")
const DUSK_HORIZON := Color("ff9a5c")
const NIGHT_TOP := Color("0c1636")
const NIGHT_HORIZON := Color("2a3672")
const DAY_FOG := Color("d9e6ff")
const NIGHT_FOG := Color("1a2140")
const SUN_NOON := Color("fff1dc")
const SUN_LOW := Color("ffb070")

## Per-floor overrides of the palette above (Floor 1 keeps the constants).
## Floor 2 "Mirewood": paler misty sky, warm haze, a late-afternoon start.
const FLOOR_PALETTES := {
	2: {"start_hour": 15.5, "day_top": Color("6f9ac4"), "day_horizon": Color("e8d4b0"), "dusk_top": Color("4d3a66"),
		"dusk_horizon": Color("e07a4a"), "night_top": Color("0a1020"), "night_horizon": Color("1d2a40"),
		"day_fog": Color("cfc6b2"), "night_fog": Color("16202a"), "sun_noon": Color("ffe9c8"), "sun_low": Color("ffa060"),
		"ambient_day": 0.5, "ambient_night": 0.14},
}
var _day_top := DAY_TOP
var _day_horizon := DAY_HORIZON
var _dusk_top := DUSK_TOP
var _dusk_horizon := DUSK_HORIZON
var _night_top := NIGHT_TOP
var _night_horizon := NIGHT_HORIZON
var _day_fog := DAY_FOG
var _night_fog := NIGHT_FOG
var _sun_noon := SUN_NOON
var _sun_low := SUN_LOW
var _ambient_day := 0.45
var _ambient_night := 0.12


func setup(world: Node3D) -> void:
	var pal: Dictionary = FLOOR_PALETTES.get(GameState.floor, {})
	time_of_day = float(pal.get("start_hour", START_HOUR))
	_day_top = pal.get("day_top", DAY_TOP)
	_day_horizon = pal.get("day_horizon", DAY_HORIZON)
	_dusk_top = pal.get("dusk_top", DUSK_TOP)
	_dusk_horizon = pal.get("dusk_horizon", DUSK_HORIZON)
	_night_top = pal.get("night_top", NIGHT_TOP)
	_night_horizon = pal.get("night_horizon", NIGHT_HORIZON)
	_day_fog = pal.get("day_fog", DAY_FOG)
	_night_fog = pal.get("night_fog", NIGHT_FOG)
	_sun_noon = pal.get("sun_noon", SUN_NOON)
	_sun_low = pal.get("sun_low", SUN_LOW)
	_ambient_day = float(pal.get("ambient_day", 0.45))
	_ambient_night = float(pal.get("ambient_night", 0.12))
	_sun = world.get_node_or_null("Sun")
	_fill = world.get_node_or_null("SkyFill")
	var we: WorldEnvironment = world.get_node_or_null("WorldEnvironment")
	if we:
		_env = we.environment
		if _env.sky and _env.sky.sky_material is ProceduralSkyMaterial:
			_sky = _env.sky.sky_material
		elif _env.sky and _env.sky.sky_material is ShaderMaterial:
			_sky_sm = _env.sky.sky_material
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY  # the sky draws any directional light as a disc
	_moon.light_color = Color("9fb4ff")
	_moon.light_energy = 0.0
	_moon.shadow_enabled = true
	_moon.directional_shadow_max_distance = 120.0
	_moon.light_specular = 0.2
	world.add_child(_moon)
	_apply()


## Daylight 0..1 (0 at night, 1 at noon) and how far into night we are.
func daylight() -> float:
	var h := fmod(time_of_day, 24.0)
	return clampf(sin((h - 6.0) / 12.0 * PI), 0.0, 1.0) if h >= 6.0 and h <= 18.0 else 0.0


func night() -> float:
	return 1.0 - smoothstep(0.0, 0.25, daylight())


func is_night() -> bool:
	return night() > 0.5


func clock_text() -> String:
	var h := int(time_of_day) % 24
	var m := int((time_of_day - floor(time_of_day)) * 60.0)
	return "%02d:%02d" % [h, m]


func _process(delta: float) -> void:
	if not paused:
		time_of_day = fmod(time_of_day + delta * 24.0 / DAY_LENGTH_SEC, 24.0)
	_apply()
	if Net.online and multiplayer.is_server():
		_sync_t += delta
		if _sync_t >= SYNC_INTERVAL:
			_sync_t = 0.0
			sync_time.rpc(time_of_day)


@rpc("authority", "call_remote", "reliable")
func sync_time(t: float) -> void:
	time_of_day = t
	_apply()


func _apply() -> void:
	var h := fmod(time_of_day, 24.0)
	var d := daylight()
	var n := night()
	# Dusk/dawn weight: strongest when the sun sits on the horizon.
	# Strongest at sunrise/sunset (6:00 / 18:00), gone 1.5 h either side.
	var dusk := clampf(1.0 - minf(absf(h - 6.0), absf(h - 18.0)) / 1.5, 0.0, 1.0)
	if _sun:
		var elev := (h - 6.0) / 12.0 * PI  # 0 at 6:00, PI/2 at noon, PI at 18:00
		_sun.rotation = Vector3(-elev, deg_to_rad(38), 0)
		_sun.visible = d > 0.001
		_sun.light_energy = lerpf(0.0, 1.0, smoothstep(0.0, 0.35, d)) * (1.0 - 0.25 * dusk)
		_sun.light_color = _sun_noon.lerp(_sun_low, clampf(1.0 - d * 2.0, 0.0, 1.0))
	if _moon:
		var melev := (fmod(h + 12.0, 24.0) - 6.0) / 12.0 * PI
		_moon.rotation = Vector3(-melev, deg_to_rad(-120), 0)
		_moon.visible = n > 0.01
		_moon.light_energy = 0.22 * n
	if _fill:
		_fill.light_energy = 0.18 * (0.3 + 0.7 * d)
	if _sky:
		var top := _night_top.lerp(_day_top, smoothstep(0.0, 0.5, d)).lerp(_dusk_top, dusk * 0.6)
		var hor := _night_horizon.lerp(_day_horizon, smoothstep(0.0, 0.5, d)).lerp(_dusk_horizon, dusk)
		_sky.sky_top_color = top
		_sky.sky_horizon_color = hor
		_sky.ground_horizon_color = hor
		_sky.ground_bottom_color = Color("9fb4d8").lerp(Color("0a0e22"), n)
		_sky.sky_energy_multiplier = lerpf(0.35, 1.0, d)
	if _sky_sm:
		var top := _night_top.lerp(_day_top, smoothstep(0.0, 0.5, d)).lerp(_dusk_top, dusk * 0.6)
		var hor := _night_horizon.lerp(_day_horizon, smoothstep(0.0, 0.5, d)).lerp(_dusk_horizon, dusk)
		_sky_sm.set_shader_parameter("top_color", top)
		_sky_sm.set_shader_parameter("horizon_color", hor)
		_sky_sm.set_shader_parameter("ground_color", Color("9fb4d8").lerp(Color("0a0e22"), n))
		_sky_sm.set_shader_parameter("energy", lerpf(0.75, 1.0, d))
		_sky_sm.set_shader_parameter("night", n)
		if _moon:
			_sky_sm.set_shader_parameter("moon_dir", _moon.global_transform.basis.z)
	if _env:
		_env.ambient_light_energy = lerpf(_ambient_night, _ambient_day, d)
		_env.fog_light_color = _night_fog.lerp(_day_fog, d)
		_env.fog_light_energy = lerpf(0.5, 1.0, d)
	if absf(n - _last_night) > 0.01:
		_last_night = n
		WorldArt.set_lantern_glow(n)
		WorldArt.set_night_tint(n)
