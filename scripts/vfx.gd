class_name VFX
extends Node3D
## Client-side combat juice: pooled slash arcs, hit flashes, sparks, dust
## puffs, ground rings, one short-lived hit light, and the mob death dissolve.
## Purely cosmetic: nothing here touches damage, hit detection, replication or
## rpc payloads, and every entry point is a no-op on a headless / dedicated
## process (same rule as Audio). One instance hangs under the scene root and
## owns all pools, so nothing is allocated per hit beyond a Tween.

const MAX_PARTICLES := 16   # live GPUParticles3D emitters, shared by every effect
const MAX_SLASHES := 8      # slash arc quads
const MAX_FLASHES := 6      # billboard impact flashes
const MAX_RINGS := 6        # flat ground rings
const BASIC_COLOR := Color(0.55, 0.9, 1.0)
## Sword Art colours, by skill index (Horizontal, Vertical Arc, Rage Spike).
const KIND_COLORS := [Color(1.0, 0.58, 0.12), Color(0.4, 0.55, 1.0), Color(1.0, 0.2, 0.28)]
## Slash arc mesh: an arc of `SLASH_SWEEP` radians, thick in the middle and
## pointed at both ends, vertex alpha fading toward the tips (the Kenney slash
## PNGs are too faint to read over bright ground, so the arc is geometry).
const SLASH_SWEEP := 2.3
const SLASH_SEGMENTS := 28
const PARTICLE_AABB := AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
## Polygon-shatter death: pale crystal cyan by default (players, most mobs).
const SHATTER_COLOR := Color(0.62, 0.9, 1.0)
const PARRY_COLOR := Color(1.0, 0.86, 0.45)
const STAGGER_COLOR := Color(1.0, 0.86, 0.3)
const WINDUP_COLOR := Color(0.95, 0.1, 0.08)
const MAX_SHATTERS := 6     # concurrent shard bursts (MultiMesh pool)
## Shards per burst by preset; `big` (bosses) doubles it.
const SHARDS := {"Low": 36, "Medium": 60, "High": 90, "Ultra": 140}
const SHATTER_GLOW := 0.16  # seconds the body glows glass-white before it breaks

static var _inst: VFX
static var _checked := false
static var _ok := false

var _particles: Array[GPUParticles3D] = []
var _slashes: Array[MeshInstance3D] = []
var _flashes: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _light_tw: Tween
var _color_ramp: GradientTexture1D
var _scale_curve: CurveTexture
var _dissolve_shader: Shader
var _high_preset := false
var _slash_mesh: ArrayMesh
var _shard_mesh: ArrayMesh
var _shard_shader: Shader
var _glow_shader: Shader
var _bursts: Array[MultiMeshInstance3D] = []
## Live bursts: [MultiMeshInstance3D, shard states Array, age, life].
var _live: Array = []
var _shard_count := 40


## False on a dedicated / headless process: no renderer, nothing to draw.
static func enabled() -> bool:
	if not _checked:
		_checked = true
		_ok = not (DisplayServer.get_name() == "headless" or Net.dedicated or "--server" in OS.get_cmdline_user_args())
	return _ok


## The shared instance, created on first use under the scene root. Null when
## effects are disabled or `from` is not in a tree yet.
static func get_for(from: Node) -> VFX:
	if not enabled() or from == null or not from.is_inside_tree():
		return null
	if _inst == null or not is_instance_valid(_inst) or not _inst.is_inside_tree():
		_inst = VFX.new()
		_inst.name = "VFX"
		from.get_tree().root.add_child(_inst)
	return _inst


static func kind_color(kind: int) -> Color:
	if kind >= 0 and kind < KIND_COLORS.size():
		return KIND_COLORS[kind]
	return BASIC_COLOR


func _ready() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.55, Color(1, 1, 1, 0.9))
	_color_ramp = GradientTexture1D.new()
	_color_ramp.gradient = g
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.6))
	c.add_point(Vector2(0.25, 1.0))
	c.add_point(Vector2(1.0, 0.25))
	_scale_curve = CurveTexture.new()
	_scale_curve.curve = c
	_dissolve_shader = load("res://shaders/dissolve.gdshader")
	_refresh_preset()
	if Settings.has_signal("changed"):
		Settings.changed.connect(_refresh_preset)


func _refresh_preset() -> void:
	var preset: String = Settings.effective_preset()
	_high_preset = preset in ["High", "Ultra"]
	_shard_count = int(SHARDS.get(preset, 40))


# ---------------------------------------------------------------- pools ----

## Oldest-first reuse: a free entry if any, else the one that ends soonest.
func _take(pool: Array, maker: Callable, cap: int) -> Node3D:
	var now := Time.get_ticks_msec()
	var best: Node3D = null
	var best_end := INF
	for n in pool:
		var e: int = n.get_meta("end_ms", 0)
		if e <= now:
			return n
		if e < best_end:
			best_end = e
			best = n
	if pool.size() < cap:
		var n: Node3D = maker.call()
		pool.append(n)
		add_child(n)
		return n
	return best


func _restart_tween(n: Node3D, seconds: float) -> Tween:
	if n.has_meta("tw"):
		var old: Tween = n.get_meta("tw")
		if old and old.is_valid():
			old.kill()
	n.set_meta("end_ms", Time.get_ticks_msec() + int(seconds * 1000.0))
	var tw := n.create_tween()
	n.set_meta("tw", tw)
	return tw


func _quad_mat(billboard: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.no_depth_test = false
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return m


## Crescent in the XY plane, bulging toward +Y, radius 1, centred on origin.
func _slash_arc() -> ArrayMesh:
	if _slash_mesh:
		return _slash_mesh
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var a0 := PI / 2.0 - SLASH_SWEEP / 2.0
	for i in SLASH_SEGMENTS + 1:
		var t := float(i) / SLASH_SEGMENTS
		var ang := a0 + SLASH_SWEEP * t
		var bulge := sin(PI * t)
		var r_out := 1.0
		var r_mid := 1.0 - 0.12 * pow(bulge, 0.8)
		var r_in := 1.0 - 0.45 * pow(bulge, 0.8)
		var alpha := pow(bulge, 0.5)
		verts.append(Vector3(cos(ang) * r_in, sin(ang) * r_in, 0))
		verts.append(Vector3(cos(ang) * r_mid, sin(ang) * r_mid, 0))
		verts.append(Vector3(cos(ang) * r_out, sin(ang) * r_out, 0))
		# Inner: white-hot core. Middle: the tint. Outer: dark ink rim so the
		# arc reads over bright ground (vertex colour multiplies albedo_color).
		cols.append(Color(1.6, 1.6, 1.6, alpha))
		cols.append(Color(1, 1, 1, alpha))
		cols.append(Color(0.12, 0.1, 0.2, alpha * 0.95))
		if i < SLASH_SEGMENTS:
			var b := i * 3
			idx.append_array([b, b + 1, b + 3, b + 1, b + 4, b + 3, b + 1, b + 2, b + 4, b + 2, b + 5, b + 4])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	_slash_mesh = ArrayMesh.new()
	_slash_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _slash_mesh


func _make_slash() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _slash_arc()
	var m := _quad_mat(false)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


func _make_quad(billboard: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	mi.material_override = _quad_mat(billboard)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


func _make_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.amount = 24
	p.lifetime = 0.5
	p.visibility_aabb = PARTICLE_AABB
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.color_ramp = _color_ramp
	pm.scale_curve = _scale_curve
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := _quad_mat(false)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.draw_pass_1 = q
	return p


## Generic one-shot emitter configuration; every effect below is a preset.
func _fire(pos: Vector3, tex: String, additive: bool, color: Color, ratio: float, life: float,
		vmin: float, vmax: float, dir: Vector3, spread: float, grav: float,
		smin: float, smax: float, ring_r: float, streak: bool) -> void:
	var p := _take(_particles, _make_particles, MAX_PARTICLES) as GPUParticles3D
	if p == null:
		return
	var pm := p.process_material as ParticleProcessMaterial
	var mat := (p.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	p.set_meta("end_ms", Time.get_ticks_msec() + int(life * 1000.0))
	p.global_position = pos
	mat.albedo_texture = AssetLib.vfx_texture(tex)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED if streak else BaseMaterial3D.BILLBOARD_PARTICLES
	pm.particle_flag_align_y = streak
	pm.color = color
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.direction = dir
	pm.spread = spread
	pm.gravity = Vector3(0, grav, 0)
	pm.scale_min = smin
	pm.scale_max = smax
	if ring_r > 0.0:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = ring_r
		pm.emission_ring_inner_radius = ring_r * 0.75
		pm.emission_ring_height = 0.1
	else:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	p.lifetime = life
	p.amount_ratio = clampf(ratio, 0.05, 1.0)
	p.restart()


# -------------------------------------------------------------- effects ----

## Slash arc for a swing. `kind` -1 = basic, 0.. = Sword Art. `flip` mirrors
## the crescent so alternating basic swings read as a combo.
func slash(origin: Vector3, forward: Vector3, kind: int, flip := false) -> void:
	var mi := _take(_slashes, _make_slash, MAX_SLASHES) as MeshInstance3D
	if mi == null:
		return
	var col := kind_color(kind)
	var mat := mi.material_override as StandardMaterial3D
	mat.albedo_color = Color(col.r, col.g, col.b, 1.0)
	var f := forward
	f.y = 0.0
	f = f.normalized() if f.length_squared() > 0.001 else Vector3.FORWARD
	var size := 1.0                        # arc radius in metres at full size
	var roll := PI if flip else 0.0        # ∩ vs ∪: alternate basic swings
	var pitch := 0.6                       # lean the arc over like a horizontal cut
	var height := 1.1
	var twist := 0.5 if flip else -0.5     # sweep direction
	match kind:
		0:
			size = 1.5
			pitch = 0.75
		1:
			size = 1.15
			roll = PI / 2.0 if not flip else -PI / 2.0
			pitch = 0.0
			height = 1.2
		2:
			size = 1.2
			roll = 0.8 if not flip else -0.8
			pitch = 0.35
	mi.visible = true
	mi.global_position = origin + f * 0.9 + Vector3(0, height, 0)
	mi.look_at(mi.global_position - f, Vector3.UP)
	mi.rotate_object_local(Vector3.RIGHT, -pitch)
	mi.rotate_object_local(Vector3.FORWARD, roll)
	mi.scale = Vector3.ONE * size * 0.6
	var dur := 0.26 if kind < 0 else 0.34
	var tw := _restart_tween(mi, dur)
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 1.25, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float): mi.rotate_object_local(Vector3.FORWARD, a), 0.0, twist * 0.1, dur)
	tw.tween_property(mi, "global_position", mi.global_position + f * 0.5, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur * 0.7).set_delay(dur * 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func(): mi.visible = false)


## Billboard impact flash: a soft disc that pops and fades in ~0.15 s.
func flash(pos: Vector3, color: Color, size := 1.0) -> void:
	var mi := _take(_flashes, _make_quad.bind(true), MAX_FLASHES) as MeshInstance3D
	if mi == null:
		return
	var mat := mi.material_override as StandardMaterial3D
	mat.albedo_texture = AssetLib.vfx_texture("circle_05")
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	mi.visible = true
	mi.global_position = pos
	mi.scale = Vector3.ONE * size * 0.3
	var tw := _restart_tween(mi, 0.18)
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 1.3, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.14).set_delay(0.04)
	tw.chain().tween_callback(func(): mi.visible = false)


## Flat ring on the ground that expands and fades (skill activation, landing).
func ring(pos: Vector3, color: Color, size := 2.4, dur := 0.35, tex := "circle_02") -> void:
	var mi := _take(_rings, _make_quad.bind(false), MAX_RINGS) as MeshInstance3D
	if mi == null:
		return
	var mat := mi.material_override as StandardMaterial3D
	mat.albedo_texture = AssetLib.vfx_texture(tex)
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	mi.visible = true
	mi.global_position = pos + Vector3(0, 0.06, 0)
	mi.rotation = Vector3(-PI / 2.0, randf() * TAU, 0)
	mi.scale = Vector3.ONE * size * 0.25
	var tw := _restart_tween(mi, dur)
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur * 0.75).set_delay(dur * 0.25)
	tw.chain().tween_callback(func(): mi.visible = false)


## Hit sparks flying away from `dir` plus a flash and (High/Ultra) a light.
func hit(pos: Vector3, dir: Vector3, color: Color, crit := false) -> void:
	var d := dir
	d.y = 0.0
	d = d.normalized() if d.length_squared() > 0.001 else Vector3.FORWARD
	var up := (d + Vector3.UP * 0.9).normalized()
	var k := 1.5 if crit else 1.0
	_fire(pos, "star_05", true, color, 0.75 * k, 0.32, 5.0 * k, 9.0 * k, up, 55.0, -12.0, 0.12, 0.26 * k, 0.0, false)
	if crit:
		_fire(pos, "spark_04", true, Color(1, 1, 1, 1), 0.3, 0.2, 0.5, 1.5, up, 90.0, 0.0, 0.8, 1.4, 0.0, false)
	flash(pos, color.lightened(0.4), 1.6 * k)
	flash_light(pos, color, 4.0 * k)


## One pooled short-lived point light; High/Ultra only, never stacked.
func flash_light(pos: Vector3, color: Color, energy := 4.0) -> void:
	if not _high_preset:
		return
	if _light == null:
		_light = OmniLight3D.new()
		_light.omni_range = 4.5
		_light.omni_attenuation = 1.4
		_light.shadow_enabled = false
		_light.visible = false
		add_child(_light)
	if _light_tw and _light_tw.is_valid():
		_light_tw.kill()
	_light.global_position = pos + Vector3(0, 0.3, 0)
	_light.light_color = color
	_light.light_energy = energy
	_light.visible = true
	_light_tw = _light.create_tween()
	_light_tw.tween_property(_light, "light_energy", 0.0, 0.14)
	_light_tw.tween_callback(func(): _light.visible = false)


## Soft dust puff at the feet (steps, jump, landing).
func puff(pos: Vector3, size := 1.0, color := Color(0.86, 0.8, 0.68, 0.55)) -> void:
	_fire(pos + Vector3(0, 0.05, 0), "smoke_03", false, color, 0.3 * size, 0.45 + 0.2 * size,
		0.6 * size, 1.6 * size, Vector3.UP, 70.0, 0.4, 0.35 * size, 0.7 * size, 0.0, false)


## Expanding dust ring on the ground (boss slam, heavy landing).
func dust_ring(pos: Vector3, radius := 4.0) -> void:
	_fire(pos + Vector3(0, 0.1, 0), "smoke_05", false, Color(0.8, 0.72, 0.6, 0.7), 1.0, 0.9,
		radius * 1.6, radius * 2.4, Vector3.UP, 85.0, -1.5, 1.2, 2.2, radius * 0.25, false)
	_fire(pos + Vector3(0, 0.2, 0), "dirt_02", false, Color(0.55, 0.42, 0.3, 0.9), 0.7, 0.7,
		4.0, 9.0, Vector3.UP, 40.0, -16.0, 0.25, 0.5, 0.0, false)
	ring(pos, Color(1.0, 0.8, 0.5), radius * 1.8, 0.5, "circle_02")


## Loot / reward sparkle burst: gold stars rising and twinkling.
func sparkle(pos: Vector3, color := Color(1.0, 0.85, 0.35)) -> void:
	_fire(pos, "star_05", true, color, 0.8, 0.9, 1.2, 3.2, Vector3.UP, 60.0, -2.5, 0.12, 0.3, 0.0, false)
	_fire(pos, "circle_05", true, color.lightened(0.5), 0.4, 0.6, 0.3, 1.0, Vector3.UP, 90.0, 0.0, 0.3, 0.6, 0.0, false)


## Dash streaks: speed lines trailing behind the dasher.
func dash(pos: Vector3, dir: Vector3, color := Color(0.75, 0.9, 1.0, 0.9)) -> void:
	var back := -dir
	back.y = 0.0
	back = back.normalized() if back.length_squared() > 0.001 else Vector3.BACK
	_fire(pos + Vector3(0, 0.9, 0), "trace_01", true, color, 0.7, 0.28, 6.0, 11.0, back, 18.0, 0.0, 0.5, 1.1, 0.0, true)
	puff(pos, 1.2)


## Parry: the two blades meet. A hard white-gold flare with a cross glint,
## a fan of sparks thrown both ways and a quick shock ring. `broke` is the
## other case (the defender's guard was broken): the flare goes red-orange
## and a few glass chips fly, as if the guard itself cracked.
func parry_flash(pos: Vector3, broke := false) -> void:
	var col := Color(1.0, 0.42, 0.22) if broke else PARRY_COLOR
	var cam := get_viewport().get_camera_3d()
	var side := cam.global_transform.basis.x if cam else Vector3.RIGHT
	for s in [-1.0, 1.0]:
		var d: Vector3 = (side * s + Vector3.UP * 0.35).normalized()
		_fire(pos, "spark_04", true, col.lightened(0.3), 0.9, 0.3, 6.0, 12.0, d, 28.0, -14.0, 0.08, 0.2, 0.0, true)
	flash(pos, col, 0.9)
	# The cross glint is alpha-blended (not added) so it keeps its shape and
	# colour against bright daylight ground, where additive light washes out.
	_glint(pos, col.darkened(0.15), 2.6, 0.3, true)
	_glint(pos, Color(1, 1, 1), 0.8, 0.18)
	_shock_ring(pos, col, 1.9 if not broke else 2.4, 0.24)
	flash_light(pos, col, 6.0)
	if broke:
		burst_at(AABB(pos - Vector3(0.25, 0.25, 0.25), Vector3(0.5, 0.5, 0.5)), Color(1.0, 0.55, 0.35), false)


## Stagger: the mob reels. A burst at the head, then a halo of small gold
## stars circling above it for `seconds` (follows the mob; freed after).
func stagger(enemy: Node3D, seconds: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var box := _body_bounds(enemy)
	var h := box.size.y if box.size.y > 0.1 else 1.6
	var r := clampf(maxf(box.size.x, box.size.z) * 0.35, 0.35, 1.6)
	var top := Vector3(0, h + 0.15, 0)
	if box.size.y > 0.1:
		top = enemy.to_local(box.position + Vector3(box.size.x * 0.5, box.size.y + 0.15, box.size.z * 0.5))
	var pivot := Node3D.new()
	pivot.name = "StaggerHalo"
	enemy.add_child(pivot)
	pivot.position = top
	var n := 5
	for i in n:
		var q := _make_quad(true)
		var m := q.material_override as StandardMaterial3D
		m.albedo_texture = AssetLib.vfx_texture("star_06")
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		m.albedo_color = STAGGER_COLOR.darkened(0.12)
		q.visible = true
		var heart := _make_quad(true)
		(heart.material_override as StandardMaterial3D).albedo_texture = AssetLib.vfx_texture("star_06")
		heart.visible = true
		heart.scale = Vector3.ONE * 0.5
		q.add_child(heart)
		q.scale = Vector3.ONE * clampf(r * 0.55, 0.25, 0.7)
		var a := TAU * i / n
		q.position = Vector3(cos(a), 0.0, sin(a)) * r
		pivot.add_child(q)
	_fire(pivot.global_position, "star_05", true, STAGGER_COLOR, 0.8, 0.6, 1.5, 3.5, Vector3.UP, 70.0, -4.0, 0.1, 0.22, 0.0, false)
	_shock_ring(pivot.global_position, STAGGER_COLOR.darkened(0.5), r * 3.0, 0.3)
	var dur := clampf(seconds, 0.3, 3.0)
	var tw := pivot.create_tween()
	tw.set_parallel(true)
	tw.tween_property(pivot, "rotation:y", TAU * dur * 0.9, dur)
	tw.tween_property(pivot, "position:y", top.y + 0.12, dur * 0.5).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(pivot, "scale", Vector3.ZERO, 0.15)
	tw.chain().tween_callback(pivot.queue_free)


## Mob wind-up telegraph: a red glint gathers at the striking side of the
## mob for the wind-up and pops just before the blow lands, so a player who
## watches the glint can step out or parry on the pop.
func windup_glint(enemy: Node3D, seconds: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var box := _body_bounds(enemy)
	var at := enemy.global_position + Vector3(0, 1.2, 0)
	if box.size.y > 0.1:
		var fwd := -enemy.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
		var c := box.get_center()
		at = Vector3(c.x, box.position.y + box.size.y * 0.72, c.z) + fwd * maxf(box.size.x, box.size.z) * 0.45
	var q := _make_quad(true)
	var m := q.material_override as StandardMaterial3D
	m.albedo_texture = AssetLib.vfx_texture("star_07")
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_color = Color(WINDUP_COLOR, 0.0)
	m.render_priority = 2
	m.no_depth_test = true
	var core := _make_quad(true)
	var cm := core.material_override as StandardMaterial3D
	cm.albedo_texture = AssetLib.vfx_texture("star_07")
	cm.albedo_color = Color(1.0, 0.85, 0.7, 1.0)
	cm.no_depth_test = true
	cm.render_priority = 3
	core.visible = true
	core.scale = Vector3.ONE * 0.3
	q.add_child(core)
	enemy.add_child(q)
	q.global_position = at
	q.visible = true
	var s := clampf(maxf(box.size.y, 1.0) * 0.6, 0.9, 2.6)
	q.scale = Vector3.ONE * s * 0.2
	var dur := maxf(seconds - 0.06, 0.12)
	var tw := q.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "albedo_color:a", 1.0, dur * 0.35)
	tw.tween_property(q, "scale", Vector3.ONE * s, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(q, "rotation:z", PI * 0.5, dur)
	tw.chain().tween_callback(func():
		if is_instance_valid(q):
			flash(q.global_position, WINDUP_COLOR, s * 0.9))
	tw.chain().tween_property(q, "scale", Vector3.ONE * s * 1.6, 0.06)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.06)
	tw.chain().tween_callback(q.queue_free)


# --- Floor boss (BossBrain hooks) ---------------------------------------------

const DANGER_COLOR := Color(1.0, 0.16, 0.1)
const ENRAGE_COLOR := Color(1.0, 0.18, 0.08)
const BAR_BREAK_COLOR := Color(0.7, 0.95, 1.0)
var _telegraph_shader: Shader
var _telegraphs := {}  # boss instance id -> Array[MeshInstance3D]


## Boss wakes: a red shock ring at its feet, a ring of dust and a glint at
## its head as it roars.
func boss_engage(enemy: Node3D) -> void:
	if not _valid(enemy):
		return
	var box := _body_bounds(enemy)
	var feet := Vector3(enemy.global_position.x, _ground_y(enemy.global_position), enemy.global_position.z)
	var w := maxf(box.size.x, box.size.z)
	ring(feet, DANGER_COLOR, w * 3.2, 0.6)
	dust_ring(feet, w * 1.2)
	var head := Vector3(box.get_center().x, box.end.y - box.size.y * 0.15, box.get_center().z)
	_glint(head, DANGER_COLOR, w * 0.9, 0.5, true)
	_shock_ring(head, DANGER_COLOR.darkened(0.3), w * 2.2, 0.45)
	flash_light(head, DANGER_COLOR, 5.0)


## Sweep: a red sector in front of the boss that fills over the wind-up.
func boss_sweep_warning(enemy: Node3D, reach: float, arc_deg: float, secs: float) -> void:
	if not _valid(enemy):
		return
	var c := enemy.global_position
	_telegraph(enemy, 1, Vector3(c.x, _ground_y(c), c.z), Vector2.ONE * reach * 2.0, _forward(enemy), secs, deg_to_rad(arc_deg) * 0.5)


func boss_sweep_impact(enemy: Node3D, reach: float, arc_deg: float) -> void:
	if not _valid(enemy):
		return
	var fwd := _forward(enemy)
	var c := enemy.global_position
	var g := _ground_y(c)
	slash(c + Vector3(0, _body_bounds(enemy).size.y * 0.45, 0), fwd, 2)
	var half := deg_to_rad(arc_deg) * 0.5
	for k in 5:
		var a := lerpf(-half, half, k / 4.0)
		var d := fwd.rotated(Vector3.UP, a)
		puff(Vector3(c.x, g, c.z) + d * reach * 0.8, 1.4)
	flash(Vector3(c.x, g + 1.0, c.z) + fwd * reach * 0.5, Color(1.0, 0.55, 0.35), 2.5)


## Charge: a lane from the boss to where it will stop, filling toward the end.
func boss_charge_warning(enemy: Node3D, from: Vector3, to: Vector3, secs: float) -> void:
	if not _valid(enemy):
		return
	var d := to - from
	d.y = 0.0
	var length := maxf(d.length(), 1.0)
	var half_w := 1.3 + float(enemy.get("size").z if enemy.get("size") is Vector3 else 2.0) * 0.5 + 1.0
	var mid := from + d * 0.5
	var t := _telegraph(enemy, 2, Vector3(mid.x, _ground_y(mid), mid.z), Vector2(half_w * 2.0, length), d.normalized() if d.length() > 0.01 else _forward(enemy), secs)
	# The end of the run gets a target ring.
	if t:
		ring(Vector3(to.x, _ground_y(to), to.z), DANGER_COLOR, half_w * 2.4, secs)


func boss_charge_impact(enemy: Node3D, pos: Vector3) -> void:
	var g := Vector3(pos.x, _ground_y(pos), pos.z)
	dust_ring(g, 3.0)
	puff(g, 2.5)
	flash(g + Vector3(0, 1.2, 0), Color(1.0, 0.6, 0.3), 3.0)
	flash_light(g + Vector3(0, 1.0, 0), Color(1.0, 0.55, 0.3), 5.0)


## Slam: a circle around the impact point; the fill reaching the rim is the hit.
func boss_slam_warning(enemy: Node3D, pos: Vector3, radius: float, secs: float) -> void:
	if not _valid(enemy):
		return
	_telegraph(enemy, 0, Vector3(pos.x, _ground_y(pos), pos.z), Vector2.ONE * radius * 2.0, Vector3.FORWARD, secs)


func boss_slam_impact(enemy: Node3D, pos: Vector3, radius: float) -> void:
	var g := Vector3(pos.x, _ground_y(pos), pos.z)
	dust_ring(g, radius)
	ring(g, Color(1.0, 0.8, 0.6), radius * 2.2, 0.45, "circle_03")
	_fire(g + Vector3(0, 0.3, 0), "dirt_02", false, Color(0.55, 0.45, 0.35, 1.0), 0.9, 0.9, 4.0, 8.0, Vector3.UP, 40.0, -16.0, 0.25, 0.6, radius * 0.4, false)
	_shock_ring(g + Vector3(0, 0.6, 0), Color(1.0, 0.7, 0.4), radius * 1.4, 0.3)
	flash_light(g + Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.3), 6.0)
	var me := get_tree().get_first_node_in_group("player") as Node3D
	if me and me.has_method("shake") and me.global_position.distance_to(g) < radius * 2.5:
		me.call("shake", 0.35)


## Rockfall: a marked ring on the ground, and a stone from the broken crown
## above the summit that drops to land exactly when the warning runs out.
func boss_rockfall_warning(enemy: Node3D, pos: Vector3, radius: float, secs: float) -> void:
	if not _valid(enemy):
		return
	var g := Vector3(pos.x, _ground_y(pos), pos.z)
	_telegraph(enemy, 0, g, Vector2.ONE * radius * 2.0, Vector3.FORWARD, secs)
	var rock := MeshInstance3D.new()
	rock.mesh = WorldArt.boulder_mesh()
	if _rock_mat == null:
		_rock_mat = StandardMaterial3D.new()
		_rock_mat.albedo_color = Color(0.46, 0.43, 0.4)
		_rock_mat.roughness = 0.95
	rock.material_override = _rock_mat
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(rock)
	var sz := radius * 0.55
	rock.global_transform = Transform3D(Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, 0.0)).scaled(Vector3(sz, sz * 0.8, sz)), g + Vector3(0, 16.0, 0))
	# Track it with the telegraphs so boss_reset clears it too.
	var id := enemy.get_instance_id()
	var list: Array = _telegraphs.get(id, [])
	list.append(rock)
	_telegraphs[id] = list
	var fall := minf(0.55, secs)
	var tw := rock.create_tween()
	tw.tween_interval(maxf(secs - fall, 0.0))
	tw.tween_property(rock, "global_position", g + Vector3(0, sz * 0.35, 0), fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(rock, "rotation", rock.rotation + Vector3(2.5, 1.2, 0.0), fall)
	tw.tween_interval(0.9)
	tw.tween_property(rock, "global_position", g - Vector3(0, sz, 0), 0.6)
	tw.tween_callback(rock.queue_free)
	# A trickle of grit from above as the warning starts.
	_fire(g + Vector3(0, 9.0, 0), "dirt_02", false, Color(0.5, 0.45, 0.4, 0.8), 0.5, 1.2, 0.5, 2.0, Vector3.DOWN, 15.0, -9.0, 0.08, 0.2, radius * 0.3, false)


func boss_rockfall_impact(enemy: Node3D, pos: Vector3, radius: float) -> void:
	var g := Vector3(pos.x, _ground_y(pos), pos.z)
	dust_ring(g, radius * 0.8)
	_fire(g + Vector3(0, 0.3, 0), "dirt_02", false, Color(0.55, 0.47, 0.38, 1.0), 0.7, 0.8, 3.0, 7.0, Vector3.UP, 50.0, -18.0, 0.2, 0.5, radius * 0.35, false)
	_shock_ring(g + Vector3(0, 0.4, 0), Color(1.0, 0.75, 0.5), radius * 1.2, 0.25)
	var me := get_tree().get_first_node_in_group("player") as Node3D
	if me and me.has_method("shake") and me.global_position.distance_to(g) < radius * 3.0:
		me.call("shake", 0.2)


var _rock_mat: StandardMaterial3D


## Chest opened: the lid's light spills out as a pillar of motes and a star
## in the item's rank colour (Crafting ranks; -1 = no gear, warm gold).
func chest_open(pos: Vector3, rank := -1) -> void:
	var col := Color(1.0, 0.82, 0.4) if rank < 0 else Crafting.rank_color(clampi(rank, 0, 5))
	var top := pos + Vector3(0, 0.8, 0)
	flash(top, col.lightened(0.3), 1.4)
	_glint(top + Vector3(0, 0.3, 0), col, 1.6 + 0.35 * maxi(rank, 0), 0.9, true)
	ring(pos + Vector3(0, 0.05, 0), col, 2.6, 0.5)
	_fire(top, "star_06", false, col, 0.6, 1.4, 1.0, 3.0, Vector3.UP, 18.0, 1.5, 0.08, 0.18, 0.35, false)
	flash_light(top, col, 3.0 + maxi(rank, 0))
	if rank >= 2:
		# Rare and above: a second, slower bloom so a good drop feels special.
		get_tree().create_timer(0.25).timeout.connect(func():
			if is_inside_tree():
				_glint(top + Vector3(0, 0.6, 0), col.lightened(0.25), 2.4, 1.1, true)
				_shock_ring(top, col, 3.0, 0.4))


## Idle twinkle on an unopened chest: a small star glints somewhere on it
## every second or so. Call with on = false to stop (e.g. while it refills).
func chest_sparkle(node: Node3D, on := true, color := Color(1.0, 0.88, 0.5)) -> void:
	if node == null or not is_instance_valid(node):
		return
	var old := node.get_node_or_null("VFXSparkle")
	if not on:
		if old:
			old.queue_free()
		return
	if old:
		return
	var t := Timer.new()
	t.name = "VFXSparkle"
	t.wait_time = 1.1 + randf() * 0.5
	t.autostart = true
	node.add_child(t)
	t.timeout.connect(func():
		if not is_inside_tree() or not node.is_visible_in_tree():
			return
		var off := Vector3(randf_range(-0.45, 0.45), randf_range(0.35, 0.85), randf_range(-0.3, 0.3))
		_glint(node.global_position + node.global_transform.basis * off, color, 0.35, 0.5, true))


## An HP bar emptied: a ring of glass shards bursts off the boss with a cold
## flash, like the bar itself breaking.
func boss_bar_break(enemy: Node3D, bar_left: int, bars: int) -> void:
	if not _valid(enemy):
		return
	var box := _body_bounds(enemy)
	var shrink := box.grow(-minf(box.size.x, box.size.z) * 0.2)
	burst_at(shrink if shrink.size.x > 0.1 else box, BAR_BREAK_COLOR, true)
	# Flash on the camera side of the body so it is never hidden inside it.
	var chest := box.get_center() + Vector3(0, box.size.y * 0.1, 0)
	var cam := get_viewport().get_camera_3d()
	if cam:
		chest += (cam.global_position - chest).normalized() * maxf(box.size.x, box.size.z) * 0.6
	_shock_ring(chest, BAR_BREAK_COLOR, maxf(box.size.x, box.size.z) * 2.6, 0.4)
	_glint(chest, Color(1, 1, 1), maxf(box.size.y, 1.0) * 1.1, 0.35)
	flash_light(chest, BAR_BREAK_COLOR, 6.0)
	if bars > 0 and bar_left == 1:
		boss_enrage(enemy, 0.0)


## Enrage (last bar): the body flares red for `secs`, then keeps a faint red
## rim until the boss resets or dies. Red embers rise off it while it roars.
func boss_enrage(enemy: Node3D, secs: float) -> void:
	if not _valid(enemy):
		return
	var mat := _enrage_mat(enemy)
	var tw := enemy.create_tween()
	if secs > 0.0:
		var pulses := maxi(int(secs / 0.45), 1)
		for i in pulses:
			tw.tween_property(mat, "shader_parameter/amount", 0.75, 0.12)
			tw.tween_property(mat, "shader_parameter/amount", 0.3, 0.3)
		var box := _body_bounds(enemy)
		_fire(box.get_center(), "flame_04", true, ENRAGE_COLOR, 0.8, minf(secs, 2.0), 1.0, 3.0, Vector3.UP, 35.0, 3.0, 0.3, 0.7, maxf(box.size.x, box.size.z) * 0.4, false)
		flash_light(box.get_center(), ENRAGE_COLOR, 6.0)
	tw.tween_property(mat, "shader_parameter/amount", 0.14, 0.4)


func boss_reset(enemy: Node3D) -> void:
	if enemy == null:
		return
	var id := enemy.get_instance_id()
	for t in _telegraphs.get(id, []):
		if is_instance_valid(t):
			t.queue_free()
	_telegraphs.erase(id)
	if is_instance_valid(enemy) and enemy.has_meta("vfx_enrage"):
		for mi in enemy.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).material_overlay == enemy.get_meta("vfx_enrage"):
				(mi as MeshInstance3D).material_overlay = null
		enemy.remove_meta("vfx_enrage")


func _enrage_mat(enemy: Node3D) -> ShaderMaterial:
	if enemy.has_meta("vfx_enrage"):
		return enemy.get_meta("vfx_enrage")
	var m := ShaderMaterial.new()
	m.shader = _glow_shader if _glow_shader else load("res://shaders/shatter_glow.gdshader")
	m.set_shader_parameter("glow_color", ENRAGE_COLOR)
	m.set_shader_parameter("amount", 0.0)
	enemy.set_meta("vfx_enrage", m)
	var rig = enemy.get("_rig")
	var root: Node = rig if rig is Node3D and is_instance_valid(rig) else enemy
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_overlay == null:
			(mi as MeshInstance3D).material_overlay = m
	return m


func _telegraph(owner: Node3D, shape: int, center: Vector3, size: Vector2, forward: Vector3, secs: float, arc := 1.3) -> MeshInstance3D:
	if _telegraph_shader == null:
		_telegraph_shader = load("res://shaders/telegraph.gdshader")
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = _telegraph_shader
	m.set_shader_parameter("shape", shape)
	m.set_shader_parameter("arc", arc)
	m.set_shader_parameter("progress", 0.0)
	m.set_shader_parameter("fade", 0.0)
	m.set_shader_parameter("color", DANGER_COLOR)
	m.set_shader_parameter("rim_px", clampf(0.35 / maxf(minf(size.x, size.y) * 0.5, 0.5), 0.015, 0.12))
	m.render_priority = 1
	mi.material_override = m
	add_child(mi)
	var f := Vector3(forward.x, 0.0, forward.z)
	if f.length_squared() < 0.0001:
		f = Vector3.FORWARD
	mi.global_transform = Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), center + Vector3(0, 0.07, 0))
	var id := owner.get_instance_id()
	var list: Array = _telegraphs.get(id, [])
	list = list.filter(func(n): return is_instance_valid(n))
	list.append(mi)
	_telegraphs[id] = list
	var tw := mi.create_tween()
	tw.tween_property(m, "shader_parameter/fade", 1.0, 0.1)
	tw.parallel().tween_property(m, "shader_parameter/progress", 1.0, maxf(secs, 0.1))
	tw.tween_property(m, "shader_parameter/fade", 0.0, 0.22)
	tw.tween_callback(mi.queue_free)
	return mi


func _valid(n: Node3D) -> bool:
	return n != null and is_instance_valid(n) and n.is_inside_tree()


func _forward(n: Node3D) -> Vector3:
	var f := -n.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


## Height of the ground under `p` (ray down onto the world layer), so decals
## sit on the floor whatever the boss's origin is.
func _ground_y(p: Vector3) -> float:
	var w := get_world_3d()
	if w == null:
		return p.y
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 3.0, 0), p - Vector3(0, 12.0, 0), 1)
	var hit := w.direct_space_state.intersect_ray(q)
	return float(hit["position"].y) if hit else p.y


## Bounds of a mob's body only (its rig), so name plates and labels
## floating above it don't count.
func _body_bounds(enemy: Node3D) -> AABB:
	var rig = enemy.get("_rig")
	if rig is Node3D and is_instance_valid(rig):
		return visual_bounds(rig)
	return visual_bounds(enemy)


## Four-point cross glint (two crossed streaks), billboarded.
func _glint(pos: Vector3, color: Color, size: float, dur: float, mix := false) -> void:
	var q := _make_quad(true)
	var m := q.material_override as StandardMaterial3D
	if mix:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = AssetLib.vfx_texture("star_07")
	m.albedo_color = Color(color if mix else color.lightened(0.4), 1.0)
	add_child(q)
	q.global_position = pos
	q.visible = true
	q.scale = Vector3.ONE * size * 0.7
	q.rotation.z = randf() * 0.5
	var tw := q.create_tween()
	tw.set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE * size, dur * 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, dur * 0.6).set_delay(dur * 0.4)
	tw.chain().tween_callback(q.queue_free)


## Camera-facing shock ring (unlike ring(), which lies on the ground).
func _shock_ring(pos: Vector3, color: Color, size: float, dur: float) -> void:
	var q := _make_quad(true)
	var m := q.material_override as StandardMaterial3D
	m.albedo_texture = AssetLib.vfx_texture("circle_02")
	m.albedo_color = Color(color, 1.0)
	add_child(q)
	q.global_position = pos
	q.visible = true
	q.scale = Vector3.ONE * size * 0.2
	var tw := q.create_tween()
	tw.set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE * size, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, dur * 0.7).set_delay(dur * 0.3)
	tw.chain().tween_callback(q.queue_free)


## Death dissolve: `rig` is lifted out of the (now hidden) mob into this node
## with its world transform kept, burns away over `dur`, then goes back where
## it came from with its original materials. `cache` is per-mob and filled on
## first use: [[MeshInstance3D, original material, dissolve material], ...].
## `delay` holds the intact rig for that long first (rigged models act out
## their death clip before they burn).
func dissolve(owner_mesh: Node3D, rig: Node3D, cache: Array, edge: Color, dur := 0.6, delay := 0.0) -> void:
	if rig == null or rig.get_parent() != owner_mesh:
		return  # Already dissolving (or detached); never double-reparent.
	if cache.is_empty():
		for mi in rig.find_children("*", "MeshInstance3D", true, false):
			# One slot per surface for merged rigs (MeshMerge keeps each toon
			# material as a surface override); otherwise the material_override.
			var slots: Array = []
			if mi.material_override != null or mi.mesh == null:
				slots.append([-1, mi.material_override])
			else:
				for s in mi.get_surface_override_material_count():
					slots.append([s, mi.get_surface_override_material(s)])
			for sl in slots:
				var orig: Material = sl[1]
				var dm := ShaderMaterial.new()
				dm.shader = _dissolve_shader
				var col := Color.WHITE
				if orig is ShaderMaterial:
					var a = orig.get_shader_parameter("albedo")
					if a is Color:
						col = a
					# Textured creature materials keep their map while burning.
					var tex = orig.get_shader_parameter("albedo_tex")
					if tex is Texture2D:
						dm.set_shader_parameter("albedo_tex", tex)
				elif orig is BaseMaterial3D:
					col = orig.albedo_color
				dm.set_shader_parameter("albedo", col)
				dm.set_shader_parameter("edge_color", edge)
				cache.append([mi, orig, dm, sl[0]])
	var xf := rig.global_transform
	owner_mesh.remove_child(rig)
	add_child(rig)
	rig.global_transform = xf
	for e in cache:
		(e[2] as ShaderMaterial).set_shader_parameter("dissolve", 0.0)
		_swap_mat(e[0], e[3] if e.size() > 3 else -1, e[2])
	var tw := rig.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	# A burst of embers while it goes.
	tw.tween_callback(_fire.bind(xf.origin + Vector3(0, 0.6, 0), "circle_05", true, edge, 0.6, 0.8, 0.8, 2.5, Vector3.UP, 70.0, 1.5, 0.08, 0.2, 0.0, false))
	tw.tween_method(_set_dissolve.bind(cache), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(_end_dissolve.bind(owner_mesh, rig, cache))


## Merged rigs keep their toon materials per surface (surface >= 0); kept
## parts use material_override (surface -1).
static func _swap_mat(mi: MeshInstance3D, surface: int, m: Material) -> void:
	if surface < 0:
		mi.material_override = m
	else:
		mi.set_surface_override_material(surface, m)


func _set_dissolve(v: float, cache: Array) -> void:
	for e in cache:
		(e[2] as ShaderMaterial).set_shader_parameter("dissolve", v)


func _end_dissolve(owner_mesh: Node3D, rig: Node3D, cache: Array) -> void:
	for e in cache:
		if is_instance_valid(e[0]):
			_swap_mat(e[0], e[3] if e.size() > 3 else -1, e[1])
	if not is_instance_valid(rig):
		return
	if is_instance_valid(owner_mesh) and owner_mesh.is_inside_tree() and rig.get_parent() == self:
		remove_child(rig)
		owner_mesh.add_child(rig)
		rig.transform = Transform3D.IDENTITY
	else:
		rig.queue_free()


# -------------------------------------------------------------- shatter ----

## A flat shard triangle, roughly unit size, centred on the origin. UV holds
## two barycentric coordinates for the edge glow in shard.gdshader.
func _shard_tri() -> ArrayMesh:
	if _shard_mesh:
		return _shard_mesh
	var verts := PackedVector3Array([Vector3(0, 0.62, 0), Vector3(-0.42, -0.34, 0), Vector3(0.5, -0.28, 0)])
	var uvs := PackedVector2Array([Vector2(1, 0), Vector2(0, 1), Vector2(0, 0)])
	var n := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = n
	_shard_mesh = ArrayMesh.new()
	_shard_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _shard_mesh


func _make_burst() -> MultiMeshInstance3D:
	if _shard_shader == null:
		_shard_shader = load("res://shaders/shard.gdshader")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _shard_tri()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = _shard_shader
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = PARTICLE_AABB
	mmi.visible = false
	return mmi


## World-space bounds of everything visible under `node` (empty AABB at the
## node's origin if it has no geometry).
static func visual_bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var list: Array = [node] if node is GeometryInstance3D else []
	list.append_array(node.find_children("*", "GeometryInstance3D", true, false))
	for gi in list:
		if not (gi as GeometryInstance3D).is_visible_in_tree() or gi is GPUParticles3D:
			continue
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh == null:
			continue
		var b: AABB = (gi as GeometryInstance3D).global_transform * (gi as VisualInstance3D).get_aabb()
		if b.size.length_squared() < 0.0001:
			continue
		box = b if first else box.merge(b)
		first = false
	if first:
		return AABB(node.global_position + Vector3(-0.4, 0, -0.4), Vector3(0.8, 1.6, 0.8))
	return box


## Polygon-shatter burst where `node` stands: glowing glass shards blown out
## of its silhouette, a flash and (High/Ultra) a light. Purely cosmetic and
## does not touch `node`; hide or free it yourself.
func shatter_node(node: Node3D, color := SHATTER_COLOR, big := false) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	burst_at(visual_bounds(node), color, big)


## Shard burst filling `box` (world space).
func burst_at(box: AABB, color := SHATTER_COLOR, big := false) -> void:
	var mmi := _take(_bursts, _make_burst, MAX_SHATTERS) as MultiMeshInstance3D
	if mmi == null:
		return
	for i in range(_live.size() - 1, -1, -1):
		if _live[i][0] == mmi:
			_live.remove_at(i)
	var count := _shard_count * (2 if big else 1)
	var mm := mmi.multimesh
	mm.instance_count = count
	var center := box.get_center()
	var half := box.size * 0.5
	# Shard size follows the body: a rat breaks into chips, a dragon into plates.
	var body := clampf(pow(box.size.x * box.size.y * box.size.z, 1.0 / 3.0), 0.4, 6.0)
	var base_size := clampf(body * 0.12, 0.06, 0.5) * (1.25 if big else 1.0)
	var life := 0.95 if big else 0.75
	var states: Array = []
	for i in count:
		# Uniform-ish point inside the bounding ellipsoid.
		var u := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		if u.length() > 1.0:
			u = u.normalized() * randf()
		var p := center + u * half * 0.85
		var out := (p - center)
		out = out.normalized() if out.length_squared() > 0.0001 else Vector3.UP
		var speed := randf_range(0.9, 3.2) * clampf(body * 0.7, 0.8, 2.6)
		var v := (out + Vector3(0, 0.55, 0)).normalized() * speed
		var s := base_size * randf_range(0.45, 1.25)
		var shape := Vector3(randf_range(0.6, 1.4), randf_range(0.7, 1.6), 1.0)
		var tint := color.lerp(Color(1, 1, 1), randf() * randf() * 0.5)
		states.append({
			"p": p, "v": v, "s": s * shape, "axis": Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(),
			"spin": randf_range(6.0, 16.0), "rot": Basis(Vector3(randf(), randf(), randf()).normalized(), randf() * TAU),
			"life": life * randf_range(0.7, 1.15), "c": tint,
		})
		mm.set_instance_custom_data(i, Color(randf(), 0, 0, 0))
	mmi.global_transform = Transform3D.IDENTITY
	mmi.visible = true
	mmi.set_meta("end_ms", Time.get_ticks_msec() + int(life * 1.2 * 1000.0))
	_live.append([mmi, states, 0.0])
	_step_burst(_live[-1], 0.0)
	flash(center, color.lightened(0.3), clampf(body * 1.0, 1.0, 5.0))
	flash_light(center, color, 5.0 if not big else 8.0)
	_fire(center, "star_05", true, color.lightened(0.4), 0.9 if big else 0.6, 0.6, 0.8, 2.6 * clampf(body, 0.8, 2.5),
		Vector3.UP, 90.0, 0.8, 0.06, 0.16, 0.0, false)


func _step_burst(b: Array, dt: float) -> bool:
	var mmi: MultiMeshInstance3D = b[0]
	var states: Array = b[1]
	b[2] += dt
	var age: float = b[2]
	var mm := mmi.multimesh
	var alive := false
	var drag := exp(-2.6 * dt)
	for i in states.size():
		var st: Dictionary = states[i]
		var t: float = age / st["life"]
		if t >= 1.0:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), st["p"]))
			continue
		alive = true
		st["v"] = st["v"] * drag + Vector3(0, 0.9 * dt, 0)   # float up a touch, like they evaporate
		st["p"] += st["v"] * dt
		st["rot"] = (st["rot"] as Basis).rotated(st["axis"], st["spin"] * dt).orthonormalized()
		# Pop in, hold, then shrink and fade over the last 45 %.
		var grow := minf(1.0, t * 10.0)
		var fade := 1.0 - smoothstep(0.55, 1.0, t)
		var sc: Vector3 = st["s"] * grow * lerpf(0.35, 1.0, fade)
		mm.set_instance_transform(i, Transform3D((st["rot"] as Basis).scaled(sc), st["p"]))
		var c: Color = st["c"]
		mm.set_instance_color(i, Color(c.r, c.g, c.b, fade))
	return alive


func _process(dt: float) -> void:
	for i in range(_live.size() - 1, -1, -1):
		var b: Array = _live[i]
		if not is_instance_valid(b[0]) or not _step_burst(b, dt):
			if is_instance_valid(b[0]):
				(b[0] as MultiMeshInstance3D).visible = false
			_live.remove_at(i)


## Death shatter, same call shape as dissolve() plus `big` (bosses). The rig
## holds for `delay` (a death clip can play), glows glass-white for
## SHATTER_GLOW, then vanishes in a shard burst.
## With `owner_mesh`: the rig is lifted into this node (world transform kept)
## and goes back under `owner_mesh` afterwards with visibility restored, so
## the owner must already be hidden (as mobs are). Without (player death):
## the rig stays where it is and is left hidden; the caller shows it again.
## `cache` is accepted for dissolve() parity and unused.
func shatter(owner_mesh: Node3D, rig: Node3D, _cache: Array = [], color := SHATTER_COLOR, big := false, delay := 0.0) -> void:
	if rig == null or not is_instance_valid(rig) or not rig.is_inside_tree():
		return
	var lifted := false
	if owner_mesh != null:
		if rig.get_parent() != owner_mesh:
			return  # Already shattering (or detached); never double-reparent.
		var xf := rig.global_transform
		owner_mesh.remove_child(rig)
		add_child(rig)
		rig.global_transform = xf
		lifted = true
	if _glow_shader == null:
		_glow_shader = load("res://shaders/shatter_glow.gdshader")
	var glow := ShaderMaterial.new()
	glow.shader = _glow_shader
	glow.set_shader_parameter("glow_color", color.lightened(0.45))
	glow.set_shader_parameter("amount", 0.0)
	var gis: Array = rig.find_children("*", "GeometryInstance3D", true, false)
	if rig is GeometryInstance3D:
		gis.append(rig)
	var olds: Array = []
	for gi in gis:
		olds.append((gi as GeometryInstance3D).material_overlay)
		(gi as GeometryInstance3D).material_overlay = glow
	var tw := rig.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(func(a: float): glow.set_shader_parameter("amount", a), 0.0, 1.0, SHATTER_GLOW).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if is_instance_valid(rig):
			burst_at(visual_bounds(rig), color, big)
			rig.visible = false)
	tw.tween_interval(0.05)
	tw.tween_callback(_end_shatter.bind(owner_mesh, rig, gis, olds, lifted))


func _end_shatter(owner_mesh: Node3D, rig: Node3D, gis: Array, olds: Array, lifted: bool) -> void:
	for i in gis.size():
		if is_instance_valid(gis[i]):
			(gis[i] as GeometryInstance3D).material_overlay = olds[i]
	if not is_instance_valid(rig) or not lifted:
		return
	rig.visible = true
	if is_instance_valid(owner_mesh) and owner_mesh.is_inside_tree() and rig.get_parent() == self:
		remove_child(rig)
		owner_mesh.add_child(rig)
		rig.transform = Transform3D.IDENTITY
	else:
		rig.queue_free()
