class_name BotInput
extends CarInputProvider
## Simple bot (§7.7). Same interface as PlayerInput; always drives with DriveMode.DIRECTIONAL, so the car's
## directional drive (auto U-turn, stuck assist) does the steering. Decisions use Match.rng (gameplay randomness).
## Frozen cars ignore bot input automatically (the car replaces it with neutral input).

const THINK_INTERVAL := 0.4
const ROCKET_RANGE := 25.0
const ROCKET_LEAD_TIME := 0.3
const BOOST_MIN_BATTERY := 0.5
const BOOST_MIN_DISTANCE := 15.0
const BOOST_MAX_ANGLE_DEG := 20.0
const AREA_ITEM_REACH := 0.8         # Shocker / Blast: use when the target is within this share of the reach
const REACHABLE_HEIGHT := 1.5        # skip item boxes this far above / below the bot (e.g. on the table)
const ARRIVE_DISTANCE := 3.0         # wander points count as reached within this distance
const WANDER_EXTENT := 35.0          # random wander points within ±this on X and Z
const BOMB_FLEE_RANGE := 15.0        # sticky bomb: run from the holder when it is this close
const HAZARD_LOOKAHEAD := 5.0        # m ahead checked for harmful fluids (lava, acid, deadly) …
const HAZARD_LOOKAHEAD_PER_SPEED := 0.35   # … plus this many m per m/s of speed …
const HAZARD_LOOKAHEAD_TIME := 0.6   # … plus where the car will be in this many seconds
const HAZARD_TURNS: Array[float] = [35.0, -35.0, 70.0, -70.0, 110.0, -110.0, 180.0]   # degrees to try instead

@export var aim_error: float = 1.5   # random aim offset (m) per axis
@export var reaction_delay_min: float = 0.3
@export var reaction_delay_max: float = 0.8

var match_node: Match = null

var _target_car: Car = null
var _target_point: Vector3 = Vector3.ZERO
var _wandering: bool = false
var _think_left: float = 0.0
var _aim_offset: Vector3 = Vector3.ZERO
var _reaction_left: float = -1.0     # < 0: not waiting to fire
var _fire_latched: bool = false
var _current: CarInput = CarInput.new()

func _ready() -> void:
	super()
	_think_left = match_node.rng.randf() * THINK_INTERVAL   # spread the bots' thinking over ticks

func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car) or not Net.is_authority():
		return
	_think_left -= delta
	var arrived := _target_car == null and _flat(_target_point - car.global_position).length() < ARRIVE_DISTANCE
	if _think_left <= 0.0 or arrived:
		_think_left = THINK_INTERVAL
		_think()

	# Sticky bomb: the holder hunts the nearest car to pass it on; everyone else runs from the holder.
	var bomb := match_node.mode as StickyBombMode
	var flee := false
	if bomb != null and bomb.holder != null:
		if bomb.holder == car:
			_target_car = _nearest_car()
		elif _flat(bomb.holder.global_position - car.global_position).length() < BOMB_FLEE_RANGE:
			flee = true
	var target := _target_car.global_position if _target_car != null else _target_point
	if flee:
		target = car.global_position + _flat(car.global_position - bomb.holder.global_position)
	var to_target := _flat(target - car.global_position)
	var i := CarInput.new()
	i.drive_mode = CarInput.DriveMode.DIRECTIONAL
	i.move_world = to_target.normalized() if to_target.length_squared() > 0.01 else Vector3.ZERO
	i.move_world = _avoid_hazards(i.move_world)
	var fwd := _flat(-car.global_basis.z).normalized()
	var angle := rad_to_deg(fwd.angle_to(i.move_world)) if i.move_world != Vector3.ZERO else 180.0
	i.boost = car.battery > BOOST_MIN_BATTERY and to_target.length() > BOOST_MIN_DISTANCE and angle < BOOST_MAX_ANGLE_DEG
	i.aim_point = _aim_point()
	if _update_fire(delta):
		_fire_latched = true
	_current = i

## Keeps the bot out of harmful fluids: if the way ahead leads into one, turn to the nearest safe direction.
func _avoid_hazards(direction: Vector3) -> Vector3:
	var inside := FluidZone.harmful_zone_at(car.global_position)
	if inside != null:   # pushed in anyway: shortest way out
		return inside.exit_direction(car.global_position)
	if direction == Vector3.ZERO or not _heading_into_hazard(direction):
		return direction
	for turn in HAZARD_TURNS:
		var d := direction.rotated(Vector3.UP, deg_to_rad(turn))
		if not _heading_into_hazard(d):
			return d
	return direction

func _heading_into_hazard(direction: Vector3) -> bool:
	var here := car.global_position
	var ahead := here + direction * (HAZARD_LOOKAHEAD + car.linear_velocity.length() * HAZARD_LOOKAHEAD_PER_SPEED)
	var drift := here + _flat(car.linear_velocity) * HAZARD_LOOKAHEAD_TIME + direction * (HAZARD_LOOKAHEAD * 0.5)
	return FluidZone.harmful_at(ahead) or FluidZone.harmful_at(drift)

## Called by the car once per tick; the fire pulse is consumed here.
func get_car_input(_car: Car) -> CarInput:
	_current.fire = _fire_latched
	_fire_latched = false
	return _current

## Every THINK_INTERVAL: no item → nearest reachable active item box; item → nearest other car;
## nothing to chase → a random wander point in the arena (kept until reached).
func _think() -> void:
	var rng := match_node.rng
	_aim_offset = Vector3(rng.randf_range(-aim_error, aim_error), 0.0, rng.randf_range(-aim_error, aim_error))
	_target_car = null
	if car.held_item == null:
		var box := _nearest_box()
		if box != null:
			_target_point = box.global_position
			_wandering = false
			return
	else:
		_target_car = _nearest_car()
		if _target_car != null:
			_wandering = false
			return
	if not _wandering or _flat(_target_point - car.global_position).length() < ARRIVE_DISTANCE:
		for attempt in 4:   # not into lava and the like
			_target_point = Vector3(rng.randf_range(-WANDER_EXTENT, WANDER_EXTENT), 0.0, rng.randf_range(-WANDER_EXTENT, WANDER_EXTENT))
			if not FluidZone.harmful_at(_target_point):
				break
		_wandering = true

## True on the tick the bot fires: after a reaction delay once the held item has a target in range
## (Shocker / Blast: a car close by).
func _update_fire(delta: float) -> bool:
	var item := car.held_item
	var can_fire := false
	if item != null and item.aim_type == ItemDef.AimType.NONE:   # Shocker, Blast: someone close enough
		var near := _nearest_car()
		can_fire = near != null and near.global_position.distance_to(car.global_position) <= item.explosion_radius * AREA_ITEM_REACH
	elif item != null and _target_car != null:
		var fire_range := ROCKET_RANGE if item.aim_type == ItemDef.AimType.STRAIGHT else item.max_range
		can_fire = _flat(_target_car.global_position - car.global_position).length() <= fire_range
	if not can_fire:
		_reaction_left = -1.0
		return false
	if _reaction_left < 0.0:
		_reaction_left = match_node.rng.randf_range(reaction_delay_min, reaction_delay_max)
	_reaction_left -= delta
	if _reaction_left > 0.0:
		return false
	_reaction_left = -1.0
	return true

## Leads the target: position + velocity × lead time (rockets 0.3 s, balloons their flight time) + aim error.
func _aim_point() -> Vector3:
	if _target_car == null:
		return _target_point
	var lead := ROCKET_LEAD_TIME
	var item := car.held_item
	if item != null and item.aim_type == ItemDef.AimType.LOB:
		lead = Ballistics.lob_flight_time(_flat(_target_car.global_position - car.global_position).length(), item.max_range)
	var p := _target_car.global_position + _target_car.linear_velocity * lead + _aim_offset
	p.y = _target_car.global_position.y
	return p

func _nearest_box() -> ItemBox:
	var best: ItemBox = null
	var best_d := INF
	for box in match_node.item_boxes:
		if not box.active or absf(box.global_position.y - car.global_position.y) > REACHABLE_HEIGHT \
				or FluidZone.harmful_at(box.global_position):
			continue
		var d := car.global_position.distance_squared_to(box.global_position)
		if d < best_d:
			best_d = d
			best = box
	return best

func _nearest_car() -> Car:
	var best: Car = null
	var best_d := INF
	for other in match_node.cars:
		if other == car or other.eliminated:
			continue
		var d := car.global_position.distance_squared_to(other.global_position)
		if d < best_d:
			best_d = d
			best = other
	return best

func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
