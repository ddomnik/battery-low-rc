class_name UiKit
## Small helpers so all menus share one look. Every menu is built in code.

const TITLE_FONT_SIZE := 72
const HEADING_FONT_SIZE := 48
const BUTTON_FONT_SIZE := 28
const BUTTON_SIZE := Vector2(320.0, 56.0)
const ROW_LABEL_WIDTH := 140.0
const SEPARATION := 16
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.55)

## A full-rect CenterContainer with a VBoxContainer inside; returns the VBox.
static func centered_column(parent: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", SEPARATION)
	center.add_child(box)
	return box

static func title(parent: Control, text: String, font_size: int = TITLE_FONT_SIZE) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	parent.add_child(label)
	return label

static func button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BUTTON_SIZE
	b.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	parent.add_child(b)
	return b

## A row "Label: <control>" for settings fields; returns the row so the caller can add the control.
static func row(parent: Control, text: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", SEPARATION)
	parent.add_child(r)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = ROW_LABEL_WIDTH
	label.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	r.add_child(label)
	return r

## Semi-transparent full-screen backdrop that also blocks clicks to whatever is behind.
static func dim_background(parent: Control) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = DIM_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
	return bg
