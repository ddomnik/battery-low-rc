class_name Arena
extends Node3D
## The play area, built from a MapData (MapCatalog / MapLoader): floor, placed objects (boxes, ramps,
## cylinders, catalog / own models, curved roads / walls), charging pads, light, spawn and item markers.
## Objects marked "border" (the outer walls) are left out when with_walls is false ("Last on table").
## North = −Z, screen-right = +X. Set map and with_walls before adding to the tree.

const CHECKER_SHADER: Shader = preload("res://arena/shaders/checker.gdshader")
const FLOOR_THICKNESS := 1.0
const PATH_STEP := 0.5                    # m between curve segments of roads / walls
const PATH_SMOOTHING := 1.0 / 6.0         # curve handles (Catmull-Rom): smooth bends through every point
const PARTICLE_COLLISION_BOTTOM := -1.0
const PARTICLE_COLLISION_MIN_HEIGHT := 10.0
const PARTICLE_COLLISION_MARGIN := 4.0
const PARTICLE_COLLISION_EDGE := 4.0      # m beyond the floor edge (walls, slopes at the border)

var map: MapData = null
var with_walls: bool = true               # false: border objects are left out ("Last on table")
var spawn_points: Array[Marker3D] = []
var item_spawn_points: Array[Marker3D] = []
var podium_transform: Transform3D = Transform3D.IDENTITY

var lowest_y: float = 0.0                 # lowest point of anything built (fall-off height follows it)

var _top_y: float = 0.0                   # highest point of anything built (particle heightfield size)
var _own_models: Dictionary = {}          # "map/<name>" → loaded model (instanced per use), see MapModels

func _ready() -> void:
	if map == null:
		map = MapCatalog.load_map(MapCatalog.DEFAULT_ID)
	_build_environment()
	_build_floor()
	for o in map.objects:
		if with_walls or not o.get("border", false):
			_build_object(o)
	for p in map.pads:
		var pad := ChargingPad.new()
		pad.name = "ChargingPad_%d_%d" % [int(p.x), int(p.z)]
		pad.position = p
		add_child(pad)
	_build_particle_collision()
	_build_markers()

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = map.sun_rotation_deg
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = map.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

func _build_floor() -> void:
	if map.floor_material != "none":
		var floor_mat: Material
		if map.floor_material == "checker":
			var checker := ShaderMaterial.new()
			checker.shader = CHECKER_SHADER
			floor_mat = checker
		else:
			floor_mat = ArenaBuilder.material(map.floor_color)
		ArenaBuilder.box_with_material(self, Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0),
			Vector3(map.floor_size.x, FLOOR_THICKNESS, map.floor_size.y), floor_mat)

func _build_object(o: Dictionary) -> void:
	var xf: Transform3D = o["transform"]
	match o["type"]:
		&"box":
			ArenaBuilder.box_at(self, xf, o["size"], ArenaBuilder.material(o["color"]))
			_top_y = maxf(_top_y, xf.origin.y + (o["size"] as Vector3).length() * 0.5)
		&"wedge":
			ArenaBuilder.wedge_at(self, xf, o["size"], o["color"])
			_top_y = maxf(_top_y, xf.origin.y + (o["size"] as Vector3).length())
		&"cylinder":
			ArenaBuilder.cylinder_at(self, xf, o["size"], o["color"])
			_top_y = maxf(_top_y, xf.origin.y + (o["size"] as Vector3).length() * 0.5)
		&"prop":
			_build_prop(xf, o["model"], o["scale"], o["collision"])
		&"path":
			_build_path(o["points"], o["profile"], o["width"], o["height"], o["color"])
		&"fluid":
			var tex: Texture2D = null
			if not String(o["texture"]).is_empty():
				var errors: Array[String] = []
				tex = MapModels.load_texture(map.id, String(o["texture"]).trim_prefix("map/"), errors)
				for e in errors:
					push_warning("Map '%s': %s" % [map.id, e])
			var fluid := FluidZone.new()
			fluid.name = "Fluid%d" % get_child_count()
			fluid.setup(o, tex)
			add_child(fluid)
			lowest_y = minf(lowest_y, xf.origin.y - (o["size"] as Vector3).y)

## A catalog or own model. The body stays unscaled (physics dislikes scaled bodies); the model and the
## collision shapes carry the scale instead. Collision-only meshes (MapModels.is_collision_node) are never drawn
## and, if a model has any, they alone collide (exact triangle mesh).
func _build_prop(xf: Transform3D, model_id: String, scale: Vector3, collision: String) -> void:
	var model := _instantiate_model(model_id)
	if model == null:
		return
	var holder: Node3D
	if collision == "none":
		holder = Node3D.new()
		holder.transform = xf
		add_child(holder)
	else:
		var body := StaticBody3D.new()
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.transform = xf
		add_child(body)
		holder = body
	model.scale = scale
	holder.add_child(model)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	var collision_only: Array[MeshInstance3D] = []
	for mi in meshes:
		if MapModels.is_collision_node(mi.name):
			collision_only.append(mi)
	if not collision_only.is_empty():
		for mi in collision_only:
			mi.visible = false
			if collision != "none" and mi.mesh != null:
				_add_mesh_shape(holder, mi.mesh, _transform_in(model, mi, scale))
		collision = "none"   # the visible meshes don't collide
	var bounds := AABB()
	var first := true
	for mi in meshes:
		mi.layers = Layers.RENDER_WORLD
		var local := _transform_in(model, mi, scale)
		var box := local * mi.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		if collision == "mesh" and mi.mesh != null:
			_add_mesh_shape(holder, mi.mesh, local)
		elif collision == "convex" and mi.mesh != null:
			var hull := mi.mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
			if hull != null:
				var points := PackedVector3Array()
				for p in hull.points:
					points.append(local * p)
				hull.points = points
				_add_shape(holder, hull, Transform3D.IDENTITY)
	if collision == "box" and not first:
		var shape := BoxShape3D.new()
		shape.size = bounds.size
		_add_shape(holder, shape, Transform3D(Basis.IDENTITY, bounds.get_center()))
	if not first:
		var world_box := Transform3D(xf.basis, xf.origin) * bounds
		_top_y = maxf(_top_y, world_box.end.y)
		lowest_y = minf(lowest_y, world_box.position.y)

func _instantiate_model(model_id: String) -> Node3D:
	if not model_id.begins_with("map/"):
		return PropCatalog.instantiate(model_id)
	if not _own_models.has(model_id):
		var errors: Array[String] = []
		_own_models[model_id] = MapModels.load_model(map.id, model_id.trim_prefix("map/"), errors)
		for e in errors:
			push_warning("Map '%s': %s" % [map.id, e])
	var template: Node3D = _own_models[model_id]
	return template.duplicate() as Node3D if template != null else null

## Exact triangle-mesh collision (terrain, custom shapes); local = the mesh's transform in the body.
func _add_mesh_shape(body: Node3D, mesh: Mesh, local: Transform3D) -> void:
	var faces := mesh.get_faces()
	if faces.is_empty():
		return
	for i in faces.size():
		faces[i] = local * faces[i]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true   # thin or open meshes collide from both sides
	_add_shape(body, shape, Transform3D.IDENTITY)

func _exit_tree() -> void:
	for template: Variant in _own_models.values():
		if template != null and is_instance_valid(template):
			(template as Node).free()
	_own_models.clear()

## A smooth curve through the points, swept with a road slab (top on the curve) or a wall (standing on it).
func _build_path(points: PackedVector3Array, profile: String, width: float, height: float, color: Color) -> void:
	var curve := smooth_curve(points)
	for p in points:
		_top_y = maxf(_top_y, p.y + height)
	var path := Path3D.new()
	path.name = "Path%d" % get_child_count()
	path.curve = curve
	add_child(path)
	var csg := CSGPolygon3D.new()
	csg.polygon = path_polygon(profile, width, height)
	csg.mode = CSGPolygon3D.MODE_PATH
	csg.path_node = NodePath("../" + String(path.name))   # siblings
	csg.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	csg.path_interval = PATH_STEP
	csg.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH_FOLLOW
	csg.path_local = false
	csg.smooth_faces = true
	csg.material = ArenaBuilder.material(color)
	csg.use_collision = true
	csg.collision_layer = Layers.WORLD
	csg.collision_mask = 0
	csg.layers = Layers.RENDER_WORLD
	add_child(csg)

## A smooth curve through every point (Catmull-Rom handles). The map editor uses the same curve.
static func smooth_curve(points: PackedVector3Array) -> Curve3D:
	var curve := Curve3D.new()
	for i in points.size():
		var prev := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, points.size() - 1)]
		var handle := (next - prev) * PATH_SMOOTHING
		curve.add_point(points[i], -handle, handle)
	return curve

## Cross-section swept along a path: a road slab hangs below the curve, a wall stands on it.
static func path_polygon(profile: String, width: float, height: float) -> PackedVector2Array:
	var w := width * 0.5
	if profile == "wall":
		return PackedVector2Array([Vector2(-w, 0.0), Vector2(-w, height), Vector2(w, height), Vector2(w, 0.0)])
	return PackedVector2Array([Vector2(-w, -height), Vector2(-w, 0.0), Vector2(w, 0.0), Vector2(w, -height)])

## GPU particles (oil / glue drops) land on everything built here (render layer "world"), slopes included.
func _build_particle_collision() -> void:
	var hf := GPUParticlesCollisionHeightField3D.new()
	hf.name = "ParticleCollision"
	var bottom := minf(PARTICLE_COLLISION_BOTTOM, lowest_y - 1.0)
	var height := maxf(PARTICLE_COLLISION_MIN_HEIGHT, _top_y + PARTICLE_COLLISION_MARGIN - bottom)
	var margin := PARTICLE_COLLISION_EDGE * 2.0
	hf.size = Vector3(map.floor_size.x + margin, height, map.floor_size.y + margin)
	hf.position = Vector3(0.0, bottom + height * 0.5, 0.0)
	hf.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_1024
	hf.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	hf.heightfield_mask = Layers.RENDER_WORLD
	add_child(hf)

func _build_markers() -> void:
	for i in map.spawns.size():
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.transform = map.spawns[i]
		m.add_to_group("spawn_point")
		add_child(m)
		spawn_points.append(m)
	for i in map.items.size():
		var m := Marker3D.new()
		m.name = "ItemSpawn%d" % i
		m.position = map.items[i]
		m.add_to_group("item_spawn")
		add_child(m)
		item_spawn_points.append(m)
	podium_transform = map.podium

func _add_shape(body: Node3D, shape: Shape3D, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		_collect_meshes(c, out)

## mesh_instance's transform relative to the model's parent, including the model's scale.
func _transform_in(model: Node3D, node: Node3D, scale: Vector3) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != model and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return Transform3D(Basis.from_scale(scale), Vector3.ZERO) * xf
