@tool
class_name MapSourceIO
## Converts between a map source scene (MapSource + children, built in the editor) and the map file format
## (see MapLoader). to_dict(): scene → map data (export). build_from_map(): map → editable scene nodes (used to
## create source scenes for existing maps).

const DIGITS := 0.001                     # exported numbers are rounded to millimeters / thousandths
const PATH_SAMPLE_STEP := 2.0             # m between exported points of a curve (the game re-smooths them)
const NO_COLLISION_GROUP := &"map_no_collision"
const BOX_COLLISION_GROUP := &"map_box_collision"
const CONVEX_COLLISION_GROUP := &"map_convex_collision"
const MESH_COLLISION_GROUP := &"map_mesh_collision"
const COLLISION_GROUPS := {"none": NO_COLLISION_GROUP, "box": BOX_COLLISION_GROUP, "convex": CONVEX_COLLISION_GROUP,
	"mesh": MESH_COLLISION_GROUP}
const FLOOR_NAMES: Array[String] = ["checker", "color", "none"]
## Props whose model name starts like this get no collision by default (cars drive through small plants).
const SOFT_PREFIXES: Array[String] = ["flower", "grass", "plant_flat", "mushroom"]
const BORDER_GROUP := &"map_border"
const FOLDERS: Array[String] = ["Walls", "Shapes", "Props", "Paths", "Fluids", "Spawns", "Items", "Pads"]

# --- Scene → map data ----------------------------------------------------------------------------------------

static func to_dict(src: MapSource, warnings: Array[String]) -> Dictionary:
	var d := {
		"format": MapLoader.FORMAT, "name": src.map_name, "author": src.author,
		"floor": {"size": [_r(src.floor_size.x), _r(src.floor_size.y)],
			"material": FLOOR_NAMES[src.floor_material],
			"color": "#" + src.floor_color.to_html(false)},
		"light": {"sun_rotation": _v(src.sun_rotation), "ambient": _r(src.ambient)},
		"objects": [], "spawns": [], "items": [], "pads": [],
	}
	_collect(src, src, src.global_transform.affine_inverse(), d, warnings)
	return d

## "nature/…" for catalog models, "map/<name>" for this map's own models, "" otherwise.
static func model_id(src: MapSource, file: String) -> String:
	var id := PropCatalog.id_for_path(file)
	return id if not id.is_empty() else MapModels.id_for_path(src.resolved_id(), file)

static func _collect(src: MapSource, node: Node, to_map: Transform3D, d: Dictionary, warnings: Array[String]) -> void:
	for child in node.get_children():
		if child is Node3D and not (child as Node3D).visible:
			continue   # hidden = draft, not exported
		if not child is Node3D:
			_collect(src, child, to_map, d, warnings)
			continue
		var n := child as Node3D
		var xf := to_map * n.global_transform
		var rot := _deg(xf.basis)
		var scale := xf.basis.get_scale()
		if n is MapShape:
			var s := n as MapShape
			_add_object(d, n, {"type": s.type_name(), "pos": _v(xf.origin), "rot": rot,
				"size": _v((s.size * scale).abs()), "color": "#" + s.color.to_html(false)})
		elif n is MapPath:
			var p := n as MapPath
			var points := _path_points(p, to_map)
			if points.size() >= 2:
				_add_object(d, n, {"type": "path", "profile": p.profile_name(), "points": points,
					"width": _r(p.width), "height": _r(p.height), "color": "#" + p.color.to_html(false)})
			else:
				warnings.append("%s: a path needs at least 2 points, skipped" % n.name)
		elif n is MapFluid:
			var f := n as MapFluid
			var up := xf.basis.y.normalized()
			if up.dot(Vector3.UP) < 0.999:
				warnings.append("%s: fluids stay level — only the turn around the vertical is used" % n.name)
			var fwd_f := -xf.basis.z
			var o := {"type": "fluid", "preset": f.preset_name(), "pos": _v(xf.origin),
				"rot": [0.0, _r(rad_to_deg(atan2(-fwd_f.x, -fwd_f.z))), 0.0], "size": _v((f.size * scale).abs()),
				"color": "#" + f.color.to_html(false), "opacity": _r(f.opacity), "damage": _r(f.damage), "slow": _r(f.slow),
				"drag": _r(f.drag), "buoyancy": _r(f.buoyancy), "grip": _r(f.grip), "kill": f.kill,
				"current": [_r(f.current.x), _r(f.current.y)], "coat": _r(f.coat)}
			if f.texture != null:
				var tex_id := MapModels.texture_id_for_path(src.resolved_id(), f.texture.resource_path)
				if tex_id.is_empty():
					warnings.append("%s: the texture must be a PNG in this map's textures/ folder (maps/%s/textures/) — left out" % [
						n.name, src.resolved_id()])
				else:
					o["texture"] = tex_id
			_add_object(d, n, o)
		elif n is MapSpawn:
			var fwd := -xf.basis.z
			(d["spawns"] as Array).append({"pos": _v(xf.origin), "yaw": _r(rad_to_deg(atan2(-fwd.x, -fwd.z)))})
		elif n is MapItem:
			(d["items"] as Array).append({"pos": _v(xf.origin + Vector3.UP * MapItem.HEIGHT)})
		elif n is MapPad:
			(d["pads"] as Array).append({"pos": _v(xf.origin)})
		elif n is MapPodium:
			var fwd := -xf.basis.z
			d["podium"] = {"pos": _v(xf.origin), "yaw": _r(rad_to_deg(atan2(-fwd.x, -fwd.z)))}
		elif not n.scene_file_path.is_empty():
			var model := model_id(src, n.scene_file_path)
			if model.is_empty():
				warnings.append("%s: '%s' can't be used — models must be in assets/kenney_nature_kit/ or in this map's models/ folder (maps/%s/models/), skipped" % [
					n.name, n.scene_file_path, src.resolved_id()])
				continue
			_add_object(d, n, {"type": "prop", "model": model, "pos": _v(xf.origin), "rot": rot,
				"scale": _v(scale), "collision": _prop_collision(n, model)})
		elif n.get_class() == "Terrain3D":
			warnings.append("%s: Terrain3D isn't supported (use a Blender terrain .glb) — ignored" % n.name)
		else:
			_collect(src, n, to_map, d, warnings)   # a plain folder node: look inside

## Appends an object; nodes in group "map_border" become outer walls (left out in modes without walls).
static func _add_object(d: Dictionary, n: Node, o: Dictionary) -> void:
	if n.is_in_group(BORDER_GROUP):
		o["border"] = true
	(d["objects"] as Array).append(o)

static func _prop_collision(n: Node, model: String) -> String:
	for kind: String in COLLISION_GROUPS:
		if n.is_in_group(COLLISION_GROUPS[kind]):
			return kind
	return _default_collision(model)

## The curve sampled every ~2 m (map space); the game draws a smooth curve back through these points.
static func _path_points(p: MapPath, to_map: Transform3D) -> Array:
	var out: Array = []
	if p.curve == null or p.curve.point_count < 2:
		return out
	var length := p.curve.get_baked_length()
	var count := clampi(ceili(length / PATH_SAMPLE_STEP), 1, MapLoader.MAX_PATH_POINTS - 1)
	var to_map_path := to_map * p.global_transform
	for i in count + 1:
		out.append(_v(to_map_path * p.curve.sample_baked(length * float(i) / count, true)))
	return out

# --- Map data → scene ----------------------------------------------------------------------------------------

## Sets src's settings from map and adds editable nodes for everything in it (owner = src, so it can be saved).
static func build_from_map(src: MapSource, map: MapData) -> void:
	src.map_id = ""   # export to the folder the scene is saved in (safe to duplicate a map folder)
	src.map_name = map.name
	src.author = map.author
	src.floor_size = map.floor_size
	src.floor_material = FLOOR_NAMES.find(map.floor_material) as MapSource.FloorMaterial
	src.floor_color = map.floor_color
	src.sun_rotation = map.sun_rotation_deg
	src.ambient = map.ambient_energy
	var folders := {}
	for f in FOLDERS:
		var folder := Node3D.new()
		folder.name = f
		src.add_child(folder)
		folder.owner = src
		folders[f] = folder
	for o in map.objects:
		var xf: Transform3D = o["transform"]
		var border: bool = o.get("border", false)
		var node: Node3D = null
		match o["type"]:
			&"box", &"wedge", &"cylinder":
				var s := MapShape.new()
				s.kind = MapShape.KIND_TYPES.find(String(o["type"])) as MapShape.Kind
				s.size = o["size"]
				s.color = o["color"]
				node = s
				_add(src, folders["Walls" if border else "Shapes"], s, xf, "Wall" if border else "")
			&"prop":
				var model := _editor_model(map.id, String(o["model"]))
				if model == null:
					continue
				var scale: Vector3 = o["scale"]
				node = model
				_add(src, folders["Walls" if border else "Props"], model, Transform3D(xf.basis.scaled_local(scale), xf.origin),
					String(o["model"]).get_slice("/", 1))
				var collision: String = o["collision"]
				if collision != _default_collision(String(o["model"])):
					model.add_to_group(COLLISION_GROUPS[collision], true)
			&"path":
				var p := MapPath.new()
				p.profile = MapPath.PROFILE_NAMES.find(String(o["profile"])) as MapPath.Profile
				p.width = o["width"]
				p.height = o["height"]
				p.color = o["color"]
				p.curve = Arena.smooth_curve(o["points"])
				node = p
				_add(src, folders["Walls" if border else "Paths"], p, Transform3D.IDENTITY, "")
			&"fluid":
				var f := MapFluid.new()
				f.preset = FluidPresets.NAMES.find(String(o["preset"])) as MapFluid.Preset
				f.size = o["size"]
				f.color = o["color"]
				f.opacity = o["opacity"]
				f.damage = o["damage"]
				f.slow = o["slow"]
				f.drag = o["drag"]
				f.buoyancy = o["buoyancy"]
				f.grip = o["grip"]
				f.kill = o["kill"]
				f.current = o["current"]
				f.coat = o["coat"]
				if not String(o["texture"]).is_empty():
					f.texture = load(MapModels.texture_path(map.id, String(o["texture"]).trim_prefix("map/"))) as Texture2D
				node = f
				_add(src, folders["Fluids"], f, xf, String(o["preset"]).capitalize())
		if border and node != null:
			node.add_to_group(BORDER_GROUP, true)
	for t in map.spawns:
		_add(src, folders["Spawns"], MapSpawn.new(), t, "Spawn")
	for i in map.items:
		_add(src, folders["Items"], MapItem.new(), Transform3D(Basis.IDENTITY, i - Vector3.UP * MapItem.HEIGHT), "Item")
	for pad in map.pads:
		_add(src, folders["Pads"], MapPad.new(), Transform3D(Basis.IDENTITY, pad), "Pad")
	_add(src, src, MapPodium.new(), map.podium, "Podium")

## A model as an editable instance of its file (catalog or this map's models/ folder).
static func _editor_model(map_id: String, model: String) -> Node3D:
	if not model.begins_with("map/"):
		return PropCatalog.instantiate(model)
	var scene := load(MapModels.path(map_id, model.trim_prefix("map/"))) as PackedScene
	return scene.instantiate() as Node3D if scene != null else null

static func _default_collision(model: String) -> String:
	if model.begins_with("map/"):
		return "mesh"
	var name := model.get_slice("/", 1)
	for prefix in SOFT_PREFIXES:
		if name.begins_with(prefix):
			return "none"
	return "convex"

static func _add(src: MapSource, parent: Node, node: Node3D, xf: Transform3D, base_name: String) -> void:
	if not base_name.is_empty():
		node.name = base_name
	parent.add_child(node, true)
	node.transform = xf
	node.owner = src

# --- Number formatting ---------------------------------------------------------------------------------------

static func _r(f: float) -> float:
	return snappedf(f, DIGITS)

static func _v(v: Vector3) -> Array:
	return [_r(v.x), _r(v.y), _r(v.z)]

static func _deg(b: Basis) -> Array:
	return _v(b.orthonormalized().get_euler() * (180.0 / PI))
