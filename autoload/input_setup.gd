extends Node
## InputSetup autoload: registers actions in code so nobody has to hand-edit serialized events in project.godot.
## Uses physical keycodes so WASD stays in place on QWERTZ / AZERTY layouts.
## Player controls can be remapped (Settings menu); remaps are stored in Settings.key_bindings.

const KEYS := {
	"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"handbrake": [KEY_SPACE], "boost": [KEY_SHIFT], "reset": [KEY_R], "pause": [KEY_ESCAPE],
	"toggle_fullscreen": [KEY_F11], "spectate_next": [KEY_TAB],
	"debug_toggle_camera": [KEY_F2], "debug_overlay": [KEY_F3], "debug_draw": [KEY_F4],
	"debug_fill_battery": [KEY_F6], "debug_add_score": [KEY_F7],
	"debug_give_item_1": [KEY_1], "debug_give_item_2": [KEY_2],
	"debug_give_item_3": [KEY_3], "debug_give_item_4": [KEY_4], "debug_give_item_5": [KEY_5],
	"debug_give_item_6": [KEY_6], "debug_give_item_7": [KEY_7],
}
const MOUSE := {"fire": [MOUSE_BUTTON_LEFT]}

## Actions shown in the Settings menu, in order, with their labels. Debug keys are not remappable.
const REMAPPABLE := {
	"move_up": "Accelerate", "move_down": "Brake / reverse", "move_left": "Steer left", "move_right": "Steer right",
	"handbrake": "Handbrake / drift", "boost": "Boost", "fire": "Use item", "reset": "Reset car",
	"pause": "Menu", "toggle_fullscreen": "Fullscreen",
}
const SLOTS := 2                         # bindings per action shown in the menu

func _ready() -> void:
	for action: String in KEYS:
		_ensure(action)
	for action: String in MOUSE:
		_ensure(action)
	for action: String in KEYS.keys() + MOUSE.keys():
		_set_events(action, default_events(action))
	apply_saved_bindings()

func default_events(action: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for key: Key in KEYS.get(action, []):
		out.append(key_event(key))
	for button: MouseButton in MOUSE.get(action, []):
		out.append(mouse_event(button))
	return out

## Applies Settings.key_bindings on top of the defaults.
func apply_saved_bindings() -> void:
	for action: String in Settings.key_bindings:
		if not REMAPPABLE.has(action):
			continue
		var events: Array[InputEvent] = []
		for code: String in Settings.key_bindings[action]:
			var ev := decode(code)
			if ev != null:
				events.append(ev)
		_set_events(action, events)

## The binding in a slot (0 = primary, 1 = secondary), or null.
func binding(action: String, slot: int) -> InputEvent:
	var events := InputMap.action_get_events(action)
	return events[slot] if slot < events.size() else null

## Puts an event into an action's slot. The same key is removed from any other remappable action first,
## so nothing is bound twice. Saved immediately.
func set_binding(action: String, slot: int, ev: InputEvent) -> void:
	for other: String in REMAPPABLE:
		if other == action:
			continue
		var kept: Array[InputEvent] = []
		var changed := false
		for e in InputMap.action_get_events(other):
			if _same(e, ev):
				changed = true
			else:
				kept.append(e)
		if changed:
			_set_events(other, kept)
			_store(other)
	var events: Array[InputEvent] = []
	for e in InputMap.action_get_events(action):
		if not _same(e, ev):
			events.append(e)
	if slot < events.size():
		events[slot] = ev
	else:
		events.append(ev)
	_set_events(action, events)
	_store(action)
	Settings.save_settings()

func reset_bindings() -> void:
	Settings.key_bindings = {}
	for action: String in REMAPPABLE:
		_set_events(action, default_events(action))
	Settings.save_settings()

## Human-readable name of a binding ("W", "Space", "Left mouse").
static func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := KEY_NONE
		if DisplayServer.get_name() != "headless":   # shows the key as labeled on the user's layout (QWERTZ…)
			code = DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
		return OS.get_keycode_string(code if code != KEY_NONE else k.physical_keycode)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "Left mouse"
			MOUSE_BUTTON_RIGHT:
				return "Right mouse"
			MOUSE_BUTTON_MIDDLE:
				return "Middle mouse"
			var b:
				return "Mouse %d" % b
	return "—"

static func key_event(key: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	return ev

static func mouse_event(button: MouseButton) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	return ev

static func encode(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return "key:%d" % (ev as InputEventKey).physical_keycode
	if ev is InputEventMouseButton:
		return "mouse:%d" % (ev as InputEventMouseButton).button_index
	return ""

static func decode(code: String) -> InputEvent:
	var kind := code.get_slice(":", 0)
	var value := code.get_slice(":", 1).to_int()
	if kind == "key":
		return key_event(value as Key)
	if kind == "mouse":
		return mouse_event(value as MouseButton)
	return null

func _store(action: String) -> void:
	var codes: Array[String] = []
	for e in InputMap.action_get_events(action):
		codes.append(encode(e))
	Settings.key_bindings[action] = codes

func _set_events(action: String, events: Array[InputEvent]) -> void:
	InputMap.action_erase_events(action)
	for e in events:
		InputMap.action_add_event(action, e)

static func _same(a: InputEvent, b: InputEvent) -> bool:
	return encode(a) == encode(b) and encode(a) != ""

func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
