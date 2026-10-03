extends Node
## Headless probe for mouse aim, turret, items, pickups and explosions (M4).
## Runs a real Match (fixed camera), drives the local car with scripted input and records play_effect calls.
## Run: godot --headless --path . --fixed-fps 60 res://tests/items_probe.tscn

const ScriptedInput := preload("res://tests/scripted_input.gd")
const MATCH_SCENE: PackedScene = preload("res://match/match.tscn")
const TICK := 1.0 / 60.0

var _m: Match
var _car: Car
var _input: ScriptedInput
var _effects: Array[Dictionary] = []
var _failures: int = 0
var _next_id: int = 2

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var cfg := MatchConfig.new()
	cfg.camera_mode = CameraRig.Mode.FIXED
	cfg.round_time = 600.0
	cfg.bot_count = 0   # isolated tests; bots have their own probe
	_m = MATCH_SCENE.instantiate() as Match
	add_child(_m)
	_m.setup(cfg)
	_m.effect_played.connect(func(kind: StringName, pos: Vector3, param: float) -> void:
		_effects.append({"kind": kind, "pos": pos, "param": param}))
	await _ticks(int(Match.COUNTDOWN_TIME * 60.0) + 5)
	_car = _m.local_car
	_input = ScriptedInput.new()
	_input.car = _car
	add_child(_input)
	_car.input_provider = _input

	await _aim_raycast()
	await _turret()
	await _rocket()
	await _rocket_trio()
	await _balloon("on flat ground, 12 m", Vector3(0.0, 0.0, 12.0), false)
	await _balloon("beyond max range (40 m)", Vector3(40.0, 0.0, 0.0), true)
	await _pickups()
	await _magnet()
	await _explosion_falloff()
	await _battery_and_hud()
	await _catch_up_weights()
	_sound_bank()

	print("\n%s: %d failing check(s)" % ["FAIL" if _failures > 0 else "PASS", _failures])
	get_tree().quit(1 if _failures > 0 else 0)

# --- Scenarios ---------------------------------------------------------------------------------

func _aim_raycast() -> void:
	_header("Mouse aim: reticle on the surface under the cursor")
	await _place(Vector3(8.0, 0.8, -4.0), Vector3.FORWARD)
	var dummy := await _dummy(Vector3(13.0, 0.8, -4.0))
	_m.camera_rig.snap_to_target()
	await get_tree().process_frame
	var cam := _m.camera_rig.camera
	var pi := _m.local_input
	for t: Array in [["floor", Vector3(10.0, 0.0, 2.0)], ["ramp A (14° slope)", Vector3(0.0, 1.5, 0.0)],
			["table top", Vector3(4.0, 3.0, -12.0)]]:
		var target: Vector3 = t[1]
		pi.aim_at_screen(cam.unproject_position(target))
		var err := pi.aim_point.distance_to(target)
		_check("%s: aim point within 5 cm (err m)" % t[0], err, err < 0.05)
	pi.aim_at_screen(cam.unproject_position(dummy.global_position))
	var on_car := pi.aim_point.distance_to(dummy.global_position)
	_check("another car: aim point on its body (< 1.2 m from its center)", on_car, on_car < 1.2)
	pi.aim_at_screen(cam.unproject_position(_car.global_position))
	_check("own car is ignored (aim goes to the floor under it)", pi.aim_point.y, pi.aim_point.y < 0.05)
	_remove(dummy)

func _turret() -> void:
	_header("Turret follows the aim point")
	await _place(Vector3(-30.0, 0.8, -25.0), Vector3.FORWARD)
	_input.aim_point = _car.global_position + Vector3(8.0, 0.0, 0.0)
	await _ticks(30)
	_check("parked: turret points at the aim (err deg)", _turret_error(), _turret_error() < 3.0)
	_input.aim_point = Vector3(-20.0, 0.0, -25.0)   # fixed world point outside the circle the car drives
	_input.throttle = 1.0
	_input.steer = 1.0
	await _ticks(60)
	var worst := 0.0
	for i in 60:
		await get_tree().physics_frame
		worst = maxf(worst, _turret_error())
	_input.throttle = 0.0
	_input.steer = 0.0
	_check("while circling: turret stays on target (worst err < 12°)", worst, worst < 12.0)
	await _place_on_surface(Vector3(0.0, 0.0, 1.0), Vector3.FORWARD)
	_input.aim_point = Vector3(8.0, 0.0, 1.0)
	await _ticks(40)
	_check("on the 14° ramp: turret points at the aim (err deg)", _turret_error(), _turret_error() < 5.0)

func _rocket() -> void:
	_header("Bottle rocket flies straight to the reticle")
	await _place(Vector3(-30.0, 0.8, -25.0), Vector3.FORWARD)
	var target := Vector3(-30.0, 0.0, -40.0)
	var hits := await _fire(&"bottle_rocket", target, 1)
	if hits.size() == 1:
		_check("explodes at the reticle (horizontal err m)", _flat_dist(hits[0], target), _flat_dist(hits[0], target) < 0.6)

func _rocket_trio() -> void:
	_header("Rocket trio fans out")
	await _place(Vector3(-30.0, 0.8, -25.0), Vector3.FORWARD)
	var target := Vector3(-15.0, 0.0, -25.0)
	var hits := await _fire(&"rocket_trio", target, 3)
	if hits.size() == 3:
		var widest := 0.0
		var closest := INF
		for a in hits:
			closest = minf(closest, _flat_dist(a, target))
			for b in hits:
				widest = maxf(widest, _flat_dist(a, b))
		_check("middle rocket hits the reticle (err m)", closest, closest < 0.6)
		_check("outer rockets are > 4.5 m apart at 15 m (24° fan)", widest, widest > 4.5)

func _balloon(label: String, offset: Vector3, clamped: bool) -> void:
	_header("Water balloon " + label)
	await _place(Vector3(-30.0, 0.8, -25.0), Vector3.FORWARD)
	var target := Vector3(-30.0, 0.0, -25.0) + offset
	var hits := await _fire(&"water_balloon", target, 1)
	if hits.is_empty():
		return
	var from_car := _flat_dist(hits[0], _car.global_position)
	if clamped:
		var max_range := _item(&"water_balloon").max_range
		_check("clamped at max range %.0f m (landing distance m)" % max_range, from_car, absf(from_car - max_range) < 0.7)
	else:
		_check("lands at the reticle (horizontal err m, spec < 0.5)", _flat_dist(hits[0], target), _flat_dist(hits[0], target) < 0.5)

func _pickups() -> void:
	_header("Item boxes")
	var boxes := _m.get_node("ItemBoxes").get_children()
	var box_a := _box_near(boxes, Vector3(-24.0, 0.8, 0.0))
	var box_b := _box_near(boxes, Vector3(-17.0, 0.8, -17.0))
	_car.set_held_item(null)
	await _place(Vector3(-30.0, 0.8, 0.0), Vector3.RIGHT)
	_effects.clear()
	_input.throttle = 0.5
	var picked_at := -1.0
	for i in 90:
		await get_tree().physics_frame
		if picked_at < 0.0 and not box_a.active:
			picked_at = _m.time
	_input.throttle = 0.0
	var item := _car.held_item
	_check("driving through a box gives an item", item.id if item != null else &"none", item != null and not box_a.active and _count(&"pickup") == 1)
	await _place(Vector3(-11.5, 0.8, -17.0), Vector3.LEFT)
	_input.throttle = 0.5
	await _ticks(90)
	_input.throttle = 0.0
	_check("holding an item: second box is ignored and stays active", box_b.active, box_b.active and _car.held_item == item)

	# Park empty-handed inside box A while it is away; it must hand out an item when it comes back.
	_car.set_held_item(null)
	await _place(Vector3(-24.0, 0.8, 0.0), Vector3.RIGHT)
	var got_at := -1.0
	while _m.time - picked_at < 8.0:
		await get_tree().physics_frame
		if got_at < 0.0 and _car.held_item != null:
			got_at = _m.time - picked_at
	_info("box A came back and served the parked car after (s)", got_at)
	_check("box respawns after ~6 s and serves a car parked inside", got_at, got_at > 5.9 and got_at < 6.3)

func _magnet() -> void:
	_header("Magnetic item boxes")
	var boxes := _m.get_node("ItemBoxes").get_children()
	var box := _box_near(boxes, Vector3(24.0, 0.8, 0.0))
	var home := box.global_position
	_car.set_held_item(_item(&"bottle_rocket"))
	await _place(Vector3(19.5, 0.8, 0.0), Vector3.RIGHT)   # 4.5 m from the box
	await _ticks(60)
	_check("car holding an item: the box stays home", box.global_position.distance_to(home), box.global_position.distance_to(home) < 0.01)
	_car.set_held_item(null)
	var t := 0.0
	var got := -1.0
	var max_move := 0.0
	while t < 3.0 and got < 0.0:
		await get_tree().physics_frame
		t += TICK
		max_move = maxf(max_move, box.global_position.distance_to(home))
		if _car.held_item != null:
			got = t
	_info("box travelled before pickup (m)", max_move)
	_check("empty-handed car 4.5 m away: the box flies to it and is picked up (< 2 s)", got, got > 0.0 and got < 2.0)
	await _ticks(2)
	_check("the used box waits at its home spot", box.global_position.distance_to(home), not box.active and box.global_position.distance_to(home) < 0.01)
	_car.set_held_item(null)

	var box_c := _box_near(boxes, Vector3(0.0, 0.8, -24.0))
	var home_c := box_c.global_position
	await _place(Vector3(0.0, 0.8, -30.5), Vector3.BACK)   # 6.5 m away: weak pull at the edge of the range
	await _ticks(20)
	var pulled := box_c.global_position.distance_to(home_c)
	_car.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-30.0, 0.8, -40.0)))   # escape
	await _ticks(150)
	_info("pulled toward the car before it escaped (m)", pulled)
	_check("car escapes: the box drifts back home", box_c.global_position.distance_to(home_c),
		pulled > 0.1 and box_c.active and box_c.global_position.distance_to(home_c) < 0.01)

func _explosion_falloff() -> void:
	_header("Explosion knockback falls off with distance")
	await _place(Vector3(-30.0, 0.8, -12.0), Vector3.FORWARD)
	var center := Vector3(-30.0, 0.0, -38.0)
	var near := await _dummy(center + Vector3(1.5, 0.8, 0.0))
	var mid := await _dummy(center + Vector3(3.5, 0.8, 0.0))
	var outside := await _dummy(center + Vector3(6.0, 0.8, 0.0))
	await _ticks(40)
	var score0: int = _m.scores.get(_car.player_id, 0)
	var balloon := _item(&"water_balloon")
	var rest_y := near.global_position.y
	_m.explode(center, balloon.explosion_radius, balloon.knockback, balloon.up_knockback, _car)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var v_near := near.linear_velocity.length()
	var v_mid := mid.linear_velocity.length()
	var v_out := outside.linear_velocity.length()
	_info("water balloon, velocity after the blast: 1.5 m / 3.5 m / 6 m", "%.2f / %.2f / %.2f" % [v_near, v_mid, v_out])
	_check("near > mid > 0, outside the radius untouched", v_near, v_near > v_mid and v_mid > 0.2 and v_out < 0.05)
	_check("near victim scores a hit for the attacker", _m.scores[_car.player_id], _m.scores[_car.player_id] == score0 + 1)
	_m.explode(center, balloon.explosion_radius, balloon.knockback, balloon.up_knockback, _car)
	await get_tree().physics_frame
	_check("same victim again within 1 s: no extra score", _m.scores[_car.player_id], _m.scores[_car.player_id] == score0 + 1)
	var peak := {near: 0.0, mid: 0.0}
	for i in 90:
		await get_tree().physics_frame
		for c: Car in peak:
			peak[c] = maxf(peak[c], c.global_position.y - rest_y)
	_info("launch height (two blasts): 1.5 m / 3.5 m from the center", "%.2f / %.2f m" % [peak[near], peak[mid]])
	_check("cars near the center are launched into the air (> 1 m)", peak[near], peak[near] > 1.0)
	for d: Car in [near, mid, outside]:
		_remove(d)

func _battery_and_hud() -> void:
	_header("Battery pack and HUD item slot")
	var label := _m.get_node("UI/Hud/ItemSlot/ItemLabel") as Label
	_car.set_battery(0.2)
	_car.set_held_item(_item(&"battery_pack"))
	await get_tree().physics_frame
	_check("HUD shows the held item", label.text, label.text == "Battery Pack")
	_input.fire = true
	await _ticks(3)
	_check("battery pack adds 50 %", _car.battery, is_equal_approx(_car.battery, 0.7))
	_check("HUD slot empty after use", label.text, label.text == "—" and _car.held_item == null)
	_press("debug_give_item_3")
	await get_tree().physics_frame
	_check("debug key 3 gives the water balloon", _car.held_item.id if _car.held_item != null else &"none", _car.held_item != null and _car.held_item.id == &"water_balloon")
	_car.set_held_item(null)

func _catch_up_weights() -> void:
	_header("Catch-up roll weights")
	var other := await _dummy(Vector3(-20.0, 0.8, -20.0))
	_m.scores[_car.player_id] = 5
	_m.scores[other.player_id] = 0
	_check("leading: rocket_trio weight 0", _m.item_weights(_car), _m.item_weights(_car)[3] == 0.0)
	_m.scores[_car.player_id] = 0
	_m.scores[other.player_id] = 5
	var w := _m.item_weights(_car)
	var total := 0.0
	for x in w:
		total += x
	_check("last: rocket_trio ≈ 40 %", w[3] / total, absf(w[3] / total - 0.4) < 0.01)
	_remove(other)

## Sound files: every kind resolves, variations rotate, loops loop, music is found. (Headless plays nothing.)
func _sound_bank() -> void:
	_header("Sound bank")
	var bank := SoundBank.new()
	var missing: Array[String] = []
	for kind: StringName in SoundBank.FILES:
		if bank.next(kind) == null:
			missing.append(String(kind))
	_check("every sound kind finds its file(s)", missing, missing.is_empty())
	var seen: Array[AudioStream] = [bank.next(&"pickup"), bank.next(&"pickup"), bank.next(&"pickup"), bank.next(&"pickup")]
	_check("variations rotate (pickup: 1 → 2 → 3 → 1)", seen.size(),
		seen[0] != seen[1] and seen[1] != seen[2] and seen[0] != seen[2] and seen[3] == seen[0])
	var engine := bank.looping(&"engine") as AudioStreamWAV
	_check("engine sound loops", engine != null and engine.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		engine != null and engine.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	_check("music tracks found", bank.music_tracks().size(), bank.music_tracks().size() >= 2)

# --- Helpers -----------------------------------------------------------------------------------

## Gives the car an item, aims at target, fires, and returns the explosion positions (waits up to 3.5 s).
func _fire(id: StringName, target: Vector3, expected: int) -> Array[Vector3]:
	_car.set_held_item(_item(id))
	_input.aim_point = target
	await _ticks(20)   # let the turret turn (cosmetic) and last_aim_point update
	_effects.clear()
	_input.fire = true
	var hits: Array[Vector3] = []
	var t := 0.0
	while t < 3.5 and hits.size() < expected:
		await get_tree().physics_frame
		t += TICK
		hits.clear()
		for e in _effects:
			if e["kind"] == &"explosion" or e["kind"] == &"splash":
				hits.append(e["pos"])
	_check("fired: %d explosion(s), muzzle flash" % expected, hits.size(), hits.size() == expected and _count(&"fire") + _count(&"throw") == 1)
	await _ticks(30)
	return hits

func _place(pos: Vector3, facing: Vector3) -> void:
	_input.throttle = 0.0
	_input.steer = 0.0
	_car.teleport_to(Transform3D(Basis.looking_at(facing, Vector3.UP), pos))
	await _ticks(45)

func _place_on_surface(pos: Vector3, facing: Vector3) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 20.0, pos + Vector3.DOWN * 5.0, Layers.WORLD))
	var n: Vector3 = hit.normal
	var p: Vector3 = hit.position
	var fwd := (facing - n * facing.dot(n)).normalized()
	_input.throttle = 0.0
	_car.teleport_to(Transform3D(Basis.looking_at(fwd, n), p + n * 0.62))
	await _ticks(45)

## A parked car with no input (stand-in for a bot until M6).
func _dummy(pos: Vector3) -> Car:
	var c := _m.spawn_car({"player_id": _next_id, "peer_id": 1, "name": "Dummy %d" % _next_id,
		"color": Match.PLAYER_COLORS[_next_id % Match.PLAYER_COLORS.size()], "is_bot": true, "model_path": ""})
	_next_id += 1
	c.teleport_to(Transform3D(Basis.IDENTITY, pos))
	await _ticks(30)
	return c

func _remove(c: Car) -> void:
	_m.cars.erase(c)
	c.queue_free()

## Angle between the barrel and the aim direction, measured in the car's own plane (the turret yaws in it).
func _turret_error() -> float:
	var v := _car.visual
	var barrel := v.to_local(v.muzzle.global_position) - v.turret_mount
	var to_aim := v.to_local(_car.last_aim_point) - v.turret_mount
	barrel.y = 0.0
	to_aim.y = 0.0
	return rad_to_deg(barrel.angle_to(to_aim))

func _box_near(boxes: Array[Node], pos: Vector3) -> ItemBox:
	for b in boxes:
		if (b as ItemBox).global_position.distance_to(pos) < 1.0:
			return b as ItemBox
	push_error("items_probe: no box near %s" % pos)
	return null

func _item(id: StringName) -> ItemDef:
	for d in _m.item_defs:
		if d.id == id:
			return d
	return null

func _count(kind: StringName) -> int:
	var n := 0
	for e in _effects:
		if e["kind"] == kind:
			n += 1
	return n

func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)

func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _header(title: String) -> void:
	print("\n== %s" % title)

func _check(label: String, value: Variant, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("  [%s] %s: %s" % ["ok" if ok else "FAIL", label, _fmt(value)])

func _info(label: String, value: Variant) -> void:
	print("  [..] %s: %s" % [label, _fmt(value)])

func _fmt(value: Variant) -> String:
	if value is float:
		return "%.3f" % value
	return str(value)
