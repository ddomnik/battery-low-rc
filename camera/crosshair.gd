class_name Crosshair
extends Control
## Small 2D crosshair drawn where the (hidden) mouse cursor is. Positioned by AimVisuals.

const RADIUS := 9.0
const TICK_LENGTH := 6.0
const LINE_WIDTH := 2.0
const COLOR := Color(1.0, 1.0, 1.0, 0.9)
const OUTLINE := Color(0.0, 0.0, 0.0, 0.6)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2.ONE * (RADIUS + TICK_LENGTH) * 2.0

func _draw() -> void:
	var c := size * 0.5
	for pass_color: Color in [OUTLINE, COLOR]:
		var w := LINE_WIDTH + (2.0 if pass_color == OUTLINE else 0.0)
		draw_arc(c, RADIUS, 0.0, TAU, 32, pass_color, w, true)
		for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + dir * (RADIUS - TICK_LENGTH * 0.5), c + dir * (RADIUS + TICK_LENGTH), pass_color, w, true)

## Centers the crosshair on a screen position.
func move_to(screen_pos: Vector2) -> void:
	position = screen_pos - size * 0.5
