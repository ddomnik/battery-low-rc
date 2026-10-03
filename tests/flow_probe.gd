extends Node
## Headless game-flow probe (M3): main menu → match → in-game menu → exit loops, orphan node baseline,
## countdown / round timer / results, Play again, Exit to menu, Quit only in the main menu.
## Clicks are simulated by emitting the buttons' pressed signals; keys through InputEventAction.
## Headless ignores mouse-mode changes, so the probe checks Match.desired_mouse_mode() instead.
## Run: godot --headless --path . --fixed-fps 60 res://tests/flow_probe.tscn

const MAIN_SCENE: PackedScene = preload("res://main/main.tscn")

var _main: Main
var _failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var saved_bots := Settings.bot_count
	var saved_camera := Settings.camera_mode
	Settings.bot_count = 0   # menu loops: nobody rams the car while it coasts with the menu open
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	await _frames(10)
	var baseline := _orphans()
	_header("Main menu")
	_check("menu shows Play, Bots, Camera and Quit", true,
		_find_button(_main.ui_root, "Play") != null and _find_button(_main.ui_root, "Quit") != null
		and _find(_main.ui_root, "SpinBox") != null and _find(_main.ui_root, "OptionButton") != null)
	_info("orphan node baseline", baseline)

	for loop in 5:
		_header("Loop %d: Play → drive → Escape → Exit to menu" % (loop + 1))
		_click(_main.ui_root, "Play")
		await _frames(3)
		var m := _match()
		_check("match running, starts in COUNTDOWN", m != null, m != null and m.state == Match.State.COUNTDOWN)
		if m == null:
			break
		_check("cars frozen during the countdown", m.local_car.frozen, m.local_car.frozen)
		_check("mouse hidden while driving", m.desired_mouse_mode(), m.desired_mouse_mode() == Input.MOUSE_MODE_CONFINED_HIDDEN)
		await _physics(int(Match.COUNTDOWN_TIME * 60.0) + 5)
		_check("PLAYING after 3 s, car unfrozen", m.state, m.state == Match.State.PLAYING and not m.local_car.frozen)
		_check("no Quit button inside the match", _find_button(m, "Quit") == null, _find_button(m, "Quit") == null)
		Input.action_press("move_up")
		await _physics(90)
		var speed_before := m.local_car.linear_velocity.length()
		_press("pause")
		await _physics(2)
		var menu := m.get_node("UI/InGameMenu") as InGameMenu
		_check("Escape opens the in-game menu, input off, mouse visible", menu.visible,
			menu.visible and not m.local_input.enabled and m.desired_mouse_mode() == Input.MOUSE_MODE_VISIBLE)
		var t_before := m.time
		await _physics(240)
		Input.action_release("move_up")
		_info("speed when the menu opened (m/s)", speed_before)
		_check("world keeps running (match clock advanced 4 s)", m.time - t_before, m.time - t_before > 3.9)
		_check("car coasted and holds still (< 0.1 m/s) with W still held", m.local_car.linear_velocity.length(),
			m.local_car.linear_velocity.length() < 0.1)
		if loop == 0:
			_press("pause")
			await _physics(2)
			_check("Escape again resumes (menu closed, input on, mouse hidden)", menu.visible, not menu.visible
				and m.local_input.enabled and m.desired_mouse_mode() == Input.MOUSE_MODE_CONFINED_HIDDEN)
			_press("pause")
			await _physics(2)
		_click(menu, "Exit to menu")
		await _frames(5)
		_check("back in the main menu", _match() == null, _match() == null and _find_button(_main.ui_root, "Play") != null)
		_check("orphan nodes back to baseline (%d)" % baseline, _orphans(), _orphans() == baseline)

	_header("Round end → results → Play again → results → Exit to menu")
	var cfg := MatchConfig.from_settings()
	cfg.round_time = 2.0
	cfg.bot_count = 9   # cleanup must also work with a full field of bots
	Game.start_match(cfg)
	await _frames(3)
	var first := _match()
	await _physics(int((Match.COUNTDOWN_TIME + cfg.round_time) * 60.0) + 10)
	var results := first.get_node("UI/Results") as ResultsScreen
	_check("results appear when the timer ends", first.state, first.state == Match.State.RESULTS and results.visible)
	_check("cars frozen, mouse visible on results", first.local_car.frozen,
		first.local_car.frozen and first.desired_mouse_mode() == Input.MOUSE_MODE_VISIBLE)
	_check("ranked list shows the player", _find_label(results, cfg.player_name) != null, _find_label(results, cfg.player_name) != null)
	_press("pause")
	await _physics(2)
	_check("Escape does nothing on the results screen", true, not (first.get_node("UI/InGameMenu") as InGameMenu).visible)
	_click(results, "Play again")
	await _frames(5)
	var second := _match()
	_check("Play again starts a fresh match with the same round time", second != null,
		second != null and second != first and second.state == Match.State.COUNTDOWN and is_equal_approx(second.time_left, 2.0))
	await _physics(int((Match.COUNTDOWN_TIME + cfg.round_time) * 60.0) + 10)
	_check("results again", second.state, second.state == Match.State.RESULTS)
	_click(second.get_node("UI/Results"), "Exit to menu")
	await _frames(5)
	_check("Exit to menu from results", _match() == null, _match() == null)
	_check("orphan nodes back to baseline (%d)" % baseline, _orphans(), _orphans() == baseline)

	_header("In-game Restart and camera toggle (9 bots)")
	Settings.bot_count = 9
	_click(_main.ui_root, "Play")
	await _frames(3)
	var r1 := _match()
	_press("pause")
	await _physics(2)
	var menu2 := r1.get_node("UI/InGameMenu") as InGameMenu
	var cam_before := r1.camera_rig.mode
	_click(menu2, "Camera:")
	await _physics(2)
	_check("camera toggle in the menu switches mode", r1.camera_rig.mode, r1.camera_rig.mode != cam_before)
	_click(menu2, "Camera:")
	_click(menu2, "Restart")
	await _frames(5)
	var r2 := _match()
	_check("Restart starts a fresh match in COUNTDOWN", r2 != null, r2 != null and r2 != r1 and r2.state == Match.State.COUNTDOWN)
	_check("menu closed, input enabled after restart", true, r2.local_input.enabled)
	Game.exit_to_menu()
	await _frames(5)
	_check("orphan nodes back to baseline (%d)" % baseline, _orphans(), _orphans() == baseline)

	Settings.bot_count = saved_bots
	Settings.camera_mode = saved_camera
	Settings.save_settings()
	print("\n%s: %d failing check(s)" % ["FAIL" if _failures > 0 else "PASS", _failures])
	get_tree().quit(1 if _failures > 0 else 0)

# --- Helpers -----------------------------------------------------------------------------------

func _match() -> Match:
	for child in _main.world_root.get_children():
		if child is Match and not child.is_queued_for_deletion():
			return child as Match
	return null

func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

## Presses the first visible button whose text starts with `text`.
func _click(root: Node, text: String) -> void:
	var b := _find_button(root, text)
	if b == null:
		_check("button '%s' exists" % text, false, false)
		return
	b.pressed.emit()

func _find_button(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text.begins_with(text) and (root as Button).is_visible_in_tree():
		return root as Button
	for c in root.get_children():
		var found := _find_button(c, text)
		if found != null:
			return found
	return null

func _find_label(root: Node, text: String) -> Label:
	if root is Label and (root as Label).text == text:
		return root as Label
	for c in root.get_children():
		var found := _find_label(c, text)
		if found != null:
			return found
	return null

func _find(root: Node, cls: String) -> Node:
	if root.is_class(cls):
		return root
	for c in root.get_children():
		var found := _find(c, cls)
		if found != null:
			return found
	return null

func _press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _header(title: String) -> void:
	print("\n== %s" % title)

func _check(label: String, value: Variant, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("  [%s] %s: %s" % ["ok" if ok else "FAIL", label, str(value)])

func _info(label: String, value: Variant) -> void:
	print("  [..] %s: %s" % [label, str(value)])
