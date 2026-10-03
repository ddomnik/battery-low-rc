class_name ItemModels
## The 3D model a car carries on its roof while it holds an item.
## A scene at res://assets/items/<item id>.glb (or .tscn) wins; otherwise a low-poly placeholder is built here.
## Model convention: origin = mount point (bottom center, on the roof), forward = −Z, about 0.3–0.7 m in size,
## and an optional Marker3D named "Muzzle" where shots leave (default: MUZZLE_FALLBACK above the origin).

const MODEL_DIR := "res://assets/items/"
const MODEL_EXTENSIONS: Array[String] = [".glb", ".tscn"]
const MUZZLE_FALLBACK := Vector3(0.0, 0.3, 0.0)
const DARK := Color(0.18, 0.18, 0.2)
const METAL := Color(0.62, 0.64, 0.68)
const WHITE := Color(0.95, 0.95, 0.92)
const COPPER := Color(0.85, 0.48, 0.2)
const HAZARD_YELLOW := Color(1.0, 0.82, 0.15)
const GLOW_ENERGY := 2.5

static var _muzzles: Dictionary = {}   # item id → muzzle position in model space

static func build(item: ItemDef) -> Node3D:
	for ext in MODEL_EXTENSIONS:
		var path := MODEL_DIR + String(item.id) + ext
		if ResourceLoader.exists(path):
			var scene := load(path) as PackedScene
			if scene != null:
				return scene.instantiate() as Node3D
	return _placeholder(item)

## Where shots leave the model, in model space (cached per item; gameplay uses it, so it never depends on
## which frame the visual is in).
static func muzzle_offset(item: ItemDef) -> Vector3:
	if not _muzzles.has(item.id):
		var model := build(item)
		var marker := model.find_child("Muzzle", true, false) as Node3D
		_muzzles[item.id] = _position_in(model, marker) if marker != null else MUZZLE_FALLBACK
		model.free()
	return _muzzles[item.id]

static func _position_in(root: Node3D, node: Node3D) -> Vector3:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf.origin

# --- Placeholders ------------------------------------------------------------------------------------

static func _placeholder(item: ItemDef) -> Node3D:
	var root := Node3D.new()
	root.name = "ItemModel_%s" % item.id
	match item.id:
		&"bottle_rocket":
			_launcher(root, PackedFloat32Array([0.0]), 0.09, 0.7, item.color)
		&"rocket_trio":
			_launcher(root, PackedFloat32Array([-0.17, 0.0, 0.17]), 0.07, 0.6, item.color)
		&"water_balloon":
			_part(root, _cylinder(0.12, 0.12, 0.06), DARK, Vector3(0.0, 0.03, 0.0))
			_part(root, _cylinder(0.025, 0.025, 0.22), METAL, Vector3(0.0, 0.15, 0.0))
			_part(root, _cylinder(0.0, 0.05, 0.07), item.color, Vector3(0.0, 0.28, 0.0), Vector3(180.0, 0.0, 0.0))   # knot
			var balloon := _part(root, _sphere(0.22), item.color, Vector3(0.0, 0.5, 0.0))
			balloon.scale = Vector3(1.0, 1.15, 1.0)
			_muzzle(root, Vector3(0.0, 0.5, -0.05))
		&"oil_slick":
			_part(root, _cylinder(0.2, 0.2, 0.45), item.color, Vector3(0.0, 0.225, 0.0), Vector3.ZERO, 0.0, 0.6, 0.25)
			for y: float in [0.1, 0.35]:
				_part(root, _torus(0.19, 0.215), METAL, Vector3(0.0, y, 0.0))
			_part(root, _cylinder(0.035, 0.035, 0.16), METAL, Vector3(0.0, 0.5, -0.08), Vector3(-45.0, 0.0, 0.0))   # spout
			_muzzle(root, Vector3(0.0, 0.55, -0.14))
		&"sticky_glue":
			_part(root, _cylinder(0.14, 0.14, 0.34), item.color, Vector3(0.0, 0.17, 0.0))
			_part(root, _cylinder(0.05, 0.14, 0.1), item.color, Vector3(0.0, 0.39, 0.0))   # shoulder
			_part(root, _cylinder(0.0, 0.05, 0.16), WHITE, Vector3(0.0, 0.48, -0.06), Vector3(-50.0, 0.0, 0.0))   # nozzle
			_muzzle(root, Vector3(0.0, 0.53, -0.13))
		&"shocker":
			_part(root, _cylinder(0.18, 0.2, 0.08), DARK, Vector3(0.0, 0.04, 0.0))
			_part(root, _cylinder(0.07, 0.07, 0.34), COPPER, Vector3(0.0, 0.25, 0.0), Vector3.ZERO, 0.0, 0.5, 0.35)
			_part(root, _torus(0.07, 0.17), METAL, Vector3(0.0, 0.43, 0.0), Vector3.ZERO, 0.0, 0.8, 0.2)
			_part(root, _sphere(0.1), item.color, Vector3(0.0, 0.5, 0.0), Vector3.ZERO, GLOW_ENERGY)
			_muzzle(root, Vector3(0.0, 0.5, 0.0))
		&"blast":
			_part(root, _cylinder(0.26, 0.28, 0.06), DARK, Vector3(0.0, 0.03, 0.0))
			_part(root, _torus(0.24, 0.29), HAZARD_YELLOW, Vector3(0.0, 0.07, 0.0))
			var dome := SphereMesh.new()
			dome.radius = 0.22
			dome.height = 0.22
			dome.is_hemisphere = true
			_part(root, dome, item.color, Vector3(0.0, 0.06, 0.0), Vector3.ZERO, GLOW_ENERGY * 0.5)
			_muzzle(root, Vector3(0.0, 0.15, 0.0))
		_:
			_part(root, BoxMesh.new(), item.color, Vector3(0.0, 0.25, 0.0)).scale = Vector3.ONE * 0.4
	return root

## Launch tubes on a small swivel base, a rocket tip peeking out of each.
static func _launcher(root: Node3D, xs: PackedFloat32Array, radius: float, length: float, tip: Color) -> void:
	var tube_y := 0.27
	_part(root, BoxMesh.new(), DARK, Vector3(0.0, 0.04, 0.0)).scale = Vector3(0.3 + 0.2 * (xs.size() - 1), 0.08, 0.3)
	_part(root, _cylinder(0.05, 0.05, 0.16), METAL, Vector3(0.0, 0.15, 0.0))
	for x in xs:
		_part(root, _cylinder(radius, radius, length), METAL, Vector3(x, tube_y, -0.05), Vector3(-90.0, 0.0, 0.0), 0.0, 0.6, 0.3)
		_part(root, _cylinder(0.0, radius * 0.8, radius * 1.8), tip, Vector3(x, tube_y, -0.05 - length * 0.5 - radius * 0.7),
			Vector3(-90.0, 0.0, 0.0))
	_muzzle(root, Vector3(0.0, tube_y, -0.05 - length * 0.5 - radius * 1.6))

static func _muzzle(root: Node3D, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = "Muzzle"
	m.position = pos
	root.add_child(m)

static func _part(root: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO,
		glow: float = 0.0, metallic: float = 0.0, roughness: float = 0.5) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.layers = Layers.RENDER_CARS
	root.add_child(mi)
	return mi

static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 16
	return m

static func _sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 16
	m.rings = 8
	return m

static func _torus(inner: float, outer: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 16
	m.ring_segments = 8
	return m
