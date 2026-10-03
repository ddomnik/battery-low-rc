class_name DebugOverlay
extends Label
## F3: live numbers for the local car and the engine.

const UPDATE_INTERVAL := 0.1

var match_node: Match = null

var _ticks: int = 0
var _tick_window: float = 0.0
var _measured_tps: int = 0
var _refresh: float = 0.0

func _ready() -> void:
	visible = false
	position = Vector2(12.0, 12.0)
	add_theme_font_size_override("font_size", 16)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	bg.set_content_margin_all(8.0)
	add_theme_stylebox_override("normal", bg)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		visible = not visible
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	_ticks += 1
	_tick_window += delta
	if _tick_window >= 1.0:
		_measured_tps = _ticks
		_ticks = 0
		_tick_window -= 1.0

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = UPDATE_INTERVAL
	var lines: PackedStringArray = []
	lines.append("FPS %d   physics %d/s (target %d)" % [Engine.get_frames_per_second(), _measured_tps, Engine.physics_ticks_per_second])
	var car: Car = match_node.local_car if match_node != null else null
	if car != null and is_instance_valid(car):
		lines.append("speed %.1f m/s   fwd %.2f   lat %.2f" % [car.linear_velocity.length(), car.forward_speed, car.lateral_speed])
		lines.append("grounded %d/4   air %.2f s   up·Y %.2f" % [car.grounded_count, car.air_time, car.global_basis.y.dot(Vector3.UP)])
		lines.append("pos (%.1f, %.1f, %.1f)" % [car.global_position.x, car.global_position.y, car.global_position.z])
		lines.append("battery %.0f %%   drifting %s   boosting %s   pads %d" % [car.battery * 100.0, car.is_drifting, car.is_boosting, car.pad_overlaps])
		lines.append("steer %.2f" % car.last_steer)
		lines.append("item %s" % (car.held_item.display_name if car.held_item != null else "-"))
		lines.append("score %d   rank_fraction %.2f" % [match_node.scores.get(car.player_id, 0), match_node.rank_fraction(car)])
		var weights := match_node.item_weights(car)
		var total := 0.0
		for w in weights:
			total += w
		var odds: PackedStringArray = []
		for i in weights.size():
			odds.append("%s %.0f%%" % [match_node.item_defs[i].id, 100.0 * weights[i] / total if total > 0.0 else 0.0])
		lines.append("roll: " + "  ".join(odds))
		var rig := match_node.camera_rig
		lines.append("camera %s   yaw %.0f°" % [CameraRig.Mode.keys()[rig.mode], rad_to_deg(rig.rotation.y)])
	lines.append("orphan nodes %d" % Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	text = "\n".join(lines)
