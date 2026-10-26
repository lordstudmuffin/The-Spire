extends Node
## Input manager (autoload "InputSetup"): registers every gameplay action with
## keyboard/mouse AND gamepad (Xbox layout) defaults, applies the player's
## remaps from Settings.data["bindings"], tracks which device is in use so
## hints can show key names or button glyphs, and drives rumble.
##
## Bindings are stored per action in two columns, "kb" (keys + mouse buttons)
## and "pad" (joypad buttons + axes), as small JSON-friendly dictionaries
## (see event_to_dict / dict_to_event). Only remapped actions are persisted.

## "keyboard" or "gamepad": the device the player last touched.
signal input_device_changed(device: String)
## InputMap changed (remap, reset or settings applied): hints refresh.
signal bindings_changed

## Default bindings. Keys are physical keycodes; a mouse button is written
## ["mouse", MOUSE_BUTTON_*]; "pad" holds JOY_BUTTON_* ints or [axis, sign].
const DEFAULTS := {
	"move_forward": {"kb": [KEY_W, KEY_UP], "pad": [[JOY_AXIS_LEFT_Y, -1]]},
	"move_back": {"kb": [KEY_S, KEY_DOWN], "pad": [[JOY_AXIS_LEFT_Y, 1]]},
	"move_left": {"kb": [KEY_A, KEY_LEFT], "pad": [[JOY_AXIS_LEFT_X, -1]]},
	"move_right": {"kb": [KEY_D, KEY_RIGHT], "pad": [[JOY_AXIS_LEFT_X, 1]]},
	"camera_up": {"kb": [], "pad": [[JOY_AXIS_RIGHT_Y, -1]]},
	"camera_down": {"kb": [], "pad": [[JOY_AXIS_RIGHT_Y, 1]]},
	"camera_left": {"kb": [], "pad": [[JOY_AXIS_RIGHT_X, -1]]},
	"camera_right": {"kb": [], "pad": [[JOY_AXIS_RIGHT_X, 1]]},
	"jump": {"kb": [KEY_SPACE], "pad": [JOY_BUTTON_A]},
	"sprint": {"kb": [KEY_SHIFT], "pad": [JOY_BUTTON_LEFT_STICK]},
	"dash": {"kb": [KEY_Q], "pad": [JOY_BUTTON_B]},
	"attack": {"kb": [["mouse", MOUSE_BUTTON_LEFT]], "pad": [JOY_BUTTON_X]},
	"skill_1": {"kb": [KEY_1], "pad": [JOY_BUTTON_RIGHT_SHOULDER]},
	"skill_2": {"kb": [KEY_2], "pad": [JOY_BUTTON_LEFT_SHOULDER]},
	"skill_3": {"kb": [KEY_3], "pad": [[JOY_AXIS_TRIGGER_RIGHT, 1]]},
	# Unique Sword Arts (only usable by a unique skill holder). On a gamepad
	# they are LT (target) held + RB / LB / RT, handled in Player.
	"skill_4": {"kb": [KEY_4], "pad": []},
	# Tap as a strike lands to parry; hold to guard.
	"parry": {"kb": [KEY_F, ["mouse", MOUSE_BUTTON_RIGHT]], "pad": [JOY_BUTTON_RIGHT_STICK]},
	"skill_5": {"kb": [KEY_5], "pad": []},
	"skill_6": {"kb": [KEY_6], "pad": []},
	# Hidden-class arts (HiddenClasses): R / C, or on a pad hold Target (LT)
	# and press Attack (X) / Dash (B). See docs/HIDDEN_CLASSES.md.
	"class_1": {"kb": [KEY_R], "pad": []},
	"class_2": {"kb": [KEY_C], "pad": []},
	"target": {"kb": [["mouse", MOUSE_BUTTON_MIDDLE]], "pad": [[JOY_AXIS_TRIGGER_LEFT, 1]]},
	"interact": {"kb": [KEY_E], "pad": [JOY_BUTTON_Y]},
	# Pad: hold Target (LT) and press Interact (Y) instead (player.gd).
	"quick_heal": {"kb": [KEY_H], "pad": []},
	"stats_menu": {"kb": [KEY_TAB], "pad": [JOY_BUTTON_BACK]},
	"quick_save": {"kb": [KEY_F5], "pad": []},
	"pause": {"kb": [KEY_ESCAPE], "pad": [JOY_BUTTON_START]},
	"chat": {"kb": [KEY_ENTER], "pad": [JOY_BUTTON_MISC1]},
	# UI screens (handled by scripts/hud.gd). Esc / B closes any of them.
	"inventory": {"kb": [KEY_I], "pad": [JOY_BUTTON_DPAD_UP]},
	"quest_log": {"kb": [KEY_J], "pad": [JOY_BUTTON_DPAD_LEFT]},
	"map": {"kb": [KEY_M], "pad": [JOY_BUTTON_DPAD_DOWN]},
	"nearby": {"kb": [KEY_O], "pad": [JOY_BUTTON_DPAD_RIGHT]},
	"map_zoom_in": {"kb": [KEY_EQUAL, KEY_KP_ADD, KEY_BRACKETRIGHT], "pad": [JOY_BUTTON_RIGHT_SHOULDER]},
	"map_zoom_out": {"kb": [KEY_MINUS, KEY_KP_SUBTRACT, KEY_BRACKETLEFT], "pad": [JOY_BUTTON_LEFT_SHOULDER]},
}

## Actions offered in the Controls remap list, in display order.
const REMAPPABLE := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"], ["move_right", "Move right"],
	["jump", "Jump"], ["sprint", "Sprint"], ["dash", "Dash"], ["attack", "Attack"],
	["skill_1", "Sword Art 1"], ["skill_2", "Sword Art 2"], ["skill_3", "Sword Art 3"], ["parry", "Parry / guard"], ["skill_4", "Unique Art 1"], ["skill_5", "Unique Art 2"], ["skill_6", "Unique Art 3"], ["class_1", "Class Art 1"], ["class_2", "Class Art 2"], ["target", "Target enemy"], ["quick_heal", "Healing Crystal"],
	["interact", "Interact"], ["inventory", "Inventory"], ["quest_log", "Quest log"], ["map", "Map"],
	["nearby", "Party & nearby"], ["stats_menu", "Character"], ["chat", "Chat"], ["pause", "Pause / back"],
	["quick_save", "Quick save"], ["map_zoom_in", "Minimap zoom in"], ["map_zoom_out", "Minimap zoom out"],
]

## Analogue stick actions get the configurable deadzone; buttons keep 0.5.
const STICK_ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "camera_up", "camera_down", "camera_left", "camera_right"]

const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_MISC1: "Share",
	JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down", JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right",
	JOY_BUTTON_PADDLE1: "P1", JOY_BUTTON_PADDLE2: "P2", JOY_BUTTON_PADDLE3: "P3", JOY_BUTTON_PADDLE4: "P4", JOY_BUTTON_TOUCHPAD: "Pad",
}
const AXIS_NAMES := {
	JOY_AXIS_LEFT_X: ["LS ←", "LS →"], JOY_AXIS_LEFT_Y: ["LS ↑", "LS ↓"],
	JOY_AXIS_RIGHT_X: ["RS ←", "RS →"], JOY_AXIS_RIGHT_Y: ["RS ↑", "RS ↓"],
	JOY_AXIS_TRIGGER_LEFT: ["LT", "LT"], JOY_AXIS_TRIGGER_RIGHT: ["RT", "RT"],
}
const KEY_SHORT := {"Escape": "Esc", "Return": "Enter", "Enter": "Enter", "Kp Enter": "Enter", "Backspace": "Bksp",
	"Up": "↑", "Down": "↓", "Left": "←", "Right": "→", "Equal": "=", "Minus": "-", "Kp Add": "Num +", "Kp Subtract": "Num -",
	"BracketLeft": "[", "BracketRight": "]", "Bracketleft": "[", "Bracketright": "]", "QuoteLeft": "`"}

var device := "keyboard"
var deadzone := 0.2


## The Settings autoload, looked up by path so this script also compiles
## stand-alone (tools, --check-only) before the autoloads exist.
func _settings() -> Node:
	return get_node_or_null("/root/Settings") if is_inside_tree() else null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply_defaults()
	Input.joy_connection_changed.connect(_on_joy_connection)
	if has_gamepad() and DisplayServer.get_name() != "headless":
		device = "gamepad"


## Is a controller plugged in?
func has_gamepad() -> bool:
	return not Input.get_connected_joypads().is_empty()


func using_gamepad() -> bool:
	return device == "gamepad"


# --- Device tracking -------------------------------------------------------

func _input(event: InputEvent) -> void:
	var d := ""
	if event is InputEventJoypadButton:
		d = "gamepad"
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > maxf(deadzone, 0.35):
			d = "gamepad"
	elif event is InputEventKey or event is InputEventMouseButton:
		d = "keyboard"
	if d != "" and d != device:
		device = d
		input_device_changed.emit(device)


func _on_joy_connection(_id: int, connected: bool) -> void:
	var d := "gamepad" if connected or has_gamepad() else "keyboard"
	if d != device:
		device = d
		input_device_changed.emit(device)


# --- Building the InputMap -----------------------------------------------

## Every action with its defaults.
func apply_defaults() -> void:
	apply_bindings({})


## Saved remaps (Settings.data["bindings"]) over the defaults.
func apply_bindings(bindings: Dictionary) -> void:
	for action in DEFAULTS:
		var kb := _default_events(action, "kb")
		var pad := _default_events(action, "pad")
		if bindings.has(action) and bindings[action] is Dictionary:
			var b: Dictionary = bindings[action]
			if b.has("kb") and b["kb"] is Array:
				kb = _events_from(b["kb"])
			if b.has("pad") and b["pad"] is Array:
				pad = _events_from(b["pad"])
		_set_action(action, kb, pad)
	apply_deadzone(deadzone)
	bindings_changed.emit()


func apply_deadzone(dz: float) -> void:
	deadzone = clampf(dz, 0.05, 0.6)
	for a in STICK_ACTIONS:
		if InputMap.has_action(a):
			InputMap.action_set_deadzone(a, deadzone)


func _set_action(action: String, kb: Array, pad: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone if action in STICK_ACTIONS else 0.5)
	InputMap.action_erase_events(action)
	for ev in kb + pad:
		ev.device = -1  # any keyboard / any pad, like project-file actions
		InputMap.action_add_event(action, ev)


func _default_events(action: String, column: String) -> Array:
	var out: Array = []
	for e in DEFAULTS[action][column]:
		if column == "kb":
			if e is Array:
				var mb := InputEventMouseButton.new()
				mb.button_index = int(e[1]) as MouseButton
				out.append(mb)
			else:
				var k := InputEventKey.new()
				k.physical_keycode = int(e) as Key
				out.append(k)
		elif e is Array:
			var m := InputEventJoypadMotion.new()
			m.axis = int(e[0]) as JoyAxis
			m.axis_value = float(e[1])
			out.append(m)
		else:
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(e) as JoyButton
			out.append(jb)
	return out


# --- Queries ---------------------------------------------------------------

static func is_pad_event(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton or ev is InputEventJoypadMotion


static func is_kb_event(ev: InputEvent) -> bool:
	return ev is InputEventKey or ev is InputEventMouseButton


## The action's events in one column: "kb" or "pad".
func events(action: String, column: String) -> Array:
	var out: Array = []
	if not InputMap.has_action(action):
		return out
	for ev in InputMap.action_get_events(action):
		if (column == "pad") == is_pad_event(ev):
			out.append(ev)
	return out


## Short display text for one event: "W", "Esc", "LMB", "A", "RB", "RS ↑".
static func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		var t := OS.get_keycode_string(code)
		return KEY_SHORT.get(t, t)
	if ev is InputEventMouseButton:
		var bi := (ev as InputEventMouseButton).button_index
		return {MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
			MOUSE_BUTTON_WHEEL_UP: "Wheel ↑", MOUSE_BUTTON_WHEEL_DOWN: "Wheel ↓"}.get(bi, "Mouse %d" % bi)
	if ev is InputEventJoypadButton:
		var b := (ev as InputEventJoypadButton).button_index
		return PAD_NAMES.get(b, "Btn %d" % b)
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		if AXIS_NAMES.has(m.axis):
			return AXIS_NAMES[m.axis][1 if m.axis_value > 0.0 else 0]
		return "Axis %d%s" % [m.axis, "+" if m.axis_value > 0.0 else "-"]
	return ev.as_text()


## Text of the first binding in a column, or "" when unbound.
func binding_text(action: String, column: String) -> String:
	var evs := events(action, column)
	return event_text(evs[0]) if not evs.is_empty() else ""


## Hint for the device in use. Besides real actions it knows a few composite
## names: "move" (WASD / LS), "camera" (Mouse / RS), "skills" (1-3 / RB LB RT),
## "map_zoom" (+ / - or RB / LB), "confirm" (Enter / A), "back" (Esc / B),
## "yes" / "no" (Y / N or A / B).
func hint(action: String) -> String:
	var pad := using_gamepad()
	var col := "pad" if pad else "kb"
	match action:
		"move":
			return "LS" if pad else "WASD"
		"camera":
			return "RS" if pad else "Mouse"
		"skills":
			if pad:
				return "%s %s %s" % [binding_text("skill_1", col), binding_text("skill_2", col), binding_text("skill_3", col)]
			return "%s-%s" % [binding_text("skill_1", col), binding_text("skill_3", col)]
		"map_zoom":
			return "%s / %s" % [binding_text("map_zoom_in", col), binding_text("map_zoom_out", col)]
		"confirm":
			return "A" if pad else "Enter"
		"back":
			return "B" if pad else "Esc"
		"yes":
			return "A" if pad else "Y"
		"no":
			return "B" if pad else "N"
	var t := binding_text(action, col)
	if t == "":
		t = binding_text(action, "kb" if pad else "pad")
	return t if t != "" else "—"


## Face buttons get a coloured round glyph: A green, B red, X blue, Y yellow.
static func face_color(text: String) -> Color:
	return {"A": Color("5fc46a"), "B": Color("e2605f"), "X": Color("5d8fe6"), "Y": Color("e8c547")}.get(text, Color(0, 0, 0, 0))


# --- Remapping -------------------------------------------------------------

## Bind `ev` as the only binding of `action` in the event's column; a
## conflicting binding on another action in that column is removed. Saves
## through Settings. Returns the action that lost its binding, or "".
func rebind(action: String, ev: InputEvent) -> String:
	if not DEFAULTS.has(action):
		return ""
	var column := "pad" if is_pad_event(ev) else "kb"
	var displaced := ""
	var bindings := _current_bindings()
	for other in DEFAULTS:
		if other == action:
			continue
		var kept: Array = []
		var changed := false
		for e in events(other, column):
			if _same(e, ev):
				changed = true
				displaced = other
			else:
				kept.append(e)
		if changed:
			bindings[other][column] = _events_to(kept)
	bindings[action][column] = _events_to([ev])
	_store(bindings)
	return displaced


func clear_binding(action: String, column: String) -> void:
	var bindings := _current_bindings()
	bindings[action][column] = []
	_store(bindings)


func reset_bindings() -> void:
	var st := _settings()
	if st:
		st.set_value("bindings", {})
	else:
		apply_bindings({})


func is_default(action: String) -> bool:
	var st := _settings()
	return st == null or not st.data["bindings"].has(action)


## Every action's current bindings as dictionaries (the full picture, so
## conflicts can be resolved); _store() trims it to the remapped ones.
func _current_bindings() -> Dictionary:
	var out := {}
	for action in DEFAULTS:
		out[action] = {"kb": _events_to(events(action, "kb")), "pad": _events_to(events(action, "pad"))}
	return out


func _store(full: Dictionary) -> void:
	var trimmed := {}
	for action in full:
		var def := {"kb": _events_to(_default_events(action, "kb")), "pad": _events_to(_default_events(action, "pad"))}
		if full[action] != def:
			trimmed[action] = full[action]
	var st := _settings()
	if st:
		st.set_value("bindings", trimmed)  # Settings.apply_input re-applies the map
	else:
		apply_bindings(trimmed)


func _same(a: InputEvent, b: InputEvent) -> bool:
	return event_to_dict(a) == event_to_dict(b)


static func event_to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return {"type": "key", "code": int(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)}
	if ev is InputEventMouseButton:
		return {"type": "mouse", "button": int((ev as InputEventMouseButton).button_index)}
	if ev is InputEventJoypadButton:
		return {"type": "joy", "button": int((ev as InputEventJoypadButton).button_index)}
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		return {"type": "axis", "axis": int(m.axis), "value": 1 if m.axis_value > 0.0 else -1}
	return {}


static func dict_to_event(d: Dictionary) -> InputEvent:
	match str(d.get("type", "")):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("code", 0)) as Key
			return k
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(d.get("button", 1)) as MouseButton
			return mb
		"joy":
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(d.get("button", 0)) as JoyButton
			return jb
		"axis":
			var m := InputEventJoypadMotion.new()
			m.axis = int(d.get("axis", 0)) as JoyAxis
			m.axis_value = 1.0 if float(d.get("value", 1)) > 0.0 else -1.0
			return m
	return null


static func _events_to(evs: Array) -> Array:
	var out: Array = []
	for e in evs:
		var d := event_to_dict(e)
		if not d.is_empty():
			out.append(d)
	return out


static func _events_from(list: Array) -> Array:
	var out: Array = []
	for d in list:
		if d is Dictionary:
			var e := dict_to_event(d)
			if e:
				out.append(e)
	return out


## Normalise an event the player pressed while remapping into a clean
## binding (strip modifiers, snap axes to ±1). Null when it is not bindable.
static func bindable(ev: InputEvent) -> InputEvent:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var src := ev as InputEventKey
		var k := InputEventKey.new()
		k.physical_keycode = src.physical_keycode if src.physical_keycode != KEY_NONE else src.keycode
		return k
	if ev is InputEventMouseButton and ev.pressed:
		var mb := InputEventMouseButton.new()
		mb.button_index = (ev as InputEventMouseButton).button_index
		return mb
	if ev is InputEventJoypadButton and ev.pressed:
		var jb := InputEventJoypadButton.new()
		jb.button_index = (ev as InputEventJoypadButton).button_index
		return jb
	if ev is InputEventJoypadMotion and absf((ev as InputEventJoypadMotion).axis_value) > 0.6:
		var m := InputEventJoypadMotion.new()
		m.axis = (ev as InputEventJoypadMotion).axis
		m.axis_value = signf((ev as InputEventJoypadMotion).axis_value)
		return m
	return null


# --- Rumble ----------------------------------------------------------------

## Short vibration on every connected pad, when the setting allows it.
## `weak`/`strong` are 0..1 motor strengths, `duration` in seconds.
func rumble(weak: float, strong: float, duration: float) -> void:
	var st := _settings()
	if st and not st.data.get("vibration", true):
		return
	for id in Input.get_connected_joypads():
		Input.start_joy_vibration(id, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)
