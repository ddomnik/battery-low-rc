class_name Car
extends RigidBody3D
## Arcade raycast-suspension car. Physics runs in _integrate_forces, game logic in _physics_process.
## Consumes CarInput only; never reads Input. Every feel number comes from `tuning`.

signal battery_changed(value: float)
signal item_changed(item: ItemDef)
signal item_used(car: Car, item: ItemDef, aim_point: Vector3)
signal perfect_landing(car: Car)
signal bumped(car: Car, attacker: Car, strength: float)
signal touched(car: Car, other: Car)    # any car-on-car contact, however soft (sticky bomb hand-over)
signal wall_hit(car: Car, position: Vector3, impact_speed: float)
signal respawn_requested(car: Car)

const WHEELS := 4
const MUZZLE_FALLBACK_HEIGHT := 0.8   # used only without a visual or an item

## Driving intent for one physics tick, resolved from CarInput.
class DriveCommand:
	var throttle: float = 0.0   # -1..1
	var steer: float = 0.0      # -1..1, + = left
	var handbrake: bool = false

@export var tuning: CarTuning

var player_id: int = 0
var peer_id: int = 1
var display_name: String = "Player"
var color: Color = Color.WHITE
var input_provider: CarInputProvider = null

var battery: float = 0.0
var held_item: ItemDef = null
var is_boosting: bool = false
var is_drifting: bool = false
var frozen: bool = true
var eliminated: bool = false            # out of the round: hidden, no collisions, ignored by everyone
var knockback_multiplier: float = 1.0   # scales knockback this car receives (Last on table damage %)
var wheel_oil: Array[float] = [0.0, 0.0, 0.0, 0.0]    # seconds each wheel stays oiled
var wheel_glue: Array[float] = [0.0, 0.0, 0.0, 0.0]   # seconds each wheel stays glued
var shock_left: float = 0.0             # seconds of Shocker stall left: no drive, speed runs down to zero
var _shock_decel: float = 0.0           # m/s² that takes the speed at the hit to zero over the shock time
var pad_overlaps: int = 0               # charging pads this car is inside (pads count it up and down)

# Read-only caches for visuals, HUD, debug, bots.
var grounded_count: int = 0
var forward_speed: float = 0.0
var lateral_speed: float = 0.0
var air_time: float = 0.0
var last_steer: float = 0.0
var last_aim_point: Vector3 = Vector3.ZERO
var last_landing_reward: float = 0.0    # 0..1 share of the maximum reward of the latest perfect landing
var wheel_grounded: Array[bool] = [false, false, false, false]
var wheel_spring_len: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_force: Array[float] = [0.0, 0.0, 0.0, 0.0]   # suspension force per wheel (N), for debug draw
var wheel_contact: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]   # ground point under each wheel
var wheel_normal: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]            # ground normal there

@onready var visual: CarVisual = $Visual

var _input: CarInput = CarInput.new()
var _drive: DriveCommand = DriveCommand.new()
var _ground_normal: Vector3 = Vector3.UP
var _was_airborne: bool = false
var _landing_window: float = 0.0
var _landing_air_time: float = 0.0
var _pending_landing_reward: bool = false
var _step_velocity: Vector3 = Vector3.ZERO       # velocity entering the latest physics step (pre-collision)
var _prev_step_velocity: Vector3 = Vector3.ZERO  # the value before that, see velocity_into_last_step()
var _step_velocity_frame: int = -1
var _wall_cooldown: float = 0.0
var _pending_wall_hits: Array[Dictionary] = []
var _pending_bumps: Array[Dictionary] = []
var _pending_touches: Array[Car] = []
var _bump_cooldowns: Dictionary = {}             # other car instance id → seconds left
var _pending_teleport: Variant = null       # Transform3D or null
var _boost_locked: bool = false             # battery ran dry while boosting: release boost before it works again
var _upside_down_time: float = 0.0
var _reset_cooldown: float = 0.0
var _stuck_timer: float = 0.0
var _auto_reverse_timer: float = 0.0
var _tight_turn: bool = false               # current turn-around started slow (DIRECTIONAL)
var _parked: bool = false                   # hold brake active this tick
var _air_axis_locked: Array[bool] = [false, false]   # air-control axes held since takeoff (see _air_control_axes)
var _gravity: Vector3 = Vector3.ZERO        # scaled gravity acting on this body

func _ready() -> void:
	if tuning == null:
		tuning = CarTuning.new()
	mass = tuning.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = tuning.center_of_mass
	inertia = tuning.inertia
	gravity_scale = tuning.gravity_scale
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = tuning.linear_damp
	angular_damp = tuning.angular_damp
	var mat := PhysicsMaterial.new()
	mat.friction = tuning.body_friction
	mat.bounce = tuning.body_bounce
	physics_material_override = mat
	collision_layer = Layers.CARS
	collision_mask = Layers.WORLD | Layers.CARS
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var g_dir: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector")
	_gravity = g_dir * g * gravity_scale
	for i in WHEELS:
		wheel_spring_len[i] = tuning.suspension_rest_length

# --- Physics (runs inside the physics step) ---------------------------------------------------

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not Net.is_authority():
		return
	if _pending_teleport != null:
		state.transform = _pending_teleport
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_pending_teleport = null
		wheel_oil.fill(0.0)
		wheel_glue.fill(0.0)
		_was_airborne = false
		_landing_window = 0.0
		air_time = 0.0
		_record_step_velocity(Vector3.ZERO)
		reset_physics_interpolation.call_deferred()
		return

	var dt := state.step
	_detect_wall_hits(state, dt)
	var xf := state.transform
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var right := xf.basis.x

	for i in WHEELS:
		wheel_oil[i] = maxf(0.0, wheel_oil[i] - dt)
		wheel_glue[i] = maxf(0.0, wheel_glue[i] - dt)
	_sample_wheels(state, xf, up)
	forward_speed = state.linear_velocity.dot(fwd)
	lateral_speed = state.linear_velocity.dot(right)
	_drive = _resolve_drive(fwd, dt)
	last_steer = _drive.steer

	_apply_suspension(state, xf, up)
	if grounded_count >= 2:
		_apply_drive(state, fwd, dt)
		_apply_grip(state, xf, right, up, dt)
		_apply_yaw(state, up)
		state.apply_central_force(-_ground_normal * tuning.downforce_per_speed * absf(forward_speed) * mass)
	elif grounded_count == 0:
		_apply_air_control(state, xf)
	_update_landing(state, xf, fwd, dt)
	_detect_bumps(state)
	if state.angular_velocity.length() > tuning.max_angular_speed:
		state.angular_velocity = state.angular_velocity.normalized() * tuning.max_angular_speed
	_record_step_velocity(state.linear_velocity)

## The velocity this car had going into the physics step that produced the current contacts, i.e. before a
## collision was resolved. Safe to call from another car's _integrate_forces in either order.
func velocity_into_last_step() -> Vector3:
	return _prev_step_velocity if _step_velocity_frame == Engine.get_physics_frames() else _step_velocity

func _record_step_velocity(v: Vector3) -> void:
	_prev_step_velocity = _step_velocity
	_step_velocity = v
	_step_velocity_frame = Engine.get_physics_frames()

## Car-on-car (§7.3.6): each car handles its own side. It measures how fast the OTHER car drove into it (before
## the crash) and knocks itself away; the attacker only feels the physics engine's normal response.
func _detect_bumps(state: PhysicsDirectBodyState3D) -> void:
	for i in state.get_contact_count():
		var other := state.get_contact_collider_object(i) as Car
		if other == null or other == self:
			continue
		if not _pending_touches.has(other):
			_pending_touches.append(other)
		var id := other.get_instance_id()
		if _bump_cooldowns.get(id, 0.0) > 0.0:
			continue
		var dir := state.transform.origin - other.global_position
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			continue
		dir = dir.normalized()
		var attack := other.velocity_into_last_step().dot(dir)   # how fast the other car drove INTO me
		if attack < tuning.bump_min_speed:
			continue
		var strength := tuning.bump_base + attack * tuning.bump_speed_scale
		if other.is_boosting:
			strength *= tuning.bump_boost_mult
		state.apply_central_impulse((dir * strength + Vector3.UP * tuning.bump_pop) * mass * knockback_multiplier)
		# Cosmetic spin on the authority (spec §7.3.6), so plain randf is fine here.
		state.apply_torque_impulse(Vector3.UP * randf_range(-1.0, 1.0) * tuning.bump_spin * tuning.inertia.y)
		_bump_cooldowns[id] = tuning.bump_cooldown
		_pending_bumps.append({"attacker": other, "strength": strength})

## Crashing into a wall (static geometry with a steep normal) kicks the car back, scaled by the speed it had
## going into the wall. Uses the velocity from before the step, because the solver has already stopped the car.
func _detect_wall_hits(state: PhysicsDirectBodyState3D, dt: float) -> void:
	_wall_cooldown = maxf(0.0, _wall_cooldown - dt)
	if _wall_cooldown > 0.0:
		return
	for i in state.get_contact_count():
		if state.get_contact_collider_object(i) is Car:
			continue   # car-on-car is bumping (M6)
		var pos := state.get_contact_local_position(i)
		var n := state.get_contact_local_normal(i)
		if n.dot(state.transform.origin - pos) < 0.0:
			n = -n   # make it point from the wall into the car
		if absf(n.y) > tuning.wall_normal_max_y:
			continue   # floor, ramp or roof contact
		n.y = 0.0
		n = n.normalized()
		var impact := -velocity_into_last_step().dot(n)
		if impact < tuning.wall_bounce_min_speed:
			continue
		state.apply_central_impulse((n * impact * tuning.wall_bounce_factor + Vector3.UP * impact * tuning.wall_bounce_pop) * mass)
		# Slight physics spin: tip the top away from the wall (side facing it lifts) plus a small random twist.
		var spin := Vector3.UP.cross(n) * impact * tuning.wall_bounce_tumble \
			+ Vector3.UP * randf_range(-1.0, 1.0) * impact * tuning.wall_bounce_spin
		state.apply_torque_impulse(angular_impulse_for(spin, state.transform.basis))
		_wall_cooldown = tuning.wall_bounce_cooldown
		_pending_wall_hits.append({"position": pos, "impact": impact})
		return   # one kickback per tick

func _sample_wheels(state: PhysicsDirectBodyState3D, xf: Transform3D, up: Vector3) -> void:
	var space := state.get_space_state()
	var ray_len := tuning.suspension_rest_length + tuning.wheel_radius
	var normal_sum := Vector3.ZERO
	grounded_count = 0
	for i in WHEELS:
		var from: Vector3 = xf * tuning.wheel_mounts[i]
		var query := PhysicsRayQueryParameters3D.create(from, from - up * ray_len, Layers.WORLD, [get_rid()])
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			wheel_grounded[i] = false
			wheel_spring_len[i] = tuning.suspension_rest_length
			continue
		wheel_grounded[i] = true
		grounded_count += 1
		var hit_pos: Vector3 = hit.position
		var hit_normal: Vector3 = hit.normal
		wheel_contact[i] = hit_pos
		wheel_normal[i] = hit_normal
		match Puddle.kind_at(hit_pos):
			ItemDef.Kind.OIL:
				wheel_oil[i] = tuning.wheel_coating_time
			ItemDef.Kind.GLUE:
				wheel_glue[i] = tuning.wheel_coating_time
		wheel_spring_len[i] = clampf(from.distance_to(hit_pos) - tuning.wheel_radius, 0.0, tuning.suspension_rest_length)
		normal_sum += hit_normal
	_ground_normal = normal_sum.normalized() if grounded_count > 0 else Vector3.UP

## Turns CarInput into throttle / steer / handbrake (§7.3.3).
## CLASSIC (players): passed through. DIRECTIONAL (bots): move_world is a world direction; the car steers toward
## it at its normal turning rate, keeps momentum and can drift. A target behind at speed triggers an automatic
## handbrake U-turn. A stuck assist reverses out of walls.
func _resolve_drive(fwd: Vector3, dt: float) -> DriveCommand:
	var d := DriveCommand.new()
	d.handbrake = _input.handbrake
	if _input.drive_mode == CarInput.DriveMode.CLASSIC:
		d.throttle = _input.throttle
		d.steer = _input.steer
		return d

	var want := Vector3(_input.move_world.x, 0.0, _input.move_world.z)
	var amount := minf(want.length(), 1.0)
	if amount < tuning.direction_deadzone:
		_stuck_timer = 0.0
		_auto_reverse_timer = 0.0
		_tight_turn = false
		return d
	want /= want.length()
	var fwd_flat := Vector3(fwd.x, 0.0, fwd.z)
	if fwd_flat.length_squared() < 0.01:
		return d  # car is vertical; air control / recovery handles it
	fwd_flat = fwd_flat.normalized()

	var angle := fwd_flat.signed_angle_to(want, Vector3.UP)  # + = target is to the left
	var abs_angle := absf(angle)
	var uturn := deg_to_rad(tuning.uturn_angle_deg)
	d.steer = clampf(angle / deg_to_rad(tuning.direction_full_steer_angle_deg), -1.0, 1.0)
	if abs_angle > uturn:
		# A turn-around that starts slow stays a tight turn, even if it speeds up past uturn_min_speed.
		_tight_turn = _tight_turn or forward_speed <= tuning.uturn_min_speed
		if not _tight_turn:
			d.throttle = tuning.uturn_throttle
			d.handbrake = true          # automatic handbrake U-turn
		else:
			d.throttle = tuning.tight_turn_throttle
	else:
		_tight_turn = false
		d.throttle = amount * lerpf(1.0, tuning.turn_throttle_min, abs_angle / uturn)

	# Stuck assist: pushing forward without moving → reverse briefly; reversed steering swings the nose toward the target.
	if _auto_reverse_timer > 0.0:
		_auto_reverse_timer -= dt
		d.throttle = -1.0
		d.steer = -d.steer
		d.handbrake = false
	elif d.throttle > 0.0 and absf(forward_speed) < tuning.stuck_speed:
		_stuck_timer += dt
		if _stuck_timer > tuning.stuck_time:
			_stuck_timer = 0.0
			_auto_reverse_timer = tuning.auto_reverse_time
	else:
		_stuck_timer = 0.0
	return d

func _apply_suspension(state: PhysicsDirectBodyState3D, xf: Transform3D, up: Vector3) -> void:
	for i in WHEELS:
		wheel_force[i] = 0.0
		if not wheel_grounded[i]:
			continue
		# apply_force's position is an offset from the body origin in GLOBAL orientation, not a world position.
		var offset: Vector3 = xf.basis * tuning.wheel_mounts[i]
		var compression := tuning.suspension_rest_length - wheel_spring_len[i]
		var spring_vel := state.get_velocity_at_local_position(offset).dot(up)
		var force := tuning.spring_strength * compression - tuning.spring_damping * spring_vel
		if force > 0.0:
			wheel_force[i] = force
			state.apply_force(up * force, offset)

func _apply_drive(state: PhysicsDirectBodyState3D, fwd: Vector3, dt: float) -> void:
	var fwd_g := (fwd - _ground_normal * fwd.dot(_ground_normal)).normalized()  # follows slopes
	var slow := _speed_mult()
	var max_speed := tuning.max_speed * (tuning.boost_speed_mult if is_boosting else 1.0) * slow
	var stop_speed := tuning.direction_change_speed
	var t := _drive.throttle
	var accel := 0.0
	var traction := lerpf(1.0, tuning.oil_brake_mult, coated_share(wheel_oil))   # oiled tires barely brake
	var stalled := shock_left > 0.0
	_parked = false
	if t > 0.01:
		if forward_speed < -stop_speed:
			accel = tuning.brake_decel * traction
		elif not stalled:
			accel = tuning.acceleration * slow * t * clampf(1.0 - forward_speed / max_speed, 0.0, 1.0)
	elif t < -0.01:
		if forward_speed > stop_speed:
			accel = -tuning.brake_decel * traction
		elif not stalled:
			accel = -tuning.reverse_accel * -t * clampf(1.0 + forward_speed / tuning.reverse_max_speed, 0.0, 1.0)
	elif absf(forward_speed) < tuning.hold_brake_speed:
		# Hold brake: cancel residual speed so the car parks on slopes.
		# Also cancels the slope pull; cancelling speed alone leaves a steady creep of g·sin(slope)·dt.
		_parked = true
		var hold_max := tuning.hold_brake_max_accel * traction
		accel = clampf(-forward_speed / dt - _gravity.dot(fwd_g), -hold_max, hold_max)
	else:
		accel = -signf(forward_speed) * tuning.rolling_decel
	if _drive.handbrake:
		accel -= signf(forward_speed) * minf(tuning.handbrake_decel * traction, absf(forward_speed) / dt)
	if is_boosting and not stalled:
		accel += tuning.boost_accel * slow * clampf(1.0 - forward_speed / max_speed, 0.0, 1.0)
	if stalled:
		# Linear run-down: at least the Shocker's deceleration (braking may add more), never past zero.
		var opposing := maxf(-accel * signf(forward_speed), _shock_decel)
		accel = -signf(forward_speed) * minf(opposing, absf(forward_speed) / dt)
	var glued := coated_share(wheel_glue)
	if glued > 0.0 and absf(forward_speed) > max_speed:
		accel -= signf(forward_speed) * minf(tuning.glue_drag * glued, (absf(forward_speed) - max_speed) / dt)
	state.apply_central_force(fwd_g * accel * mass)

## Share of wheels (0..1) still coated with oil or glue.
func coated_share(timers: Array[float]) -> float:
	var n := 0
	for t in timers:
		if t > 0.0:
			n += 1
	return float(n) / WHEELS

## Top speed / acceleration factor from glued wheels.
func _speed_mult() -> float:
	return lerpf(1.0, tuning.glue_speed_mult, coated_share(wheel_glue))

func _apply_grip(state: PhysicsDirectBodyState3D, xf: Transform3D, right: Vector3, up: Vector3, dt: float) -> void:
	var wheel_mass := mass / WHEELS
	var max_force := wheel_mass * tuning.max_lateral_accel
	# While parked, each grounded wheel also holds its share of the sideways slope pull.
	var hold := -_gravity.dot(right) * mass / grounded_count if _parked else 0.0
	# Grip ignores the sideways wheel speed caused by the car's own yaw; otherwise grip brakes every turn
	# and the car only reaches a fraction of max_yaw_rate. Roll and pitch still count (anti-roll).
	var yaw_spin := up * state.angular_velocity.dot(up)
	var drifting := _drive.handbrake   # handbrake slides only: slip-based looseness would feed itself
	for i in WHEELS:
		if not wheel_grounded[i]:
			continue
		var front := i < 2
		var grip := tuning.front_grip if front else tuning.rear_grip
		if _drive.handbrake:
			grip = tuning.drift_front_grip if front else tuning.drift_rear_grip
		var wheel_max := max_force * (tuning.drift_lateral_accel_mult if drifting else 1.0)
		var wheel_hold := hold
		if wheel_oil[i] > 0.0:
			grip *= tuning.oil_grip_mult
			wheel_max *= tuning.oil_lateral_accel_mult
			wheel_hold = 0.0
		var offset: Vector3 = xf.basis * tuning.wheel_mounts[i]
		var lat_vel := (state.get_velocity_at_local_position(offset) - yaw_spin.cross(offset)).dot(right)
		var force := clampf(-lat_vel * grip * wheel_mass / dt + wheel_hold, -wheel_max, wheel_max)
		# Apply at a fixed low height to avoid grip-induced rollovers.
		var apply_at := offset - up * offset.dot(up) + up * tuning.grip_force_height
		state.apply_force(right * force, apply_at)

func _apply_yaw(state: PhysicsDirectBodyState3D, up: Vector3) -> void:
	var speed_abs := absf(forward_speed)
	var factor := clampf(speed_abs / tuning.full_steer_speed, 0.0, 1.0)
	if absf(_drive.throttle) > 0.01:
		factor = maxf(factor, tuning.min_steer_factor)   # can turn while pulling away
	factor *= lerpf(1.0, tuning.high_speed_steer_mult, clampf(speed_abs / tuning.max_speed, 0.0, 1.0))
	var stop_speed := tuning.direction_change_speed
	var reversing := forward_speed < -stop_speed or (_drive.throttle < 0.0 and forward_speed < stop_speed)
	var target := _drive.steer * tuning.max_yaw_rate * factor * (-1.0 if reversing else 1.0)
	if _drive.handbrake:
		target *= tuning.drift_yaw_mult
	var oiled := coated_share(wheel_oil)
	target *= lerpf(1.0, tuning.oil_yaw_mult, oiled)
	var response := tuning.yaw_response * lerpf(1.0, tuning.oil_yaw_response_mult, oiled)
	if _drive.handbrake:
		response *= tuning.drift_yaw_response_mult
	var yaw_rate := state.angular_velocity.dot(up)
	state.apply_torque(up * (target - yaw_rate) * response * tuning.inertia.y)

func _apply_air_control(state: PhysicsDirectBodyState3D, xf: Transform3D) -> void:
	var inertia_avg := (tuning.inertia.x + tuning.inertia.y + tuning.inertia.z) / 3.0
	var axes := _air_control_axes()
	var axis := Vector3.ZERO
	if _input.drive_mode == CarInput.DriveMode.DIRECTIONAL:
		var dir := Vector3(axes.x, 0.0, axes.y)
		if dir.length() > tuning.direction_deadzone:
			axis = Vector3.UP.cross(dir.normalized())   # tilts the car's up vector toward the pressed direction
	else:
		# W = nose down, S = nose up, A = roll left, D = roll right.
		axis = xf.basis.x * -axes.x + (-xf.basis.z) * -axes.y
	state.apply_torque(axis * tuning.air_control_accel * inertia_avg)
	state.apply_torque(xf.basis.y.cross(Vector3.UP) * tuning.air_auto_level * inertia_avg)  # gentle self-levelling
	state.apply_torque(-state.angular_velocity * tuning.air_angular_damp * inertia_avg)

## The two air-control input axes (classic: throttle, steer; directional: world x, world z).
## With air_control_needs_repress, an axis already held at takeoff stays inactive until it is released,
## so holding W over a jump doesn't dive the nose; pressing again in the air tilts as usual.
func _air_control_axes() -> Vector2:
	var classic := _input.drive_mode == CarInput.DriveMode.CLASSIC
	var axes := Vector2(_input.throttle, _input.steer) if classic else Vector2(_input.move_world.x, _input.move_world.z)
	if not tuning.air_control_needs_repress:
		return axes
	for i in 2:
		var held := absf(axes[i]) > tuning.direction_deadzone
		if not _was_airborne:
			# First airborne tick (_update_landing sets _was_airborne later in this tick).
			_air_axis_locked[i] = held
		elif not held:
			_air_axis_locked[i] = false
		if _air_axis_locked[i]:
			axes[i] = 0.0
	return axes

func _update_landing(state: PhysicsDirectBodyState3D, xf: Transform3D, fwd: Vector3, dt: float) -> void:
	if grounded_count == 0:
		air_time += dt
		_was_airborne = true
		return
	if _was_airborne:
		_was_airborne = false
		# Judged at the first wheel contact: the car has to arrive level, not just slap flat afterwards.
		var level := xf.basis.y.dot(_ground_normal) >= tuning.perfect_landing_dot
		if air_time >= tuning.min_air_time_for_landing and level:
			_landing_window = tuning.landing_window
			_landing_air_time = air_time
		air_time = 0.0
	if _landing_window > 0.0:
		_landing_window -= dt
		if frozen:
			_landing_window = 0.0   # no rewards outside play (e.g. the winner hopping on the podium)
		elif grounded_count == WHEELS:
			_landing_window = 0.0
			last_landing_reward = landing_reward_fraction(_landing_air_time)
			var push := lerpf(tuning.landing_boost_min, tuning.landing_boost_max, last_landing_reward)
			var fwd_g := (fwd - _ground_normal * fwd.dot(_ground_normal)).normalized()
			state.apply_central_impulse(fwd_g * push * mass)
			_pending_landing_reward = true   # battery + signal handled in _physics_process

## Perfect-landing reward share: 0 at the minimum airtime, 1 at landing_full_reward_air_time and beyond.
func landing_reward_fraction(air: float) -> float:
	return clampf(inverse_lerp(tuning.min_air_time_for_landing, tuning.landing_full_reward_air_time, air), 0.0, 1.0)

# --- Game logic (main thread, every physics tick) ----------------------------------------------

func _physics_process(delta: float) -> void:
	if not Net.is_authority():
		return
	_input = input_provider.get_car_input(self) if input_provider != null else CarInput.new()
	if frozen:
		_input = CarInput.neutral(_input.aim_point)
	last_aim_point = _input.aim_point
	for id: int in _bump_cooldowns.keys():
		_bump_cooldowns[id] = maxf(0.0, _bump_cooldowns[id] - delta)
	shock_left = maxf(0.0, shock_left - delta)
	_update_battery(delta)
	_flush_events()
	if _input.fire and held_item != null:
		var item := held_item
		set_held_item(null)
		item_used.emit(self, item, _input.aim_point)   # Match spawns the effect
	_update_recovery(delta)

## Battery gain: drifting, airtime and charging pads (only while nearly stopped). Boost drains it.
func _update_battery(delta: float) -> void:
	is_drifting = grounded_count >= 2 and absf(forward_speed) > tuning.drift_min_speed \
		and absf(lateral_speed) > tuning.drift_slip_threshold
	var gain := 0.0
	if is_drifting:
		gain += tuning.drift_charge_rate
	if grounded_count == 0 and air_time > tuning.air_charge_delay:
		gain += tuning.air_charge_rate
	if pad_overlaps > 0 and linear_velocity.length() < tuning.pad_max_speed:
		gain += tuning.pad_charge_rate
	if not _input.boost:
		_boost_locked = false
	is_boosting = _input.boost and battery > 0.0 and not _boost_locked
	if is_boosting:
		gain = -tuning.boost_drain_rate   # nothing charges while boosting
	set_battery(battery + gain * delta)
	if is_boosting and battery <= 0.0:
		_boost_locked = true   # else a trickle charge (drift, air, pad) would restart it every other tick

func _flush_events() -> void:
	if _pending_landing_reward:
		_pending_landing_reward = false
		set_battery(battery + lerpf(tuning.perfect_landing_battery_min, tuning.perfect_landing_battery_max, last_landing_reward))
		perfect_landing.emit(self)
	for hit in _pending_wall_hits:
		wall_hit.emit(self, hit["position"], hit["impact"])
	_pending_wall_hits.clear()
	for b in _pending_bumps:
		bumped.emit(self, b["attacker"], b["strength"])
	_pending_bumps.clear()
	for other in _pending_touches:
		if is_instance_valid(other) and not other.eliminated:
			touched.emit(self, other)
	_pending_touches.clear()

func _update_recovery(delta: float) -> void:
	if eliminated:
		return
	_reset_cooldown = maxf(0.0, _reset_cooldown - delta)
	if global_basis.y.dot(Vector3.UP) < tuning.flip_dot and linear_velocity.length() < tuning.flip_max_speed:
		_upside_down_time += delta
	else:
		_upside_down_time = 0.0
	if frozen:
		_upside_down_time = 0.0   # frozen cars stay as placed (podium ceremony: losers lie on their roofs)
	if (_input.reset and _reset_cooldown <= 0.0) or _upside_down_time > tuning.flip_auto_time:
		_upside_down_time = 0.0
		_reset_cooldown = tuning.reset_cooldown
		var f := -global_basis.z
		f.y = 0.0
		if f.length_squared() < 0.01:
			f = Vector3.FORWARD
		teleport_to(Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), global_position + Vector3.UP * tuning.reset_lift))
	if global_position.y < tuning.kill_y:
		respawn_requested.emit(self)

## Takes the car out of the round (hidden, frozen in place, no collisions) or brings it back (podium ceremony).
func set_eliminated(on: bool) -> void:
	eliminated = on
	visible = not on
	freeze = on
	frozen = true
	collision_layer = 0 if on else Layers.CARS
	collision_mask = 0 if on else Layers.WORLD | Layers.CARS
	if on:
		set_held_item(null)
		is_boosting = false
		is_drifting = false

## Teleports must go through _integrate_forces; setting global_position on a RigidBody3D fights the solver.
func teleport_to(xf: Transform3D) -> void:
	_pending_teleport = xf

## Explosion knockback: velocity change (m/s), a yaw spin (rad/s) and an optional tumble (world angular velocity
## change, rad/s) that tips the car.
func apply_knockback(velocity_change: Vector3, spin: float, tumble: Vector3 = Vector3.ZERO) -> void:
	apply_central_impulse(velocity_change * mass * knockback_multiplier)
	apply_torque_impulse(Vector3.UP * spin * tuning.inertia.y + angular_impulse_for(tumble, global_basis))

## Torque impulse that changes the angular velocity by `delta_omega` (world space). The inertia is set per
## body axis, so the change is converted to the body frame, scaled, and converted back.
func angular_impulse_for(delta_omega: Vector3, body_basis: Basis) -> Vector3:
	var b := body_basis.orthonormalized()
	return b * ((b.transposed() * delta_omega) * tuning.inertia)

## World position of the item model's muzzle (item: the one being fired, default the held one); aimed items point
## at last_aim_point. Computed from the car transform and ItemModels data rather than the animated model, so
## gameplay never depends on cosmetic smoothing (identical once the model has turned).
func get_muzzle_position(item: ItemDef = null) -> Vector3:
	var it := item if item != null else held_item
	if visual == null or it == null:
		return to_global(Vector3.UP * MUZZLE_FALLBACK_HEIGHT)
	var yaw := 0.0   # Shocker / Blast models face forward
	var d := to_local(last_aim_point) - visual.item_mount
	if it.aim_type != ItemDef.AimType.NONE and Vector2(d.x, d.z).length_squared() > 0.0001:
		yaw = atan2(-d.x, -d.z)
	return to_global(visual.item_mount + Basis(Vector3.UP, yaw) * ItemModels.muzzle_offset(it))

func set_battery(v: float) -> void:
	var nv := clampf(v, 0.0, 1.0)
	if not is_equal_approx(nv, battery):
		battery = nv
		battery_changed.emit(battery)

## Shocker hit: no drive for duration seconds, and the speed at the hit runs down linearly to zero over that
## time (a new shock restarts it from the current speed).
func apply_shock(duration: float) -> void:
	shock_left = maxf(shock_left, duration)
	_shock_decel = absf(forward_speed) / maxf(duration, 0.01)

func set_held_item(item: ItemDef) -> void:
	held_item = item
	item_changed.emit(item)
