extends Node
## Headless probe for the game modes: plays each mode with 9 bots (fixed 60 ticks/s) and checks eliminations,
## respawns, mode visuals, spectating, the round end and the podium.
## Run: godot --headless --path . --fixed-fps 60 res://tests/modes_probe.tscn

const MATCH_SCENE: PackedScene = preload("res://match/match.tscn")
const MAX_TICKS := 60 * 240          # give up after 4 minutes of game time

var _failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await _timed()
	await _last_on_table()
	await _lives()
	await _sticky_bomb()
	print("\n%s: %d failing check(s)" % ["FAIL" if _failures > 0 else "PASS", _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _timed() -> void:
	_header("Time deathmatch")
	var m := await _start(GameMode.Kind.TIMED, 25.0)
	var ended := await _play(m, 60 * 30)
	_check("ends when the round timer runs out (25 s)", ended, ended and m.time_left <= 0.0)
	_check("nobody is ever eliminated", m.eliminated_order.size(), m.eliminated_order.is_empty())
	await _finish(m)

func _last_on_table() -> void:
	_header("Last on table")
	var m := await _start(GameMode.Kind.LAST_ON_TABLE, 600.0)
	_check("arena has no outer walls", m.arena.with_walls, not m.arena.with_walls)
	var victim := m.cars[3]
	victim.teleport_to(Transform3D(Basis.IDENTITY, Vector3(60.0, 5.0, 0.0)))   # off the map
	await _ticks(150)
	_check("falling off = out, no respawn", victim.eliminated,
		victim.eliminated and not m.eliminated_order.is_empty() and m.eliminated_order[0] == victim)
	m.eliminate(m.local_car)
	await _ticks(2)
	var watched := m.camera_rig.target
	_check("local player out → spectating another car", watched.display_name,
		watched != m.local_car and not watched.eliminated)
	var first_name := m.cars[3].display_name
	var sent := 0
	var alive := m.alive_cars()
	for i in range(1, alive.size()):   # everyone but one goes over the edge
		alive[i].teleport_to(Transform3D(Basis.IDENTITY, Vector3(60.0 + i * 6.0, 5.0, 0.0)))
		sent += 1
	var ended := await _play(m, 60 * 20)
	_check("ends with one car left", m.eliminated_order.size(), ended and m.eliminated_order.size() == m.cars.size() - 1)
	var ranking := m.get_ranking()
	_check("ranking: survivor first, first out last", "%s … %s" % [ranking[0].display_name, ranking.back().display_name],
		not m.eliminated_order.has(ranking[0]) and ranking.back().display_name == first_name)
	await _finish(m)

func _lives() -> void:
	_header("Deathmatch (lives)")
	var m := await _start(GameMode.Kind.LIVES, 600.0, 2)
	var balloons := m.local_car.visual.find_children("Balloon*", "Node3D", false, false).size()
	_check("2 lives → 2 balloons on the car", balloons, balloons == 2)
	var victim := m.cars[2]
	m.register_hit(m.cars[1], victim)
	await _ticks(2)
	_check("a scoring hit pops a balloon", m.mode.score_text(victim), m.mode.score_text(victim) == "1")
	m.register_hit(m.cars[4], victim)
	await _ticks(2)
	_check("safe for a moment after a pop", m.mode.score_text(victim), m.mode.score_text(victim) == "1")
	await _ticks(100)
	victim.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0.0, -20.0, 0.0)))
	await _ticks(10)
	_check("falling off pops the last balloon → out", victim.eliminated, victim.eliminated)
	var ended := await _play(m, MAX_TICKS)
	_info("cars out when the round ended", m.eliminated_order.size())
	_check("bots play it out: ends with one car left", m.eliminated_order.size(), ended and m.eliminated_order.size() == m.cars.size() - 1)
	await _finish(m)

func _sticky_bomb() -> void:
	_header("Sticky bomb")
	var fuse := 6.0
	var m := await _start(GameMode.Kind.STICKY_BOMB, 600.0, 3, fuse)
	var bomb := m.mode as StickyBombMode
	_check("a car holds the bomb after GO", bomb.holder != null, bomb.holder != null)
	var passes := 0
	var last := bomb.holder
	var first_out_at := -1.0
	var t0 := m.time
	for i in 60 * 20:
		await get_tree().physics_frame
		if bomb.holder != last and bomb.holder != null and last != null and not last.eliminated:
			passes += 1
		last = bomb.holder
		if first_out_at < 0.0 and not m.eliminated_order.is_empty():
			first_out_at = m.time - t0
	_info("hand-overs in 20 s", passes)
	_check("the holder is out when the fuse (%.0f s) runs out" % fuse, first_out_at,
		first_out_at > fuse - 0.2 and first_out_at < fuse + 0.3)
	var ended := await _play(m, MAX_TICKS)
	_check("ends with one car left", m.eliminated_order.size(), ended and m.eliminated_order.size() == m.cars.size() - 1)
	await _finish(m)

# --- Helpers -----------------------------------------------------------------------------------

func _start(kind: GameMode.Kind, round_time: float, lives: int = 3, bomb_time: float = 20.0) -> Match:
	var cfg := MatchConfig.new()
	cfg.game_mode = kind
	cfg.bot_count = 9
	cfg.round_time = round_time
	cfg.lives = lives
	cfg.bomb_time = bomb_time
	cfg.rng_seed = 7
	var m := MATCH_SCENE.instantiate() as Match
	add_child(m)
	m.setup(cfg)
	await _ticks(int(Match.COUNTDOWN_TIME * 60.0) + 5)
	return m

## Plays until the results start or max_ticks pass. True if the round ended.
func _play(m: Match, max_ticks: int) -> bool:
	for i in max_ticks:
		if m.state == Match.State.RESULTS:
			return true
		await get_tree().physics_frame
	return m.state == Match.State.RESULTS

## Ceremony sanity check, then free the match.
func _finish(m: Match) -> void:
	if m.state == Match.State.RESULTS:
		await _ticks(120)
		var all_back := true
		for c in m.cars:
			all_back = all_back and not c.eliminated and c.visible
		_check("podium: everyone is back for the ceremony", all_back, all_back)
	m.queue_free()
	await _ticks(2)

func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _header(title: String) -> void:
	print("\n== %s" % title)

func _check(label: String, value: Variant, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("  [%s] %s: %s" % ["ok" if ok else "FAIL", label, str(value)])

func _info(label: String, value: Variant) -> void:
	print("  [..] %s: %s" % [label, str(value)])
