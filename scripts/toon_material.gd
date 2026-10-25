class_name ToonMaterial
extends RefCounted
## Factory for the anime cel-shaded materials in res://shaders/.
## Shader resources are loaded once and shared; every call returns a fresh
## ShaderMaterial so per-part colours can differ. Outline materials of the
## same width are shared, since they carry no per-part state.

const TOON_SHADER_PATH := "res://shaders/toon.gdshader"
const OUTLINE_SHADER_PATH := "res://shaders/outline.gdshader"

static var _toon_shader: Shader
static var _outline_shader: Shader
static var _outline_cache := {}


static func _toon() -> Shader:
	if _toon_shader == null:
		_toon_shader = load(TOON_SHADER_PATH)
	return _toon_shader


static func _outline() -> Shader:
	if _outline_shader == null:
		_outline_shader = load(OUTLINE_SHADER_PATH)
	return _outline_shader


## Cel-shaded surface material with a flat albedo and optional glow.
static func make(color: Color, emission := Color.BLACK, emission_strength := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _toon()
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("emission_color", emission)
	m.set_shader_parameter("emission_strength", emission_strength)
	return m


## Cel material that already carries the ink outline as its next_pass.
## `width` is in model units; 0 disables the outline (eyes, highlights).
static func part(color: Color, width := 0.02, emission := Color.BLACK, emission_strength := 0.0) -> ShaderMaterial:
	var m := make(color, emission, emission_strength)
	if width > 0.0:
		m.next_pass = outline(width)
	return m


## Inverted-hull outline material; assign as next_pass or to a second mesh.
static func outline(width := 0.02, color := Color(0.07, 0.05, 0.1)) -> ShaderMaterial:
	var key := "%0.4f:%s" % [width, color.to_html(false)]
	if _outline_cache.has(key):
		return _outline_cache[key]
	var m := ShaderMaterial.new()
	m.shader = _outline()
	m.set_shader_parameter("outline_width", width)
	m.set_shader_parameter("outline_color", color)
	_outline_cache[key] = m
	return m


## Re-tints an existing toon material in place (cheap; keeps the outline).
static func tint(m: ShaderMaterial, color: Color, emission := Color.BLACK, emission_strength := 0.0) -> void:
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("emission_color", emission)
	m.set_shader_parameter("emission_strength", emission_strength)
