class_name NpcBark
extends Node
## Speech bubbles over villagers who are out on a day/night routine
## (scripts/npc_routines.gd): when the player walks within NEAR metres, the
## NPC's bark line fades in above their name tag and fades out again when
## the player leaves or the NPC goes home. Original art (shaders/speech_bubble).

const NEAR := 6.0
const FAR := 8.0
const PX := 0.005           # Label3D pixel size (metres per font pixel)
const WRAP_PX := 440.0      # wrap width in font pixels

var routines: Node
var _bubbles := {}          # npc_name -> {root, label, quad, mat, a}
var _poll := 0.0


static func attach(world: Node, routines_node: Node) -> NpcBark:
	var n := NpcBark.new()
	n.name = "NpcBark"
	n.routines = routines_node
	world.add_child(n)
	return n


func _process(delta: float) -> void:
	if routines == null or not is_instance_valid(routines):
		return
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.25
		_scan()
	for k in _bubbles.keys():
		var b: Dictionary = _bubbles[k]
		var target: float = 1.0 if b["want"] else 0.0
		b["a"] = move_toward(b["a"], target, delta * 4.0)
		(b["root"] as Node3D).visible = b["a"] > 0.01
		(b["label"] as Label3D).modulate.a = b["a"]
		(b["label"] as Label3D).outline_modulate.a = b["a"] * 0.9
		(b["mat"] as ShaderMaterial).set_shader_parameter("fade", b["a"])


func _scan() -> void:
	var me := get_tree().get_first_node_in_group("player") as Node3D
	var npcs: Dictionary = routines.get("_npcs") if routines.get("_npcs") is Dictionary else {}
	for name in npcs:
		var npc: Node3D = npcs[name].get("node")
		if npc == null or not is_instance_valid(npc):
			continue
		var line: String = routines.call("bark", name) if routines.has_method("bark") else ""
		var d := INF if me == null else me.global_position.distance_to(npc.global_position)
		var b: Dictionary = _bubbles.get(name, {})
		var was: bool = b.get("want", false)
		var want := line != "" and (d < NEAR or (was and d < FAR))
		if want and b.is_empty():
			b = _make(npc, line)
			_bubbles[name] = b
		if not b.is_empty():
			b["want"] = want


func _make(npc: Node3D, line: String) -> Dictionary:
	var root := Node3D.new()
	var h := 2.2
	for c in npc.get_children():
		if c is Label3D:
			h = maxf(h, (c as Label3D).position.y)
	root.position = Vector3(0, h + 0.95, 0)
	npc.add_child(root)
	var l := Label3D.new()
	l.text = line
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = PX
	l.font_size = 32
	l.outline_size = 8
	l.modulate = Color(1, 1, 1, 0)
	l.outline_modulate = Color(0.04, 0.05, 0.1, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = WRAP_PX
	l.render_priority = 2
	l.outline_render_priority = 1
	var f := UITheme.ui_font()
	if f:
		l.font = f
	root.add_child(l)
	# Size the panel from the wrapped text.
	var font: Font = l.font if l.font else ThemeDB.fallback_font
	var lines := ceilf(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x / WRAP_PX)
	var w := minf(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x, WRAP_PX) * PX + 0.22
	var hh := lines * font.get_height(l.font_size) * PX + 0.14
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, hh + 0.12)
	q.mesh = qm
	q.position = Vector3(0, -0.06, 0)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/speech_bubble.gdshader")
	m.set_shader_parameter("size", Vector2(w, hh))
	m.set_shader_parameter("fade", 0.0)
	m.render_priority = 0
	q.material_override = m
	root.add_child(q)
	root.visible = false
	return {"root": root, "label": l, "quad": q, "mat": m, "a": 0.0, "want": false}
