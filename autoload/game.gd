extends Node
## Game autoload: app state machine. Starts, exits and restarts matches through the registered Main.

enum State { BOOT, MENU, MATCH }

const TOAST_LAYER := 100
const TOAST_FONT_SIZE := 22
const TOAST_MARGIN := 24
const TOAST_TIME := 3.5
const TOAST_FADE := 0.6

var state: State = State.BOOT
var audio: AudioDirector = null   # music, interface and positional sounds
var current_config: MatchConfig = null

var _main: Main = null

func _ready() -> void:
	audio = AudioDirector.new()
	audio.name = "Audio"
	add_child(audio)
	_apply_window_mode()
	_handle_cmdline.call_deferred()

## F11 toggles fullscreen anywhere (menus and matches); the choice is saved.
## A game embedded in the editor's Game view can't change its window mode, so it only gets a hint.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		get_viewport().set_input_as_handled()
		if Engine.is_embedded_in_editor():
			_show_toast("Fullscreen isn't available while the game runs embedded in the editor.\nRun it in its own window (Game tab ⋮ menu → untick \"Embed Game on Next Play\").")
			return
		Settings.fullscreen = not Settings.fullscreen
		Settings.save_settings()
		_apply_window_mode()

## Short message at the top of the screen, above every menu; fades out on its own.
func _show_toast(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = TOAST_LAYER
	add_child(layer)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", TOAST_FONT_SIZE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, TOAST_MARGIN)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	var tw := label.create_tween()
	tw.tween_interval(TOAST_TIME)
	tw.tween_property(label, "modulate:a", 0.0, TOAST_FADE)
	tw.tween_callback(layer.queue_free)

func _apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if Settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

## Called by Main in its _ready.
func register_main(main: Main) -> void:
	_main = main
	state = State.MENU

func start_match(config: MatchConfig) -> void:
	if _main == null:
		push_error("Game.start_match: no Main registered")
		return
	current_config = config
	state = State.MATCH
	_main.show_match(config)

func exit_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	state = State.MENU
	if _main != null:
		_main.show_menu()

## Exits and starts again with the same config (exercises the cleanup path).
func restart_match() -> void:
	if current_config == null:
		return
	var config := current_config.copy()
	exit_to_menu()
	start_match(config)

## Only offered by the main menu.
func quit_app() -> void:
	get_tree().quit()

## Headless smoke tests: `-- --autostart --bots=N --camera=follow|fixed --round=SECONDS`.
func _handle_cmdline() -> void:
	var autostart := false
	var config := MatchConfig.from_settings()
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--autostart":
			autostart = true
		elif arg.begins_with("--bots="):
			config.bot_count = clampi(arg.get_slice("=", 1).to_int(), 0, MatchConfig.MAX_BOTS)
		elif arg.begins_with("--camera="):
			var mode := arg.get_slice("=", 1)
			if mode == "follow":
				config.camera_mode = CameraRig.Mode.FOLLOW
			elif mode == "fixed":
				config.camera_mode = CameraRig.Mode.FIXED
			else:
				push_warning("Game: unknown --camera value '%s' (use follow|fixed)" % mode)
		elif arg.begins_with("--round="):
			config.round_time = maxf(1.0, arg.get_slice("=", 1).to_float())
		else:
			push_warning("Game: unknown command-line argument '%s'" % arg)
	if autostart:
		print("Game: autostart (bots=%d, camera=%s, round=%.0f s)" % [
			config.bot_count, CameraRig.Mode.keys()[config.camera_mode], config.round_time])
		start_match(config)
