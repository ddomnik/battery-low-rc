extends Control
## Main menu: Play, bot count, camera mode, Quit. Values persist through Settings.
## Quit lives only here.

const CAMERA_OPTIONS: Array[String] = ["Follow (recommended)", "Classic (fixed)"]   # index = CameraRig.Mode

var _orphan_label: Label

func _ready() -> void:
	var box := UiKit.centered_column(self)
	UiKit.title(box, "BATTERY LOW!")

	var play := UiKit.button(box, "Play")
	play.pressed.connect(_on_play)

	var bots := SpinBox.new()
	bots.min_value = 0
	bots.max_value = MatchConfig.MAX_BOTS
	bots.step = 1
	bots.value = Settings.bot_count
	bots.custom_minimum_size.x = UiKit.BUTTON_SIZE.x - UiKit.ROW_LABEL_WIDTH - UiKit.SEPARATION
	bots.get_line_edit().add_theme_font_size_override("font_size", UiKit.BUTTON_FONT_SIZE)
	bots.value_changed.connect(_on_bots_changed)
	UiKit.row(box, "Bots").add_child(bots)

	var camera := OptionButton.new()
	for option in CAMERA_OPTIONS:
		camera.add_item(option)
	camera.select(Settings.camera_mode)
	camera.custom_minimum_size.x = bots.custom_minimum_size.x
	camera.add_theme_font_size_override("font_size", UiKit.BUTTON_FONT_SIZE)
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

func _on_bots_changed(value: float) -> void:
	Settings.bot_count = int(value)
	Settings.save_settings()

func _on_camera_selected(index: int) -> void:
	Settings.camera_mode = index as CameraRig.Mode
	Settings.save_settings()
