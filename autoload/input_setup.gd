extends Node
## InputSetup autoload: registers actions in code so nobody has to hand-edit serialized events in project.godot.
## Uses physical keycodes so WASD stays in place on QWERTZ / AZERTY layouts.

const KEYS := {
	"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"handbrake": [KEY_SPACE], "boost": [KEY_SHIFT], "reset": [KEY_R], "pause": [KEY_ESCAPE],
	"toggle_fullscreen": [KEY_F11],
	"debug_toggle_camera": [KEY_F2], "debug_overlay": [KEY_F3], "debug_draw": [KEY_F4],
	"debug_fill_battery": [KEY_F6], "debug_add_score": [KEY_F7],
	"debug_give_item_1": [KEY_1], "debug_give_item_2": [KEY_2],
	"debug_give_item_3": [KEY_3], "debug_give_item_4": [KEY_4],
}
const MOUSE := {"fire": [MOUSE_BUTTON_LEFT]}

func _ready() -> void:
	for action: String in KEYS:
		_ensure(action)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action: String in MOUSE:
		_ensure(action)
		for button: MouseButton in MOUSE[action]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)

func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
