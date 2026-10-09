@tool
class_name MapSource
extends Node3D
## Root of a map you build in the Godot editor (maps/<id>/source.tscn). Shows the floor and sun
## while you edit; "Export map" writes maps/<id>/map.json, which is what the game plays. Press F6 on this scene
## to export and test it right away (a match with bots on this map).
##
## Children it understands (any depth, so group them under plain Node3D folders):
##   MapShape (box / ramp / cylinder) · MapPath (curved road / wall) · dragged-in nature kit .glb models (props)
##   MapFluid (water / lava / mud / acid areas) · MapSpawn · MapItem · MapPad · MapPodium.
##   Hidden nodes are skipped (handy for drafts).
## Models: nature kit .glb files, or your own .glb files in maps/<id>/models/ (e.g. a Blender terrain).
## Collision override groups: "map_no_collision", "map_box_collision", "map_convex_collision", "map_mesh_collision".
## Group "map_border" on any object marks an outer wall: left out in "Last on table" (cars can be pushed off).
## See docs/MAP_MAKING.md.

enum FloorMaterial { CHECKER, COLOR, NONE }   # NONE: no floor (your terrain model is the ground)

const CHECKER_SHADER: Shader = preload("res://arena/shaders/checker.gdshader")
const TEST_BOTS := 5

@export_tool_button("Export map", "Save") var export_action: Callable = export_map

@export_group("Map")
@export var map_id: String = ""            # folder in maps/; empty = the folder this scene is in
@export var map_name: String = "My Map"
@export var author: String = ""

@export_group("Floor")
@export var floor_size: Vector2 = Vector2(90.0, 90.0):
	set(v):
		floor_size = v.clamp(Vector2.ONE * 10.0, Vector2.ONE * MapLoader.SIZE_RANGE.y)
		_refresh()
@export var floor_material: FloorMaterial = FloorMaterial.CHECKER:
	set(v):
		floor_material = v
		_refresh()
@export var floor_color: Color = Color("#7FB55E"):
	set(v):
		floor_color = v
		_refresh()

@export_group("Light")
@export var sun_rotation: Vector3 = Vector3(-55.0, 35.0, 0.0):
	set(v):
		sun_rotation = v
		_refresh()
@export_range(0.0, 4.0, 0.05) var ambient: float = 0.6

var _preview: Node3D = null

func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh()
		return
	# Run with F6 (this scene is the one being played): export, then play a match on this map.
	if get_tree().current_scene == self and export_map():
		var config := MatchConfig.from_settings()
		config.map_id = resolved_id()
		config.bot_count = TEST_BOTS
		Game.queue_match(config)
		get_tree().change_scene_to_file.call_deferred(Game.MAIN_SCENE)

## The map id this scene exports to.
func resolved_id() -> String:
	if not map_id.strip_edges().is_empty():
		return map_id.strip_edges()
	return scene_file_path.get_base_dir().get_file()

## Writes maps/<id>/map.json. Returns true on success; problems are printed to the Output panel.
func export_map() -> bool:
	var id := resolved_id()
	if not MapCatalog.valid_id(id):
		_report_error("map id '%s' is not valid: use lowercase letters, digits, _ and - (set Map Id, or save this scene in maps/<id>/)." % id)
		return false
	var warnings: Array[String] = []
	var data := MapSourceIO.to_dict(self, warnings)
	var text := JSON.stringify(data, " ")
	var errors: Array[String] = []
	var map := MapLoader.parse(text, id, errors)
	for w in warnings + errors:
		print_rich("[color=orange]Map '%s': %s[/color]" % [id, w])
	if map == null:
		_report_error("not exported — fix the problems above.")
		return false
	var dir := MapCatalog.BUILTIN_DIR + id
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir + "/" + MapCatalog.MAP_FILE, FileAccess.WRITE)
	if file == null:
		_report_error("cannot write %s/%s" % [dir, MapCatalog.MAP_FILE])
		return false
	file.store_string(text + "\n")
	file.close()
	print_rich("[color=green]Map '%s' exported: %d objects, %d spawns, %d item spots, %d pads → %s/%s[/color]" % [
		id, map.objects.size(), map.spawns.size(), map.items.size(), map.pads.size(), dir, MapCatalog.MAP_FILE])
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		Engine.get_singleton(&"EditorInterface").call(&"get_resource_filesystem").call(&"scan")
	return true

func _report_error(message: String) -> void:
	push_error("Map export: " + message)
	print_rich("[color=red]Map export: %s[/color]" % message)

## Editor preview: floor and sun as the game will build them.
func _refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview != null:
		_preview.queue_free()
	_preview = Node3D.new()
	add_child(_preview, false, Node.INTERNAL_MODE_BACK)
	if floor_material != FloorMaterial.NONE:
		var floor_mat: Material
		if floor_material == FloorMaterial.CHECKER:
			var checker := ShaderMaterial.new()
			checker.shader = CHECKER_SHADER
			floor_mat = checker
		else:
			floor_mat = _standard(floor_color)
		_preview_box(Vector3(0.0, -0.5, 0.0), Vector3(floor_size.x, 1.0, floor_size.y), floor_mat)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = sun_rotation
	sun.shadow_enabled = true
	_preview.add_child(sun)

func _preview_box(center: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = center
	_preview.add_child(mi)

func _standard(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = ArenaBuilder.ROUGHNESS
	return m
