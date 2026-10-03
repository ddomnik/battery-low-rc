class_name DebugDraw
extends Node3D
## F4: wheel rays (green grounded, red airborne), suspension force per wheel, velocity vector.
## Rebuilt every rendered frame from the interpolated car transforms.

const FORCE_SCALE := 0.0006           # m of line per N of suspension force
const VELOCITY_SCALE := 0.25          # m of line per m/s
const COLOR_GROUNDED := Color(0.2, 1.0, 0.2)
const COLOR_AIRBORNE := Color(1.0, 0.2, 0.2)
const COLOR_FORCE := Color(1.0, 0.9, 0.1)
const COLOR_VELOCITY := Color(0.2, 0.8, 1.0)

var match_node: Match = null

var _mesh: ImmediateMesh = ImmediateMesh.new()
var _material: StandardMaterial3D = StandardMaterial3D.new()
var _enabled: bool = false

func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_draw"):
		_enabled = not _enabled
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	if not _enabled or match_node == null or match_node.cars.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	for car in match_node.cars:
		_draw_car(car)
	_mesh.surface_end()

func _draw_car(car: Car) -> void:
	var t := car.tuning
	var xf := car.get_global_transform_interpolated()
	var up := xf.basis.y
	for i in Car.WHEELS:
		var from: Vector3 = xf * t.wheel_mounts[i]
		if car.wheel_grounded[i]:
			_line(from, from - up * (car.wheel_spring_len[i] + t.wheel_radius), COLOR_GROUNDED)
		else:
			_line(from, from - up * (t.suspension_rest_length + t.wheel_radius), COLOR_AIRBORNE)
		if car.wheel_force[i] > 0.0:
			_line(from, from + up * car.wheel_force[i] * FORCE_SCALE, COLOR_FORCE)
	_line(xf.origin, xf.origin + car.linear_velocity * VELOCITY_SCALE, COLOR_VELOCITY)

func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(b)
