class_name MatchConfig
extends RefCounted
## Everything needed to start a match. Built by the main menu or by command-line autostart.

const MAX_BOTS := 9

var bot_count: int = 5
var camera_mode: CameraRig.Mode = CameraRig.Mode.FOLLOW
var round_time: float = 180.0
var player_name: String = "Player"
var rng_seed: int = 0               # 0 = random. Spec calls this `seed`, which would shadow the built-in seed().
var car_model_path: String = ""     # empty = auto

static func from_settings() -> MatchConfig:
	var c := MatchConfig.new()
	c.bot_count = Settings.bot_count
	c.camera_mode = Settings.camera_mode
	c.player_name = Settings.player_name
	return c

func copy() -> MatchConfig:
	var c := MatchConfig.new()
	c.bot_count = bot_count
	c.camera_mode = camera_mode
	c.round_time = round_time
	c.player_name = player_name
	c.rng_seed = rng_seed
	c.car_model_path = car_model_path
	return c
