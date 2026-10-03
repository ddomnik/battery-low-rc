class_name ChargingPad
extends Area3D
## Charging pad (§7.2): a car standing (nearly) still on it recharges its battery.
## The pad only counts overlaps (Car.pad_overlaps); the car decides how much it charges.

const SIZE := 5.0
const TRIGGER_HEIGHT := 2.0
const THICKNESS := 0.04              # visual only; wheels never touch it (no collision on WORLD)
const COLOR := Color(1.0, 0.85, 0.2)
const EMISSION_MIN := 0.4
const EMISSION_MAX := 1.4
const PULSE_SPEED := 2.5

var _material: StandardMaterial3D
var _time: float = 0.0

func _ready() -> void:
	collision_layer = Layers.TRIGGERS
	collision_mask = Layers.CARS
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE, TRIGGER_HEIGHT, SIZE)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = TRIGGER_HEIGHT * 0.5
	add_child(cs)

	_material = StandardMaterial3D.new()
	_material.albedo_color = COLOR
	_material.emission_enabled = true
	_material.emission = COLOR
	var mesh := BoxMesh.new()
	mesh.size = Vector3(SIZE, THICKNESS, SIZE)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material
	mi.position.y = THICKNESS * 0.5
	mi.layers = Layers.RENDER_WORLD
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(delta: float) -> void:
	_time += delta
	_material.emission_energy_multiplier = lerpf(EMISSION_MIN, EMISSION_MAX, 0.5 + 0.5 * sin(_time * PULSE_SPEED))

func _on_body_entered(body: Node3D) -> void:
	var car := body as Car
	if car != null and Net.is_authority():
		car.pad_overlaps += 1

func _on_body_exited(body: Node3D) -> void:
	var car := body as Car
	if car != null and Net.is_authority():
		car.pad_overlaps = maxi(0, car.pad_overlaps - 1)
