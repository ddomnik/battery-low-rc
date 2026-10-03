class_name ResultsScreen
extends Control
## End-of-round screen: ranked list (rank, name, score; local player highlighted), Play again, Exit to menu.
## Sits in a panel on the right so the podium ceremony stays visible.

signal play_again_requested
signal exit_requested

const ROW_FONT_SIZE := 28
const LOCAL_HIGHLIGHT := Color(1.0, 0.9, 0.3)
const NAME_COLUMN_WIDTH := 260.0
const PANEL_MARGIN := 32

var _table: GridContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var panel := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	bg.set_corner_radius_all(12)
	bg.set_content_margin_all(24.0)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, PANEL_MARGIN)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiKit.SEPARATION)
	panel.add_child(box)
	UiKit.title(box, "TIME'S UP!", UiKit.HEADING_FONT_SIZE)
	_table = GridContainer.new()
	_table.columns = 3
	_table.add_theme_constant_override("h_separation", 32)
	_table.add_theme_constant_override("v_separation", 6)
	box.add_child(_table)
	UiKit.button(box, "Play again").pressed.connect(play_again_requested.emit)
	UiKit.button(box, "Exit to menu").pressed.connect(exit_requested.emit)

## ranking is best first; values[i] is the game mode's score text for ranking[i] (points, lives, IN / OUT).
func show_results(ranking: Array[Car], values: Array[String], local_car: Car) -> void:
	for child in _table.get_children():
		_table.remove_child(child)
		child.queue_free()
	var place := 0
	var last_value := ""
	for i in ranking.size():
		var car := ranking[i]
		if values[i] != last_value or not values[i].is_valid_int():
			place = i + 1   # tied point / life counts share a place
			last_value = values[i]
		var color := LOCAL_HIGHLIGHT if car == local_car else car.color
		_cell("%d." % place, color, 0.0)
		_cell(car.display_name, color, NAME_COLUMN_WIDTH)
		_cell(values[i], color, 0.0)
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
