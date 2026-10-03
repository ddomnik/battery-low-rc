class_name ResultsScreen
extends Control
## End-of-round screen: ranked list (rank, name, score; local player highlighted), Play again, Exit to menu.

signal play_again_requested
signal exit_requested

const ROW_FONT_SIZE := 28
const LOCAL_HIGHLIGHT := Color(1.0, 0.9, 0.3)
const NAME_COLUMN_WIDTH := 260.0

var _table: GridContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	UiKit.dim_background(self)
	var box := UiKit.centered_column(self)
	UiKit.title(box, "TIME'S UP!", UiKit.HEADING_FONT_SIZE)
	_table = GridContainer.new()
	_table.columns = 3
	_table.add_theme_constant_override("h_separation", 32)
	_table.add_theme_constant_override("v_separation", 6)
	box.add_child(_table)
	UiKit.button(box, "Play again").pressed.connect(play_again_requested.emit)
	UiKit.button(box, "Exit to menu").pressed.connect(exit_requested.emit)

## ranking is best first; scores maps player_id → score.
func show_results(ranking: Array[Car], scores: Dictionary, local_car: Car) -> void:
	for child in _table.get_children():
		_table.remove_child(child)
		child.queue_free()
	var place := 0
	var last_score := -1
	for i in ranking.size():
		var car := ranking[i]
		var score: int = scores.get(car.player_id, 0)
		if score != last_score:
			place = i + 1   # tied scores share a place
			last_score = score
		var color := LOCAL_HIGHLIGHT if car == local_car else car.color
		_cell("%d." % place, color, 0.0)
		_cell(car.display_name, color, NAME_COLUMN_WIDTH)
		_cell(str(score), color, 0.0)
	visible = true

func _cell(text: String, color: Color, min_width: float) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = min_width
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	_table.add_child(label)
