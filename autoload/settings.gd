extends Node
## Settings autoload: persisted user settings (user://settings.cfg).

const PATH := "user://settings.cfg"
const SECTION := "game"
const AUDIO := "audio"
const HUD := "hud"
const CONTROLS := "controls"

var camera_mode: CameraRig.Mode = CameraRig.Mode.FOLLOW
var bot_count: int = 5
var player_name: String = "Player"
var fullscreen: bool = false
var music_volume: float = 0.8           # 0..1, linear
var sfx_volume: float = 1.0             # 0..1, linear; effects and engines
var show_name_labels: bool = true
var game_mode: GameMode.Kind = GameMode.Kind.TIMED
var map_id: String = MapCatalog.DEFAULT_ID
var round_time: float = 180.0
var lives: int = 3
var bomb_time: float = 20.0
## Remapped controls: action → Array of encoded events ("key:<physical keycode>" / "mouse:<button>").
## Actions missing here use InputSetup's defaults.
var key_bindings: Dictionary = {}

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
	music_volume = clampf(float(cfg.get_value(AUDIO, "music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value(AUDIO, "sfx_volume", sfx_volume)), 0.0, 1.0)
	show_name_labels = bool(cfg.get_value(HUD, "show_name_labels", show_name_labels))
	var gm: int = cfg.get_value(SECTION, "game_mode", game_mode)
	game_mode = clampi(gm, 0, GameMode.Kind.size() - 1) as GameMode.Kind
	var mid := str(cfg.get_value(SECTION, "map", map_id))
	map_id = mid if MapCatalog.valid_id(mid) else MapCatalog.DEFAULT_ID
	round_time = clampf(float(cfg.get_value(SECTION, "round_time", round_time)), 30.0, 900.0)
	lives = clampi(int(cfg.get_value(SECTION, "lives", lives)), 1, 9)
	bomb_time = clampf(float(cfg.get_value(SECTION, "bomb_time", bomb_time)), 5.0, 120.0)
	var bindings: Variant = cfg.get_value(CONTROLS, "bindings", {})
	key_bindings = bindings if bindings is Dictionary else {}

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "camera_mode", camera_mode)
	cfg.set_value(SECTION, "bot_count", bot_count)
	cfg.set_value(SECTION, "player_name", player_name)
	cfg.set_value(SECTION, "fullscreen", fullscreen)
	cfg.set_value(AUDIO, "music_volume", music_volume)
	cfg.set_value(AUDIO, "sfx_volume", sfx_volume)
	cfg.set_value(HUD, "show_name_labels", show_name_labels)
	cfg.set_value(SECTION, "game_mode", game_mode)
	cfg.set_value(SECTION, "map", map_id)
	cfg.set_value(SECTION, "round_time", round_time)
	cfg.set_value(SECTION, "lives", lives)
	cfg.set_value(SECTION, "bomb_time", bomb_time)
	cfg.set_value(CONTROLS, "bindings", key_bindings)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [PATH, err])
