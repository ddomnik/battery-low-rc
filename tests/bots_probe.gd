extends Node
## Headless probe for bumping, scoring, the scoreboard and bots (M6), plus crash / blast spin.
## Run: godot --headless --path . --fixed-fps 60 res://tests/bots_probe.tscn

const ScriptedInput := preload("res://tests/scripted_input.gd")
const MATCH_SCENE: PackedScene = preload("res://match/match.tscn")
const TICK := 1.0 / 60.0

var _m: Match
var _car: Car
var _input: ScriptedInput
var _effects: Array[Dictionary] = []
var _bumps: Array[Dictionary] = []
var _failures: int = 0
var _next_id: int = 2

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await _start_match(0)
	await _ram("parked car, full speed", 18.0, false)
	await _ram("parked car, full speed, boosted", 18.0, true)
	await _low_speed_contact()
	await _hit_credit()
	await _crash_and_blast_spin()
	await _knockouts()
	await _camera_height_and_fullscreen()
	await _scoreboard_and_odds()
	_m.queue_free()
	await get_tree().physics_frame
	await _bots_match()

	print("\n%s: %d failing check(s)" % ["FAIL" if _failures > 0 else "PASS", _failures])
	get_tree().quit(1 if _failures > 0 else 0)

# --- Scenarios ---------------------------------------------------------------------------------

## Rams a parked car (no input, frozen) from behind... broadside: the victim faces east, the attacker drives north.
func _ram(label: String, speed: float, boosted: bool) -> void:
	_header("Ram a %s" % label)
	var victim := await _dummy(Vector3(-30.0, 0.8, -26.0), Vector3.RIGHT)
	await _place(Vector3(-30.0, 0.8, -14.0), Vector3.FORWARD, speed)
	_car.set_battery(1.0 if boosted else 0.0)
	_input.boost = boosted
	_input.throttle = 1.0
	_bumps.clear()
	var start := victim.global_position
	var rest_y := start.y
	var hop := 0.0
	for i in 150:
		await get_tree().physics_frame
		hop = maxf(hop, victim.global_position.y - rest_y)
		if i == 40:
			_input.throttle = 0.0
			_input.boost = false
	var moved := Vector2(victim.global_position.x - start.x, victim.global_position.z - start.z).length()
	var strength := _bump_strength(victim)
	_info("bump strength (velocity change, m/s)", strength)
	_info("victim pushed (m) / hop (m)", "%.1f / %.2f" % [moved, hop])
	_check("victim launched ≥ 2 car lengths (4 m) with a small hop", moved, moved >= 4.0 and hop > 0.1)
	_check("attacker credited", _m.scores.get(_car.player_id, 0), _m.scores.get(_car.player_id, 0) >= 1)
	_m.scores[_car.player_id] = 0
	_remove(victim)
	if boosted:
		_check("boosted ram is stronger (× bump_boost_mult)", strength, strength > 20.0)

func _low_speed_contact() -> void:
	_header("Low-speed contact")
	var victim := await _dummy(Vector3(-30.0, 0.8, -26.0), Vector3.RIGHT)
	await _place(Vector3(-30.0, 0.8, -22.5), Vector3.FORWARD, 2.0)
	_bumps.clear()
	_input.throttle = 0.1
	await _ticks(90)
	_input.throttle = 0.0
	_check("no bump below bump_min_speed (3 m/s)", _bumps.size(), _bumps.is_empty())
	_remove(victim)

## Credit rule: +1 to the attacker, at most once per second per victim.
func _hit_credit() -> void:
	_header("Hit credit")
	var victim := await _dummy(Vector3(-20.0, 0.8, -40.0), Vector3.RIGHT)
	_m.scores[_car.player_id] = 0
	_m._on_bumped(victim, _car, 10.0)
	await _ticks(30)
	_m._on_bumped(victim, _car, 10.0)
	_check("second hit within 1 s: not credited", _m.scores[_car.player_id], _m.scores[_car.player_id] == 1)
	await _ticks(40)
	_m._on_bumped(victim, _car, 10.0)
	_check("after 1 s: credited again", _m.scores[_car.player_id], _m.scores[_car.player_id] == 2)
	_m._on_bumped(victim, _car, 5.0)
	_check("weak bump (< bump_score_strength 7) never scores", _m.scores[_car.player_id], _m.scores[_car.player_id] == 2)
	_m.scores[_car.player_id] = 0
	_remove(victim)

func _crash_and_blast_spin() -> void:
	_header("Wall crash and blast: hop + slight spin")
	await _place(Vector3(-30.0, 0.8, -30.0), Vector3.FORWARD, 17.0)
	_input.throttle = 1.0
	var r := await _track_air(_car, 90, 15)
	_info("wall crash at 17 m/s: hop (m) / max tilt (deg) / max yaw rate (rad/s)", "%.2f / %.0f / %.1f" % [r[0], r[1], r[2]])
	_check("wall crash adds a visible hop (> 0.3 m) and some tilt (> 5°)", r[0], r[0] > 0.3 and r[1] > 5.0)
	await _ticks(60)
	_check("lands back on its wheels", _up(_car), _up(_car) > 0.9)

	var victim := await _dummy(Vector3(-30.0, 0.8, -36.0), Vector3.RIGHT)
	var balloon := _item(&"water_balloon")
	_m.explode(victim.global_position + Vector3(1.0, -0.6, 0.0), balloon.explosion_radius, balloon.knockback,
		balloon.up_knockback, _car, balloon.spin, balloon.tumble)
	var b := await _track_air(victim, 150, 0)
	_info("balloon 1 m from a car: hop (m) / max tilt (deg)", "%.2f / %.0f" % [b[0], b[1]])
	_check("blast tilts the car (> 10°) and it lands on its wheels", b[1], b[1] > 10.0 and _up(victim) > 0.9)
	_remove(victim)

## Knocking a car off the map: +10 for whoever hit it last (within 6 s); bots respawn like everyone else.
func _knockouts() -> void:
	_header("Knockouts (+10) and respawn")
	var victim := await _dummy(Vector3(-20.0, 0.8, -40.0), Vector3.RIGHT)
	_m.scores[_car.player_id] = 0
	_m._on_bumped(victim, _car, 10.0)                                   # +1 for the hit
	victim.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-20.0, -20.0, -40.0)))   # "falls off the map"
	await _ticks(20)
	_check("hit then fell off: +1 hit +10 knockout, victim respawned", _m.scores[_car.player_id],
		_m.scores[_car.player_id] == 11 and victim.global_position.y > 0.0)
	var popup_seen := _find_label(_m.get_node("UI/Hud"), "KNOCKOUT!") != null
	_check("KNOCKOUT! popup for the local attacker", popup_seen, popup_seen)

	_m.scores[_car.player_id] = 0
	victim.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-20.0, -20.0, -40.0)))
	await _ticks(20)
	_check("falling off without a recent hit scores nothing", _m.scores[_car.player_id], _m.scores[_car.player_id] == 0)

	_m.note_hit(_car, victim)
	await _ticks(int(Match.KNOCKOUT_CREDIT_TIME * 60.0) + 30)
	victim.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-20.0, -20.0, -40.0)))
	await _ticks(20)
	_check("a hit older than %.0f s gives no knockout" % Match.KNOCKOUT_CREDIT_TIME, _m.scores[_car.player_id], _m.scores[_car.player_id] == 0)
	_remove(victim)

	# The real thing: a boosted ram over the low south wall (0.6 m).
	var bot := await _dummy(Vector3(2.0, 0.8, 42.0), Vector3.RIGHT)
	await _place(Vector3(2.0, 0.8, 27.0), Vector3.BACK, 18.0)
	_car.set_battery(1.0)
	_input.boost = true
	_input.throttle = 1.0
	var fell := false
	var respawned := false
	for i in 300:
		await get_tree().physics_frame
		if i == 50:
			_input.boost = false
			_input.throttle = 0.0
		fell = fell or bot.global_position.y < -5.0
		respawned = respawned or (fell and bot.global_position.y > 0.0)
	_info("boosted ram toward the south wall: victim left the map / respawned", "%s / %s" % [fell, respawned])
	if fell:
		_check("knocked off: attacker gets the knockout", _m.scores[_car.player_id], _m.scores[_car.player_id] >= 10 and respawned)
	_m.scores[_car.player_id] = 0
	_remove(bot)

func _camera_height_and_fullscreen() -> void:
	_header("Camera height and fullscreen toggle")
	_m.set_camera_mode(CameraRig.Mode.FOLLOW)
	await _place(Vector3(0.0, 3.8, -12.0), Vector3.FORWARD, 0.0)   # on the table (3 m up)
	await _ticks(60)
	_check("camera height follows the car up onto the table (smoothly)", _m.camera_rig.global_position.y,
		_m.camera_rig.global_position.y > 2.0)
	_m.set_camera_mode(CameraRig.Mode.FIXED)
	var before := Settings.fullscreen
	_press("toggle_fullscreen")
	await _ticks(2)   # injected events are handled at the start of the next frame
	var toggled := Settings.fullscreen != before
	_press("toggle_fullscreen")
	await _ticks(2)
	_check("F11 toggles fullscreen (setting flips and flips back)", toggled, toggled and Settings.fullscreen == before)

func _find_label(root: Node, text: String) -> Label:
	if root is Label and (root as Label).text == text:
		return root as Label
	for c in root.get_children():
		var found := _find_label(c, text)
		if found != null:
			return found
	return null

func _scoreboard_and_odds() -> void:
	_header("Scoreboard and catch-up odds (debug overlay)")
	var other := await _dummy(Vector3(-20.0, 0.8, -40.0), Vector3.RIGHT)
	_press("debug_overlay")
	_press("debug_add_score")
	await _ticks(10)
	var overlay := _m.get_node("UI/DebugOverlay") as Label
	_check("F7 → leading: overlay shows rocket_trio 0%", overlay.text.contains("rocket_trio 0%"), overlay.text.contains("rocket_trio 0%"))
	_m.scores[other.player_id] = 5
	_m.scores_changed.emit()
	await _ticks(10)
	_check("last: overlay shows rocket_trio 40%", overlay.text.contains("rocket_trio 40%"), overlay.text.contains("rocket_trio 40%"))
	var table := _m.get_node("UI/Hud/Scoreboard/Table") as GridContainer
	var first_name := (table.get_child(1) as Label).text
	_check("scoreboard lists every car, leader first", first_name, table.get_child_count() == _m.cars.size() * 3 and first_name == other.display_name)
	_press("debug_overlay")
	_remove(other)

## A full match with 9 bots: physics time per tick and what the bots actually do.
func _bots_match() -> void:
	_header("9 bots, 25 s of play")
	await _start_match(9)
	_input.throttle = 0.0   # the local car just sits; bots chase it and each other
	_effects.clear()
	var samples := 0
	var speed_sum := 0.0
	var fired: Array[int] = [0]   # lambdas capture locals by value; an array is shared
	for c in _m.cars:
		c.item_used.connect(func(_c: Car, _i: ItemDef, _a: Vector3) -> void: fired[0] += 1)
	# Headless + --fixed-fps: Performance.TIME_PHYSICS_PROCESS is not meaningful here, so measure wall-clock time
	# per tick (physics + scripts, no rendering). The budget at 60 ticks/s is 16.7 ms.
	var t0 := Time.get_ticks_usec()
	for i in 1500:
		await get_tree().physics_frame
		samples += 1
		for c in _m.cars:
			if c != _car:
				speed_sum += c.linear_velocity.length()
	var per_tick := (Time.get_ticks_usec() - t0) / 1000.0 / samples
	var fired_items := fired[0]
	var pickups := _count(&"pickup")
	var bumps := _count(&"bump")
	var explosions := _count(&"explosion")
	_info("wall-clock time per tick, no rendering (ms, budget 16.7)", per_tick)
	_info("bots' average speed (m/s)", speed_sum / (samples * 9.0))
	_info("pickups / items used / explosions / bumps+crashes", "%d / %d / %d / %d" % [pickups, fired_items, explosions, bumps])
	_info("scores", _m.scores)
	_check("holds 60 ticks/s: < 5 ms per tick without rendering", per_tick, per_tick < 5.0)
	_check("bots drive around (avg speed > 4 m/s)", speed_sum / (samples * 9.0), speed_sum / (samples * 9.0) > 4.0)
	_check("bots pick up and use items", fired_items, pickups >= 5 and fired_items >= 3)

# --- Helpers -----------------------------------------------------------------------------------

func _start_match(bots: int) -> void:
	var cfg := MatchConfig.new()
	cfg.camera_mode = CameraRig.Mode.FIXED
	cfg.round_time = 600.0
	cfg.bot_count = bots
	cfg.rng_seed = 1234
	_m = MATCH_SCENE.instantiate() as Match
	add_child(_m)
	_m.setup(cfg)
	_m.effect_played.connect(func(kind: StringName, pos: Vector3, param: float) -> void:
		_effects.append({"kind": kind, "pos": pos, "param": param}))
	for c in _m.cars:
		c.bumped.connect(func(victim: Car, attacker: Car, strength: float) -> void:
			_bumps.append({"victim": victim, "attacker": attacker, "strength": strength}))
	await _ticks(int(Match.COUNTDOWN_TIME * 60.0) + 5)
	_car = _m.local_car
	_input = ScriptedInput.new()
	_input.car = _car
	add_child(_input)
	_car.input_provider = _input
	_next_id = bots + 2

## Returns [max hop above the start height, max tilt (deg), max |yaw rate|] over n ticks.
func _track_air(c: Car, n: int, skip: int) -> Array[float]:
	var rest_y := c.global_position.y
	var hop := 0.0
	var tilt := 0.0
	var yaw := 0.0
	for i in n:
		await get_tree().physics_frame
		if i < skip:
			continue
		hop = maxf(hop, c.global_position.y - rest_y)
		tilt = maxf(tilt, rad_to_deg(acos(clampf(_up(c), -1.0, 1.0))))
		yaw = maxf(yaw, absf(c.angular_velocity.y))
	_input.throttle = 0.0
	var out: Array[float] = [hop, tilt, yaw]
	return out

func _bump_strength(victim: Car) -> float:
	var best := 0.0
	for b in _bumps:
		if b["victim"] == victim:
			best = maxf(best, b["strength"])
	return best

func _place(pos: Vector3, facing: Vector3, speed: float) -> void:
	_input.throttle = 0.0
	_input.boost = false
	_car.teleport_to(Transform3D(Basis.looking_at(facing, Vector3.UP), pos))
	await _ticks(40)
	if speed > 0.0:
		_car.linear_velocity = facing * speed

## A parked, frozen car (spawned mid-round, so it stays frozen and its bot input is ignored).
func _dummy(pos: Vector3, facing: Vector3) -> Car:
	var c := _m.spawn_car({"player_id": _next_id, "peer_id": 1, "name": "Dummy %d" % _next_id,
		"color": Match.PLAYER_COLORS[_next_id % Match.PLAYER_COLORS.size()], "is_bot": true, "model_path": ""})
	c.bumped.connect(func(victim: Car, attacker: Car, strength: float) -> void:
		_bumps.append({"victim": victim, "attacker": attacker, "strength": strength}))
	_next_id += 1
	c.teleport_to(Transform3D(Basis.looking_at(facing, Vector3.UP), pos))
	await _ticks(30)
	return c

func _remove(c: Car) -> void:
	_m.cars.erase(c)
	_m.scores.erase(c.player_id)
	c.queue_free()

func _up(c: Car) -> float:
	return c.global_basis.y.dot(Vector3.UP)

func _item(id: StringName) -> ItemDef:
	for d in _m.item_defs:
		if d.id == id:
			return d
	return null

func _count(kind: StringName) -> int:
	var n := 0
	for e in _effects:
		if e["kind"] == kind:
			n += 1
	return n

func _press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)

func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _header(title: String) -> void:
	print("\n== %s" % title)

func _check(label: String, value: Variant, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("  [%s] %s: %s" % ["ok" if ok else "FAIL", label, _fmt(value)])

func _info(label: String, value: Variant) -> void:
	print("  [..] %s: %s" % [label, _fmt(value)])

func _fmt(value: Variant) -> String:
	if value is float:
		return "%.3f" % value
	return str(value)
