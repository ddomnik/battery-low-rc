class_name Match
extends Node3D
## One match: arena, cars, inputs, camera and match UI. Owns the gameplay rules; created by Main, freed on exit.
## The game mode (child "Mode", see GameMode) decides scoring extras, eliminations, ranking and the round end.

signal camera_mode_changed(mode: CameraRig.Mode)
signal scores_changed
## Every cosmetic effect passes through play_effect; listeners (tests, later audio / network) hear it here.
signal effect_played(kind: StringName, pos: Vector3, param: float)

## COUNTDOWN: cars frozen, "3 · 2 · 1 · GO!". PLAYING: until the mode says the round is over. RESULTS: podium.
enum State { COUNTDOWN, PLAYING, RESULTS }

const ARENA_SCENE: PackedScene = preload("res://arena/test_arena.tscn")
const CAR_SCENE: PackedScene = preload("res://car/car.tscn")
const CAMERA_RIG_SCENE: PackedScene = preload("res://camera/camera_rig.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/hud.tscn")
const INGAME_MENU_SCENE: PackedScene = preload("res://ui/ingame_menu.tscn")
const RESULTS_SCENE: PackedScene = preload("res://ui/results.tscn")
const COUNTDOWN_TIME := 3.0
const PODIUM_POSITION := Vector3(0.0, 0.0, 13.0)   # open floor south of ramp A; the losers' row lies at z ≈ 18
const PODIUM_VIEW_HEIGHT := 1.2                     # camera aims at this height above the podium base
const HIT_COOLDOWN := 1.0             # a hit on the same victim scores at most once per second per attacker
const KNOCKOUT_POINTS := 10           # knocking a car off the map
const KNOCKOUT_CREDIT_TIME := 6.0     # the last car that hit the victim this recently gets the knockout
const EXPLOSION_HIT_FACTOR := 0.6     # explosions score when strength * falloff >= bump_score_strength * this
const EXPLOSION_SHAKE := 0.6          # camera trauma at the center of an explosion
const EXPLOSION_SHAKE_RANGE := 3.0    # trauma falls to 0 at this many explosion radii from the local car
const LOCAL_PLAYER_ID := 1
const LANDING_EFFECT_DROP := 0.6      # landing ring sits this far below the car origin (ground at rest)
const PERFECT_LANDING_COLOR := Color(0.4, 0.95, 1.0)
const SCORE_POPUP_COLOR := Color(1.0, 0.9, 0.3)
const KNOCKOUT_COLOR := Color(1.0, 0.45, 0.2)
const OUT_COLOR := Color(1.0, 0.4, 0.35)
const SPECTATE_DELAY := 1.5           # s the camera lingers where the local car went out before spectating
const SHAKE_DIVISOR := 30.0           # camera trauma = bump strength or crash impact speed / this
const SPAWN_LIFT := 0.8               # car origin above a spawn marker; the car settles onto its springs
const RESPAWN_IGNORE_TIME := 0.5
const PLAYER_COLORS: Array[Color] = [
	Color(0.92, 0.22, 0.22),  # red
	Color(0.22, 0.45, 0.95),  # blue
	Color(1.0, 0.85, 0.15),   # yellow
	Color(0.25, 0.78, 0.3),   # green
	Color(1.0, 0.55, 0.12),   # orange
	Color(0.62, 0.32, 0.88),  # purple
	Color(0.2, 0.85, 0.92),   # cyan
	Color(1.0, 0.45, 0.75),   # pink
	Color(0.68, 1.0, 0.2),    # lime
	Color(0.95, 0.95, 0.95),  # white
]

var config: MatchConfig = null
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var cars: Array[Car] = []
var scores: Dictionary = {}           # player_id → int
var item_defs: Array[ItemDef] = []
var item_boxes: Array[ItemBox] = []
var local_car: Car = null
var local_input: PlayerInput = null
var arena: TestArena = null
var camera_rig: CameraRig = null
var time: float = 0.0                 # match clock (physics time)
var state: State = State.COUNTDOWN
var state_time: float = 0.0           # seconds since entering the current state
var countdown_left: float = COUNTDOWN_TIME
var time_left: float = 0.0            # round timer (modes with uses_round_timer)
var mode: GameMode = null
var eliminated_order: Array[Car] = []  # first out first
var _spectate_at: float = -1.0        # match time to switch to spectating (local car just went out)

var _cars_root: Node3D
var _projectiles_root: Node3D
var _effects: Effects
var _inputs_root: Node
var _ui: CanvasLayer
var _hud: Hud
var _local_score_shown: int = 0
var _countdown_shown: int = 0         # last countdown number that beeped
var _ingame_menu: InGameMenu
var _results: ResultsScreen
var _podium: Podium = null
var _last_respawn: Dictionary = {}    # player_id → match time of the last accepted respawn
var _hit_times: Dictionary = {}       # Vector2i(attacker id, victim id) → match time of the last scored hit
var _last_hit_by: Dictionary = {}     # victim player_id → {"attacker": Car, "time": float} (any bump / blast)

func setup(cfg: MatchConfig) -> void:
	config = cfg
	if cfg.rng_seed != 0:
		rng.seed = cfg.rng_seed
	else:
		rng.randomize()

	item_defs = ItemRegistry.all()
	mode = GameMode.create(cfg.game_mode)
	mode.name = "Mode"
	mode.match_node = self

	arena = ARENA_SCENE.instantiate() as TestArena
	arena.name = "Arena"
	arena.with_walls = mode.arena_has_walls()
	add_child(arena)
	var boxes := _add_node3d("ItemBoxes")
	for marker in arena.item_spawn_points:
		var box := ItemBox.new()
		box.name = "ItemBox_%s" % marker.name
		box.match_node = self
		box.position = marker.global_position
		boxes.add_child(box)
		item_boxes.append(box)
	_cars_root = _add_node3d("Cars")
	_projectiles_root = _add_node3d("Projectiles")
	_effects = Effects.new()
	_effects.name = "Effects"
	add_child(_effects)
	_inputs_root = Node.new()
	_inputs_root.name = "Inputs"
	add_child(_inputs_root)
	camera_rig = CAMERA_RIG_SCENE.instantiate() as CameraRig
	camera_rig.mode = cfg.camera_mode
	add_child(camera_rig)
	var debug_draw := DebugDraw.new()
	debug_draw.name = "DebugDraw"
	debug_draw.match_node = self
	add_child(debug_draw)
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	add_child(_ui)
	_hud = HUD_SCENE.instantiate() as Hud
	_ui.add_child(_hud)
	_results = RESULTS_SCENE.instantiate() as ResultsScreen
	_results.play_again_requested.connect(Game.restart_match)
	_results.exit_requested.connect(Game.exit_to_menu)
	_ui.add_child(_results)
	_ingame_menu = INGAME_MENU_SCENE.instantiate() as InGameMenu
	_ingame_menu.resume_requested.connect(_set_menu_open.bind(false))
	_ingame_menu.restart_requested.connect(Game.restart_match)
	_ingame_menu.camera_toggle_requested.connect(_toggle_camera_mode)
	_ingame_menu.exit_requested.connect(Game.exit_to_menu)
	_ui.add_child(_ingame_menu)
	var overlay := DebugOverlay.new()
	overlay.name = "DebugOverlay"
	overlay.match_node = self
	_ui.add_child(overlay)

	local_car = spawn_car({
		"player_id": LOCAL_PLAYER_ID, "peer_id": Net.local_peer_id(), "name": cfg.player_name,
		"color": PLAYER_COLORS[0], "is_bot": false,
		"model_path": CarVisual.resolve_model_path(cfg.car_model_path, -1),
	})
	for b in cfg.bot_count:
		spawn_car({
			"player_id": LOCAL_PLAYER_ID + 1 + b, "peer_id": Net.local_peer_id(), "name": "Bot %d" % (b + 1),
			"color": PLAYER_COLORS[(b + 1) % PLAYER_COLORS.size()], "is_bot": true,
			"model_path": CarVisual.resolve_model_path("", b),
		})
	add_child(mode)   # after the cars exist (modes attach balloons, listen for touches)
	camera_rig.target = local_car
	camera_rig.snap_to_target()
	_hud.bind(local_car, self)
	scores_changed.connect(_on_scores_changed)
	var aim := AimVisuals.new()
	aim.name = "AimVisuals"
	aim.match_node = self
	aim.player_input = local_input
	aim.car = local_car
	add_child(aim)
	time_left = cfg.round_time
	_enter_state(State.COUNTDOWN)

func _physics_process(delta: float) -> void:
	time += delta
	state_time += delta
	if not Net.is_authority():
		return
	match state:
		State.COUNTDOWN:
			countdown_left -= delta
			if ceili(countdown_left) != _countdown_shown and countdown_left > 0.0:
				_countdown_shown = ceili(countdown_left)
				Game.audio.play_ui(&"countdown")
			if countdown_left <= 0.0:
				countdown_left = 0.0
				_enter_state(State.PLAYING)
		State.PLAYING:
			if _spectate_at >= 0.0 and time >= _spectate_at:
				_spectate_at = -1.0
				_spectate_next()
			if mode.uses_round_timer():
				time_left = maxf(time_left - delta, 0.0)
			if mode.is_round_over():
				_enter_state(State.RESULTS)

func _enter_state(new_state: State) -> void:
	state = new_state
	state_time = 0.0
	var frozen := new_state != State.PLAYING
	for car in cars:
		car.frozen = frozen
	if new_state == State.PLAYING:
		Game.audio.play_ui(&"go")
		if Net.is_authority():
			mode.on_round_start()
	if new_state == State.RESULTS:
		_set_menu_open(false)
		mode.on_round_end()
		for car in cars:
			if car.eliminated:
				car.set_eliminated(false)   # everyone takes part in the ceremony
		camera_rig.target = local_car
		_hud.set_spectating("")
		_hud.visible = false   # the results panel shows the ranking; keep the podium view clear
		_start_ceremony()
		var ranking := get_ranking()
		var values: Array[String] = []
		for car in ranking:
			values.append(mode.score_text(car))
		_results.show_results(ranking, values, local_car)
	_update_mouse_mode()

## Podium ceremony: top three on the podium (winner hopping), the rest on their roofs in front of it.
func _start_ceremony() -> void:
	for p in _projectiles_root.get_children():
		p.queue_free()
	_podium = Podium.new()
	_podium.name = "Podium"
	_podium.position = PODIUM_POSITION
	add_child(_podium)
	if Net.is_authority():
		_podium.place_cars(get_ranking())
	camera_rig.show_point(PODIUM_POSITION + Vector3.UP * PODIUM_VIEW_HEIGHT)
	Game.audio.play_ui(&"perfect_landing")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if state != State.RESULTS:
			_set_menu_open(not _ingame_menu.visible)
	elif local_car.eliminated and state == State.PLAYING and not _ingame_menu.visible \
			and (event.is_action_pressed("spectate_next") or event.is_action_pressed("fire")):
		get_viewport().set_input_as_handled()
		_spectate_next()
	elif OS.is_debug_build() and event.is_action_pressed("debug_toggle_camera"):
		get_viewport().set_input_as_handled()
		_toggle_camera_mode()
	elif OS.is_debug_build() and Net.is_authority() and event.is_action_pressed("debug_fill_battery"):
		get_viewport().set_input_as_handled()
		local_car.set_battery(1.0)
	elif OS.is_debug_build() and Net.is_authority() and event.is_action_pressed("debug_add_score"):
		get_viewport().set_input_as_handled()
		scores[local_car.player_id] = int(scores.get(local_car.player_id, 0)) + 1
		scores_changed.emit()
	elif OS.is_debug_build() and Net.is_authority():
		for i in item_defs.size():
			if event.is_action_pressed("debug_give_item_%d" % (i + 1)):
				get_viewport().set_input_as_handled()
				local_car.set_held_item(item_defs[i])

## In-game menu overlay. The tree keeps running; the local car just gets no input (coasts, then holds still).
func _set_menu_open(open: bool) -> void:
	if open:
		_ingame_menu.open(config.camera_mode)
	else:
		_ingame_menu.close()
	if local_input != null:
		local_input.enabled = not open
	_update_mouse_mode()

## Hidden and confined while driving; visible whenever a menu is up.
func desired_mouse_mode() -> Input.MouseMode:
	var menu_up := _ingame_menu.visible or state == State.RESULTS
	return Input.MOUSE_MODE_VISIBLE if menu_up else Input.MOUSE_MODE_CONFINED_HIDDEN

func _update_mouse_mode() -> void:
	Input.mouse_mode = desired_mouse_mode()

func _toggle_camera_mode() -> void:
	var follow := config.camera_mode == CameraRig.Mode.FOLLOW
	set_camera_mode(CameraRig.Mode.FIXED if follow else CameraRig.Mode.FOLLOW)

## Switches the local camera mode (follow / classic fixed) and persists it. Controls are the same in both.
func set_camera_mode(mode: CameraRig.Mode) -> void:
	config.camera_mode = mode
	camera_rig.mode = mode
	_ingame_menu.set_camera_mode(mode)
	Settings.camera_mode = mode
	Settings.save_settings()
	camera_mode_changed.emit(mode)

## Cars ordered best first, by the game mode's rules.
func get_ranking() -> Array[Car]:
	return mode.ranking()

func alive_cars() -> Array[Car]:
	var out: Array[Car] = []
	for car in cars:
		if not car.eliminated:
			out.append(car)
	return out

## Takes a car out of the round. The local player then spectates the remaining cars.
func eliminate(car: Car) -> void:
	if car.eliminated or not Net.is_authority():
		return
	car.set_eliminated(true)
	eliminated_order.append(car)
	play_effect(&"pop", car.global_position, 0.0)
	if car == local_car:
		popup("YOU'RE OUT!", OUT_COLOR)
		_spectate_at = time + SPECTATE_DELAY   # see your car go first (balloon, burst), then spectate
	elif camera_rig.target == car:
		_spectate_next()
	scores_changed.emit()

## Spectating: the camera follows the next car still in the round (Tab or click switches).
func _spectate_next() -> void:
	var alive := alive_cars()
	if alive.is_empty():
		return
	var i := alive.find(camera_rig.target)
	var next := alive[(i + 1) % alive.size()]
	camera_rig.target = next
	_hud.set_spectating("SPECTATING %s  —  Tab / click: next car" % next.display_name)

## Big fading text for the local player (modes use this too).
func popup(text: String, color: Color) -> void:
	_hud.popup(text, color)

## info = {player_id, peer_id, name, color, is_bot, model_path}
func spawn_car(info: Dictionary) -> Car:
	var car := CAR_SCENE.instantiate() as Car
	car.player_id = info["player_id"]
	car.peer_id = info["peer_id"]
	car.display_name = info["name"]
	car.color = info["color"]
	car.name = "Car_%d" % car.player_id
	var spawn := arena.spawn_points[(car.player_id - 1) % arena.spawn_points.size()]
	car.transform = _spawn_transform(spawn)
	_cars_root.add_child(car)
	car.reset_physics_interpolation()
	var is_bot: bool = info["is_bot"]
	var model_path: String = info["model_path"]
	var model_scene: PackedScene = load(model_path) as PackedScene if model_path != "" else null
	car.visual.setup(model_scene, car.tuning, car.color, not is_bot and car.player_id == LOCAL_PLAYER_ID)
	car.set_battery(car.tuning.start_battery)

	if is_bot:
		var bot := BotInput.new()
		bot.name = "BotInput_%d" % car.player_id
		bot.car = car
		bot.match_node = self
		_inputs_root.add_child(bot)
		car.input_provider = bot
	else:
		var input := PlayerInput.new()
		input.name = "PlayerInput_%d" % car.player_id
		input.car = car
		input.camera_rig = camera_rig
		_inputs_root.add_child(input)
		car.input_provider = input
		local_input = input
	car.respawn_requested.connect(respawn)
	car.item_used.connect(_on_item_used)
	car.perfect_landing.connect(_on_perfect_landing)
	car.wall_hit.connect(_on_wall_hit)
	car.bumped.connect(_on_bumped)
	cars.append(car)
	scores[car.player_id] = 0
	return car

## The car fell off the map: award a knockout, then put it at the spawn point farthest from all other cars.
func respawn(car: Car) -> void:
	if not Net.is_authority() or state == State.RESULTS:
		return   # the podium places every car itself (eliminated cars may still be below the map for a tick)
	var last: float = _last_respawn.get(car.player_id, -INF)
	if time - last < RESPAWN_IGNORE_TIME:
		return
	_last_respawn[car.player_id] = time
	_award_knockout(car)
	if not mode.on_fell_off(car):
		return   # eliminated by the mode
	var best: Marker3D = arena.spawn_points[0]
	var best_dist := -1.0
	for sp in arena.spawn_points:
		var nearest := INF
		for other in cars:
			if other != car:
				nearest = minf(nearest, other.global_position.distance_to(sp.global_position))
		if nearest > best_dist:
			best_dist = nearest
			best = sp
	car.teleport_to(_spawn_transform(best))

# --- Items, projectiles, explosions, scoring (§7.6) --------------------------------------------

## 0 = leading, 1 = last, 0.5 = everyone tied or alone.
func rank_fraction(car: Car) -> float:
	var mine: int = scores.get(car.player_id, 0)
	var better := 0
	var worse := 0
	for c in cars:
		var s: int = scores.get(c.player_id, 0)
		if s > mine:
			better += 1
		elif s < mine:
			worse += 1
	if better + worse == 0:
		return 0.5
	return float(better) / float(better + worse)

## Catch-up roll weights: each item blends from weight_leader to weight_last by rank_fraction.
func item_weights(car: Car) -> Array[float]:
	var r := rank_fraction(car)
	var weights: Array[float] = []
	for def in item_defs:
		weights.append(maxf(0.0, lerpf(def.weight_leader, def.weight_last, r)))
	return weights

func roll_item(car: Car) -> ItemDef:
	var weights := item_weights(car)
	var total := 0.0
	for w in weights:
		total += w
	var pick := rng.randf() * total
	for i in item_defs.size():
		pick -= weights[i]
		if pick <= 0.0:
			return item_defs[i]
	return item_defs.back()

func _on_item_used(car: Car, item: ItemDef, aim_point: Vector3) -> void:
	if not Net.is_authority():
		return
	var effect := &"fire"
	match item.kind:
		ItemDef.Kind.SHOCK:
			for other in cars:
				if other != car and not other.eliminated \
						and other.global_position.distance_to(car.global_position) <= item.explosion_radius:
					other.apply_shock(item.effect_time)
					note_hit(car, other)
					register_hit(car, other)   # a point; in Deathmatch (lives) it also pops a balloon
					play_effect(&"shock_arc", other.global_position, 0.0, item.color, car, other)
			play_effect(&"shock", car.global_position, item.explosion_radius, item.color, car)
			return
		ItemDef.Kind.BLAST:
			explode(car.global_position, item.explosion_radius, item.knockback, item.up_knockback, car, 4.0, 2.5,
				&"explosion", car)
			return
		ItemDef.Kind.ROCKET:
			for n in item.count:
				var t := 0.0 if item.count == 1 else float(n) / float(item.count - 1) - 0.5
				spawn_projectile(car, item, aim_point, t * item.spread_deg)
		ItemDef.Kind.BALLOON, ItemDef.Kind.OIL, ItemDef.Kind.GLUE:
			var space := car.get_world_3d().direct_space_state
			spawn_projectile(car, item, Ballistics.clamp_target(space, car.global_position, aim_point, item.max_range), 0.0)
			effect = &"throw"
	play_effect(effect, car.get_muzzle_position(item), 0.0)

func spawn_projectile(shooter: Car, item: ItemDef, target: Vector3, spread_deg: float) -> void:
	var origin := shooter.get_muzzle_position(item)
	var velocity: Vector3
	if item.aim_type == ItemDef.AimType.LOB:
		var flight := Ballistics.lob_flight_time(Vector2(target.x - origin.x, target.z - origin.z).length(), item.max_range)
		velocity = Ballistics.lob_velocity(origin, target, item.gravity, flight)
	else:
		velocity = Ballistics.straight_velocity(origin, target, item.speed, item.max_pitch_deg)
		velocity = velocity.rotated(Vector3.UP, deg_to_rad(spread_deg))
	var p := Projectile.new()
	p.launch(self, shooter, item, origin, velocity)
	_projectiles_root.add_child(p)

## Oil / glue puddle on the surface below pos (thrown items).
func spawn_puddle(item: ItemDef, pos: Vector3) -> void:
	if not Net.is_authority():
		return
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.0, pos + Vector3.DOWN * 30.0, Layers.WORLD))
	if hit.is_empty():
		return   # landed off the map
	var puddle := Puddle.new()
	puddle.kind = item.kind
	puddle.radius = item.explosion_radius
	puddle.lifetime = item.effect_time
	puddle.color = item.color
	puddle.shape_seed = rng.randi()   # the blob layout decides where tires get coated
	puddle.position = hit.position
	_projectiles_root.add_child(puddle)
	play_effect(&"splat", hit.position, item.explosion_radius, item.color)

## Knocks back every car in the radius (linear falloff) and scores hits for the attacker.
## spin = random yaw twist, tumble = tip-away spin (both rad/s at the center). effect = &"explosion", &"firework"
## or &"splash".
## skip: a car the blast leaves alone (the sticky bomb's holder, which gets its own launch).
func explode(pos: Vector3, radius: float, strength: float, up_strength: float, attacker: Car,
		spin: float = 3.0, tumble: float = 1.5, effect: StringName = &"explosion", skip: Car = null) -> void:
	if not Net.is_authority():
		return
	for car in cars:
		if car.eliminated or car == skip:
			continue
		var offset := car.global_position - pos
		var dist := offset.length()
		if dist > radius:
			continue
		var falloff := 1.0 - dist / radius
		var dir := Vector3(offset.x, 0.0, offset.z)
		dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU)
		car.apply_knockback((dir * strength + Vector3.UP * up_strength) * falloff, rng.randf_range(-spin, spin) * falloff,
			Vector3.UP.cross(dir) * tumble * falloff)
		note_hit(attacker, car)
		mode.on_damage(car, strength * falloff)
		if car != attacker and strength * falloff >= car.tuning.bump_score_strength * EXPLOSION_HIT_FACTOR:
			register_hit(attacker, car)
	play_effect(effect, pos, radius)

## The car that last bumped or blasted the victim within KNOCKOUT_CREDIT_TIME, or null.
func last_attacker(victim: Car) -> Car:
	var hit: Dictionary = _last_hit_by.get(victim.player_id, {})
	if hit.is_empty() or time - float(hit["time"]) > KNOCKOUT_CREDIT_TIME:
		return null
	var attacker: Car = hit["attacker"]
	return attacker if is_instance_valid(attacker) else null

## Remembers who last touched a car (any bump or blast), for knockout credit.
func note_hit(attacker: Car, victim: Car) -> void:
	if attacker != null and attacker != victim:
		_last_hit_by[victim.player_id] = {"attacker": attacker, "time": time}

## +KNOCKOUT_POINTS for the car that last hit the victim within KNOCKOUT_CREDIT_TIME. Falling off alone scores nothing.
func _award_knockout(victim: Car) -> void:
	var hit: Dictionary = _last_hit_by.get(victim.player_id, {})
	_last_hit_by.erase(victim.player_id)
	if hit.is_empty() or state != State.PLAYING or time - float(hit["time"]) > KNOCKOUT_CREDIT_TIME:
		return
	var attacker: Car = hit["attacker"]
	if not is_instance_valid(attacker):
		return
	scores[attacker.player_id] = int(scores.get(attacker.player_id, 0)) + KNOCKOUT_POINTS
	if attacker == local_car:
		_hud.popup("KNOCKOUT!", KNOCKOUT_COLOR)
	scores_changed.emit()

## +1 for the attacker, at most once per HIT_COOLDOWN per attacker/victim pair. Only while PLAYING.
func register_hit(attacker: Car, victim: Car) -> void:
	if not Net.is_authority() or state != State.PLAYING or attacker == null or attacker == victim:
		return
	var key := Vector2i(attacker.player_id, victim.player_id)
	var last: float = _hit_times.get(key, -INF)
	if time - last < HIT_COOLDOWN:
		return
	_hit_times[key] = time
	scores[attacker.player_id] = int(scores.get(attacker.player_id, 0)) + 1
	mode.on_scoring_hit(attacker, victim)
	scores_changed.emit()

func _on_perfect_landing(car: Car) -> void:
	play_effect(&"landing", car.global_position + Vector3.DOWN * LANDING_EFFECT_DROP, 0.0)
	if car == local_car:
		_hud.popup("PERFECT LANDING!", PERFECT_LANDING_COLOR)

## A car was rammed. Strong enough rams score a hit for the attacker (§7.3.6).
func _on_bumped(car: Car, attacker: Car, strength: float) -> void:
	note_hit(attacker, car)
	mode.on_damage(car, strength)
	if strength >= car.tuning.bump_score_strength:
		register_hit(attacker, car)
	play_effect(&"bump", (car.global_position + attacker.global_position) * 0.5, strength)
	if car == local_car or attacker == local_car:
		camera_rig.add_trauma(strength / SHAKE_DIVISOR)

func _on_wall_hit(car: Car, pos: Vector3, impact_speed: float) -> void:
	play_effect(&"wall", pos, impact_speed)
	if car == local_car:
		camera_rig.add_trauma(impact_speed / SHAKE_DIVISOR)

func _on_scores_changed() -> void:
	var mine: int = scores.get(LOCAL_PLAYER_ID, 0)
	if mine > _local_score_shown:
		_hud.popup("+%d" % (mine - _local_score_shown), SCORE_POPUP_COLOR)
	_local_score_shown = mine

## The single choke point for cosmetic effects (later an RPC). Adds camera shake for the local player.
## color: tint for effects that need one (confetti, car burst).
## from / to: nodes the effect stays attached to while it plays (the Shocker's bolts run from the user to each
## shocked car). Over the network they become player ids.
func play_effect(kind: StringName, pos: Vector3, param: float, color: Color = Color.WHITE, from: Node3D = null,
		to: Node3D = null) -> void:
	_effects.play(kind, pos, param, color, from, to)
	if (kind == &"explosion" or kind == &"firework" or kind == &"splash" or kind == &"car_burst") and local_car != null:
		var d := local_car.global_position.distance_to(pos)
		camera_rig.add_trauma(clampf(1.0 - d / (param * EXPLOSION_SHAKE_RANGE), 0.0, 1.0) * EXPLOSION_SHAKE)
	effect_played.emit(kind, pos, param)

func _spawn_transform(spawn: Marker3D) -> Transform3D:
	return Transform3D(spawn.global_basis, spawn.global_position + Vector3.UP * SPAWN_LIFT)

func _add_node3d(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	add_child(n)
	return n
