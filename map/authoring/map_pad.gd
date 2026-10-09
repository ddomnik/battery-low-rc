@tool
class_name MapPad
extends MapMarker
## A charging pad (5 × 5 m) on the ground: cars standing still on it recharge their battery.

func _build_preview(root: Node3D) -> void:
	var size := ChargingPad.SIZE
	preview_part(root, box_mesh(Vector3(size, 0.05, size)), ChargingPad.COLOR, Vector3(0.0, 0.03, 0.0), 0.8)
