class_name CameraRig
extends Node3D
## Top-down camera with a fixed pitch that lazily follows the local car with look-ahead toward velocity and cursor.
## FOLLOW: the yaw smoothly swings behind the car's nose, so screen-up ≈ the car's forward.
## FIXED: the yaw stays at fixed_yaw_deg (0 = north-up). This is purely local presentation; gameplay never reads it.

enum Mode {FOLLOW, FIXED}

@export var mode: Mode = Mode.FOLLOW
@export var pitch_deg: float = 45.0 # pitch, distance and fov apply live (tune them in the Remote tree)
@export var fixed_yaw_deg: float = 0.0 # FIXED mode yaw; 0 = north-up
@export var yaw_follow_sharpness: float = 3.0 # 1/s; FOLLOW mode, lower = lazier rotation
@export var follow_min_up_dot: float = 0.5 # heading is only followed while the car is roughly upright
@export var distance: float = 50.0 # along the view direction; height above the focus = sin(pitch) · distance
@export var view_offset: float = -1.0 # m; negative: car sits above screen center (more view behind), positive: below
@export var fov_deg: float = 35.0 # narrow FOV from far away ≈ near-orthographic readability
@export var follow_sharpness: float = 3.5 # 1/s; lower = lazier
@export var height_sharpness: float = 1.5 # vertical follow is slower so bumps don't bob the view
@export var velocity_lookahead_time: float = 0.25
@export var max_velocity_lookahead: float = 5.0
@export var aim_lookahead_fraction: float = 0.25
@export var max_aim_lookahead: float = 6.0
@export var lookahead_sharpness: float = 2.5 # velocity look-ahead (lazy)
@export var aim_lookahead_sharpness: float = 5.0 # mouse look-ahead: applied on top of the lazy follow, so it reacts fast
@export var shake_decay: float = 1.6
@export var shake_max_offset: float = 0.6
@export var shake_noise_speed: float = 60.0
@export var showcase_distance: float = 24.0    # closer view for the podium ceremony
@export var showcase_sharpness: float = 2.0   # 1/s; glide to the podium
@export var showcase_swivel_deg: float = 9.0  # the podium view slowly sways left and right by this much
@export var showcase_swivel_speed: float = 0.5
@export var cutout_radius: float = 3.5        # occlusion cutout around the camera→car line (m); 0 = off
@export var cutout_transparency: float = 0.7  # how see-through the cut area gets (0..1)
@export var cutout_fade_speed: float = 8.0    # 1/s; fade in / out when the car gets hidden / visible

var target: Car = null
var aim_point: Vector3 = Vector3.ZERO # written by PlayerInput
var has_aim: bool = false
var camera: Camera3D = null

var _focus: Vector3 = Vector3.ZERO
var _lookahead: Vector3 = Vector3.ZERO
var _aim_lookahead: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _goal_yaw: float = 0.0
var _trauma: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()
var _time: float = 0.0
var _car_hidden: bool = false
var _showcase: bool = false           # looking at a fixed point (podium) instead of following the car
var _showcase_point: Vector3 = Vector3.ZERO
var _lens_distance: float = 0.0
var _cutout_amount: float = 0.0       # 0..1, faded toward _car_hidden

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
	_lens_distance = distance
	_apply_lens()

## Places the camera on the rig from pitch_deg, distance and fov_deg.
func _apply_lens() -> void:
	var pitch := deg_to_rad(pitch_deg)
	camera.fov = fov_deg
	camera.position = Vector3(0.0, sin(pitch) * _lens_distance, cos(pitch) * _lens_distance)
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
		_aim_lookahead = Vector3.ZERO
		global_position = _focus
		_update_goal_yaw(target.global_transform, true) # freshly spawned cars are not grounded yet
		_yaw = _goal_yaw
		rotation.y = _yaw

func _process_showcase(delta: float) -> void:
	var blend := 1.0 - exp(-showcase_sharpness * delta)
	_time += delta
	var swivel := deg_to_rad(showcase_swivel_deg) * sin(_time * showcase_swivel_speed)
	_yaw = lerp_angle(_yaw, swivel, blend)
	rotation.y = _yaw
	_focus = _focus.lerp(_showcase_point, blend)
	global_position = _focus
	_car_hidden = false
	RenderingServer.global_shader_parameter_set(&"cutout_strength", 0.0)

func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"cutout_strength", 0.0)   # no match → nothing is cut

## Is the car hidden behind world geometry? Rays from the camera to the car's center, nose and tail
## (physics queries belong in physics ticks; _process fades the cutout from the result).
func _physics_process(_delta: float) -> void:
	_car_hidden = false
	if _showcase or target == null or not is_instance_valid(target) or camera == null:
		return
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var xf := target.global_transform
	for local: Vector3 in [Vector3(0.0, 0.4, 0.0), Vector3(0.0, 0.2, -0.9), Vector3(0.0, 0.2, 0.9)]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, xf * local, Layers.WORLD))
		if not hit.is_empty():
			_car_hidden = true
			return

## Glides to a fixed point, north-up and closer (podium ceremony). Stays there until the match ends.
func show_point(point: Vector3) -> void:
	_showcase = true
	_showcase_point = point

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func _process(delta: float) -> void:
	_lens_distance = lerpf(_lens_distance, showcase_distance if _showcase else distance, 1.0 - exp(-showcase_sharpness * delta))
	_apply_lens()
	if _showcase:
		_process_showcase(delta)
		return
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
	_lookahead = _lookahead.lerp(wanted, 1.0 - exp(-lookahead_sharpness * delta))
	var wanted_aim := Vector3.ZERO
	if has_aim:
		var to_aim := aim_point - car_pos
		to_aim.y = 0.0
		wanted_aim = (to_aim * aim_lookahead_fraction).limit_length(max_aim_lookahead)
	_aim_lookahead = _aim_lookahead.lerp(wanted_aim, 1.0 - exp(-aim_lookahead_sharpness * delta))
	var goal := car_pos + _lookahead
	var xz := Vector2(_focus.x, _focus.z).lerp(Vector2(goal.x, goal.z), 1.0 - exp(-follow_sharpness * delta))
	var y := lerpf(_focus.y, goal.y, 1.0 - exp(-height_sharpness * delta))
	_focus = Vector3(xz.x, y, xz.y)
	global_position = _focus + _aim_lookahead
	_cutout_amount = move_toward(_cutout_amount, 1.0 if _car_hidden else 0.0, delta * cutout_fade_speed)
	RenderingServer.global_shader_parameter_set(&"focus_car_pos", car_pos)
	RenderingServer.global_shader_parameter_set(&"cutout_radius", cutout_radius)
	RenderingServer.global_shader_parameter_set(&"cutout_strength", cutout_transparency * _cutout_amount)

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
