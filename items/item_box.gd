class_name ItemBox
extends Area3D
## Pickup box (§7.6.3). An empty-handed car that touches it gets a rolled item (Match.roll_item);
## the box then hides and comes back at its home spot after respawn_time. A car already holding an item drives through.
## Magnet: the nearest car with a free item slot within magnet_range pulls the box like gravity (stronger when
## closer). With nobody pulling, the box drifts back home. Movement happens on the authority only.

const SHAPE_SIZE := 1.4
const VISUAL_SIZE := 1.0
const SPIN_SPEED := 1.5              # rad/s
const BOB_HEIGHT := 0.15
const BOB_SPEED := 2.5
const HUE_SPEED := 0.25              # rainbow cycles per second
const ALPHA := 0.6
const LABEL_FONT_SIZE := 96
const RECHECK_TICKS := 2             # physics ticks after reactivation before re-checking overlaps
const MIN_PULL_DISTANCE := 0.5       # caps the 1/d² pull very close to the car

@export var respawn_time: float = 6.0

@export_group("Magnet")
@export var magnet_range: float = 7.0            # cars with a free item slot within this distance pull the box
@export var magnet_strength: float = 150.0       # gravity-like pull: acceleration = strength / distance² (m/s²)
@export var magnet_max_accel: float = 45.0
@export var magnet_max_speed: float = 24.0       # faster than a car at full speed (18), slower than boost
@export var magnet_steer: float = 8.0            # 1/s; turns the box's velocity toward the car so it doesn't orbit
@export var magnet_max_height_diff: float = 2.0  # cars on another level (e.g. under the table) don't pull
@export var return_speed: float = 4.0            # m/s back to the home spot when nobody pulls

var match_node: Match = null
var active: bool = true

var _home: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO
var _visual: Node3D
var _material: StandardMaterial3D
var _timer: Timer
var _recheck_ticks: int = 0
var _time: float = 0.0

func _ready() -> void:
	_home = global_position
	collision_layer = Layers.PICKUPS
	collision_mask = Layers.CARS
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * SHAPE_SIZE
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)

	# The box moves in physics ticks (interpolated); the visual follows the interpolated position every frame,
	# adding spin and bob, so it is top-level with its own interpolation off.
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.top_level = true
	_visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_visual)
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * VISUAL_SIZE
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(mi)
	var label := Label3D.new()
	label.text = "?"
	label.font_size = LABEL_FONT_SIZE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 12
	_visual.add_child(label)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_reactivate)
	add_child(_timer)
	body_entered.connect(_try_pickup)
	_time = (position.x + position.z) * 0.37   # cosmetic phase offset so boxes don't spin in sync
	_process(0.0)

func _process(delta: float) -> void:
	if not active:
		return
	_time += delta
	var origin := get_global_transform_interpolated().origin
	_visual.global_transform = Transform3D(Basis(Vector3.UP, _time * SPIN_SPEED), origin + Vector3.UP * sin(_time * BOB_SPEED) * BOB_HEIGHT)
	_material.albedo_color = Color.from_hsv(fposmod(_time * HUE_SPEED, 1.0), 0.7, 1.0, ALPHA)

func _physics_process(delta: float) -> void:
	if _recheck_ticks > 0:
		_recheck_ticks -= 1
		if _recheck_ticks == 0:
			# A car may already be parked inside when the box comes back.
			for body in get_overlapping_bodies():
				_try_pickup(body)
	if active and Net.is_authority():
		_update_magnet(delta)

## Gravity-like pull toward the nearest eligible car, or a slow drift back home.
func _update_magnet(delta: float) -> void:
	var car := _magnet_target()
	if car == null:
		_velocity = Vector3.ZERO
		if not global_position.is_equal_approx(_home):
			global_position = global_position.move_toward(_home, return_speed * delta)
		return
	var to := car.global_position - global_position
	var dist := maxf(to.length(), MIN_PULL_DISTANCE)
	var dir := to / dist
	var accel := minf(magnet_strength / (dist * dist), magnet_max_accel)
	_velocity += dir * accel * delta
	var speed := minf(_velocity.length(), magnet_max_speed)
	_velocity = _velocity.lerp(dir * speed, 1.0 - exp(-magnet_steer * delta))
	global_position += _velocity * delta

func _magnet_target() -> Car:
	if match_node == null:
		return null
	var best: Car = null
	var best_d := magnet_range
	for car in match_node.cars:
		if car.held_item != null or absf(car.global_position.y - global_position.y) > magnet_max_height_diff:
			continue
		var d := car.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = car
	return best

func _try_pickup(body: Node3D) -> void:
	if not active or not Net.is_authority() or match_node == null:
		return
	var car := body as Car
	if car == null or car.held_item != null:
		return
	car.set_held_item(match_node.roll_item(car))
	match_node.play_effect(&"pickup", global_position, 0.0)
	_deactivate()

func _deactivate() -> void:
	active = false
	visible = false
	set_deferred("monitoring", false)
	_go_home.call_deferred()      # may run inside a physics callback; move the area afterwards
	_timer.start(respawn_time)   # child Timer: dies with the match, unlike a SceneTreeTimer

func _go_home() -> void:
	_velocity = Vector3.ZERO
	global_position = _home
	reset_physics_interpolation()

func _reactivate() -> void:
	active = true
	visible = true
	set_deferred("monitoring", true)
	_recheck_ticks = RECHECK_TICKS
