class_name ArenaBuilder
## Static helpers that build blockout geometry in code. All bodies: layer WORLD, mask 0.

const ROUGHNESS := 0.8
const CUTOUT_SHADER: Shader = preload("res://arena/shaders/cutout.gdshader")

static var _materials: Dictionary = {}   # Color → ShaderMaterial, shared across matches

## One cached material per color. Uses the occlusion-cutout shader, so these objects open up when they stand
## between the camera and the local car (§10.1). The floor uses its own checker material and is never cut.
static func material(color: Color) -> ShaderMaterial:
	var m: ShaderMaterial = _materials.get(color)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = CUTOUT_SHADER
		m.set_shader_parameter("albedo", color)
		m.set_shader_parameter("roughness", ROUGHNESS)
		_materials[color] = m
	return m

## StaticBody3D + MeshInstance3D(BoxMesh) + CollisionShape3D(BoxShape3D).
static func box(parent: Node3D, center: Vector3, size: Vector3, color: Color, yaw_deg: float = 0.0) -> StaticBody3D:
	return box_with_material(parent, center, size, material(color), yaw_deg)

static func box_with_material(parent: Node3D, center: Vector3, size: Vector3, mat: Material, yaw_deg: float = 0.0) -> StaticBody3D:
	return box_at(parent, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), center), size, mat)

## Box with any rotation (xf = its center and orientation).
static func box_at(parent: Node3D, xf: Transform3D, size: Vector3, mat: Material) -> StaticBody3D:
	var body := _static_body_at(parent, xf)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	_add_mesh(body, mesh)
	var shape := BoxShape3D.new()
	shape.size = size
	_add_shape(body, shape)
	return body

## Triangular prism. Footprint size.x (width) × size.z (length), height size.y.
## In local space it rises toward −Z: low edge at z = +L/2 (y = 0), high edge at z = −L/2 (y = H).
## yaw_deg rotates it around Y (0 = rises toward north, 90 = west, 180 = south, −90 = east).
## Slope angle = atan(H / L).
static func wedge(parent: Node3D, base_center: Vector3, size: Vector3, yaw_deg: float, color: Color) -> StaticBody3D:
	return wedge_at(parent, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), base_center), size, color)

## Wedge with any rotation (xf = the middle of its base and its orientation).
static func wedge_at(parent: Node3D, xf: Transform3D, size: Vector3, color: Color) -> StaticBody3D:
	var body := _static_body_at(parent, xf)
	_add_mesh(body, wedge_mesh(size, material(color)))
	var shape := ConvexPolygonShape3D.new()
	shape.points = wedge_points(size)
	_add_shape(body, shape)
	return body

## The six corners of a wedge (see wedge()).
static func wedge_points(size: Vector3) -> PackedVector3Array:
	var w := size.x * 0.5
	var h := size.y
	var l := size.z * 0.5
	return PackedVector3Array([Vector3(-w, 0.0, l), Vector3(w, 0.0, l), Vector3(-w, 0.0, -l), Vector3(w, 0.0, -l),
		Vector3(-w, h, -l), Vector3(w, h, -l)])

## Wedge mesh with flat normals (also the map editor's preview, so both always match).
static func wedge_mesh(size: Vector3, mat: Material) -> ArrayMesh:
	var w := size.x * 0.5
	var h := size.y
	var l := size.z * 0.5
	var low_l := Vector3(-w, 0.0, l)
	var low_r := Vector3(w, 0.0, l)
	var back_l := Vector3(-w, 0.0, -l)
	var back_r := Vector3(w, 0.0, -l)
	var top_l := Vector3(-w, h, -l)
	var top_r := Vector3(w, h, -l)
	var centroid := Vector3(0.0, h / 3.0, -l / 3.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat normals
	_add_face(st, [low_l, low_r, top_r, top_l], centroid)     # slope
	_add_face(st, [low_l, back_l, back_r, low_r], centroid)   # bottom
	_add_face(st, [back_l, top_l, top_r, back_r], centroid)   # back (vertical, high side)
	_add_face(st, [low_l, top_l, back_l], centroid)           # left side
	_add_face(st, [low_r, back_r, top_r], centroid)           # right side
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh

## Adds a convex polygon as a triangle fan, wound so its front face points away from the centroid.
static func _add_face(st: SurfaceTool, pts: Array[Vector3], centroid: Vector3) -> void:
	for i in range(1, pts.size() - 1):
		var a := pts[0]
		var b := pts[i]
		var c := pts[i + 1]
		if (b - a).cross(c - a).dot(a - centroid) < 0.0:
			var tmp := b
			b = c
			c = tmp
		# (b − a) × (c − a) now points outward; Godot front faces are clockwise, so emit a, c, b.
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)

## Upright cylinder (size.x = diameter, size.y = height) with any rotation (xf = its center).
static func cylinder_at(parent: Node3D, xf: Transform3D, size: Vector3, color: Color) -> StaticBody3D:
	var body := _static_body_at(parent, xf)
	var mesh := CylinderMesh.new()
	mesh.top_radius = size.x * 0.5
	mesh.bottom_radius = size.x * 0.5
	mesh.height = size.y
	mesh.radial_segments = 24
	mesh.material = material(color)
	_add_mesh(body, mesh)
	var shape := CylinderShape3D.new()
	shape.radius = size.x * 0.5
	shape.height = size.y
	_add_shape(body, shape)
	return body

static func _static_body_at(parent: Node3D, xf: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.transform = xf
	parent.add_child(body)
	return body

static func _add_mesh(body: StaticBody3D, mesh: Mesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.layers = Layers.RENDER_WORLD
	body.add_child(mi)

static func _add_shape(body: StaticBody3D, shape: Shape3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
