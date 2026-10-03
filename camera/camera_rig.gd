class_name CameraRig
extends Node3D
## Top-down camera with a fixed pitch that lazily follows the local car with look-ahead toward velocity and cursor.
## FOLLOW: the yaw smoothly swings behind the car's nose, so screen-up ≈ the car's forward.
## FIXED: the yaw stays at fixed_yaw_deg (0 = north-up). This is purely local presentation; gameplay never reads it.

enum Mode { FOLLOW, FIXED }

@export var mode: Mode = Mode.FOLLOW
@export var pitch_deg: float = 45.0           # pitch, distance and fov apply live (tune them in the Remote tree)
@export var fixed_yaw_deg: float = 0.0        # FIXED mode yaw; 0 = north-up
@export var yaw_follow_sharpness: float = 3.0 # 1/s; FOLLOW mode, lower = lazier rotation
@export var follow_min_up_dot: float = 0.5    # heading is only followed while the car is roughly upright
@export var distance: float = 50.0            # along the view direction; height above the focus = sin(pitch) · distance
@export var view_offset: float = 3.5           # m; shifts the view up so the car sits below screen center (more view ahead)
@export var fov_deg: float = 35.0             # narrow FOV from far away ≈ near-orthographic readability
@export var follow_sharpness: float = 3.5     # 1/s; lower = lazier
@export var height_sharpness: float = 1.5     # vertical follow is slower so bumps don't bob the view
@export var velocity_lookahead_time: float = 0.25
@export var max_velocity_lookahead: float = 5.0
@export var aim_lookahead_fraction: float = 0.25
@export var max_aim_lookahead: float = 6.0
@export var lookahead_sharpness: float = 2.5
@export var shake_decay: float = 1.6
@export var shake_max_offset: float = 0.6
@export var shake_noise_speed: float = 60.0

var target: Car = null
var aim_point: Vector3 = Vector3.ZERO   # written by PlayerInput
var has_aim: bool = false
var camera: Camera3D = null

var _focus: Vector3 = Vector3.ZERO
var _lookahead: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _goal_yaw: float = 0.0
var _trauma: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()
var _time: float = 0.0

static func mode_label(m: Mode) -> String:
	return "Follow" if m == Mode.FOLLOW else "Classic (fixed)"

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	add_child(camera)
	# Moved in _process from interpolated targets → own interpolation off.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.current = true
	_yaw = deg_to_rad(fixed_yaw_deg)
	_goal_yaw = _yaw
	rotation = Vector3(0.0, _yaw, 0.0)
	_apply_lens()

## Places the camera on the rig from pitch_deg, distance and fov_deg.
func _apply_lens() -> void:
	var pitch := deg_to_rad(pitch_deg)
	camera.fov = fov_deg
	camera.position = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
	camera.rotation = Vector3(-pitch, 0.0, 0.0)
	camera.v_offset = view_offset

func screen_up_world() -> Vector3:
	var v := -global_basis.z
	v.y = 0.0
	return v.normalized()

func screen_right_world() -> Vector3:
	var v := global_basis.x
	v.y = 0.0
	return v.normalized()

func snap_to_target() -> void:
	if target != null:
		_focus = target.global_position
		_lookahead = Vector3.ZERO
		global_position = _focus
		_update_goal_yaw(target.global_transform, true)   # freshly spawned cars are not grounded yet
		_yaw = _goal_yaw
		rotation.y = _yaw

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func _process(delta: float) -> void:
	_apply_lens()
	if target == null or not is_instance_valid(target):
		return
	var car_xf := target.get_global_transform_interpolated()
	_update_goal_yaw(car_xf)
	_yaw = lerp_angle(_yaw, _goal_yaw, 1.0 - exp(-yaw_follow_sharpness * delta))
	rotation.y = _yaw

	var car_pos := car_xf.origin
	var vel := target.linear_velocity
	vel.y = 0.0
	var wanted := (vel * velocity_lookahead_time).limit_length(max_velocity_lookahead)
	if has_aim:
		var to_aim := aim_point - car_pos
		to_aim.y = 0.0
		wanted += (to_aim * aim_lookahead_fraction).limit_length(max_aim_lookahead)
	_lookahead = _lookahead.lerp(wanted, 1.0 - exp(-lookahead_sharpness * delta))
	var goal := car_pos + _lookahead
	var xz := Vector2(_focus.x, _focus.z).lerp(Vector2(goal.x, goal.z), 1.0 - exp(-follow_sharpness * delta))
	var y := lerpf(_focus.y, goal.y, 1.0 - exp(-height_sharpness * delta))
	_focus = Vector3(xz.x, y, xz.y)
	global_position = _focus

	_time += delta
	_trauma = maxf(_trauma - shake_decay * delta, 0.0)
	var s := _trauma * _trauma * shake_max_offset
	camera.h_offset = _noise.get_noise_2d(_time * shake_noise_speed, 0.0) * s
	camera.v_offset = view_offset + _noise.get_noise_2d(0.0, _time * shake_noise_speed) * s

## FIXED: the fixed yaw. FOLLOW: the yaw that puts the camera behind the car's nose, updated only while the car
## is on the ground and upright, so jumps, flips and reversing don't swing the view.
func _update_goal_yaw(car_xf: Transform3D, ignore_grounding: bool = false) -> void:
	if mode == Mode.FIXED:
		_goal_yaw = deg_to_rad(fixed_yaw_deg)
		return
	var settled := target.grounded_count >= 2 and car_xf.basis.y.dot(Vector3.UP) >= follow_min_up_dot
	if not settled and not ignore_grounding:
		return
	var fwd := -car_xf.basis.z
	if Vector2(fwd.x, fwd.z).length_squared() > 0.01:
		_goal_yaw = atan2(-fwd.x, -fwd.z)
