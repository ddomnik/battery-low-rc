extends Node
## Headless physics probe for the car acceptance checks. Builds the test arena, drives a car with
## scripted input through each scenario and prints measured numbers against the spec thresholds.
## Run: godot --headless --path . --fixed-fps 60 res://tests/car_probe.tscn

const TICK := 1.0 / 60.0
const ScriptedInput := preload("res://tests/scripted_input.gd")

var _car_scene: PackedScene = preload("res://car/car.tscn")
var _world: Node3D
var _car: Car
var _input: ScriptedInput
var _failures: int = 0
var _landings: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_world = Node3D.new()
	add_child(_world)
	var arena := Arena.new()
	arena.map = MapCatalog.load_map(MapCatalog.DEFAULT_ID)
	_world.add_child(arena)
	await get_tree().physics_frame
	await get_tree().physics_frame

	await _park_flat()
	await _acceleration()
	await _brake_and_reverse()
	await _ramp_climb("ramp A 14° (from foot)", Vector3(0.0, 0.0, 9.0), Vector3.FORWARD, 6.0)
	await _ramp_climb("ramp B 25° (from foot)", Vector3(18.5, 0.0, -12.0), Vector3.LEFT, 6.0)
	await _ramp_climb("ramp B 25° (stopped on slope)", Vector3(13.2, 0.0, -12.0), Vector3.LEFT, 6.0)
	await _ramp_climb("ramp C 35° (from foot)", Vector3(-17.5, 0.0, -12.0), Vector3.RIGHT, 8.0)
	await _ramp_climb("ramp C 35° (stopped on slope)", Vector3(-12.6, 0.0, -12.0), Vector3.RIGHT, 8.0)
	await _park_slope("park ramp A facing uphill", Vector3(0.0, 0.0, 0.0), Vector3.FORWARD, 0.2)
	await _park_slope("park ramp A facing downhill", Vector3(0.0, 0.0, 0.0), Vector3.BACK, 0.2)
	await _park_slope("park ramp B facing uphill", Vector3(13.2, 0.0, -12.0), Vector3.LEFT, 0.2)
	await _park_slope("park ramp B facing downhill", Vector3(13.2, 0.0, -12.0), Vector3.RIGHT, 0.2)
	await _park_slope("park side slope (sideways)", Vector3(28.0, 0.0, -32.0), Vector3.FORWARD, 0.2)
	await _side_slope_crossing()
	await _humps()
	await _kicker("hold")
	await _kicker("release")
	await _kicker("repress")
	await _table_drop()
	await _full_steer("from standstill", 0.0, 1.0)
	await _full_steer("at 8 m/s", 8.0, 1.0)
	await _full_steer("at full speed", 17.0, 1.0)
	await _drift()
	await _flip_recovery()
	await _manual_reset()
	# Directional drive (bots, M6): steer toward a world direction. Map: north = −Z, east = +X.
	var north := Vector3.FORWARD
	var east := Vector3.RIGHT
	var south := Vector3.BACK
	var west := Vector3.LEFT
	await _directional("east, car facing north, at rest", Vector3(-34.0, 0.8, -30.0), north, 0.0, east)
	await _directional("east, car facing south, at rest", Vector3(-34.0, 0.8, -30.0), south, 0.0, east)
	await _directional("east, car facing west (opposite), at rest", Vector3(-30.0, 0.8, -30.0), west, 0.0, east)
	await _directional("east, car facing north at 15 m/s", Vector3(-34.0, 0.8, -26.0), north, 15.0, east)
	await _directional("north-east, car facing south, at rest", Vector3(-34.0, 0.8, -22.0), south, 0.0, (north + east).normalized())
	await _directional("south-west, car facing east at 12 m/s", Vector3(-38.0, 0.8, -40.0), east, 12.0, (south + west).normalized())
	await _directional_uturn("at 15 m/s → handbrake U-turn", 15.0, true)
	await _directional_uturn("at 3 m/s → tight turn", 3.0, false)
	await _directional_wall("nose against the north wall, target east", east)
	await _directional_wall("nose against the north wall, target west", west)
	_world.queue_free()
	await get_tree().physics_frame
	await _match_session()

	print("\n%s: %d failing check(s)" % ["FAIL" if _failures > 0 else "PASS", _failures])
	get_tree().quit(1 if _failures > 0 else 0)

# --- Scenarios ---------------------------------------------------------------------------------

func _park_flat() -> void:
	_header("Parked on flat ground")
	_spawn(Vector3(25.0, 0.8, 25.0), Vector3.FORWARD, 0.0)
	await _ticks(60)
	var speed_1s := _car.linear_velocity.length()
	var p0 := _car.global_position
	var max_speed := 0.0
	for i in 120:
		await get_tree().physics_frame
		max_speed = maxf(max_speed, _car.linear_velocity.length())
	var drift := _car.global_position - p0
	drift.y = 0.0
	_check("speed after 1 s < 0.05 m/s", speed_1s, speed_1s < 0.05)
	_check("max speed 1..3 s < 0.05 m/s", max_speed, max_speed < 0.05)
	_check("horizontal creep 1..3 s < 0.02 m", drift.length(), drift.length() < 0.02)
	var tilt := rad_to_deg(acos(clampf(_car.global_basis.y.dot(Vector3.UP), -1.0, 1.0)))
	_check("body tilt < 1°", tilt, tilt < 1.0)
	var height := _car.global_position.y
	_info("origin height (expect ≈ 0.6 → sag ≈ 0.15)", height)
	_info("spring length per wheel (rest 0.35, expect ≈ 0.20)", _car.wheel_spring_len[0])
	_despawn()

func _acceleration() -> void:
	_header("Full throttle on flat ground")
	_spawn(Vector3(-40.0, 0.8, -42.0), Vector3.RIGHT, 0.0)
	await _ticks(30)
	_input.throttle = 1.0
	var t := 0.0
	var t15 := -1.0
	var t17 := -1.0
	var speed_2s := 0.0
	while t < 4.0:
		await get_tree().physics_frame
		t += TICK
		var v := _car.forward_speed
		if t15 < 0.0 and v >= 15.0:
			t15 = t
		if t17 < 0.0 and v >= 17.0:
			t17 = t
		if absf(t - 2.0) < TICK * 0.5:
			speed_2s = v
	_info("speed after 2 s (spec: ~18 m/s in about 2 s)", speed_2s)
	_info("time to 15 m/s", t15)
	_info("time to 17 m/s", t17)
	_info("speed after 4 s", _car.forward_speed)
	_check("reaches ≥ 15 m/s within 3 s", t15, t15 > 0.0 and t15 <= 3.0)
	_input.throttle = 0.0
	var v0 := _car.forward_speed
	await _ticks(60)
	_info("rolling decel over 1 s (spec rolling_decel 3)", v0 - _car.forward_speed)
	_despawn()
	# Rolling to a stop from moderate speed.
	_spawn(Vector3(-40.0, 0.8, -42.0), Vector3.RIGHT, 8.0)
	t = 0.0
	while t < 6.0 and _car.linear_velocity.length() > 0.05:
		await get_tree().physics_frame
		t += TICK
	_check("rolls to a stop from 8 m/s (< 6 s)", t, _car.linear_velocity.length() <= 0.05)
	_despawn()

func _brake_and_reverse() -> void:
	_header("Brake and reverse")
	_spawn(Vector3(-10.0, 0.8, -42.0), Vector3.RIGHT, 15.0)
	await _ticks(2)
	_input.throttle = -1.0
	var t := 0.0
	var start_x := _car.global_position.x
	while t < 3.0 and _car.forward_speed > 0.1:
		await get_tree().physics_frame
		t += TICK
	_info("brake time from 15 m/s (s)", t)
	_info("brake distance (m)", _car.global_position.x - start_x)
	_check("brakes to a stop from 15 m/s within 1.5 s", t, t < 1.5)
	await _ticks(180)
	_info("reverse speed after 3 s (max 11)", _car.forward_speed)
	_check("reverses (forward speed < -9)", _car.forward_speed, _car.forward_speed < -9.0)
	_despawn()

func _ramp_climb(label: String, pos: Vector3, facing: Vector3, limit: float) -> void:
	_header("Climb: " + label)
	_spawn_on_surface(pos, facing, 0.0)
	await _ticks(30)
	_input.throttle = 1.0
	var t := 0.0
	var reached := -1.0
	while t < limit:
		await get_tree().physics_frame
		t += TICK
		if _car.global_position.y > 3.3 and _car.grounded_count >= 2:
			reached = t
			break
	_info("speed at top (m/s)", _car.linear_velocity.length())
	_check("reaches the table top within %.0f s" % limit, reached, reached > 0.0)
	_despawn()

func _park_slope(label: String, pos: Vector3, facing: Vector3, limit: float) -> void:
	_header(label)
	_spawn_on_surface(pos, facing, 0.0)
	await _ticks(60)
	var p0 := _car.global_position
	var max_speed := 0.0
	for i in 120:
		await get_tree().physics_frame
		max_speed = maxf(max_speed, _car.linear_velocity.length())
	_check("max speed 1..3 s < %.2f m/s" % limit, max_speed, max_speed < limit)
	_info("displacement 1..3 s (m)", _car.global_position.distance_to(p0))
	_despawn()

func _side_slope_crossing() -> void:
	_header("Driving across the side slope at low speed")
	_spawn_on_surface(Vector3(28.0, 0.0, -27.0), Vector3.FORWARD, 0.0)
	await _ticks(30)
	_input.throttle = 0.12
	var x0 := _car.global_position.x
	var max_lat := 0.0
	for i in 150:
		await get_tree().physics_frame
		max_lat = maxf(max_lat, absf(_car.lateral_speed))
	_info("forward speed (m/s)", _car.forward_speed)
	_info("downhill drift over 2.5 s (m)", x0 - _car.global_position.x)
	_check("max lateral speed < 0.3 m/s", max_lat, max_lat < 0.3)
	_despawn()

func _humps() -> void:
	_header("Humps at full speed")
	_spawn(Vector3(38.0, 0.8, 30.0), Vector3.FORWARD, 18.0)
	_input.throttle = 1.0
	var min_up := 1.0
	var t := 0.0
	var spring_min := 1.0
	var spring_max := 0.0
	while t < 3.5:
		await get_tree().physics_frame
		t += TICK
		min_up = minf(min_up, _car.global_basis.y.dot(Vector3.UP))
		for i in Car.WHEELS:
			if _car.wheel_grounded[i]:
				spring_min = minf(spring_min, _car.wheel_spring_len[i])
				spring_max = maxf(spring_max, _car.wheel_spring_len[i])
	_info("z after 3.5 s (humps end at −18)", _car.global_position.z)
	_info("spring length range while grounded", "%.2f..%.2f" % [spring_min, spring_max])
	_check("never close to flipping (min up·Y > 0.5)", min_up, min_up > 0.5)
	_despawn()

## mode: "hold" = W held the whole time, "release" = W let go in the air,
## "repress" = W let go after takeoff and pressed again (air control should tilt the nose down).
func _kicker(mode: String) -> void:
	_header("Kicker at full speed, W: %s" % mode)
	_spawn(Vector3(-25.0, 0.8, 38.0), Vector3.FORWARD, 18.0)
	_input.throttle = 1.0
	var landings_before := _landings
	var max_y := 0.0
	var max_air := 0.0
	var t := 0.0
	var air_ticks := 0
	var landed_up := 0.0
	var first_contact_up := 0.0
	var min_up_in_air := 1.0
	var was_air := false
	while t < 3.0:
		await get_tree().physics_frame
		t += TICK
		max_y = maxf(max_y, _car.global_position.y)
		max_air = maxf(max_air, _car.air_time)
		var airborne := _car.grounded_count == 0
		if airborne:
			air_ticks += 1
		match mode:
			"release":
				_input.throttle = 0.0 if airborne else 1.0
			"repress":
				_input.throttle = 0.0 if airborne and air_ticks <= 6 else 1.0
		if airborne and _car.global_position.z < 18.5:   # past the kicker's lip
			was_air = true
			min_up_in_air = minf(min_up_in_air, _car.global_basis.y.dot(Vector3.UP))
		elif was_air and first_contact_up == 0.0:
			first_contact_up = _car.global_basis.y.dot(Vector3.UP)
		if was_air and _car.grounded_count == Car.WHEELS and landed_up == 0.0:
			landed_up = _car.global_basis.y.dot(Vector3.UP)
	_info("max origin height (m)", max_y)
	_check("clear jump (air time ≥ 0.35 s)", max_air, max_air >= 0.35)
	_info("lowest up·Y in the air", min_up_in_air)
	_info("up·Y at first wheel contact", first_contact_up)
	_info("up·Y when all four wheels touch down", landed_up)
	if mode == "repress":
		_check("re-pressed W tilts the nose down (lowest up·Y in air < 0.85)", min_up_in_air, min_up_in_air < 0.85)
	else:
		_check("lands nearly level (up·Y at first contact > 0.85)", first_contact_up, first_contact_up > 0.85)
	_info("perfect landing triggered (M5)", _landings > landings_before)
	_check("upright after 3 s", _car.global_basis.y.dot(Vector3.UP), _car.global_basis.y.dot(Vector3.UP) > 0.9)
	_despawn()

func _full_steer(label: String, speed: float, throttle: float) -> void:
	_header("Full steer: " + label)
	_spawn(Vector3(-30.0, 0.8, -12.0), Vector3.RIGHT, speed)
	_input.throttle = throttle
	_input.steer = 1.0
	var min_up := 1.0
	var yaw_sum := 0.0
	var lat_max := 0.0
	var samples := 0
	var yaw_trace: Array[float] = []
	for i in 90:
		await get_tree().physics_frame
		yaw_trace.append(_car.angular_velocity.y)
		min_up = minf(min_up, _car.global_basis.y.dot(Vector3.UP))
		if i >= 30:
			yaw_sum += _car.angular_velocity.y
			samples += 1
			lat_max = maxf(lat_max, absf(_car.lateral_speed))
	var yaw := yaw_sum / float(samples)
	var reach := -1.0
	for i in yaw_trace.size():
		if yaw_trace[i] >= 0.9 * yaw:
			reach = (i + 1) * TICK
			break
	_info("time to 90 % of the turn rate (s)", reach)
	var v := _car.linear_velocity.length()
	_info("speed (m/s)", v)
	_info("yaw rate (rad/s)", yaw)
	_info("turn radius (m)", v / maxf(absf(yaw), 0.001))
	_info("max sideways speed (m/s)", lat_max)
	_check("no rollover (min up·Y > 0.7)", min_up, min_up > 0.7)
	_despawn()

func _table_drop() -> void:
	_header("Drive off the table's north edge")
	_spawn(Vector3(0.0, 3.8, -8.0), Vector3.FORWARD, 8.0)
	_input.throttle = 0.5
	var max_air := 0.0
	var t := 0.0
	while t < 3.0:
		await get_tree().physics_frame
		t += TICK
		max_air = maxf(max_air, _car.air_time)
		if t > 1.5:
			_input.throttle = 0.0
	_info("air time (s)", max_air)
	_check("ends on the floor below", _car.global_position.y, _car.global_position.y < 1.0)
	_check("upright after landing", _car.global_basis.y.dot(Vector3.UP), _car.global_basis.y.dot(Vector3.UP) > 0.9)
	_despawn()

func _drift() -> void:
	_header("Handbrake + steer at speed")
	_spawn(Vector3(-32.0, 0.8, -40.0), Vector3.RIGHT, 15.0)
	_input.throttle = 1.0
	_input.steer = -1.0
	_input.handbrake = true
	var max_lat := 0.0
	var min_up := 1.0
	var max_yaw := 0.0
	for i in 60:
		await get_tree().physics_frame
		max_lat = maxf(max_lat, absf(_car.lateral_speed))
		min_up = minf(min_up, _car.global_basis.y.dot(Vector3.UP))
		max_yaw = maxf(max_yaw, absf(_car.angular_velocity.y))
	_input.handbrake = false
	_input.steer = 0.0
	for i in 60:
		await get_tree().physics_frame
		min_up = minf(min_up, _car.global_basis.y.dot(Vector3.UP))
	_check("rear slides out (max lateral speed > 3 m/s)", max_lat, max_lat > 3.0)
	_info("max yaw rate (rad/s)", max_yaw)
	_info("lateral speed 1 s after release", _car.lateral_speed)
	_check("no rollover (min up·Y > 0.7)", min_up, min_up > 0.7)
	_despawn()

func _flip_recovery() -> void:
	_header("Upside down: auto recovery")
	_spawn(Vector3(25.0, 1.2, 25.0), Vector3.FORWARD, 0.0, PI)
	var t := 0.0
	var recovered := -1.0
	while t < 4.0:
		await get_tree().physics_frame
		t += TICK
		if recovered < 0.0 and _car.global_basis.y.dot(Vector3.UP) > 0.95 and t > 0.2:
			recovered = t
	_check("back on its wheels within 2.5 s (spec ~1.2 s + settle)", recovered, recovered > 0.0 and recovered < 2.5)
	_check("upright after 4 s", _car.global_basis.y.dot(Vector3.UP), _car.global_basis.y.dot(Vector3.UP) > 0.9)
	_despawn()

func _manual_reset() -> void:
	_header("Reset (R) while on its side")
	_spawn(Vector3(25.0, 1.2, 25.0), Vector3.FORWARD, 0.0, PI * 0.5)
	await _ticks(60)
	_input.reset = true
	await _ticks(60)
	_check("upright 1 s after reset", _car.global_basis.y.dot(Vector3.UP), _car.global_basis.y.dot(Vector3.UP) > 0.9)
	_despawn()

## Directional drive: the car turns to and drives in the requested world direction.
func _directional(label: String, pos: Vector3, facing: Vector3, speed: float, move: Vector3) -> void:
	_header("Directional drive: " + label)
	_spawn(pos, facing, speed)
	_input.mode = CarInput.DriveMode.DIRECTIONAL
	_input.move = move
	var t := 0.0
	var aligned_at := -1.0
	var min_up := 1.0
	while t < 4.0:
		await get_tree().physics_frame
		t += TICK
		min_up = minf(min_up, _car.global_basis.y.dot(Vector3.UP))
		if aligned_at < 0.0 and _heading_error(move) < 10.0:
			aligned_at = t
		if aligned_at >= 0.0 and t > aligned_at + 0.4:
			break
	_info("heading error at end (deg)", _heading_error(move))
	_info("velocity direction error at end (deg)", _velocity_error(move))
	_check("faces the target direction (within 10°) in < 3 s", aligned_at, aligned_at > 0.0 and aligned_at < 3.0)
	_check("drives the target direction (velocity within 15°)", _velocity_error(move), _velocity_error(move) < 15.0)
	_check("no rollover (min up·Y > 0.7)", min_up, min_up > 0.7)
	_despawn()

## Directional drive: target behind. At speed → automatic handbrake U-turn, slow → tight turn.
func _directional_uturn(label: String, speed: float, expect_handbrake: bool) -> void:
	_header("Directional drive, target behind " + label)
	_spawn(Vector3(-30.0, 0.8, -42.0), Vector3.BACK, speed)   # driving south, then target north
	_input.mode = CarInput.DriveMode.DIRECTIONAL
	await _ticks(2)
	_input.move = Vector3.FORWARD
	var t := 0.0
	var aligned_at := -1.0
	var used_handbrake := false
	var min_up := 1.0
	var max_south := _car.global_position.z
	while t < 4.0:
		await get_tree().physics_frame
		t += TICK
		used_handbrake = used_handbrake or _car._drive.handbrake
		min_up = minf(min_up, _car.global_basis.y.dot(Vector3.UP))
		max_south = maxf(max_south, _car.global_position.z)
		if aligned_at < 0.0 and _heading_error(Vector3.FORWARD) < 15.0:
			aligned_at = t
		if aligned_at >= 0.0 and t > aligned_at + 0.3:
			break
	_info("time to face north (s)", aligned_at)
	_info("overshoot to the south (m)", max_south - (-42.0))
	_check("turns around within 2.5 s", aligned_at, aligned_at > 0.0 and aligned_at < 2.5)
	_check("automatic handbrake %s" % ("used" if expect_handbrake else "not used"), used_handbrake, used_handbrake == expect_handbrake)
	_check("no rollover (min up·Y > 0.7)", min_up, min_up > 0.7)
	_despawn()

## Directional drive: nose against a wall, sideways target → stuck assist frees the car.
func _directional_wall(label: String, move: Vector3) -> void:
	_header("Directional drive stuck assist: " + label)
	var start := Vector3(-30.0, 0.8, -43.85)
	_spawn(start, Vector3.FORWARD, 0.0)
	await _ticks(20)
	_input.mode = CarInput.DriveMode.DIRECTIONAL
	_input.move = move
	var t := 0.0
	var free_at := -1.0
	while t < 3.0:
		await get_tree().physics_frame
		t += TICK
		if _car.global_position.distance_to(start) > 2.0 and _heading_error(move) < 45.0:
			free_at = t
			break
	_check("free and heading the target way within 2 s (spec ~1.5 s)", free_at, free_at > 0.0 and free_at < 2.0)
	_despawn()

func _heading_error(dir: Vector3) -> float:
	var f := -_car.global_basis.z
	f.y = 0.0
	return rad_to_deg(f.normalized().angle_to(dir))

func _velocity_error(dir: Vector3) -> float:
	var v := _car.linear_velocity
	v.y = 0.0
	return rad_to_deg(v.normalized().angle_to(dir)) if v.length() > 0.5 else 180.0

func _match_session() -> void:
	_header("Match session: model hookup, debug tools, kill-height respawn")
	var m := (load("res://match/match.tscn") as PackedScene).instantiate() as Match
	add_child(m)
	var cfg := MatchConfig.new()
	cfg.bot_count = 0   # isolated tests; bots have their own probe
	m.setup(cfg)
	await _ticks(int(Match.COUNTDOWN_TIME * 60.0) + 5)   # cars are frozen during the countdown
	var car := m.local_car
	_check("local car spawned as Car_1", car.name, car.name == "Car_1")
	_check("Kenney model with 4 animated wheels", car.visual.has_node("WheelPivot3"), car.visual.has_node("WheelPivot3"))
	_press("debug_overlay")
	_press("debug_draw")
	await _ticks(30)
	var overlay := m.get_node("UI/DebugOverlay") as Label
	_check("F3 overlay visible with text", overlay.visible, overlay.visible and overlay.text.contains("grounded"))

	await _camera_follow(m)
	car.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0.0, -20.0, 0.0)))
	await _ticks(30)
	_check("respawned above the floor after falling below kill_y", car.global_position.y, car.global_position.y > 0.0)
	m.queue_free()
	await get_tree().physics_frame

## Follow camera: swings behind the nose with lag, settles when driving straight, holds while reversing,
## F2 switches to the fixed north-up camera and back.
func _camera_follow(m: Match) -> void:
	var car := m.local_car
	var rig := m.camera_rig
	var label := m.get_node("UI/Hud/ModeLabel") as Label
	_check("starts in follow mode (HUD)", label.text, rig.mode == CameraRig.Mode.FOLLOW and label.text.contains("Follow"))
	var scripted := ScriptedInput.new()
	scripted.car = car
	add_child(scripted)
	car.input_provider = scripted
	car.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-30.0, 0.8, -22.0)))   # open area, facing north
	await _ticks(45)
	rig.snap_to_target()
	_check("snap: camera behind the car", _cam_error(m), _cam_error(m) < 2.0)

	scripted.throttle = 1.0
	scripted.steer = 1.0
	var max_lag := 0.0
	for i in 120:
		await get_tree().physics_frame
		max_lag = maxf(max_lag, _cam_error(m))
	_info("max camera lag while circling at full steer (deg)", max_lag)
	_check("camera rotates along (lag < 60°)", max_lag, max_lag < 60.0)
	scripted.steer = 0.0
	# Straight run and reverse on a clear lane (z = -40, heading east) so no obstacle kicks the car around.
	car.teleport_to(Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), Vector3(-36.0, 0.8, -40.0)))
	await _ticks(90)
	_check("settles behind the car when driving straight (< 5°)", _cam_error(m), _cam_error(m) < 5.0)
	scripted.throttle = -1.0
	var max_rev := 0.0
	for i in 90:
		await get_tree().physics_frame
		max_rev = maxf(max_rev, _cam_error(m))
	_check("reversing doesn't swing the camera (< 5°)", max_rev, max_rev < 5.0)
	scripted.throttle = 0.0

	var saved_mode := Settings.camera_mode
	_press("debug_toggle_camera")
	await _ticks(150)
	_check("F2 → classic fixed camera turns to north-up", rad_to_deg(absf(wrapf(rig.rotation.y, -PI, PI))),
		rig.mode == CameraRig.Mode.FIXED and absf(wrapf(rig.rotation.y, -PI, PI)) < deg_to_rad(3.0)
		and label.text.contains("Classic") and Settings.camera_mode == CameraRig.Mode.FIXED)
	_press("debug_toggle_camera")
	await _ticks(150)
	_check("F2 again → follow, behind the car", _cam_error(m), rig.mode == CameraRig.Mode.FOLLOW and _cam_error(m) < 5.0)
	Settings.camera_mode = saved_mode
	Settings.save_settings()
	car.input_provider = m.local_input
	scripted.queue_free()

## Angle (deg) between the camera's view direction and the car's nose, on the ground plane.
func _cam_error(m: Match) -> float:
	var cam_fwd := -m.camera_rig.global_basis.z
	var car_fwd := -m.local_car.global_basis.z
	cam_fwd.y = 0.0
	car_fwd.y = 0.0
	return rad_to_deg(cam_fwd.normalized().angle_to(car_fwd.normalized()))

func _press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)

# --- Helpers -----------------------------------------------------------------------------------

func _spawn(pos: Vector3, facing: Vector3, speed: float, roll: float = 0.0) -> void:
	var b := Basis.looking_at(facing, Vector3.UP) * Basis(Vector3.BACK, roll)
	_spawn_xf(Transform3D(b, pos), facing * speed)

## Places the car on the surface under `pos`, aligned to the surface normal.
func _spawn_on_surface(pos: Vector3, facing: Vector3, speed: float) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 20.0, pos + Vector3.DOWN * 5.0, Layers.WORLD))
	var n: Vector3 = hit.normal
	var p: Vector3 = hit.position
	var fwd := (facing - n * facing.dot(n)).normalized()
	_spawn_xf(Transform3D(Basis.looking_at(fwd, n), p + n * 0.62), fwd * speed)

func _spawn_xf(xf: Transform3D, velocity: Vector3) -> void:
	_car = _car_scene.instantiate() as Car
	_car.transform = xf
	_car.linear_velocity = velocity
	_world.add_child(_car)
	_car.frozen = false
	_input = ScriptedInput.new()
	_input.car = _car
	_world.add_child(_input)
	_car.input_provider = _input
	_car.perfect_landing.connect(func(_c: Car) -> void: _landings += 1)

func _despawn() -> void:
	_car.queue_free()
	_input.queue_free()

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
