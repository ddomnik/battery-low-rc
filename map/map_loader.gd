class_name MapLoader
## Reads a map file (JSON) into a MapData, validating everything. Maps may come from other players later, so
## nothing in the file is trusted: only known object types, numbers are clamped to sane ranges, counts and file
## size are limited, models are catalog ids (PropCatalog), never paths. Plain data in, plain data out — a map
## cannot load scenes, resources or scripts.
##
## Format 1 (all positions in meters, rotations in degrees, colors "#RRGGBB"):
## {
##   "format": 1, "name": "My map", "author": "me",
##   "floor": {"size": [90, 90], "material": "checker" | "color" | "none", "color": "#C0B8A8"},
##            ("none" = no floor, e.g. a terrain model is the ground)
##   "light": {"sun_rotation": [-55, 35, 0], "ambient": 0.6},
##   "objects": [            (any object may add "border": true = an outer wall, left out in "Last on table")
##     {"type": "box",      "pos": [x, y, z], "rot": [x, y, z], "size": [x, y, z], "color": "#FF924C"},
##     {"type": "wedge",    "pos": [..], "rot": [..], "size": [w, h, l], "color": ".."},   (ramp rising toward −Z)
##     {"type": "cylinder", "pos": [..], "rot": [..], "size": [diameter, height, diameter], "color": ".."},
##     {"type": "prop",     "model": "nature/tree_oak" | "map/<name>", "pos": [..], "rot": [..], "scale": [x, y, z] | s,
##                          "collision": "convex" | "mesh" | "box" | "none"},
##                          ("map/<name>" = maps/<id>/models/<name>.glb, see MapModels; default collision "mesh",
##                           catalog models default "convex")
##     {"type": "path",     "profile": "road" | "wall", "points": [[x, y, z], ...], "width": 4, "height": 0.4,
##                          "color": ".."}     (smooth curve through the points; roads ride on top of them)
##     {"type": "fluid",    "preset": "water" | "lava" | "mud" | "acid", "pos": [..] (surface center), "rot": [0, yaw, 0],
##                          "size": [x, depth, z], "color": "..", "opacity": 0.7, "texture": "map/<name>" (maps/<id>/textures/<name>.png),
##                          "damage": per 100 ms, "slow": 0.7, "drag": 0.8, "buoyancy": 0.55, "grip": 0.8, "kill": false,
##                          "current": [x, z] m/s (fluid's own axes), "coat": s}   (missing values: FluidPresets)
##   ],
##   "spawns": [{"pos": [x, y, z], "yaw": deg}, ...],   (2–16)
##   "items":  [{"pos": [x, y, z]}, ...],
##   "pads":   [{"pos": [x, y, z]}, ...],
##   "podium": {"pos": [x, y, z], "yaw": deg}
## }

const FORMAT := 1
const MAX_FILE_BYTES := 2_000_000
const MAX_OBJECTS := 4000
const MAX_PATH_POINTS := 256
const MIN_SPAWNS := 2
const MAX_SPAWNS := 16
const MAX_ITEMS := 64
const MAX_PADS := 16
const MAX_COORD := 1000.0
const SIZE_RANGE := Vector2(0.05, 500.0)
const SCALE_RANGE := Vector2(0.05, 50.0)
const MAX_TEXT := 60
const MAX_MAP_MODELS := 32                # different own models (maps/<id>/models/*.glb) per map
const TYPES: Array[String] = ["box", "wedge", "cylinder", "prop", "path", "fluid"]
const MAX_CURRENT := 30.0                 # m/s
const PROFILES: Array[String] = ["road", "wall"]
const COLLISIONS: Array[String] = ["convex", "mesh", "box", "none"]
const FLOOR_MATERIALS: Array[String] = ["checker", "color", "none"]

## Parses and validates map JSON. Returns null when the map is unusable; problems (also skipped objects) are
## appended to errors.
static func parse(text: String, id: String, errors: Array[String]) -> MapData:
	if text.length() > MAX_FILE_BYTES:
		errors.append("map file too large")
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("JSON error line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return null
	var root: Variant = json.data
	if not root is Dictionary:
		errors.append("top level must be an object")
		return null
	var d: Dictionary = root
	if int(_num(d.get("format"), 0.0, 0.0, 1000.0)) != FORMAT:
		errors.append("unsupported format (expected %d)" % FORMAT)
		return null

	var map := MapData.new()
	map.id = id
	map.name = _text(d.get("name"), id)
	map.author = _text(d.get("author"), "")

	var floor_d := _dict(d.get("floor"))
	var fs := _vec2(floor_d.get("size"), map.floor_size)
	map.floor_size = Vector2(clampf(fs.x, 10.0, SIZE_RANGE.y), clampf(fs.y, 10.0, SIZE_RANGE.y))
	map.floor_material = _choice(floor_d.get("material"), FLOOR_MATERIALS, map.floor_material)
	map.floor_color = _color(floor_d.get("color"), map.floor_color)


	var light_d := _dict(d.get("light"))
	map.sun_rotation_deg = _vec3(light_d.get("sun_rotation"), map.sun_rotation_deg, 360.0)
	map.ambient_energy = _num(light_d.get("ambient"), map.ambient_energy, 0.0, 4.0)

	var objects := _array(d.get("objects"))
	if objects.size() > MAX_OBJECTS:
		errors.append("too many objects (%d, max %d): the rest are skipped" % [objects.size(), MAX_OBJECTS])
	var own_models := {}
	for i in mini(objects.size(), MAX_OBJECTS):
		var o := _object(objects[i], id, errors, i)
		if o.is_empty():
			continue
		if o["type"] == &"prop" and String(o["model"]).begins_with("map/"):
			own_models[o["model"]] = true
			if own_models.size() > MAX_MAP_MODELS:
				errors.append("object %d: more than %d different own models, skipped" % [i, MAX_MAP_MODELS])
				continue
		map.objects.append(o)

	for s in _array(d.get("spawns")).slice(0, MAX_SPAWNS):
		var sd := _dict(s)
		map.spawns.append(_placement(sd))
	if map.spawns.size() < MIN_SPAWNS:
		errors.append("needs at least %d spawns" % MIN_SPAWNS)
		return null
	for it in _array(d.get("items")).slice(0, MAX_ITEMS):
		map.items.append(_vec3(_dict(it).get("pos"), Vector3.ZERO, MAX_COORD))
	for p in _array(d.get("pads")).slice(0, MAX_PADS):
		map.pads.append(_vec3(_dict(p).get("pos"), Vector3.ZERO, MAX_COORD))
	if d.has("podium"):
		map.podium = _placement(_dict(d.get("podium")))
	return map

static func _object(v: Variant, map_id: String, errors: Array[String], index: int) -> Dictionary:
	var d := _dict(v)
	var type := _choice(d.get("type"), TYPES, "")
	if type == "":
		errors.append("object %d: unknown type, skipped" % index)
		return {}
	var basis := Basis.from_euler(_vec3(d.get("rot"), Vector3.ZERO, 360.0) * (PI / 180.0))
	var o := {"type": StringName(type), "transform": Transform3D(basis, _vec3(d.get("pos"), Vector3.ZERO, MAX_COORD)),
		"border": d.get("border") == true}
	match type:
		"box", "wedge", "cylinder":
			o["size"] = _size(d.get("size"), Vector3.ONE * 2.0)
			o["color"] = _color(d.get("color"), Color.GRAY)
		"prop":
			var model := _text(d.get("model"), "")
			var own := model.begins_with("map/")
			if not (PropCatalog.has(model) or (own and MapModels.exists(map_id, model.trim_prefix("map/")))):
				errors.append("object %d: unknown model '%s', skipped" % [index, model])
				return {}
			o["model"] = model
			var s: Variant = d.get("scale")
			var scale := Vector3.ONE * _num(s, 1.0, SCALE_RANGE.x, SCALE_RANGE.y) if s is float or s is int \
				else _vec3(s, Vector3.ONE, SCALE_RANGE.y)
			o["scale"] = scale.clamp(Vector3.ONE * SCALE_RANGE.x, Vector3.ONE * SCALE_RANGE.y)
			o["collision"] = _choice(d.get("collision"), COLLISIONS, "mesh" if own else "convex")
		"path":
			var points := PackedVector3Array()
			for p in _array(d.get("points")).slice(0, MAX_PATH_POINTS):
				points.append(_vec3(p, Vector3.ZERO, MAX_COORD))
			if points.size() < 2:
				errors.append("object %d: a path needs 2+ points, skipped" % index)
				return {}
			o["points"] = points
			o["profile"] = _choice(d.get("profile"), PROFILES, "road")
			o["width"] = _num(d.get("width"), 4.0, SIZE_RANGE.x, 100.0)
			o["height"] = _num(d.get("height"), 0.4, SIZE_RANGE.x, 50.0)
			o["color"] = _color(d.get("color"), Color.GRAY)
		"fluid":
			var preset := _choice(d.get("preset"), FluidPresets.NAMES, "water")
			var p := FluidPresets.get_preset(preset)
			var yaw := deg_to_rad(_vec3(d.get("rot"), Vector3.ZERO, 360.0).y)   # fluids stay level
			o["transform"] = Transform3D(Basis(Vector3.UP, yaw), (o["transform"] as Transform3D).origin)
			o["preset"] = preset
			o["size"] = _size(d.get("size"), Vector3(8.0, 1.0, 8.0))
			o["color"] = _color(d.get("color"), p["color"])
			o["opacity"] = _num(d.get("opacity"), p["opacity"], 0.05, 1.0)
			o["damage"] = _num(d.get("damage"), p["damage"], 0.0, 100.0)
			o["slow"] = _num(d.get("slow"), p["slow"], 0.05, 1.0)
			o["drag"] = _num(d.get("drag"), p["drag"], 0.0, 10.0)
			o["buoyancy"] = _num(d.get("buoyancy"), p["buoyancy"], 0.0, 3.0)
			o["grip"] = _num(d.get("grip"), p["grip"], 0.05, 2.0)
			o["kill"] = d.get("kill") == true
			o["current"] = _vec2(d.get("current"), Vector2.ZERO).limit_length(MAX_CURRENT)
			o["coat"] = _num(d.get("coat"), p["coat"], 0.0, 10.0)
			var tex := _text(d.get("texture"), "")
			o["texture"] = tex if tex.begins_with("map/") and MapModels.texture_exists(map_id, tex.trim_prefix("map/")) else ""
	return o

static func _placement(d: Dictionary) -> Transform3D:
	var yaw := deg_to_rad(_num(d.get("yaw"), 0.0, -360.0, 360.0))
	return Transform3D(Basis(Vector3.UP, yaw), _vec3(d.get("pos"), Vector3.ZERO, MAX_COORD))

# --- Typed, clamped readers (anything malformed falls back to the default) ---------------------------------

static func _num(v: Variant, fallback: float, lo: float, hi: float) -> float:
	if not (v is float or v is int):
		return fallback
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return fallback
	return clampf(f, lo, hi)

static func _vec3(v: Variant, fallback: Vector3, limit: float) -> Vector3:
	var a := _array(v)
	if a.size() != 3:
		return fallback
	return Vector3(_num(a[0], fallback.x, -limit, limit), _num(a[1], fallback.y, -limit, limit),
		_num(a[2], fallback.z, -limit, limit))

static func _vec2(v: Variant, fallback: Vector2) -> Vector2:
	var a := _array(v)
	if a.size() != 2:
		return fallback
	return Vector2(_num(a[0], fallback.x, -MAX_COORD, MAX_COORD), _num(a[1], fallback.y, -MAX_COORD, MAX_COORD))

static func _size(v: Variant, fallback: Vector3) -> Vector3:
	return _vec3(v, fallback, SIZE_RANGE.y).clamp(Vector3.ONE * SIZE_RANGE.x, Vector3.ONE * SIZE_RANGE.y)

static func _color(v: Variant, fallback: Color) -> Color:
	if v is String and (v as String).length() <= 9 and Color.html_is_valid(v):
		var c := Color.html(v)
		return Color(c, 1.0)
	return fallback

static func _text(v: Variant, fallback: String) -> String:
	return (v as String).left(MAX_TEXT).strip_edges() if v is String else fallback

static func _choice(v: Variant, allowed: Array[String], fallback: String) -> String:
	return v if v is String and allowed.has(v) else fallback

static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}

static func _array(v: Variant) -> Array:
	return v if v is Array else []
