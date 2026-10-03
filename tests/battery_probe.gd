extends Node
## Headless probe for battery, boost, charging pads, perfect landing and their HUD / particles (M5).
## Runs a real Match (fixed camera) and drives the local car with scripted input.
## Run: godot --headless --path . --fixed-fps 60 res://tests/battery_probe.tscn

const ScriptedInput := preload("res://tests/scripted_input.gd")
const MATCH_SCENE: PackedScene = preload("res://match/match.tscn")
const TICK := 1.0 / 60.0

var _m: Match
var _car: Car
var _input: ScriptedInput
var _effects: Array[StringName] = []
var _effect_log: Array[Dictionary] = []
var _failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var cfg := MatchConfig.new()
	cfg.camera_mode = CameraRig.Mode.FIXED
	cfg.round_time = 600.0
	cfg.bot_count = 0   # isolated tests; bots have their own probe
	_m = MATCH_SCENE.instantiate() as Match
	add_child(_m)
	_m.setup(cfg)
	_m.effect_played.connect(func(kind: StringName, _pos: Vector3, param: float) -> void:
		_effects.append(kind)
		_effect_log.append({"kind": kind, "param": param}))
	await _ticks(int(Match.COUNTDOWN_TIME * 60.0) + 5)
	_car = _m.local_car
	_input = ScriptedInput.new()
	_input.car = _car
	add_child(_input)
	_car.input_provider = _input

	await _drift_charge()
	await _kicker_charge()
	await _wall_crash()
	await _pad_charge()
	await _boost()
	await _debug_keys()

	print("\n%s: %d failing check(s)" % ["FAIL" if _failures > 0 else "PASS", _failures])
	get_tree().quit(1 if _failures > 0 else 0)

# --- Scenarios ---------------------------------------------------------------------------------

func _drift_charge() -> void:
	_header("Drifting charges the battery (spec: ~7 s empty → full)")
	await _place(Vector3(-28.0, 0.8, -24.0), Vector3.RIGHT, 12.0)
	_car.set_battery(0.0)
	_input.throttle = 1.0
	_input.steer = 1.0
	_input.handbrake = true
	var t := 0.0
	var full_at := -1.0
	var drifting_ticks := 0
	var smoke_seen := false
	var battery_at_3s := 0.0
	while t < 10.0 and full_at < 0.0:
		await get_tree().physics_frame
		t += TICK
		if _car.is_drifting:
			drifting_ticks += 1
		smoke_seen = smoke_seen or (_car.visual.get_node("DriftSmoke2") as GPUParticles3D).emitting
		if absf(t - 3.0) < TICK * 0.5:
			battery_at_3s = _car.battery
		if _car.battery >= 0.999:
			full_at = t
	_input.throttle = 0.0
	_input.steer = 0.0
	_input.handbrake = false
	_info("share of time counted as drifting", "%.0f %%" % (100.0 * drifting_ticks / (t / TICK)))
	_info("battery after 3 s", battery_at_3s)
	_check("full after (s)", full_at, full_at > 5.0 and full_at < 9.0)
	_check("drift smoke emits while drifting", smoke_seen, smoke_seen)
	var bar := _m.get_node("UI/Hud/Battery/BatteryBar") as ProgressBar
	_check("HUD battery bar follows the battery", bar.value, is_equal_approx(bar.value, _car.battery))

	await _place(Vector3(-28.0, 0.8, -24.0), Vector3.RIGHT, 15.0)
	_input.throttle = 1.0
	_input.steer = 1.0
	_input.handbrake = true
	var corner := 0
	for i in 60:
		await get_tree().physics_frame
		corner += 1 if _car.is_drifting else 0
	_input.handbrake = false
	_input.steer = 0.0
	_check("1 s handbrake corner at 15 m/s counts as drifting most of the time", "%d %%" % (100 * corner / 60), corner > 40)

	await _place(Vector3(-30.0, 0.8, -12.0), Vector3.RIGHT, 17.0)
	_input.throttle = 1.0
	_input.steer = 1.0
	var plain := 0
	for i in 90:
		await get_tree().physics_frame
		plain += 1 if _car.is_drifting else 0
	_input.throttle = 0.0
	_input.steer = 0.0
	_check("full steer at full speed without handbrake does not count", plain, plain == 0)

func _kicker_charge() -> void:
	_header("Kicker jump: airtime charge, perfect landing needs a skilled landing")
	await _kicker_jump(false)
	_info("hands-off jump: battery after landing (airtime only)", _car.battery)
	_check("airtime gives some charge", _car.battery, _car.battery > 0.05)
	_check("hands-off landing is NOT perfect (harder now)", _effects.has(&"landing"), not _effects.has(&"landing"))

	await _kicker_jump(true)
	var reward := _car.last_landing_reward
	_info("piloted jump: reward share (0 at 0.35 s air … 1 at 1.2 s)", reward)
	_info("piloted jump: battery after landing", _car.battery)
	_check("leveling with W/S in the air earns a PERFECT LANDING! (effect + popup)", _effects.has(&"landing"),
		_effects.has(&"landing") and _find_label(_m.get_node("UI/Hud"), "PERFECT LANDING!") != null)
	var t := _car.tuning
	_check("reward share grows with airtime (0.35 s → 0, 0.775 s → 0.5, 1.2 s+ → 1)", _car.landing_reward_fraction(0.775),
		is_zero_approx(_car.landing_reward_fraction(t.min_air_time_for_landing))
		and is_equal_approx(_car.landing_reward_fraction(0.775), 0.5)
		and is_equal_approx(_car.landing_reward_fraction(2.0), 1.0))

## Kicker at full speed. pilot = level the car in the air with re-pressed W/S (W = nose down, S = nose up).
func _kicker_jump(pilot: bool) -> void:
	await _place(Vector3(-25.0, 0.8, 38.0), Vector3.FORWARD, 18.0)
	_car.set_battery(0.0)
	_effects.clear()
	_input.throttle = 1.0
	var air_ticks := 0
	for i in 150:
		await get_tree().physics_frame
		if _car.grounded_count > 0 or _car.global_position.z > 18.5:
			_input.throttle = 1.0 if air_ticks == 0 else 0.0
			continue
		air_ticks += 1
		_input.throttle = 0.0
		if pilot and air_ticks > 4:   # release first: keys held at takeoff need a re-press
			var pitch := (-_car.global_basis.z).y   # > 0: nose up
			_input.throttle = 1.0 if pitch > 0.03 else (-1.0 if pitch < -0.03 else 0.0)
	_input.throttle = 0.0

func _wall_crash() -> void:
	_header("Wall crash kickback")
	await _place(Vector3(-30.0, 0.8, -30.0), Vector3.FORWARD, 17.0)   # north wall at z = -45
	_effect_log.clear()
	_input.throttle = 1.0
	var bounce := 0.0
	var crash_param := 0.0
	for i in 120:
		await get_tree().physics_frame
		bounce = maxf(bounce, _car.linear_velocity.z)   # +z = away from the north wall
	_input.throttle = 0.0
	for e: Dictionary in _effect_log:
		if e["kind"] == &"bump":
			crash_param = maxf(crash_param, e["param"])
	_info("impact speed of the first hit (m/s)", crash_param)
	_info("bounce-back speed (m/s)", bounce)
	_check("head-on at ~17 m/s: sparks + strong kickback (> 8 m/s back)", bounce, crash_param > 12.0 and bounce > 8.0)

	await _place(Vector3(-30.0, 0.8, -42.5), Vector3.FORWARD, 3.5)   # coasts into the wall at ~3 m/s
	_effect_log.clear()
	await _ticks(90)
	_input.throttle = 0.0
	_check("slow bump into the wall (3 m/s): no kickback", _effect_log.size(), not _has_effect(&"bump"))

	await _place(Vector3(-40.0, 0.8, -43.2), Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(8.0)), 16.0)
	_effect_log.clear()
	_input.throttle = 1.0
	await _ticks(60)
	_input.throttle = 0.0
	_check("glancing along the wall (8°, 16 m/s): no kickback", _effect_log.size(), not _has_effect(&"bump"))

func _has_effect(kind: StringName) -> bool:
	for e: Dictionary in _effect_log:
		if e["kind"] == kind:
			return true
	return false

func _pad_charge() -> void:
	_header("Charging pad: fills in ~3 s, only while nearly stopped")
	await _place(Vector3(-36.0, 0.8, -36.0), Vector3.FORWARD, 0.0)
	_car.set_battery(0.0)
	var t := 0.0
	var full_at := -1.0
	while t < 5.0 and full_at < 0.0:
		await get_tree().physics_frame
		t += TICK
		if _car.battery >= 0.999:
			full_at = t
	_check("parked on the pad: full after (s)", full_at, full_at > 2.8 and full_at < 3.8)
	await _place(Vector3(-44.0, 0.8, -36.0), Vector3.RIGHT, 10.0)
	_car.set_battery(0.0)
	_input.throttle = 0.3
	var crossed := false
	for i in 90:
		await get_tree().physics_frame
		crossed = crossed or _car.pad_overlaps > 0
	_input.throttle = 0.0
	_check("driving across at speed: no charge", _car.battery, crossed and _car.battery < 0.01)

func _boost() -> void:
	_header("Boost: ~2.5 s of boost, clear speed gain")
	await _place(Vector3(-42.0, 0.8, -42.0), Vector3.RIGHT, 16.5)
	_input.throttle = 1.0
	await _ticks(10)
	var plain := _car.forward_speed
	_car.set_battery(1.0)
	_input.boost = true
	var t := 0.0
	var empty_at := -1.0
	var top := 0.0
	var flame_seen := false
	while t < 4.0 and empty_at < 0.0:
		await get_tree().physics_frame
		t += TICK
		top = maxf(top, _car.forward_speed)
		flame_seen = flame_seen or (_car.visual.get_node("BoostFlame") as GPUParticles3D).emitting
		if _car.battery <= 0.0:
			empty_at = t
	_input.boost = false
	_input.throttle = 0.0
	_info("speed before boosting (m/s)", plain)
	_info("top speed while boosting (m/s)", top)
	_check("drains in ~2.5 s", empty_at, empty_at > 2.2 and empty_at < 2.8)
	_check("clear speed gain (> +4 m/s)", top - plain, top - plain > 4.0)
	_check("boost flame emits while boosting", flame_seen, flame_seen)
	await _ticks(5)
	_check("no boost with an empty battery", _car.is_boosting, not _car.is_boosting)

func _debug_keys() -> void:
	_header("Debug keys")
	_car.set_battery(0.0)
	_press("debug_fill_battery")
	await get_tree().physics_frame
	_check("F6 fills the battery", _car.battery, is_equal_approx(_car.battery, 1.0))
	var score0: int = _m.scores.get(_car.player_id, 0)
	_press("debug_add_score")
	await get_tree().physics_frame
	_check("F7 adds a point and shows +1", _m.scores[_car.player_id],
		_m.scores[_car.player_id] == score0 + 1 and _find_label(_m.get_node("UI/Hud"), "+1") != null)

# --- Helpers -----------------------------------------------------------------------------------

func _place(pos: Vector3, facing: Vector3, speed: float) -> void:
	_input.throttle = 0.0
	_input.steer = 0.0
	_input.handbrake = false
	_input.boost = false
	_car.teleport_to(Transform3D(Basis.looking_at(facing, Vector3.UP), pos))
	await _ticks(40)
	if speed > 0.0:
		_car.linear_velocity = facing * speed

func _find_label(root: Node, text: String) -> Label:
	if root is Label and (root as Label).text == text:
		return root as Label
	for c in root.get_children():
		var found := _find_label(c, text)
		if found != null:
			return found
	return null

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
