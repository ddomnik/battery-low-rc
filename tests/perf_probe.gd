extends Node
## Physics cost per tick with N bots (no rendering). Reports Godot's TIME_PHYSICS_PROCESS and wall-clock time.
## Run: godot --headless --path . --fixed-fps 60 res://tests/perf_probe.tscn

const MATCH_SCENE: PackedScene = preload("res://match/match.tscn")
const TICKS := 600

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	for bots: int in [0, 1, 4, 9]:
		var cfg := MatchConfig.new()
		cfg.bot_count = bots
		cfg.round_time = 600.0
		cfg.rng_seed = 99
		var m := MATCH_SCENE.instantiate() as Match
		add_child(m)
		m.setup(cfg)
		for i in 200:
			await get_tree().physics_frame
		var total := 0.0
		var worst := 0.0
		var t0 := Time.get_ticks_usec()
		for i in TICKS:
			await get_tree().physics_frame
			var t := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			total += t
			worst = maxf(worst, t)
		var wall := (Time.get_ticks_usec() - t0) / 1000.0 / TICKS
		print("bots=%d  physics avg %.2f ms  worst %.2f ms  wall-clock per tick %.2f ms" % [bots, total / TICKS, worst, wall])
		m.queue_free()
		await get_tree().physics_frame
	get_tree().quit()
