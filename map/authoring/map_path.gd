@tool
class_name MapPath
extends Path3D
## A curved road or wall: draw the curve with the Path3D tools (toolbar above the 3D view: add / move points,
## drag the handles to bend it). Road: the curve is the top of the road, so it can climb over hills.
## Wall: stands on the curve. The preview shows exactly what the game builds.

enum Profile { ROAD, WALL }

const PROFILE_NAMES: Array[String] = ["road", "wall"]

@export var profile: Profile = Profile.ROAD:
	set(v):
		profile = v
		_refresh()
@export_range(0.2, 100.0, 0.1, "suffix:m") var width: float = 5.0:   # road width / wall thickness
	set(v):
		width = v
		_refresh()
@export_range(0.05, 50.0, 0.05, "suffix:m") var height: float = 0.6:   # road thickness / wall height
	set(v):
		height = v
		_refresh()
@export var color: Color = Color("#B9A27A"):
	set(v):
		color = v
		_refresh()

var _preview: CSGPolygon3D = null

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	if curve == null:   # start with a gentle bend so something shows up right away
		curve = Curve3D.new()
		curve.add_point(Vector3(-8.0, 0.0, 0.0), Vector3.ZERO, Vector3(3.0, 0.0, -3.0))
		curve.add_point(Vector3(8.0, 0.0, 0.0), Vector3(-3.0, 0.0, -3.0), Vector3.ZERO)
	_refresh()

func profile_name() -> String:
	return PROFILE_NAMES[profile]

func _refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview != null:
		_preview.queue_free()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = ArenaBuilder.ROUGHNESS
	_preview = CSGPolygon3D.new()
	_preview.polygon = Arena.path_polygon(profile_name(), width, height)
	_preview.mode = CSGPolygon3D.MODE_PATH
	_preview.path_node = NodePath("..")
	_preview.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	_preview.path_interval = Arena.PATH_STEP
	_preview.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH_FOLLOW
	_preview.path_local = true
	_preview.smooth_faces = true
	_preview.material = mat
	add_child(_preview, false, Node.INTERNAL_MODE_BACK)
