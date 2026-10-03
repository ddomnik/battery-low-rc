extends Control
## Main menu: Play, game mode (+ its setting), bot count, camera mode, Settings, Quit. Values persist through
## Settings. Quit lives only here.

const CAMERA_OPTIONS: Array[String] = ["Follow (recommended)", "Classic (fixed)"]   # index = CameraRig.Mode
const FIELD_WIDTH := 300.0

var _orphan_label: Label
var _time_row: Control
var _lives_row: Control
var _bomb_row: Control

func _ready() -> void:
	var box := UiKit.centered_column(self)
	UiKit.title(box, "BATTERY LOW!")

	var play := UiKit.button(box, "Play")
	play.pressed.connect(_on_play)

	var mode := OptionButton.new()
	for label in GameMode.LABELS:
		mode.add_item(label)
	mode.select(Settings.game_mode)
	_style_field(mode)
	mode.item_selected.connect(_on_mode_selected)
	UiKit.row(box, "Mode").add_child(mode)

	# One setting per mode; only the selected mode's row is shown.
	_time_row = _spin_row(box, "Time (s)", Settings.round_time, 60.0, 900.0, 30.0, func(v: float) -> void: Settings.round_time = v)
	_lives_row = _spin_row(box, "Lives", Settings.lives, 1.0, 9.0, 1.0, func(v: float) -> void: Settings.lives = int(v))
	_bomb_row = _spin_row(box, "Bomb (s)", Settings.bomb_time, 5.0, 120.0, 5.0, func(v: float) -> void: Settings.bomb_time = v)
	_update_mode_rows()

	_spin_row(box, "Bots", Settings.bot_count, 0.0, MatchConfig.MAX_BOTS, 1.0, func(v: float) -> void: Settings.bot_count = int(v))

	var camera := OptionButton.new()
	for option in CAMERA_OPTIONS:
		camera.add_item(option)
	camera.select(Settings.camera_mode)
	_style_field(camera)
	camera.item_selected.connect(_on_camera_selected)
	UiKit.row(box, "Camera").add_child(camera)

	UiKit.button(box, "Settings").pressed.connect(func() -> void: add_child(SettingsMenu.new()))
	UiKit.button(box, "Quit").pressed.connect(Game.quit_app)
	play.grab_focus()

	if OS.is_debug_build():
		_orphan_label = Label.new()
		_orphan_label.position = Vector2(16.0, 16.0)
		add_child(_orphan_label)

func _process(_delta: float) -> void:
	if _orphan_label != null:
		_orphan_label.text = "Orphan nodes: %d" % Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

func _on_play() -> void:
	Game.start_match(MatchConfig.from_settings())

func _on_mode_selected(index: int) -> void:
	Settings.game_mode = index as GameMode.Kind
	Settings.save_settings()
	_update_mode_rows()

func _update_mode_rows() -> void:
	_time_row.visible = Settings.game_mode == GameMode.Kind.TIMED
	_lives_row.visible = Settings.game_mode == GameMode.Kind.LIVES
	_bomb_row.visible = Settings.game_mode == GameMode.Kind.STICKY_BOMB

func _on_camera_selected(index: int) -> void:
	Settings.camera_mode = index as CameraRig.Mode
	Settings.save_settings()

## "Label  [SpinBox]" row; on_change gets the new value, then the settings are saved.
func _spin_row(box: Control, text: String, value: float, lo: float, hi: float, step: float, on_change: Callable) -> Control:
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.x = FIELD_WIDTH
	spin.get_line_edit().add_theme_font_size_override("font_size", UiKit.BUTTON_FONT_SIZE)
	spin.value_changed.connect(func(v: float) -> void:
		on_change.call(v)
		Settings.save_settings())
	var row := UiKit.row(box, text)
	row.add_child(spin)
	return row

func _style_field(field: Control) -> void:
	field.custom_minimum_size.x = FIELD_WIDTH
	field.add_theme_font_size_override("font_size", UiKit.BUTTON_FONT_SIZE)
