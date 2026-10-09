@tool
class_name MapMarker
extends Marker3D
## Base of the map editor's markers (MapSpawn, MapItem, MapPad, MapPodium): a point on the ground, drawn in the
## editor with a preview of what will be there in the game. The preview is an internal child, never saved.

var _preview: Node3D = null

func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh()

## Rebuilds the editor preview.
func _refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview != null:
		_preview.queue_free()
	_preview = Node3D.new()
	add_child(_preview, false, Node.INTERNAL_MODE_BACK)
	_build_preview(_preview)

## Subclasses add their preview meshes to root.
func _build_preview(_root: Node3D) -> void:
	pass

static func preview_part(root: Node3D, mesh: Mesh, color: Color, pos: Vector3, alpha: float = 1.0) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color, alpha)
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if mesh is PrimitiveMesh:
		(mesh as PrimitiveMesh).material = mat
	else:
		(mesh as ArrayMesh).surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi

static func box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
