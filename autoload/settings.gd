extends Node
## Settings autoload: persisted user settings (user://settings.cfg).

const PATH := "user://settings.cfg"
const SECTION := "game"

var camera_mode: CameraRig.Mode = CameraRig.Mode.FOLLOW
var bot_count: int = 5
var player_name: String = "Player"
var fullscreen: bool = false

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var mode: int = cfg.get_value(SECTION, "camera_mode", camera_mode)
	camera_mode = clampi(mode, 0, CameraRig.Mode.size() - 1) as CameraRig.Mode
	var bots: int = cfg.get_value(SECTION, "bot_count", bot_count)
	bot_count = clampi(bots, 0, MatchConfig.MAX_BOTS)
	player_name = str(cfg.get_value(SECTION, "player_name", player_name))
	fullscreen = bool(cfg.get_value(SECTION, "fullscreen", fullscreen))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "camera_mode", camera_mode)
	cfg.set_value(SECTION, "bot_count", bot_count)
	cfg.set_value(SECTION, "player_name", player_name)
	cfg.set_value(SECTION, "fullscreen", fullscreen)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [PATH, err])
