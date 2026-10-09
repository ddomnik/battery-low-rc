@tool
class_name MapPodium
extends MapMarker
## Where the winners' podium appears after the round: on open, flat ground with room in front (−Z faces away
## from the camera's default north-up view; the losers' row lies about 5 m to the +Z side).

const PREVIEW_COLOR := Color(0.95, 0.85, 0.5)

func _build_preview(root: Node3D) -> void:
	preview_part(root, box_mesh(Vector3(1.8, 1.5, 1.8)), PREVIEW_COLOR, Vector3(0.0, 0.75, 0.0), 0.6)
	preview_part(root, box_mesh(Vector3(1.8, 1.0, 1.8)), PREVIEW_COLOR, Vector3(-1.9, 0.5, 0.0), 0.6)
	preview_part(root, box_mesh(Vector3(1.8, 0.6, 1.8)), PREVIEW_COLOR, Vector3(1.9, 0.3, 0.0), 0.6)
	preview_part(root, box_mesh(Vector3(8.0, 0.05, 2.0)), Color(0.6, 0.6, 0.6), Vector3(0.0, 0.03, 5.0), 0.4)
