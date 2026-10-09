extends Node
## Headless probe for fluids (water, lava, mud …): map parsing, car physics in fluids, damage per mode, deadly
## fluids, currents, wet tyres, bots avoiding lava, editor export. Writes a temporary map, removes it at the end.
## Run: godot --headless --path . --fixed-fps 60 res://tests/fluids_probe.tscn

const ScriptedInput := preload("res://tests/scripted_input.gd")
const MATCH_SCENE: PackedScene = preload("res://match/match.tscn")
const MAP_ID := "zz_probe_fluids"

var _failures: int = 0
var _m: Match = null
var _car: Car = null
var _input: ScriptedInput = null
var _effects: Array[StringName] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_write_map()
	_header("Map data")
	var errors: Array[String] = []
	var map := MapCatalog.load_map(MAP_ID)
	_check("fluid map loads", errors, map != null)
	var lava := _fluid(map, "lava")
	_check("presets fill in missing values (lava: 3 damage per 100 ms, glows)", lava.get("damage"), lava.get("damage") == 3.0)
	var tilted := MapLoader.parse(JSON.stringify({"format": 1, "spawns": [{"pos": [0, 0, 0]}, {"pos": [3, 0, 0]}],
		"objects": [{"type": "fluid", "rot": [40, 30, 20], "size": [5, 1, 5], "damage": 9999, "current": [500, 0]}]}), "t", errors)
	var basis: Basis = tilted.objects[0]["transform"].basis
	_check("fluids stay level (only the yaw is used) and values are clamped", "%s, damage %s" % [basis.y, tilted.objects[0]["damage"]],
		basis.y.is_equal_approx(Vector3.UP) and tilted.objects[0]["damage"] == 100.0
		and (tilted.objects[0]["current"] as Vector2).length() <= MapLoader.MAX_CURRENT + 0.01)

	_header("Driving through water")
	await _start(GameMode.Kind.TIMED)
	await _place(Vector3(-20.0, 0.8, -12.0), Vector3.FORWARD)   # shallow water ahead (z −26 … −14)
	_input.throttle = 1.0
	var top_in_water := 0.0
	var splash := false
	for i in 150:
		await get_tree().physics_frame
		if _car.fluid != null and _car.fluid_contact >= 1.0:
			top_in_water = maxf(top_in_water, _car.linear_velocity.length())
		splash = splash or _effects.has(&"fluid_splash")
	_check("water slows the car (top speed × %.1f)" % _fluid(map, "water")["slow"], top_in_water,
		top_in_water > 1.0 and top_in_water < _car.tuning.max_speed * 0.8)
	_check("driving in splashes", splash, splash)
	_input.throttle = 0.0
	await _place(Vector3(-20.0, 0.8, -20.0), Vector3.BACK)
	_input.throttle = 1.0
	await _ticks(130)
	_input.throttle = 0.0
	_check("tyres leave wet tracks after driving out", "%s, out %s" % [_car.wheel_wet, _car.fluid == null],
		_car.fluid == null and _car.wheel_wet.max() > 0.0)

	_header("Floating and sinking")
	await _place(Vector3(20.0, 2.0, -20.0), Vector3.FORWARD)   # deep water, buoyancy 1.4
	await _ticks(150)
	var floats := _car.global_position.y
	await _place(Vector3(20.0, 2.0, 20.0), Vector3.FORWARD)    # deep mud, buoyancy 0.3
	await _ticks(150)
	var sinks := _car.global_position.y
	_check("buoyant water keeps the car up, mud lets it sink to the floor (height m)", "%.2f / %.2f" % [floats, sinks],
		floats > 2.5 and sinks < 1.0)

	_header("Current")
	await _place(Vector3(-4.0, 0.8, -32.0), Vector3.FORWARD)
	var start_x := _car.global_position.x
	await _ticks(60)
	_check("a current pushes a car without throttle (m along +X in 1 s)", _car.global_position.x - start_x,
		_car.global_position.x - start_x > 1.0)

	_header("Lava damage per game mode")
	await _place(Vector3(-20.0, 0.8, 20.0), Vector3.FORWARD)
	_car.set_battery(1.0)
	await _ticks(30)
	_check("time deathmatch: lava drains the battery", _car.battery, _car.battery < 0.9)
	_finish()

	await _start(GameMode.Kind.LAST_ON_TABLE, 1)   # one parked bot: alone, the round would be over at once
	await _place(Vector3(-20.0, 0.8, 20.0), Vector3.FORWARD)
	await _ticks(30)
	_check("last on table: lava raises the damage %", _m.mode.score_text(_car), _car.knockback_multiplier > 1.05)
	await _place(Vector3(0.0, 0.8, 30.0), Vector3.FORWARD)    # deadly lava
	await _ticks(10)
	# (being out leaves one car, so the round ends and the podium brings everyone back: check the record)
	_check("last on table: deadly lava = out", _m.eliminated_order.has(_car), _m.eliminated_order.has(_car))
	_finish()

	await _start(GameMode.Kind.LIVES)
	await _place(Vector3(-20.0, 0.8, 20.0), Vector3.FORWARD)
	await _ticks(40)
	_check("deathmatch: lava pops a balloon", _m.mode.score_text(_car), _m.mode.score_text(_car).begins_with("2 lives"))
	_finish()

	await _start(GameMode.Kind.TIMED)
	var spawn := _car.global_position
	await _place(Vector3(0.0, 0.8, 30.0), Vector3.FORWARD)
	await _ticks(10)
	_check("deadly lava respawns the car (time deathmatch)", _car.global_position.distance_to(spawn), _car.global_position.distance_to(spawn) < 3.0)
	_finish()

	_header("Bots keep out of lava")
	await _start(GameMode.Kind.TIMED, 4, true)
	var bot_ticks := 0
	var lava_ticks := 0
	for i in 60 * 15:
		await get_tree().physics_frame
		for c in _m.cars:
			if c == _m.local_car:
				continue
			bot_ticks += 1
			if c.fluid != null and c.fluid.harmful() and c.fluid_contact > 0.0:
				lava_ticks += 1
	_check("bots spend < 3 % of their time in lava (15 s)", "%.1f %%" % (100.0 * lava_ticks / maxi(bot_ticks, 1)),
		float(lava_ticks) / maxi(bot_ticks, 1) < 0.03)
	_finish()

	_header("Editor export")
	var src := MapSource.new()
	src.map_id = MAP_ID
	add_child(src)
	var f := MapFluid.new()
	f.preset = MapFluid.Preset.LAVA
	f.apply_preset()
	f.kill = true
	f.current = Vector2(2.0, 0.0)
	src.add_child(f)
	f.position = Vector3(3.0, 0.5, -4.0)
	f.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	var warnings: Array[String] = []
	var d := MapSourceIO.to_dict(src, warnings)
	var o: Dictionary = (d["objects"] as Array)[0] if not (d["objects"] as Array).is_empty() else {}
	_check("MapFluid exports with its preset values", o,
		o.get("type") == "fluid" and o.get("preset") == "lava" and o.get("damage") == 3.0 and o.get("kill") == true
		and absf(float((o.get("rot") as Array)[1]) - 45.0) < 0.01)
	src.queue_free()

	DirAccess.remove_absolute("res://maps/%s/map.json" % MAP_ID)
	DirAccess.remove_absolute("res://maps/%s" % MAP_ID)
	print("\n%s: %d failing check(s)" % ["FAIL" if _failures > 0 else "PASS", _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _write_map() -> void:
	var objects := [
		{"type": "fluid", "preset": "water", "pos": [-20, 0.3, -20], "size": [12, 0.6, 12]},
		{"type": "fluid", "preset": "water", "pos": [20, 4, -20], "size": [10, 5, 10], "buoyancy": 1.4},
		{"type": "fluid", "preset": "mud", "pos": [20, 4, 20], "size": [10, 5, 10]},
		{"type": "fluid", "preset": "lava", "pos": [-20, 0.3, 20], "size": [10, 0.6, 10]},
		{"type": "fluid", "preset": "lava", "pos": [0, 0.3, 30], "size": [8, 0.6, 6], "kill": true},
		{"type": "fluid", "preset": "water", "pos": [0, 0.3, -32], "size": [16, 0.6, 8], "current": [6, 0]},
		{"type": "fluid", "preset": "lava", "pos": [0, 0.3, 0], "size": [16, 0.6, 16]},
	]
	var spawns := []
	for i in 6:
		var a := TAU * i / 6.0
		spawns.append({"pos": [sin(a) * 30.0, 0, cos(a) * 30.0 - 10.0], "yaw": rad_to_deg(a)})
	var map := {"format": 1, "name": "Probe Fluids", "floor": {"size": [90, 90], "material": "checker"},
		"objects": objects, "spawns": spawns}
	DirAccess.make_dir_recursive_absolute("res://maps/" + MAP_ID)
	var file := FileAccess.open("res://maps/%s/map.json" % MAP_ID, FileAccess.WRITE)
	file.store_string(JSON.stringify(map))
	file.close()

func _fluid(map: MapData, preset: String) -> Dictionary:
	for o in map.objects:
		if o["type"] == &"fluid" and o["preset"] == preset:
			return o
	return {}

func _start(mode: GameMode.Kind, bots: int = 0, keep_local_still: bool = false) -> void:
	var cfg := MatchConfig.new()
	cfg.map_id = MAP_ID
	cfg.game_mode = mode
	cfg.bot_count = bots
	cfg.round_time = 600.0
	cfg.lives = 3
	_m = MATCH_SCENE.instantiate() as Match
	add_child(_m)
	_m.setup(cfg)
	_effects.clear()
	_m.effect_played.connect(func(kind: StringName, _pos: Vector3, _param: float) -> void: _effects.append(kind))
	await _ticks(int(Match.COUNTDOWN_TIME * 60.0) + 5)
	_car = _m.local_car
	_input = ScriptedInput.new()
	_input.car = _car
	add_child(_input)
	_car.input_provider = _input
	if keep_local_still:
		_car.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-40.0, 0.8, -40.0)))
	elif bots > 0:   # bots only as extra cars: parked in a far corner
		for c in _m.cars:
			if c != _car:
				c.frozen = true
				c.teleport_to(Transform3D(Basis.IDENTITY, Vector3(40.0, 0.8, 40.0 - 4.0 * _m.cars.find(c))))

func _finish() -> void:
	_input.queue_free()
	_m.queue_free()
	_m = null

func _place(pos: Vector3, facing: Vector3) -> void:
	_input.throttle = 0.0
	_input.steer = 0.0
	_car.teleport_to(Transform3D(Basis.looking_at(facing, Vector3.UP), pos))
	await _ticks(5)

func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _header(title: String) -> void:
	print("\n== %s" % title)

func _check(label: String, value: Variant, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("  [%s] %s: %s" % ["ok" if ok else "FAIL", label, str(value)])
