class_name InGameMenu
extends Control
## Escape overlay: Resume, Restart, camera mode toggle, Exit to menu. No Quit here (main menu only).
## Never pauses the SceneTree; Match disables the local input while it is open.

signal resume_requested
signal restart_requested
signal camera_toggle_requested
signal exit_requested

var _resume_button: Button
var _camera_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	UiKit.dim_background(self)
	var box := UiKit.centered_column(self)
	UiKit.title(box, "MENU", UiKit.HEADING_FONT_SIZE)
	_resume_button = UiKit.button(box, "Resume")
	_resume_button.pressed.connect(resume_requested.emit)
	UiKit.button(box, "Restart").pressed.connect(restart_requested.emit)
	_camera_button = UiKit.button(box, "")
	_camera_button.pressed.connect(camera_toggle_requested.emit)
	UiKit.button(box, "Settings").pressed.connect(_open_settings)
	UiKit.button(box, "Exit to menu").pressed.connect(exit_requested.emit)

func open(camera_mode: CameraRig.Mode) -> void:
	set_camera_mode(camera_mode)
	visible = true
	_resume_button.grab_focus()

func close() -> void:
	for c in get_children():
		if c is SettingsMenu:
			(c as SettingsMenu).close()
	# Drop button focus so Space (handbrake) can't press a hidden button.
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()
	visible = false

func _open_settings() -> void:
	var s := SettingsMenu.new()
	s.closed.connect(_resume_button.grab_focus)
	add_child(s)

func set_camera_mode(mode: CameraRig.Mode) -> void:
	_camera_button.text = "Camera: %s" % CameraRig.mode_label(mode)
