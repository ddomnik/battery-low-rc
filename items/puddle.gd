class_name Puddle
extends Node3D
## Oil or glue puddle left by a thrown item: a random cluster of blobs (a main blob, smaller satellites, a few
## drops), each a decal so it lies on slopes, bumps and edges. The layout comes from shape_seed (set from
## Match.rng by the authority) because it decides where tires get coated. Cars check their wheel contact
## points against the active puddles (Puddle.kind_at); a wheel that touches one stays coated for a while
## (Car.wheel_oil / wheel_glue). Disappears after its lifetime, shrinking at the end.

const SHRINK_TIME := 1.0
const SURFACE_TOLERANCE := 1.0       # a wheel contact this far off a blob's surface plane still counts
const SIZE_RANGE := Vector2(0.85, 1.15)          # whole puddle, × radius
const MAIN_RADIUS := Vector2(0.48, 0.6)          # blob radii and distances below are × that size
const SATELLITES := Vector2i(4, 7)
const SATELLITE_RADIUS := Vector2(0.2, 0.4)
const SATELLITE_DISTANCE := Vector2(0.3, 0.7)
const DROPS := Vector2i(3, 6)
const DROP_RADIUS := Vector2(0.06, 0.12)
const DROP_DISTANCE := Vector2(0.8, 1.15)
const PROBE_UP := 3.0                # blob surface search: from this far above the landing point …
const PROBE_DOWN := 3.0              # … to this far below; blobs that find nothing (off an edge) are dropped
const DECAL_DEPTH := 1.0             # projection box height along the surface normal
const DECAL_NORMAL_FADE := 0.6       # don't paint the steep sides of things
const DECAL_EDGE_FADE := 0.05
const BLOB_TEXTURE_SIZE := 128
const BLOB_TEXTURE_VARIANTS := 4
const BLOB_EDGE := 0.78              # blob outline radius in the texture (share of its half size), before wobble
const BLOB_WOBBLE := 0.1             # outline wobble (share of the half size)
const BLOB_SOFTNESS := 0.05
const OIL_ROUGHNESS := 0.08          # glossy, wet look
const OIL_METALLIC := 0.6
const GLUE_ROUGHNESS := 0.55

## Every puddle currently in the world (they add / remove themselves).
static var active: Array[Puddle] = []
static var _blob_textures: Array[ImageTexture] = []

var kind: ItemDef.Kind = ItemDef.Kind.OIL
var radius: float = 3.0
var lifetime: float = 10.0
var color: Color = Color.BLACK
var shape_seed: int = 0

var _age: float = 0.0
var _size: float = 1.0                # shrinks to 0 at the end of the lifetime
var _blob_centers := PackedVector3Array()   # world, on the surface
var _blob_normals := PackedVector3Array()
var _blob_radii := PackedFloat32Array()
var _decals: Array[Decal] = []
var _decal_sizes: Array[Vector3] = []

## The kind of puddle under a world point (a wheel contact), or -1.
static func kind_at(point: Vector3) -> int:
	for p in active:
		if p.covers(point):
			return p.kind
	return -1

func covers(point: Vector3) -> bool:
	for b in _blob_centers.size():
		var d := point - _blob_centers[b]
		var along := d.dot(_blob_normals[b])
		if absf(along) < SURFACE_TOLERANCE and (d - _blob_normals[b] * along).length() < _blob_radii[b] * _size:
			return true
	return false

func blob_count() -> int:
	return _blob_centers.size()

func _enter_tree() -> void:
	active.append(self)

func _exit_tree() -> void:
	active.erase(self)

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed
	var r := radius * rng.randf_range(SIZE_RANGE.x, SIZE_RANGE.y)
	_add_blob(rng, Vector2.ZERO, r * rng.randf_range(MAIN_RADIUS.x, MAIN_RADIUS.y))
	for i in rng.randi_range(SATELLITES.x, SATELLITES.y):
		_add_blob(rng, _offset(rng, r, SATELLITE_DISTANCE), r * rng.randf_range(SATELLITE_RADIUS.x, SATELLITE_RADIUS.y))
	for i in rng.randi_range(DROPS.x, DROPS.y):
		_add_blob(rng, _offset(rng, r, DROP_DISTANCE), r * rng.randf_range(DROP_RADIUS.x, DROP_RADIUS.y))

func _physics_process(delta: float) -> void:
	_age += delta
	var left := lifetime - _age
	if left < SHRINK_TIME:
		_size = maxf(left / SHRINK_TIME, 0.0)
		var s := maxf(_size, 0.05)
		for i in _decals.size():
			_decals[i].size = _decal_sizes[i] * Vector3(s, 1.0, s)
	if left <= 0.0:
		queue_free()

func _offset(rng: RandomNumberGenerator, r: float, distance: Vector2) -> Vector2:
	return Vector2.from_angle(rng.randf() * TAU) * r * rng.randf_range(distance.x, distance.y)

## One blob on whatever surface lies under it (slopes included).
func _add_blob(rng: RandomNumberGenerator, offset: Vector2, blob_radius: float) -> void:
	var variant := rng.randi() % BLOB_TEXTURE_VARIANTS
	var spin := rng.randf() * TAU
	var top := global_position + Vector3(offset.x, PROBE_UP, offset.y)
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * (PROBE_UP + PROBE_DOWN), Layers.WORLD))
	if hit.is_empty():
		return
	var at: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	_blob_centers.append(at)
	_blob_normals.append(normal)
	_blob_radii.append(blob_radius)

	# Decal projects along its −Y: line Y up with the surface normal, random turn around it.
	var side := normal.cross(Vector3.FORWARD if absf(normal.z) < 0.9 else Vector3.RIGHT).normalized()
	var surface := Basis(side, normal, side.cross(normal)).orthonormalized() * Basis(Vector3.UP, spin)
	var extent := blob_radius / BLOB_EDGE * 2.0
	var size := Vector3(extent, DECAL_DEPTH, extent)
	var decal := Decal.new()
	decal.size = size
	decal.texture_albedo = _blob_texture(variant)
	decal.texture_orm = _orm_texture()
	decal.modulate = color
	decal.normal_fade = DECAL_NORMAL_FADE
	decal.upper_fade = DECAL_EDGE_FADE
	decal.lower_fade = DECAL_EDGE_FADE
	decal.cull_mask = Layers.RENDER_WORLD
	add_child(decal)
	decal.global_transform = Transform3D(surface, at)
	_decals.append(decal)
	_decal_sizes.append(size)

## Glossy oil, matte glue (AO, roughness, metallic).
func _orm_texture() -> ImageTexture:
	var oil := kind == ItemDef.Kind.OIL
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(1.0, OIL_ROUGHNESS if oil else GLUE_ROUGHNESS, OIL_METALLIC if oil else 0.0))
	return ImageTexture.create_from_image(img)

## White blob with a wobbly, soft outline (alpha). A few fixed variants, shared by every puddle.
static func _blob_texture(variant: int) -> ImageTexture:
	if _blob_textures.is_empty():
		for v in BLOB_TEXTURE_VARIANTS:
			_blob_textures.append(_make_blob_texture(v))
	return _blob_textures[variant]

static func _make_blob_texture(variant: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant
	var amps := PackedFloat32Array()
	var phases := PackedFloat32Array()
	for h in range(2, 7):
		amps.append(rng.randf_range(0.3, 1.0) / float(h))
		phases.append(rng.randf() * TAU)
	var amp_sum := 0.0
	for a in amps:
		amp_sum += a
	var n := BLOB_TEXTURE_SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var uv := Vector2((x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / n * 2.0 - 1.0)
			var angle := uv.angle()
			var wobble := 0.0
			for h in amps.size():
				wobble += amps[h] * sin(angle * (h + 2) + phases[h])
			var edge := BLOB_EDGE + BLOB_WOBBLE * wobble / amp_sum
			var alpha := 1.0 - smoothstep(edge - BLOB_SOFTNESS, edge, uv.length())
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)
