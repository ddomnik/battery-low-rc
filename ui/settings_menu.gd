class_name SettingsMenu
extends Control
## Settings overlay (main menu and in-game menu): audio volumes, HUD options, control remapping.
## Everything applies immediately and is saved in Settings. Escape or "Back" closes it (Escape cancels a
## pending key capture first).

signal closed

const FONT_SIZE := 22
const HEADING_SIZE := 30
const PANEL_SIZE := Vector2(760.0, 700.0)
const NAME_WIDTH := 240.0
const SLIDER_WIDTH := 320.0
const KEY_BUTTON_SIZE := Vector2(180.0, 40.0)
const LISTEN_TEXT := "Press a key…"

var _key_buttons: Dictionary = {}     # "action:slot" → Button
var _listen_action: String = ""
var _listen_slot: int = -1
var _back: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiKit.dim_background(self)
	var box := UiKit.centered_column(self)
	UiKit.title(box, "SETTINGS", UiKit.HEADING_FONT_SIZE)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = PANEL_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	_heading(list, "Audio")
	_slider(list, "Music", Settings.music_volume, func(v: float) -> void:
		Settings.music_volume = v
		Game.audio.apply_volumes())
	_slider(list, "Sound effects", Settings.sfx_volume, func(v: float) -> void:
		Settings.sfx_volume = v
		Game.audio.apply_volumes())

	_heading(list, "HUD")
	var names := CheckButton.new()
	names.text = "Show name labels"
	names.button_pressed = Settings.show_name_labels
	names.add_theme_font_size_override("font_size", FONT_SIZE)
	names.toggled.connect(func(on: bool) -> void:
		Settings.show_name_labels = on
		Settings.save_settings())
	list.add_child(names)

	_heading(list, "Controls")
	for action: String in InputSetup.REMAPPABLE:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)
		row.add_child(_label(InputSetup.REMAPPABLE[action], NAME_WIDTH))
		for slot in InputSetup.SLOTS:
			var b := Button.new()
			b.custom_minimum_size = KEY_BUTTON_SIZE
			b.add_theme_font_size_override("font_size", FONT_SIZE)
			b.pressed.connect(_start_listening.bind(action, slot))
			row.add_child(b)
			_key_buttons["%s:%d" % [action, slot]] = b
	_refresh_keys()

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", UiKit.SEPARATION)
	box.add_child(buttons)
	UiKit.button(buttons, "Reset controls").pressed.connect(func() -> void:
		_stop_listening()
		InputSetup.reset_bindings()
		_refresh_keys())
	_back = UiKit.button(buttons, "Back")
	_back.pressed.connect(close)
	_back.grab_focus()

func close() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()

## While waiting for a key, the next key / mouse button press becomes the binding (Escape cancels).
func _input(event: InputEvent) -> void:
	if _listen_action == "":
		return
	var pressed := (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE and _listen_action != "pause":
		_stop_listening()
		return
	var ev: InputEvent = null
	if event is InputEventKey:
		ev = InputSetup.key_event((event as InputEventKey).physical_keycode)
	else:
		ev = InputSetup.mouse_event((event as InputEventMouseButton).button_index)
	InputSetup.set_binding(_listen_action, _listen_slot, ev)
	_stop_listening()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()

func _start_listening(action: String, slot: int) -> void:
	_stop_listening()
	_listen_action = action
	_listen_slot = slot
	(_key_buttons["%s:%d" % [action, slot]] as Button).text = LISTEN_TEXT

func _stop_listening() -> void:
	_listen_action = ""
	_listen_slot = -1
	_refresh_keys()

func _refresh_keys() -> void:
	for id: String in _key_buttons:
		var action := id.get_slice(":", 0)
		var slot := id.get_slice(":", 1).to_int()
		var ev := InputSetup.binding(action, slot)
		(_key_buttons[id] as Button).text = InputSetup.event_text(ev) if ev != null else "—"

func _heading(parent: Control, text: String) -> void:
	var l := _label(text, 0.0)
	l.add_theme_font_size_override("font_size", HEADING_SIZE)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	parent.add_child(l)

func _slider(parent: Control, text: String, value: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	row.add_child(_label(text, NAME_WIDTH))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 100.0
	s.step = 1.0
	s.value = value * 100.0
	s.custom_minimum_size = Vector2(SLIDER_WIDTH, 32.0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var pct := _label("%d %%" % roundi(value * 100.0), 0.0)
	row.add_child(pct)
	s.value_changed.connect(func(v: float) -> void:
		pct.text = "%d %%" % roundi(v)
		on_change.call(v / 100.0))
	s.drag_ended.connect(func(_changed: bool) -> void: Settings.save_settings())

func _label(text: String, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = width
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	return l
