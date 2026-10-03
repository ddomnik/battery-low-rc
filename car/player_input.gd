class_name PlayerInput
extends CarInputProvider
## The ONLY gameplay code that reads Input or the mouse.
## Car-relative controls in every camera mode: W/S throttle (S brakes, then reverses), A/D steer.
## Mouse: aim_point = surface under the cursor (world or car), left click fires the held item.

const AIM_RAY_LENGTH := 500.0

var camera_rig: CameraRig
var enabled: bool = true

var aim_point: Vector3 = Vector3.ZERO
var aim_normal: Vector3 = Vector3.UP
var mouse_screen_position: Vector2 = Vector2.ZERO   # for the 2D crosshair

var _fire_latched: bool = false
var _reset_latched: bool = false
var _current: CarInput = CarInput.new()

func _physics_process(_delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	mouse_screen_position = get_viewport().get_mouse_position()
	aim_at_screen(mouse_screen_position)
	var i := CarInput.new()
	i.drive_mode = CarInput.DriveMode.CLASSIC
	i.aim_point = aim_point
	if enabled:
		if Input.is_action_just_pressed("fire"):
			_fire_latched = true
		if Input.is_action_just_pressed("reset"):
			_reset_latched = true
		i.throttle = Input.get_axis("move_down", "move_up")
		i.steer = -Input.get_axis("move_left", "move_right")   # + = left
		i.handbrake = Input.is_action_pressed("handbrake")
		i.boost = Input.is_action_pressed("boost")
	_current = i
	camera_rig.aim_point = aim_point
	camera_rig.has_aim = true

## Called by the car once per tick; edge-triggered actions are consumed here.
func get_car_input(_car: Car) -> CarInput:
	_current.fire = _fire_latched
	_current.reset = _reset_latched
	_fire_latched = false
	_reset_latched = false
	return _current

## Raycasts from the camera through a screen position onto the world or a car (own car excluded) and updates
## aim_point / aim_normal. Falls back to the horizontal plane at the car's height. Physics ticks only.
func aim_at_screen(screen_pos: Vector2) -> void:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * AIM_RAY_LENGTH, Layers.WORLD | Layers.CARS, [car.get_rid()])
	var hit := car.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		aim_point = hit.position
		aim_normal = hit.normal
	else:
		var p: Variant = Plane(Vector3.UP, car.global_position.y).intersects_ray(from, dir)
		if p != null:
			aim_point = p
			aim_normal = Vector3.UP
