@tool
class_name MapItem
extends MapMarker
## Where an item box floats: put the marker on the ground, the box hovers HEIGHT above it.

const HEIGHT := 0.8
const PREVIEW_COLOR := Color(1.0, 0.8, 0.2)

func _build_preview(root: Node3D) -> void:
	preview_part(root, box_mesh(Vector3.ONE * 0.8), PREVIEW_COLOR, Vector3(0.0, HEIGHT, 0.0), 0.6)
