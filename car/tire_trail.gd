class_name TireTrail
extends Node3D
## Oil / glue track one tire leaves on the ground (cosmetic). Built from the wheel's ground contacts, so it lies
## on slopes and bumps too. Kept in short mesh chunks: only the newest chunk is rebuilt as the tire rolls on,
## older ones fade out in the shader (global trail_time) and are freed after their lifetime.

const SHADER: Shader = preload("res://car/tire_trail.gdshader")
const STEP := 0.3             # m between trail points
const MAX_GAP := 1.5          # a longer jump (respawn, long hop) starts a new strip
const CHUNK_POINTS := 16
const WIDTH := 0.26
const WIDTH_JITTER := 0.3     # random ± share of the width per point (blotchy track)
const ALPHA := 0.9            # at full coating; fades as the tire dries
const ALPHA_JITTER := 0.35    # random share taken off per point
const LIFT := 0.02            # above the surface
const LIFETIME := 10.0        # s a trail point stays …
const FADE_TIME := 3.0        # … fading out over the last part
const OIL_ROUGHNESS := 0.2
const OIL_METALLIC := 0.2
const GLUE_ROUGHNESS := 0.45
const OIL_DARKEN := 0.4       # oil tracks read darker than the oil color (wet stain)

static var _materials: Dictionary = {}   # ItemDef.Kind → ShaderMaterial (shared by every trail)

var _kind: int = -1
var _points := PackedVector3Array()      # the open strip (ends in the open chunk)
var _normals := PackedVector3Array()
var _sides := PackedVector3Array()       # half-width vectors
var _colors := PackedColorArray()
var _births := PackedFloat32Array()
var _open: MeshInstance3D = null
var _chunks: Array[MeshInstance3D] = []
var _chunk_newest := PackedFloat32Array()  # birth of each chunk's newest point
var _rng := RandomNumberGenerator.new()

## The clock behind the trail_time shader global (Game keeps it updated).
static func now() -> float:
	return Time.get_ticks_msec() * 0.001

static func material(kind: int) -> ShaderMaterial:
	if not _materials.has(kind):
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("lifetime", LIFETIME)
		mat.set_shader_parameter("fade_time", FADE_TIME)
		var oil := kind == ItemDef.Kind.OIL
		mat.set_shader_parameter("roughness_value", OIL_ROUGHNESS if oil else GLUE_ROUGHNESS)
		mat.set_shader_parameter("metallic_value", OIL_METALLIC if oil else 0.0)
		_materials[kind] = mat
	return _materials[kind]

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # world-space geometry
	_rng.randomize()

## Called every physics tick. kind: ItemDef.Kind.OIL / GLUE, or -1 when the tire is clean or off the ground.
## strength: 0..1 coating left. heading: the car's forward direction.
func track(kind: int, contact: Vector3, normal: Vector3, heading: Vector3, strength: float) -> void:
	if kind < 0 or strength <= 0.0:
		_end_strip()
		return
	var p := contact + normal * LIFT
	if not _points.is_empty():
		var gap := p.distance_to(_points[-1])
		if kind != _kind or gap > MAX_GAP:
			_end_strip()
		elif gap < STEP:
			return
	_kind = kind
	var side := heading.cross(normal)
	if side.length_squared() < 0.0001:
		return
	var width := WIDTH * (1.0 + _rng.randf_range(-WIDTH_JITTER, WIDTH_JITTER))
	var c := ItemRegistry.OIL_COLOR.darkened(OIL_DARKEN) if kind == ItemDef.Kind.OIL else ItemRegistry.GLUE_COLOR
	c = c.srgb_to_linear()
	c.a = ALPHA * strength * (1.0 - _rng.randf() * ALPHA_JITTER)
	_points.append(p)
	_normals.append(normal)
	_sides.append(side.normalized() * width * 0.5)
	_colors.append(c)
	_births.append(now())
	if _points.size() >= 2:
		_rebuild_open()
	if _points.size() >= CHUNK_POINTS:
		_close_chunk()

## Number of mesh chunks currently on the ground (tests).
func chunk_count() -> int:
	return _chunks.size()

## Every vertex of every chunk, world space (tests).
func vertices() -> PackedVector3Array:
	var out := PackedVector3Array()
	for chunk in _chunks:
		var mesh := chunk.mesh as ArrayMesh
		if mesh != null and mesh.get_surface_count() > 0:
			out.append_array(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	return out

func _process(_delta: float) -> void:
	var t := now()
	for i in range(_chunks.size() - 1, -1, -1):
		if t - _chunk_newest[i] > LIFETIME:
			if _chunks[i] == _open:
				_end_strip()
			_chunks[i].queue_free()
			_chunks.remove_at(i)
			_chunk_newest.remove_at(i)

func _rebuild_open() -> void:
	if _open == null:
		_open = MeshInstance3D.new()
		_open.mesh = ArrayMesh.new()
		_open.material_override = material(_kind)
		_open.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_open.layers = Layers.RENDER_CARS
		_open.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_open)
		_chunks.append(_open)
		_chunk_newest.append(0.0)
	var n := _points.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for k in n:
		for across: float in [1.0, 0.0]:   # right side first: clockwise from above = front face, normal up
			verts.append(_points[k] + _sides[k] * (across * 2.0 - 1.0))
			normals.append(_normals[k])
			colors.append(_colors[k])
			uvs.append(Vector2(_births[k], across))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := _open.mesh as ArrayMesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	_chunk_newest[_chunks.size() - 1] = _births[n - 1]

## The open chunk is full: freeze it and start the next one from its last point, so the strip stays joined.
func _close_chunk() -> void:
	var last := _points.size() - 1
	_points = PackedVector3Array([_points[last]])
	_normals = PackedVector3Array([_normals[last]])
	_sides = PackedVector3Array([_sides[last]])
	_colors = PackedColorArray([_colors[last]])
	_births = PackedFloat32Array([_births[last]])
	_open = null

func _end_strip() -> void:
	_points.clear()
	_normals.clear()
	_sides.clear()
	_colors.clear()
	_births.clear()
	_open = null
	_kind = -1
