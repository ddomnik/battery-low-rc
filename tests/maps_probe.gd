extends Node3D
## Headless probe for the map system: catalog, loader validation (maps may come from other players, so hostile
## input must be harmless), and building an arena from a map.
## Run: godot --headless --path . --fixed-fps 60 res://tests/maps_probe.tscn

var _failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_header("Catalog")
	var maps := MapCatalog.list()
	_check("built-in maps found, default first", maps, not maps.is_empty() and maps[0]["id"] == MapCatalog.DEFAULT_ID)
	var arena_map := MapCatalog.load_map(MapCatalog.DEFAULT_ID)
	_check("test arena: 28 objects (4 border walls), 10 spawns, 10 item spots, 2 pads",
		"%d / %d / %d / %d" % [arena_map.objects.size(), arena_map.spawns.size(), arena_map.items.size(), arena_map.pads.size()],
		arena_map.objects.size() == 28 and arena_map.spawns.size() == 10 and arena_map.items.size() == 10 and arena_map.pads.size() == 2)
	var bad_ids: Array[String] = ["../secret", "..", "a/b", "C:", "res://x", "Upper", "", "x".repeat(41)]
	var accepted: Array[String] = []
	for id in bad_ids:
		if MapCatalog.valid_id(id) or MapCatalog.load_map(id) != null:
			accepted.append(id)
	_check("unsafe map ids are rejected (no path tricks)", accepted, accepted.is_empty())
	_check("nature props are in the catalog", PropCatalog.ids().size(), PropCatalog.ids().size() > 100)

	_header("Loader validation (hostile input)")
	var errors: Array[String] = []
	_check("not JSON → refused", MapLoader.parse("{oops", "t", errors) == null, MapLoader.parse("{oops", "t", errors) == null)
	_check("wrong format version → refused", null, MapLoader.parse('{"format": 99}', "t", errors) == null)
	_check("fewer than 2 spawns → refused", null,
		MapLoader.parse('{"format": 1, "spawns": [{"pos": [0, 0, 0]}]}', "t", errors) == null)
	errors.clear()
	var hostile := JSON.stringify({
		"format": 1, "name": "x".repeat(500),
		"spawns": [{"pos": [0, 0, 0]}, {"pos": [1e30, -1e30, "abc"], "yaw": 1e9}, "not a dict"],
		"objects": [
			{"type": "script", "source": "OS.execute('rm', ['-rf', '/'])"},
			{"type": "prop", "model": "res://evil/payload.tscn"},
			{"type": "prop", "model": "../../addons/thing"},
			{"type": "box", "pos": [5, 1, 5], "size": [1e9, -5, 0], "color": "javascript:alert(1)", "script": "x"},
			{"type": "path", "points": [[0, 0, 0]]},
			42, null, "box",
		],
		"items": [{"pos": [0, 0.8, 0]}],
	})
	var m := MapLoader.parse(hostile, "t", errors)
	_check("hostile map still loads safely", m != null, m != null)
	if m != null:
		_check("only the plain box survives (script type, file-path models, 1-point path dropped)",
			m.objects.size(), m.objects.size() == 1 and m.objects[0]["type"] == &"box")
		var size: Vector3 = m.objects[0]["size"]
		_check("box size clamped to sane range", size,
			size.x <= MapLoader.SIZE_RANGE.y and size.y >= MapLoader.SIZE_RANGE.x and size.z >= MapLoader.SIZE_RANGE.x)
		_check("bad color falls back", m.objects[0]["color"], m.objects[0]["color"] == Color.GRAY)
		var far := m.spawns[1].origin
		_check("huge / non-numeric coordinates clamped", far,
			absf(far.x) <= MapLoader.MAX_COORD and absf(far.y) <= MapLoader.MAX_COORD and far.z == 0.0)
		_check("name length limited", m.name.length(), m.name.length() <= MapLoader.MAX_TEXT)
		_check("problems are reported", errors.size(), errors.size() >= 3)

	_header("Arena from a map")
	var arena := Arena.new()
	arena.map = arena_map
	add_child(arena)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := arena.get_world_3d().direct_space_state
	var ramp_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 10, 1), Vector3(0, -2, 1), Layers.WORLD))
	var ramp_y: float = (ramp_hit.position as Vector3).y if not ramp_hit.is_empty() else -1.0
	_check("ramp A rebuilt in place (surface height at z = 1 ≈ 1.25 m)", ramp_y, absf(ramp_y - 1.25) < 0.02)
	_check("markers built", "%d spawns / %d items" % [arena.spawn_points.size(), arena.item_spawn_points.size()],
		arena.spawn_points.size() == 10 and arena.item_spawn_points.size() == 10)
	var wall_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 10, -45.5), Vector3(0, -5, -45.5), Layers.WORLD))
	arena.queue_free()
	var open_arena := Arena.new()
	open_arena.map = arena_map
	open_arena.with_walls = false
	add_child(open_arena)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var no_wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 10, -45.5), Vector3(0, -5, -45.5), Layers.WORLD))
	_check("border walls stand normally and are gone without walls (Last on table)",
		"%s / %s" % [not wall_hit.is_empty(), not no_wall.is_empty()], not wall_hit.is_empty() and no_wall.is_empty())
	open_arena.queue_free()

	# Props and curved paths build with collision.
	var custom := MapLoader.parse(JSON.stringify({
		"format": 1, "spawns": [{"pos": [0, 0, 0]}, {"pos": [3, 0, 0]}],
		"objects": [
			{"type": "prop", "model": PropCatalog.ids()[0], "pos": [10, 0, 0], "rot": [0, 30, 0], "scale": 2.0},
			{"type": "path", "profile": "road", "points": [[-10, 0.5, 10], [0, 2, 14], [10, 0.5, 10]], "width": 4, "height": 0.5},
		],
	}), "custom", errors)
	var arena2 := Arena.new()
	arena2.map = custom
	add_child(arena2)
	for i in 3:
		await get_tree().physics_frame
	var road_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 10, 14), Vector3(0, -2, 14), Layers.WORLD))
	var road_y: float = (road_hit.position as Vector3).y if not road_hit.is_empty() else -1.0
	_check("curved road is solid where the curve passes (top ≈ 2 m)", road_y, absf(road_y - 2.0) < 0.2)
	arena2.queue_free()

	_header("Editor source scenes ↔ map files")
	for id: String in ["test_arena", "meadow"]:   # hills is the developer's playground now
		await _round_trip(id)
	await _export_button()

	await _own_models()

	print("\n%s: %d failing check(s)" % ["FAIL" if _failures > 0 else "PASS", _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _header(title: String) -> void:
	print("\n== %s" % title)

func _check(label: String, value: Variant, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("  [%s] %s: %s" % ["ok" if ok else "FAIL", label, str(value)])

## The map's source scene exports back to the same map (objects, transforms, sizes, markers).
func _round_trip(id: String) -> void:
	var original := MapCatalog.load_map(id)
	var scene := load("res://maps/%s/source.tscn" % id) as PackedScene
	_check("%s: source.tscn exists" % id, scene != null, scene != null)
	if scene == null:
		return
	var src := scene.instantiate() as MapSource
	add_child(src)
	var warnings: Array[String] = []
	var errors: Array[String] = []
	var exported := MapLoader.parse(JSON.stringify(MapSourceIO.to_dict(src, warnings)), id, errors)
	src.queue_free()
	_check("%s: exports cleanly" % id, warnings + errors, exported != null and warnings.is_empty())
	if exported == null:
		return
	_check("%s: same objects / spawns / items / pads" % id,
		"%d/%d/%d/%d" % [exported.objects.size(), exported.spawns.size(), exported.items.size(), exported.pads.size()],
		exported.objects.size() == original.objects.size() and exported.spawns.size() == original.spawns.size()
		and exported.items.size() == original.items.size() and exported.pads.size() == original.pads.size())
	var worst := 0.0
	var mismatch := ""
	for i in mini(exported.objects.size(), original.objects.size()):
		var a: Dictionary = original.objects[i]
		var b: Dictionary = exported.objects[i]
		if a["type"] != b["type"]:
			mismatch = "object %d type %s vs %s" % [i, a["type"], b["type"]]
			break
		if a["type"] == &"path":
			var pa: PackedVector3Array = a["points"]
			var pb: PackedVector3Array = b["points"]
			worst = maxf(worst, maxf(pa[0].distance_to(pb[0]), pa[pa.size() - 1].distance_to(pb[pb.size() - 1])))
			continue
		var ta: Transform3D = a["transform"]
		var tb: Transform3D = b["transform"]
		worst = maxf(worst, ta.origin.distance_to(tb.origin))
		for axis in 3:
			worst = maxf(worst, (ta.basis[axis] - tb.basis[axis]).length())
		var key := "scale" if a["type"] == &"prop" else "size"
		worst = maxf(worst, (a[key] as Vector3).distance_to(b[key]))
		if a["type"] == &"prop" and (a["model"] != b["model"] or a["collision"] != b["collision"]):
			mismatch = "object %d: %s/%s vs %s/%s" % [i, a["model"], a["collision"], b["model"], b["collision"]]
	for i in mini(exported.spawns.size(), original.spawns.size()):
		worst = maxf(worst, original.spawns[i].origin.distance_to(exported.spawns[i].origin))
		worst = maxf(worst, (original.spawns[i].basis.z - exported.spawns[i].basis.z).length())
	for i in mini(exported.items.size(), original.items.size()):
		worst = maxf(worst, original.items[i].distance_to(exported.items[i]))
	worst = maxf(worst, original.podium.origin.distance_to(exported.podium.origin))
	_check("%s: positions / rotations / sizes / models match (worst difference)" % id,
		mismatch if not mismatch.is_empty() else "%.4f" % worst, mismatch.is_empty() and worst < 0.01)

## A map's own .glb models (Blender terrain etc.): safe loading, limits, collision-only meshes, export.
func _own_models() -> void:
	_header("Own models (maps/<id>/models/*.glb)")
	var bad_names: Array[String] = ["../terrain", "a.b", "a/b", "", "x".repeat(41), "C:"]
	var accepted: Array[String] = []
	for n in bad_names:
		if MapModels.valid_name(n) or MapModels.exists("hills", n):
			accepted.append(n)
	_check("unsafe model names are rejected", accepted, accepted.is_empty())
	var errors: Array[String] = []
	_check("random bytes are not a .glb", null, not MapModels.check_glb("hello world, not a model".to_utf8_buffer(), errors))
	_check("a .glb pointing at an outside file is refused", null, not MapModels.check_glb(_glb_with_outside_file(), errors))
	var big := PackedByteArray()
	big.resize(MapModels.MAX_FILE_BYTES + 1)
	_check("an oversized model is refused", null, MapModels._load_glb(big, "big", errors) == null)
	var parsed := MapLoader.parse(JSON.stringify({"format": 1, "spawns": [{"pos": [0, 0, 0]}, {"pos": [3, 0, 0]}],
		"objects": [{"type": "prop", "model": "map/terrain"}, {"type": "prop", "model": "map/../../hills/models/terrain"}]}),
		"test_arena", errors)
	_check("own models only from the map's own folder", parsed.objects.size(), parsed.objects.size() == 0)

	var hills := MapCatalog.load_map("hills")
	var terrain_obj := {}
	for o in (hills.objects if hills != null else []):
		if o["type"] == &"prop" and o["model"] == "map/terrain":
			terrain_obj = o
	_check("hills: terrain is an own model with mesh collision", terrain_obj.get("collision"),
		terrain_obj.get("collision") == "mesh")
	var model := MapModels.load_model("hills", "terrain", errors)
	var visible_colored := false
	var col_hidden := false
	for mi in model.get_children():
		var m := mi as MeshInstance3D
		if MapModels.is_collision_node(m.name):
			col_hidden = true
		else:
			var override := m.get_surface_override_material(0) as BaseMaterial3D
			visible_colored = override != null and override.vertex_color_use_as_albedo
	model.free()
	_check("terrain loads: vertex colors on, has a collision-only mesh", "%s / %s" % [visible_colored, col_hidden],
		visible_colored and col_hidden)
	var arena := Arena.new()
	arena.map = hills
	add_child(arena)
	for i in 3:
		await get_tree().physics_frame
	var space := arena.get_world_3d().direct_space_state
	var probe := Vector3(31.0, 0.0, -29.0)   # the big hill
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 30.0, probe + Vector3.DOWN * 10.0, Layers.WORLD))
	var hill_y: float = (hit.position as Vector3).y if not hit.is_empty() else -99.0
	var shown_col := 0
	for n in arena.find_children("*", "MeshInstance3D", true, false):
		if MapModels.is_collision_node(n.name) and (n as MeshInstance3D).is_visible_in_tree():
			shown_col += 1
	_check("cars drive on the terrain (big hill top > 4 m), collision mesh invisible", "%.2f m, %d shown" % [hill_y, shown_col],
		hill_y > 4.0 and shown_col == 0)
	_check("valleys lower the fall-off height", arena.lowest_y, arena.lowest_y < -1.0)
	arena.queue_free()

	# Exporter: this map's own model → "map/<name>"; a model from another map's folder is refused.
	var src := MapSource.new()
	src.map_id = "zz_probe_models"
	add_child(src)
	var foreign := (load("res://maps/hills/models/terrain.glb") as PackedScene).instantiate() as Node3D
	src.add_child(foreign)
	var warnings: Array[String] = []
	var d := MapSourceIO.to_dict(src, warnings)
	_check("a model from another map's folder is not exported", "%d objects, %d warnings" % [(d["objects"] as Array).size(), warnings.size()],
		(d["objects"] as Array).is_empty() and warnings.size() == 1)
	src.map_id = "hills"
	warnings.clear()
	d = MapSourceIO.to_dict(src, warnings)
	_check("the map's own model exports as map/<name>", d["objects"], (d["objects"] as Array).size() == 1
		and (d["objects"] as Array)[0]["model"] == "map/terrain")
	src.queue_free()
	await get_tree().process_frame

## A tiny .glb whose buffer points at a file outside it.
func _glb_with_outside_file() -> PackedByteArray:
	var json := '{"asset":{"version":"2.0"},"buffers":[{"uri":"../../secret.bin","byteLength":4}]}'
	while json.length() % 4 != 0:
		json += " "
	var body := json.to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(20)
	out.encode_u32(0, MapModels.GLB_MAGIC)
	out.encode_u32(4, 2)
	out.encode_u32(8, 20 + body.size())
	out.encode_u32(12, body.size())
	out.encode_u32(16, MapModels.GLB_JSON_CHUNK)
	out.append_array(body)
	return out

## The "Export map" button writes maps/<id>/map.json and the menu lists the new map.
func _export_button() -> void:
	var id := "zz_probe_export"
	var src := MapSource.new()
	src.map_id = id
	src.map_name = "Probe Export"
	add_child(src)
	for pos: Vector3 in [Vector3(-5, 0, 0), Vector3(5, 0, 0)]:
		var spawn := MapSpawn.new()
		src.add_child(spawn)
		spawn.position = pos
	var shape := MapShape.new()
	shape.kind = MapShape.Kind.RAMP
	src.add_child(shape)
	shape.rotation_degrees = Vector3(0.0, 30.0, 0.0)
	var ok := src.export_map()
	var listed := false
	for m in MapCatalog.list():
		listed = listed or m["id"] == id
	var map := MapCatalog.load_map(id)
	_check("Export map writes a playable map that shows up in the list", "%s, listed %s" % [ok, listed],
		ok and listed and map != null and map.objects.size() == 1 and map.objects[0]["type"] == &"wedge")
	src.queue_free()
	DirAccess.remove_absolute("res://maps/%s/map.json" % id)
	DirAccess.remove_absolute("res://maps/%s" % id)
	var bad := MapSource.new()
	bad.map_id = "Bad Id!"
	add_child(bad)
	_check("an invalid map id is refused", null, not bad.export_map())
	bad.queue_free()
	await get_tree().process_frame
