class_name LoadingScreen
extends CanvasLayer
## Loading overlay shown while a floor of the Spire builds: key-art gradient
## with the Spire silhouette, "Floor N · Name" title, a progress bar that moves
## between build steps and rotating lore tips.
##
## The world builder calls `await LoadingScreen.step(label, fraction)` between
## its heavy stages; that updates the bar and yields one frame so the window
## keeps painting. The menu opens the screen early (`open`) so it covers the
## scene change; a floor travel or a server join that reaches the world
## without one open gets it from the first step() call. `done()` fades it out.
## Headless (dedicated server, smoke test) and `enabled = false` (screenshot
## harness) keep the build synchronous: step() returns at once.

const FADE_IN := 0.25
const FADE_OUT := 0.45
const TIP_SECONDS := 3.6

## Set false to keep the world build synchronous (tests, screenshot harness).
static var enabled := true
static var _inst: LoadingScreen

## Lore tips: [floor or 0 for any, text]. Original names only.
const TIPS := [
	[1, "The Town of First Light keeps its lanterns lit all night. Nobody remembers who first asked it to."],
	[1, "Guide Mira has met every climber who ever stepped off the waygate. She still learns their names."],
	[1, "Hollowbrook's forge went cold the winter the ore stopped coming. Elder Wren has not forgiven the mountain."],
	[1, "Captain Rhys counts the Dire Wolves every dawn. The count has never gone down."],
	[1, "Smith Haldor says a blade remembers the hand that forged it. Craft enough and it may remember yours."],
	[1, "Talven camp sits where the woods thin. Quartermaster Dain insists that is a coincidence."],
	[1, "Gravelmaw guards the summit of the first Labyrinth. Watch the ground before you watch him."],
	[1, "The Labyrinth's terraces hang in open air. Do not look down. Then look down."],
	[2, "The Mirewood never dries. Waykeeper Bran says the mist is the floor breathing."],
	[2, "Thornwick's hunters leave an antler on every trophy post. Huntmaster Sable keeps the tally."],
	[2, "Keeper Ilsa walks the lantern boardwalk to the Shrine of Still Water each evening and back each dawn."],
	[2, "Wisp Essence cools to a pale blue when the shrine accepts it. Any other colour, bring it back."],
	[2, "The Sunken Barrow was sealed from the inside. The Drowned Knight is still in there, and still waiting."],
	[2, "Mirelord raises the drowned to fight for him. Finish the wisps first, or you will be finishing them forever."],
	[0, "Sword Arts: Sweeping Edge sweeps wide, Twin Crescent hits hard, Falcon Rush closes the distance."],
	[0, "Dash (Q) through a charge and the mob will have to turn around. Most of them are slow to turn."],
	[0, "Every craft rolls a rank, Normal to Myth. Smithing levels tilt the odds, not the ceiling."],
	[0, "Saves live in three slots. Switching climbers at the title screen keeps every climb where it was."],
	[0, "The Spire is said to have a hundred floors. So far two have been carved."],
]

var _root: Control
var _title: Label
var _kicker: Label
var _step: Label
var _tip: Label
var _bar: ProgressBar
var _tip_timer := 0.0
var _tip_order: Array = []
var _tip_idx := 0
var _closing := false
var _spin := 0.0
var _spinner: Control


# --- Static API ----------------------------------------------------------------

static func active() -> bool:
	return _inst != null and is_instance_valid(_inst) and not _inst._closing


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Puts the screen up (idempotent). `floor` picks the title and the tips.
static func open(floor: int = -1, kicker := "Ascending") -> LoadingScreen:
	if not enabled or WorldArt.headless() or Net.dedicated:
		return null
	var tree := _tree()
	if tree == null or tree.root == null:
		return null
	if _inst != null and is_instance_valid(_inst):
		if _inst._closing:
			_inst.queue_free()
			_inst = null
		else:
			_inst.set_floor(floor, kicker)
			return _inst
	var ls := LoadingScreen.new()
	ls.name = "LoadingScreen"
	tree.root.add_child(ls)
	ls.set_floor(floor, kicker)
	_inst = ls
	return ls


## Marks a build step and yields one frame so it is drawn. Opens the screen
## when a floor is being built without one (floor travel, server join).
static func step(label: String, fraction: float) -> void:
	var ls := _inst if active() else open()
	if ls == null:
		return
	ls.set_progress(label, fraction)
	var tree := _tree()
	if tree:
		await tree.process_frame


## Indeterminate state while a connection is pending.
static func connecting(text := "Connecting to the floor server...") -> void:
	var ls := open(GameState.floor, "Online")
	if ls:
		ls.set_progress(text, -1.0)


## Fades the screen out (the world is ready).
static func done() -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst.fade_out()


## Drops the screen at once (connection refused, back to the menu).
static func close() -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst.queue_free()
	_inst = null


# --- Instance -------------------------------------------------------------------

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Key art: night-to-dawn gradient, a few stars, the Spire silhouette.
	var sky := TextureRect.new()
	sky.texture = UITheme.gradient_tex([Color("05081a"), Color("0b1024"), Color("1a1f4a"), Color("3a2d5e"), Color("7a4a66")], [0.0, 0.35, 0.65, 0.86, 1.0])
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(sky)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var star_tex := UITheme.radial_dot(Color.WHITE, 8, true)
	for i in 70:
		var s := TextureRect.new()
		s.texture = star_tex
		var px := rng.randf_range(2.0, 5.0)
		s.custom_minimum_size = Vector2(px, px)
		s.stretch_mode = TextureRect.STRETCH_SCALE
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.anchor_left = rng.randf()
		s.anchor_right = s.anchor_left
		s.anchor_top = rng.randf_range(0.0, 0.55)
		s.anchor_bottom = s.anchor_top
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.modulate = Color(1, 1, 1, rng.randf_range(0.25, 0.85))
		_root.add_child(s)
	var tower := Control.new()
	tower.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tower.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tower)
	tower.draw.connect(_draw_spire.bind(tower))
	_root.resized.connect(tower.queue_redraw)
	var vig := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.6)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	vig.texture = gt
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.offset_left = -200
	vig.offset_right = 200
	vig.offset_top = -120
	vig.offset_bottom = 120
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vig)

	# Title block, bottom-left, above the bar.
	var block := VBoxContainer.new()
	block.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	block.offset_left = 96
	block.offset_right = -96
	block.offset_top = -250
	block.offset_bottom = -72
	block.add_theme_constant_override("separation", 8)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(block)
	_kicker = UITheme.kicker("Ascending")
	block.add_child(_kicker)
	_title = Label.new()
	_title.theme_type_variation = "Title"
	_title.add_theme_font_size_override("font_size", 56)
	block.add_child(_title)
	var rule := UITheme.rule()
	rule.custom_minimum_size = Vector2(380, 2)
	block.add_child(rule)
	_tip = UITheme.subtle("", 16)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tip.custom_minimum_size = Vector2(0, 52)
	_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(_tip)
	block.add_child(UITheme.spacer(2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	block.add_child(row)
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 14)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.add_theme_stylebox_override("fill", UITheme.gradient_fill_box([UITheme.CYAN, UITheme.GOLD]))
	row.add_child(_bar)
	_spinner = Control.new()
	_spinner.custom_minimum_size = Vector2(22, 22)
	_spinner.draw.connect(_draw_spinner)
	row.add_child(_spinner)
	_step = UITheme.label("", 15, UITheme.PARCH)
	_step.custom_minimum_size = Vector2(300, 0)
	_step.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_step)

	_root.modulate.a = 0.0
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_IN)
	set_floor(GameState.floor, "Ascending")


func set_floor(floor: int, kicker := "Ascending") -> void:
	if floor <= 0:
		floor = GameState.floor
	_title.text = "Floor %d  ·  %s" % [floor, GameState.FLOOR_NAMES.get(floor, "Floor %d" % floor)]
	_kicker.text = kicker
	# Floor tips first (shuffled), then the general ones.
	_tip_order = []
	var general := []
	for i in TIPS.size():
		if TIPS[i][0] == floor:
			_tip_order.append(i)
		elif TIPS[i][0] == 0:
			general.append(i)
	_tip_order.shuffle()
	general.shuffle()
	_tip_order.append_array(general)
	_tip_idx = 0
	_tip_timer = TIP_SECONDS
	_show_tip()


## fraction < 0 = indeterminate (spinner only).
func set_progress(label: String, fraction: float) -> void:
	_step.text = label
	if fraction < 0.0:
		_bar.value = 0.0
		_bar.modulate.a = 0.35
		return
	_bar.modulate.a = 1.0
	_bar.value = clampf(fraction, 0.0, 1.0)


## Harness: a representative mid-build frame.
func preview(floor: int) -> void:
	set_floor(floor)
	set_progress("Planting the meadow", 0.46)
	_tip_idx = 0
	_show_tip()


func fade_out() -> void:
	if _closing:
		return
	_closing = true
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_OUT).set_delay(0.1)
	tw.tween_callback(queue_free)


func _exit_tree() -> void:
	if _inst == self:
		_inst = null


func _process(delta: float) -> void:
	_spin += delta * 3.0
	_spinner.queue_redraw()
	_tip_timer -= delta
	if _tip_timer <= 0.0 and _tip_order.size() > 1:
		_tip_timer = TIP_SECONDS
		_tip_idx = (_tip_idx + 1) % _tip_order.size()
		var tw := _tip.create_tween()
		tw.tween_property(_tip, "modulate:a", 0.0, 0.25)
		tw.tween_callback(_show_tip)
		tw.tween_property(_tip, "modulate:a", 1.0, 0.35)


func _show_tip() -> void:
	if _tip_order.is_empty():
		return
	_tip.text = TIPS[_tip_order[_tip_idx]][1]


func _draw_spinner() -> void:
	var c := _spinner.size / 2.0
	var r := minf(c.x, c.y) - 3.0
	_spinner.draw_arc(c, r, 0.0, TAU, 32, Color(1, 1, 1, 0.12), 3.0, true)
	_spinner.draw_arc(c, r, _spin, _spin + TAU * 0.3, 16, UITheme.GOLD, 3.0, true)


## Layered silhouette of the Spire (same shapes as the title screen, dimmer).
func _draw_spire(c: Control) -> void:
	var w := _root.size.x
	var h := _root.size.y
	var cx := w * 0.68
	var far := Color("151c3a")
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(-10, 0), Vector2(-10, -h * 0.12), Vector2(w * 0.15, -h * 0.2), Vector2(w * 0.35, -h * 0.14),
		Vector2(w * 0.55, -h * 0.23), Vector2(w * 0.78, -h * 0.16), Vector2(w * 0.92, -h * 0.24), Vector2(w + 10, -h * 0.15), Vector2(w + 10, 0)]), far)
	var col := Color("0a0e22")
	for t in [[0.11, 0.0, 0.24], [0.085, 0.24, 0.43], [0.065, 0.43, 0.58], [0.047, 0.58, 0.7], [0.03, 0.7, 0.8]]:
		var hw: float = w * t[0]
		var y0: float = -h * t[1]
		var y1: float = -h * t[2]
		c.draw_colored_polygon(PackedVector2Array([Vector2(cx - hw, y0), Vector2(cx - hw * 0.92, y1), Vector2(cx + hw * 0.92, y1), Vector2(cx + hw, y0)]), col)
		c.draw_rect(Rect2(cx - hw * 1.06, y1 - 6, hw * 2.12, 10), col)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(t[1] * 1000) + 3
		for i in int(hw / 6):
			var wx := cx - hw * 0.8 + rng.randf() * hw * 1.6
			var wy := y1 + 14 + rng.randf() * (y0 - y1 - 28)
			c.draw_rect(Rect2(wx, wy, 3, 5), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, rng.randf_range(0.2, 0.7)))
	c.draw_colored_polygon(PackedVector2Array([Vector2(cx - w * 0.013, -h * 0.8), Vector2(cx, -h * 0.91), Vector2(cx + w * 0.013, -h * 0.8)]), col)
	c.draw_circle(Vector2(cx, -h * 0.9), 14, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.2))
	c.draw_circle(Vector2(cx, -h * 0.9), 4, UITheme.CYAN)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(-10, 0), Vector2(-10, -h * 0.06), Vector2(w * 0.25, -h * 0.1), Vector2(w * 0.45, -h * 0.05),
		Vector2(w * 0.7, -h * 0.09), Vector2(w * 0.88, -h * 0.04), Vector2(w + 10, -h * 0.08), Vector2(w + 10, 0)]), Color("070a18"))
