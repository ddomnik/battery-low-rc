class_name Projectile
extends Node3D
## Rocket or water balloon, moved by a manual sweep every physics tick (deterministic, network-friendly).
## The path is evaluated analytically (p0 + v0·t + ½·g·t²), so lobs land exactly where the aim preview says.

const HIT_RADIUS := 0.9              # generous car hit test around the car origin
const OWNER_IMMUNITY := 0.25         # seconds the shooter can't be hit by its own projectile
const ROCKET_RADIUS := 0.09
const ROCKET_LENGTH := 0.5
const BALLOON_RADIUS := 0.3
const WOBBLE_SPEED := 14.0
const WOBBLE_AMOUNT := 0.08
const VERTICAL_FACING_LIMIT := 0.98  # skip look_at when the velocity is this close to vertical

var match_node: Match = null
var shooter: Car = null
var item: ItemDef = null

var _origin: Vector3 = Vector3.ZERO
var _velocity0: Vector3 = Vector3.ZERO
var _gravity: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _body: MeshInstance3D = null

## Call before adding to the tree.
func launch(m: Match, from_car: Car, item_def: ItemDef, origin: Vector3, velocity: Vector3) -> void:
	match_node = m
	shooter = from_car
	item = item_def
	_origin = origin
	_velocity0 = velocity
	_gravity = Vector3.DOWN * item_def.gravity
	position = origin

func _ready() -> void:
	_build_visual()
	_face(_velocity0)
	reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	if not Net.is_authority():
		return
	var from := _position_at(_age)
	_age += delta
	var to := _position_at(_age)
	var hit: Variant = _sweep(from, to)
	if hit != null or _age >= item.lifetime:
		var at: Vector3 = hit if hit != null else to
		match_node.explode(at, item.explosion_radius, item.knockback, item.up_knockback, shooter, item.spin, item.tumble)
		queue_free()
		return
	global_position = to
	_face(_velocity0 + _gravity * _age)

func _process(_delta: float) -> void:
	if item.kind == ItemDef.Kind.BALLOON and _body != null:
		var w := sin(_age * WOBBLE_SPEED) * WOBBLE_AMOUNT
		_body.scale = Vector3(1.0 + w, 1.0 - w, 1.0 + w)

func _position_at(t: float) -> Vector3:
	return _origin + _velocity0 * t + 0.5 * _gravity * t * t

## Returns the first hit point on the segment (world geometry or a car), or null.
func _sweep(from: Vector3, to: Vector3) -> Variant:
	var immune := _age <= OWNER_IMMUNITY and is_instance_valid(shooter)
	var exclude: Array[RID] = []
	if immune:
		exclude.append(shooter.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD | Layers.CARS, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var best: Variant = null
	var best_dist := INF
	if not hit.is_empty():
		best = hit.position
		best_dist = from.distance_to(hit.position)
	for car in match_node.cars:
		if immune and car == shooter:
			continue
		var p := Geometry3D.get_closest_point_to_segment(car.global_position, from, to)
		if p.distance_to(car.global_position) < HIT_RADIUS and from.distance_to(p) < best_dist:
			best = p
			best_dist = from.distance_to(p)
	return best

func _face(velocity: Vector3) -> void:
	if velocity.length_squared() < 0.0001 or absf(velocity.normalized().dot(Vector3.UP)) > VERTICAL_FACING_LIMIT:
		return
	look_at(global_position + velocity, Vector3.UP)

func _build_visual() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = item.color
	_body = MeshInstance3D.new()
	_body.material_override = mat
	if item.kind == ItemDef.Kind.BALLOON:
		var sphere := SphereMesh.new()
		sphere.radius = BALLOON_RADIUS
		sphere.height = BALLOON_RADIUS * 2.0
		_body.mesh = sphere
		add_child(_body)
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = ROCKET_RADIUS
	cyl.bottom_radius = ROCKET_RADIUS
	cyl.height = ROCKET_LENGTH
	_body.mesh = cyl
	_body.rotation.x = -PI * 0.5   # cylinder axis (Y) along the flight direction (−Z)
	add_child(_body)
	var flame := CPUParticles3D.new()
	flame.position = Vector3(0.0, 0.0, ROCKET_LENGTH * 0.5)
	flame.amount = 24
	flame.lifetime = 0.25
	flame.local_coords = false
	flame.direction = Vector3(0.0, 0.0, 1.0)
	flame.spread = 15.0
	flame.initial_velocity_min = 2.0
	flame.initial_velocity_max = 4.0
	flame.gravity = Vector3.ZERO
	flame.scale_amount_min = 0.6
	flame.scale_amount_max = 1.0
	flame.color = Color(1.0, 0.7, 0.2)
	flame.mesh = Effects.particle_mesh(0.12)
	add_child(flame)
