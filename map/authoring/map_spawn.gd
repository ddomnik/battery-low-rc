@tool
class_name MapSpawn
extends MapMarker
## Where a car starts: put it on the ground; the car faces the marker's −Z (the blue arrow).
## A map needs at least 2 spawns, 10 for a full field (more players than spawns share them).

const PREVIEW_COLOR := Color(0.3, 0.75, 1.0)

func _build_preview(root: Node3D) -> void:
	preview_part(root, box_mesh(Vector3(1.0, 0.5, 2.0)), PREVIEW_COLOR, Vector3(0.0, 0.35, 0.0), 0.6)
	var arrow := ArenaBuilder.wedge_mesh(Vector3(0.8, 0.3, 1.0), null)
	preview_part(root, arrow, PREVIEW_COLOR.darkened(0.3), Vector3(0.0, 0.6, -0.4))
