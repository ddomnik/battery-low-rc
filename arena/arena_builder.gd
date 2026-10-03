class_name ArenaBuilder
## Static helpers that build blockout geometry in code. All bodies: layer WORLD, mask 0.

const ROUGHNESS := 0.8

static var _materials: Dictionary = {}   # Color → StandardMaterial3D, shared across matches

## One cached material per color.
static func material(color: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = _materials.get(color)
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = ROUGHNESS
		_materials[color] = m
	return m

## StaticBody3D + MeshInstance3D(BoxMesh) + CollisionShape3D(BoxShape3D).
static func box(parent: Node3D, center: Vector3, size: Vector3, color: Color, yaw_deg: float = 0.0) -> StaticBody3D:
	return box_with_material(parent, center, size, material(color), yaw_deg)

static func box_with_material(parent: Node3D, center: Vector3, size: Vector3, mat: Material, yaw_deg: float = 0.0) -> StaticBody3D:
	var body := _static_body(parent, center, yaw_deg)
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
	var body := _static_body(parent, base_center, yaw_deg)
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
	mesh.surface_set_material(0, material(color))
	_add_mesh(body, mesh)

	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([low_l, low_r, back_l, back_r, top_l, top_r])
	_add_shape(body, shape)
	return body

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

static func _static_body(parent: Node3D, pos: Vector3, yaw_deg: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = deg_to_rad(yaw_deg)
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
