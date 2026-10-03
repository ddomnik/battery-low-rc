class_name ShockArc
extends MeshInstance3D
## Jagged electric bolt from one node to another node (or a fixed point), re-struck many times a second so it
## crackles. Drawn as camera-facing ribbons: a soft blue glow plus a thin white core, with a few short forks.
## Alpha-blended rather than additive so it still reads on the light floor.
## Cosmetic only (spawned by Effects); its randomness is not gameplay randomness.

const SEGMENTS := 12
const JITTER := 0.45            # sideways kink (m) in the middle of the bolt …
const JITTER_PER_METER := 0.06  # … plus this much per meter of bolt length
const BOW := 0.5                # the bolt arches up this much (m) in the middle
const RESTRIKE_TIME := 0.045    # a new random bolt shape this often
const LIFT := 0.45              # above the node origins (roughly the car roofs)
const CORE_WIDTH := 0.14
const GLOW_WIDTH := 0.9
const CORE_COLOR := Color(0.92, 0.98, 1.0)
const GLOW_COLOR := Color(0.15, 0.55, 1.0, 0.8)
const FORKS := 3
const FORK_SEGMENTS := 4
const FORK_LENGTH := 1.4
const FORK_WIDTH_SCALE := 0.6
const MIN_FLICKER := 0.55       # each strike is this bright … full brightness
const FADE_SHARE := 0.4         # fades out over the last part of its life

var from_node: Node3D = null
var to_node: Node3D = null
var from_point: Vector3 = Vector3.ZERO   # used when from_node is gone / not set (world, already lifted)
var to_point: Vector3 = Vector3.ZERO
var duration: float = 0.5

var _age: float = 0.0
var _restrike: float = 0.0
var _flicker: float = 1.0
var _offsets: PackedVector2Array = PackedVector2Array()   # per bolt point: sideways kink (unit-less)
var _forks: Array[PackedVector3Array] = []                # per fork: its anchor index, then world offsets
var _fork_at: PackedInt32Array = PackedInt32Array()
var _rng := RandomNumberGenerator.new()
var _imesh := ImmediateMesh.new()

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # rebuilt every frame
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	_rng.randomize()
	_update_ends()
	_strike()
	_draw()

func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	_update_ends()
	_restrike -= delta
	if _restrike <= 0.0:
		_strike()
	_draw()

func _update_ends() -> void:
	if is_instance_valid(from_node):
		from_point = from_node.get_global_transform_interpolated().origin + Vector3.UP * LIFT
	if is_instance_valid(to_node):
		to_point = to_node.get_global_transform_interpolated().origin + Vector3.UP * LIFT

## New random shape: kinks along the bolt and a few forks.
func _strike() -> void:
	_restrike = RESTRIKE_TIME
	_flicker = _rng.randf_range(MIN_FLICKER, 1.0)
	_offsets.resize(SEGMENTS + 1)
	for k in SEGMENTS + 1:
		_offsets[k] = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
	_forks.clear()
	_fork_at.clear()
	for f in FORKS:
		var fork := PackedVector3Array([Vector3.ZERO])
		var dir := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.3, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()
		var step := FORK_LENGTH / FORK_SEGMENTS
		for s in FORK_SEGMENTS:
			var kink := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * step * 0.6
			fork.append(fork[fork.size() - 1] + dir * step + kink)
		_forks.append(fork)
		_fork_at.append(_rng.randi_range(2, SEGMENTS - 2))

func _bolt_points() -> PackedVector3Array:
	var span := to_point - from_point
	var length := span.length()
	var dir := span / length if length > 0.001 else Vector3.FORWARD
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var lift := side.cross(dir).normalized()
	var jitter := JITTER + JITTER_PER_METER * length
	var points := PackedVector3Array()
	for k in SEGMENTS + 1:
		var t := float(k) / SEGMENTS
		var envelope := sin(PI * t)
		var o := _offsets[k] * jitter * envelope
		points.append(from_point + span * t + side * o.x + lift * o.y + Vector3.UP * BOW * envelope)
	return points

func _draw() -> void:
	_imesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam != null else from_point + Vector3.UP * 50.0
	var fade := clampf((duration - _age) / (duration * FADE_SHARE), 0.0, 1.0)
	var bright := _flicker * fade
	var bolt := _bolt_points()
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_ribbon(bolt, eye, GLOW_WIDTH, _faded(GLOW_COLOR, bright), true)
	_ribbon(bolt, eye, CORE_WIDTH, _faded(CORE_COLOR, bright), false)
	for f in _forks.size():
		var anchor := bolt[_fork_at[f]]
		var fork := PackedVector3Array()
		for p: Vector3 in _forks[f]:
			fork.append(anchor + p)
		_ribbon(fork, eye, GLOW_WIDTH * FORK_WIDTH_SCALE, _faded(GLOW_COLOR, bright * 0.7), true)
		_ribbon(fork, eye, CORE_WIDTH * FORK_WIDTH_SCALE, _faded(CORE_COLOR, bright * 0.8), false)
	_imesh.surface_end()

func _faded(c: Color, k: float) -> Color:
	return Color(c, c.a * k)

## A camera-facing strip along the points. soft = opaque center fading out at both edges (glow).
func _ribbon(points: PackedVector3Array, eye: Vector3, width: float, color: Color, soft: bool) -> void:
	var n := points.size()
	if n < 2:
		return
	var sides := PackedVector3Array()
	sides.resize(n)
	for k in n:
		var tangent := points[mini(k + 1, n - 1)] - points[maxi(k - 1, 0)]
		var to_eye := eye - points[k]
		var side := tangent.cross(to_eye)
		sides[k] = side.normalized() * width * 0.5 if side.length_squared() > 0.000001 else Vector3.ZERO
	var edge := Color(color, 0.0) if soft else color
	for k in n - 1:
		var a := points[k]
		var b := points[k + 1]
		var sa := sides[k]
		var sb := sides[k + 1]
		_quad(a - sa, a, b, b - sb, edge, color)   # left half: edge → center
		_quad(a, a + sa, b + sb, b, color, edge)   # right half: center → edge

## Quad a0-a1-b1-b0 where a0/b0 carry c0 and a1/b1 carry c1.
func _quad(a0: Vector3, a1: Vector3, b1: Vector3, b0: Vector3, c0: Color, c1: Color) -> void:
	_vertex(a0, c0)
	_vertex(a1, c1)
	_vertex(b1, c1)
	_vertex(a0, c0)
	_vertex(b1, c1)
	_vertex(b0, c0)

func _vertex(p: Vector3, c: Color) -> void:
	_imesh.surface_set_color(c)
	_imesh.surface_add_vertex(p)
