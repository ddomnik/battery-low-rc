class_name Hud
extends Control
## In-match HUD: round timer (top center), scoreboard (top right), countdown "3 · 2 · 1 · GO!" (center),
## battery bar (bottom center, flashes when full), item slot (bottom right), camera mode label (bottom left),
## fading popups.

const MARGIN := 16.0
const SMALL_FONT_SIZE := 16
const TIMER_FONT_SIZE := 36
const COUNTDOWN_FONT_SIZE := 160
const GO_SHOW_TIME := 0.8             # "GO!" stays this long after the countdown, fading out
const ITEM_FONT_SIZE := 28
const ITEM_SLOT_SIZE := Vector2(260.0, 64.0)
const EMPTY_ITEM_TEXT := "—"
const EMPTY_ITEM_COLOR := Color(1.0, 1.0, 1.0, 0.5)
const BATTERY_BAR_SIZE := Vector2(380.0, 26.0)
const BATTERY_EMPTY_COLOR := Color(0.95, 0.3, 0.25)
const BATTERY_FULL_COLOR := Color(0.45, 0.95, 0.35)
const BATTERY_FLASH_COLOR := Color(1.0, 1.0, 0.65)
const BATTERY_FLASH_SPEED := 10.0
const BATTERY_FULL_AT := 0.999
const POPUP_FONT_SIZE := 52
const POPUP_ANCHOR_Y := 0.3           # fraction of the screen height
const POPUP_TIME := 1.2
const POPUP_RISE := 60.0
const POPUP_STACK := 64.0             # vertical spacing between popups shown at the same time
const SCORE_FONT_SIZE := 20
const SCORE_NAME_WIDTH := 150.0
const SCORE_LOCAL_COLOR := Color(1.0, 0.9, 0.3)

var car: Car = null
var match_node: Match = null

var _mode_label: Label
var _timer_label: Label
var _countdown_label: Label
var _item_label: Label
var _battery_bar: ProgressBar
var _score_table: GridContainer
var _battery_fill: StyleBoxFlat
var _live_popups: int = 0
var _time: float = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_mode_label = _make_label("ModeLabel", SMALL_FONT_SIZE, 4)
	_mode_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	_mode_label.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_timer_label = _make_label("TimerLabel", TIMER_FONT_SIZE, 8)
	_timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	_timer_label.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_countdown_label = _make_label("CountdownLabel", COUNTDOWN_FONT_SIZE, 16)
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.visible = false

	var slot := PanelContainer.new()
	slot.name = "ItemSlot"
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = ITEM_SLOT_SIZE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	bg.set_corner_radius_all(8)
	slot.add_theme_stylebox_override("panel", bg)
	add_child(slot)
	slot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	slot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	slot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_item_label = Label.new()
	_item_label.name = "ItemLabel"
	_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_item_label.add_theme_font_size_override("font_size", ITEM_FONT_SIZE)
	_item_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_item_label.add_theme_constant_override("outline_size", 6)
	slot.add_child(_item_label)
	_on_item_changed(null)

	var battery_box := VBoxContainer.new()
	battery_box.name = "Battery"
	battery_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(battery_box)
	var battery_label := Label.new()
	battery_label.text = "BATTERY"
	battery_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battery_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	battery_label.add_theme_color_override("font_outline_color", Color.BLACK)
	battery_label.add_theme_constant_override("outline_size", 4)
	battery_box.add_child(battery_label)
	_battery_bar = ProgressBar.new()
	_battery_bar.name = "BatteryBar"
	_battery_bar.min_value = 0.0
	_battery_bar.max_value = 1.0
	_battery_bar.step = 0.0
	_battery_bar.show_percentage = false
	_battery_bar.custom_minimum_size = BATTERY_BAR_SIZE
	_battery_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	bar_bg.set_corner_radius_all(6)
	bar_bg.set_border_width_all(2)
	bar_bg.border_color = Color(1.0, 1.0, 1.0, 0.6)
	_battery_fill = StyleBoxFlat.new()
	_battery_fill.set_corner_radius_all(6)
	_battery_bar.add_theme_stylebox_override("background", bar_bg)
	_battery_bar.add_theme_stylebox_override("fill", _battery_fill)
	battery_box.add_child(_battery_bar)
	battery_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	battery_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	battery_box.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var board := PanelContainer.new()
	board.name = "Scoreboard"
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var board_bg := StyleBoxFlat.new()
	board_bg.bg_color = Color(0.0, 0.0, 0.0, 0.4)
	board_bg.set_corner_radius_all(8)
	board_bg.set_content_margin_all(10.0)
	board.add_theme_stylebox_override("panel", board_bg)
	add_child(board)
	_score_table = GridContainer.new()
	_score_table.name = "Table"
	_score_table.columns = 3
	_score_table.add_theme_constant_override("h_separation", 12)
	board.add_child(_score_table)
	board.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	board.grow_horizontal = Control.GROW_DIRECTION_BEGIN

func bind(local_car: Car, m: Match) -> void:
	car = local_car
	match_node = m
	m.camera_mode_changed.connect(_on_camera_mode_changed)
	_on_camera_mode_changed(m.config.camera_mode)
	local_car.item_changed.connect(_on_item_changed)
	_on_item_changed(local_car.held_item)
	local_car.battery_changed.connect(_on_battery_changed)
	_on_battery_changed(local_car.battery)
	m.scores_changed.connect(_refresh_scoreboard)
	_refresh_scoreboard()

## Rank / name / score, best first; tied scores share a rank. Rebuilt when scores change (≤ 10 rows).
func _refresh_scoreboard() -> void:
	for child in _score_table.get_children():
		_score_table.remove_child(child)
		child.queue_free()
	var ranking := match_node.get_ranking()
	var place := 0
	var last_score := -1
	for i in ranking.size():
		var c := ranking[i]
		var score: int = match_node.scores.get(c.player_id, 0)
		if score != last_score:
			place = i + 1
			last_score = score
		var color := SCORE_LOCAL_COLOR if c == car else c.color
		_score_cell("%d." % place, color, 0.0)
		_score_cell(c.display_name, color, SCORE_NAME_WIDTH)
		_score_cell(str(score), color, 0.0)

func _score_cell(text: String, color: Color, min_width: float) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = min_width
	label.add_theme_font_size_override("font_size", SCORE_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	_score_table.add_child(label)

## Big fading text in the upper part of the screen ("PERFECT LANDING!", "+1").
func popup(text: String, color: Color = Color.WHITE) -> void:
	var label := _make_label("Popup", POPUP_FONT_SIZE, 10)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = POPUP_ANCHOR_Y
	label.anchor_bottom = POPUP_ANCHOR_Y
	label.position.y += _live_popups * POPUP_STACK
	_live_popups += 1
	var tw := label.create_tween().set_parallel()
	tw.tween_property(label, "position:y", label.position.y - POPUP_RISE, POPUP_TIME).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, POPUP_TIME).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(_end_popup.bind(label))

func _end_popup(label: Label) -> void:
	_live_popups -= 1
	label.queue_free()

func _on_battery_changed(value: float) -> void:
	_battery_bar.value = value

func _on_item_changed(item: ItemDef) -> void:
	_item_label.text = item.display_name if item != null else EMPTY_ITEM_TEXT
	_item_label.add_theme_color_override("font_color", item.color if item != null else EMPTY_ITEM_COLOR)

func _process(delta: float) -> void:
	if match_node == null:
		return
	_time += delta
	var full := car.battery >= BATTERY_FULL_AT
	var flash := 0.5 + 0.5 * sin(_time * BATTERY_FLASH_SPEED)
	_battery_fill.bg_color = BATTERY_FULL_COLOR.lerp(BATTERY_FLASH_COLOR, flash) if full \
		else BATTERY_EMPTY_COLOR.lerp(BATTERY_FULL_COLOR, car.battery)
	_timer_label.text = _format_time(match_node.time_left)
	match match_node.state:
		Match.State.COUNTDOWN:
			_countdown_label.visible = true
			_countdown_label.modulate.a = 1.0
			_countdown_label.text = str(ceili(match_node.countdown_left))
		Match.State.PLAYING:
			var since := match_node.state_time
			_countdown_label.visible = since < GO_SHOW_TIME
			_countdown_label.modulate.a = 1.0 - since / GO_SHOW_TIME
			_countdown_label.text = "GO!"
		_:
			_countdown_label.visible = false

func _on_camera_mode_changed(mode: CameraRig.Mode) -> void:
	var hint := "  (F2)" if OS.is_debug_build() else ""
	_mode_label.text = "Camera: %s%s" % [CameraRig.mode_label(mode), hint]

func _make_label(node_name: String, font_size: int, outline: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

static func _format_time(seconds: float) -> String:
	var s := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [floori(s / 60.0), s % 60]
