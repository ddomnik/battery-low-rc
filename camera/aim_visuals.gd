class_name AimVisuals
extends Node3D
## Local player only (§7.5): reticle on the surface under the cursor, rocket aim line, balloon lob arc with a
## landing ring, and the 2D crosshair. Purely cosmetic; reads PlayerInput (the only mouse reader) and the car.

const RETICLE_INNER := 0.32
const RETICLE_OUTER := 0.45
const SURFACE_LIFT := 0.05
const FLAT := 0.05                   # torus y scale → flat ring
const COLOR_NO_AIM := Color(1.0, 1.0, 1.0)
const ROCKET_LINE_LENGTH := 8.0
const ROCKET_LINE_ALPHA := 0.45
const ARC_SAMPLES := 24
const ARC_ALPHA := 0.85
const LANDING_RING_ALPHA := 0.7
const CROSSHAIR_LAYER := 5

var match_node: Match = null
var player_input: PlayerInput = null
var car: Car = null

var _reticle: MeshInstance3D
var _reticle_mat: StandardMaterial3D
var _landing_ring: MeshInstance3D
var _landing_mat: StandardMaterial3D
var _lines: ImmediateMesh = ImmediateMesh.new()
var _line_mat: StandardMaterial3D
var _crosshair: Crosshair
var _lob_target: Vector3 = Vector3.ZERO
var _has_lob_target: bool = false

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # repositioned every frame
	_reticle_mat = _unshaded()
	_reticle = _ring_mesh(RETICLE_INNER, RETICLE_OUTER, _reticle_mat)
	_landing_mat = _unshaded()
	_landing_ring = _ring_mesh(0.92, 1.0, _landing_mat)
	_line_mat = _unshaded()
	_line_mat.vertex_color_use_as_albedo = true
	var lines := MeshInstance3D.new()
	lines.mesh = _lines
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lines)
	var layer := CanvasLayer.new()
	layer.layer = CROSSHAIR_LAYER
	add_child(layer)
	_crosshair = Crosshair.new()
	layer.add_child(_crosshair)

func _physics_process(_delta: float) -> void:
	# Down-rays need physics access: clamp the lob target here and cache it for drawing.
	_has_lob_target = false
	var item: ItemDef = car.held_item if car != null else null
	if item != null and item.aim_type == ItemDef.AimType.LOB:
		var space := get_world_3d().direct_space_state
		_lob_target = Ballistics.clamp_target(space, car.global_position, player_input.aim_point, item.max_range)
		_has_lob_target = true

func _process(_delta: float) -> void:
	if car == null or player_input == null:
		return
	_crosshair.visible = match_node.desired_mouse_mode() == Input.MOUSE_MODE_CONFINED_HIDDEN
	_crosshair.move_to(player_input.mouse_screen_position)

	var item := car.held_item
	var aim_type := item.aim_type if item != null else ItemDef.AimType.NONE
	var color := item.color if aim_type != ItemDef.AimType.NONE else COLOR_NO_AIM
	_place_flat(_reticle, player_input.aim_point, player_input.aim_normal, 1.0)
	_reticle_mat.albedo_color = color

	_lines.clear_surfaces()
	_landing_ring.visible = false
	var muzzle := _muzzle_position()
	if aim_type == ItemDef.AimType.STRAIGHT:
		var to := player_input.aim_point
		var end := muzzle + (to - muzzle).limit_length(ROCKET_LINE_LENGTH)
		_lines.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
		_line(muzzle, end, Color(color, ROCKET_LINE_ALPHA))
		_lines.surface_end()
	elif aim_type == ItemDef.AimType.LOB and _has_lob_target:
		_draw_lob_arc(muzzle, _lob_target, item, Color(color, ARC_ALPHA))
		_place_flat(_landing_ring, _lob_target, Vector3.UP, item.explosion_radius)
		_landing_mat.albedo_color = Color(color, LANDING_RING_ALPHA)
		_landing_ring.visible = true

## Same parabola the projectile will fly (Ballistics.lob_velocity), drawn as dashes.
func _draw_lob_arc(from: Vector3, to: Vector3, item: ItemDef, color: Color) -> void:
	var flight := Ballistics.lob_flight_time(Vector2(to.x - from.x, to.z - from.z).length(), item.max_range)
	var v0 := Ballistics.lob_velocity(from, to, item.gravity, flight)
	var g := Vector3.DOWN * item.gravity
	_lines.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
	for i in range(0, ARC_SAMPLES, 2):
		var t0 := flight * float(i) / float(ARC_SAMPLES)
		var t1 := flight * float(i + 1) / float(ARC_SAMPLES)
		_line(from + v0 * t0 + 0.5 * g * t0 * t0, from + v0 * t1 + 0.5 * g * t1 * t1, color)
	_lines.surface_end()

func _muzzle_position() -> Vector3:
	var v := car.visual
	if v != null and v.muzzle != null:
		return v.muzzle.get_global_transform_interpolated().origin
	return car.get_global_transform_interpolated().origin

func _place_flat(node: MeshInstance3D, pos: Vector3, normal: Vector3, radius_scale: float) -> void:
	var b := Basis(Quaternion(Vector3.UP, normal.normalized())) * Basis.from_scale(Vector3(radius_scale, FLAT, radius_scale))
	node.global_transform = Transform3D(b, pos + normal * SURFACE_LIFT)

func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(a)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(b)

func _ring_mesh(inner: float, outer: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _unshaded() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat
