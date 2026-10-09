@tool
class_name MapShape
extends Node3D
## A solid block in a map: box, ramp (wedge) or cylinder, any size, rotation and color.
## Move / rotate / scale it with the gizmos; scaling multiplies size on export.
## Box and cylinder: the node sits at the center. Ramp: the node sits in the middle of its base and the ramp
## rises toward −Z (the high, vertical side is at −Z).

enum Kind { BOX, RAMP, CYLINDER }

const KIND_TYPES: Array[String] = ["box", "wedge", "cylinder"]

@export var kind: Kind = Kind.BOX:
	set(v):
		kind = v
		_refresh()
@export var size: Vector3 = Vector3(4.0, 2.0, 4.0):   # ramp: width, height, length; cylinder: diameter, height, –
	set(v):
		size = v.clamp(Vector3.ONE * MapLoader.SIZE_RANGE.x, Vector3.ONE * MapLoader.SIZE_RANGE.y)
		_refresh()
@export var color: Color = Color("#FF924C"):
	set(v):
		color = v
		_refresh()

var _preview: MeshInstance3D = null

func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh()

func type_name() -> String:
	return KIND_TYPES[kind]

func _refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview != null:
		_preview.queue_free()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = ArenaBuilder.ROUGHNESS
	var mesh: Mesh
	match kind:
		Kind.BOX:
			var box := BoxMesh.new()
			box.size = size
			box.material = mat
			mesh = box
		Kind.RAMP:
			mesh = ArenaBuilder.wedge_mesh(size, mat)
		Kind.CYLINDER:
			var cyl := CylinderMesh.new()
			cyl.top_radius = size.x * 0.5
			cyl.bottom_radius = size.x * 0.5
			cyl.height = size.y
			cyl.material = mat
			mesh = cyl
	_preview = MeshInstance3D.new()
	_preview.mesh = mesh
	add_child(_preview, false, Node.INTERNAL_MODE_BACK)
