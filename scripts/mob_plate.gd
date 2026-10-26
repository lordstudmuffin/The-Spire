class_name MobPlate
extends Node3D
## Floating mob plate in the floor-game style: a small crystal cursor whose
## colour warns how dangerous the mob is next to you, the name, and a slanted
## HP bar (green / yellow / red with a trailing white chip). No numbers on
## the bar, like the reference. Visual only; the owner feeds it set_hp().
## Headless processes get an empty node (nothing is built).

const BAR_W := 1.15
const BAR_H := 0.13
const CHIP_DELAY := 0.35
const CHIP_SPEED := 0.9   # bar fractions per second once the chip moves
## The bar and name draw over the world (no depth test), so beyond this the
## plate is hidden: far mobs would otherwise speckle walls and slabs.
const SHOW_RANGE := 34.0

var _name: Label3D
var _bar: MeshInstance3D
var _bar_mat: ShaderMaterial
var _cursor: MeshInstance3D
var _cursor_mat: StandardMaterial3D
var _hp := 1.0
var _chip := 1.0
var _chip_wait := 0.0
var _t := 0.0
var _built := false

static var _bar_shader: Shader
static var _pips_shader: Shader
var _pips: MeshInstance3D
var _pips_mat: ShaderMaterial
static var _cursor_mesh: ArrayMesh


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	if _bar_shader == null:
		_bar_shader = load("res://shaders/hp_bar.gdshader")
	_bar = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(BAR_W, BAR_H)
	_bar.mesh = q
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = _bar_shader
	_bar_mat.set_shader_parameter("aspect", BAR_W / BAR_H)
	_bar_mat.render_priority = 9
	_bar.material_override = _bar_mat
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bar)

	_name = Label3D.new()
	_name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name.font = UITheme.ui_bold()
	_name.font_size = 34
	_name.outline_size = 9
	_name.outline_modulate = Color(0.04, 0.05, 0.1, 0.9)
	_name.modulate = Color(0.97, 0.97, 1.0)
	_name.pixel_size = 0.0042
	_name.position = Vector3(0, BAR_H * 0.5 + 0.13, 0)
	_name.no_depth_test = true
	_name.render_priority = 9
	_name.fixed_size = false
	add_child(_name)

	_cursor = MeshInstance3D.new()
	_cursor.mesh = _cursor_shape()
	_cursor_mat = StandardMaterial3D.new()
	_cursor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cursor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cursor_mat.albedo_color = Color(1, 0.3, 0.3, 0.92)
	_cursor_mat.emission_enabled = true
	_cursor_mat.emission = Color(1, 0.3, 0.3)
	_cursor_mat.emission_energy_multiplier = 0.8
	_cursor.material_override = _cursor_mat
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cursor.position = Vector3(0, BAR_H * 0.5 + 0.48, 0)
	add_child(_cursor)
	for g in [_bar, _name, _cursor]:
		(g as GeometryInstance3D).visibility_range_end = SHOW_RANGE


## Inverted octahedral crystal (a long point down), ~0.22 m tall.
static func _cursor_shape() -> ArrayMesh:
	if _cursor_mesh:
		return _cursor_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, 0.07, 0)
	var bot := Vector3(0, -0.16, 0)
	var ring: Array[Vector3] = []
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		ring.append(Vector3(cos(a) * 0.075, 0, sin(a) * 0.075))
	for i in 4:
		var a := ring[i]
		var b := ring[(i + 1) % 4]
		for tri in [[top, a, b], [bot, b, a]]:
			var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			for v in tri:
				st.set_normal(n)
				st.add_vertex(v)
	_cursor_mesh = st.commit()
	return _cursor_mesh


## Threat colour by level gap (mob - player), pale pink for easy prey to
## deep crimson for something that outclasses you; bosses always crimson.
static func threat_color(gap: int, boss := false) -> Color:
	if boss:
		return Color(0.75, 0.05, 0.12)
	if gap <= -3:
		return Color(1.0, 0.72, 0.78)
	if gap <= 0:
		return Color(1.0, 0.45, 0.45)
	if gap <= 3:
		return Color(0.95, 0.18, 0.2)
	return Color(0.62, 0.04, 0.1)


func set_info(display_name: String, level: int, threat_gap := 0, boss := false) -> void:
	if not _built:
		return
	_name.text = "%s" % display_name if level <= 0 else "%s  Lv %d" % [display_name, level]
	var c := threat_color(threat_gap, boss)
	_cursor_mat.albedo_color = Color(c.r, c.g, c.b, 0.92)
	_cursor_mat.emission = c
	if boss:
		scale = Vector3.ONE * 1.6


## Boss HP bar stack: `count` pips under the bar, the `current` one (count
## down to 1) lit amber. The main bar then shows the current bar's fill.
func set_bars(count: int, current: int) -> void:
	if not _built or count <= 1:
		return
	if _pips == null:
		if _pips_shader == null:
			_pips_shader = load("res://shaders/bar_pips.gdshader")
		_pips = MeshInstance3D.new()
		var q := QuadMesh.new()
		var w := BAR_W * 0.55
		var h := 0.05
		q.size = Vector2(w, h)
		_pips.mesh = q
		_pips_mat = ShaderMaterial.new()
		_pips_mat.shader = _pips_shader
		_pips_mat.set_shader_parameter("aspect", w / h)
		_pips_mat.render_priority = 9
		_pips.material_override = _pips_mat
		_pips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pips.position = Vector3(0, -BAR_H * 0.5 - 0.06, 0)
		add_child(_pips)
	_pips_mat.set_shader_parameter("bars", count)
	_pips_mat.set_shader_parameter("current", current)


## HP as a fraction 0..1. A drop leaves the white chip behind for a moment.
func set_hp(frac: float) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if frac < _hp:
		_chip = maxf(_chip, _hp)
		_chip_wait = CHIP_DELAY
	else:
		_chip = maxf(_chip, frac)
	_hp = frac
	if _built:
		_bar_mat.set_shader_parameter("hp", _hp)
		_bar_mat.set_shader_parameter("chip", _chip)


func _process(dt: float) -> void:
	if not _built:
		return
	_t += dt
	_cursor.position.y = BAR_H * 0.5 + 0.48 + sin(_t * 2.4) * 0.03
	_cursor.rotation.y += dt * 1.6
	if _chip > _hp:
		if _chip_wait > 0.0:
			_chip_wait -= dt
		else:
			_chip = maxf(_hp, _chip - CHIP_SPEED * dt)
			_bar_mat.set_shader_parameter("chip", _chip)
