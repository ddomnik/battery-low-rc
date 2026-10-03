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
	await _new_items_and_hud()
	await _oil_handling()
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
	_header("Held item model on the roof, aimed items turn to the aim point")
	var v := _car.visual
	_check("no cannon on the car", v.find_child("Turret", true, false), v.find_child("Turret", true, false) == null)
	_check("empty-handed: no item model", v.find_child("ItemModel", true, false), v.find_child("ItemModel", true, false) == null)
	var without_muzzle: Array[StringName] = []
	for d in _m.item_defs:
		var model := ItemModels.build(d)
		if model.find_child("Muzzle", true, false) == null:
			without_muzzle.append(d.id)
		model.free()
	_check("every item has a model with a muzzle", without_muzzle, without_muzzle.is_empty())
	_car.set_held_item(_item(&"bottle_rocket"))
	await _place(Vector3(-30.0, 0.8, -25.0), Vector3.FORWARD)
	_check("holding an item mounts its model", v.find_child("ItemModel", true, false) != null, v.find_child("ItemModel", true, false) != null)
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
	var gameplay_muzzle := _car.get_muzzle_position()
	_check("gameplay muzzle = the model's muzzle (m)", gameplay_muzzle.distance_to(v.muzzle.global_position),
		gameplay_muzzle.distance_to(v.muzzle.global_position) < 0.05)
	_car.set_held_item(_item(&"shocker"))
	await _ticks(40)
	var forward_err := rad_to_deg((v.find_child("ItemMount", true, false) as Node3D).rotation.y)
	_check("Shocker sits facing forward (deg)", forward_err, absf(forward_err) < 2.0)
	_car.set_held_item(null)
	await get_tree().process_frame
	_check("used up: the model is gone", v.muzzle, v.muzzle == null)

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

func _new_items_and_hud() -> void:
	_header("Oil slick, sticky glue, shocker, blast, HUD item slot")
	var label := _m.get_node("UI/Hud/ItemSlot/ItemLabel") as Label
	_check("battery pack is gone from the items", _item(&"battery_pack"), _item(&"battery_pack") == null)

	# Oil: thrown, leaves a slippery puddle.
	await _place(Vector3(-30.0, 0.8, -25.0), Vector3.FORWARD)
	_car.set_held_item(_item(&"oil_slick"))
	await get_tree().physics_frame
	_check("HUD shows the held item", label.text, label.text == "Oil Slick")
	var oil_at := Vector3(-30.0, 0.0, -37.0)
	_input.aim_point = oil_at
	await _ticks(10)
	_input.fire = true
	await _ticks(90)
	var oil := _puddle(ItemDef.Kind.OIL)
	_check("oil lands as a puddle at the reticle", oil != null, oil != null and _flat_dist(oil.global_position, oil_at) < 0.7)
	_check("HUD slot empty after use", label.text, label.text == "—" and _car.held_item == null)
	var decals := oil.find_children("*", "Decal", false, false)
	_check("the puddle is a cluster of blobs (decals on the world layer only)", "%d blobs" % oil.blob_count(),
		oil.blob_count() >= 5 and decals.size() == oil.blob_count() and (decals[0] as Decal).cull_mask == Layers.RENDER_WORLD)
	var edge_spot := _half_on_spot(oil)
	_check("found a spot with only the left tires on the oil", edge_spot, edge_spot != Vector3.INF)
	await _place(edge_spot + Vector3.UP * 0.8, Vector3.FORWARD)
	_check("half on the oil: only the left tires get oiled", _car.wheel_oil,
		_car.wheel_oil[0] > 0.0 and _car.wheel_oil[2] > 0.0 and _car.wheel_oil[1] == 0.0 and _car.wheel_oil[3] == 0.0)
	await _place(Vector3(-30.0, 0.8, -37.0), Vector3.BACK)
	_check("on the oil: all four tires oiled (grip × %.2f each)" % _car.tuning.oil_grip_mult, _car.wheel_oil,
		_car.coated_share(_car.wheel_oil) == 1.0)
	_input.throttle = 1.0
	await _ticks(60)
	_input.throttle = 0.0
	var splatter := _car.visual.get_node("WheelSplatter2") as GPUParticles3D
	_check("driven off the puddle, the tires stay oiled", "%.1f m away, %s" % [_flat_dist(_car.global_position, oil_at), _car.wheel_oil],
		_flat_dist(_car.global_position, oil_at) > oil.radius + 1.0 and _car.coated_share(_car.wheel_oil) == 1.0)
	_check("oiled tires fling drops, more when fast", "%s, ratio %.2f" % [splatter.emitting, splatter.amount_ratio],
		splatter.emitting and splatter.amount_ratio > 0.5)
	var trail := _car.visual.get_node("TireTrail2") as TireTrail
	var track_len := 0.0
	for v in trail.vertices():
		track_len = maxf(track_len, _flat_dist(v, oil_at))
	_check("each oiled tire leaves a track behind (reaches m from the puddle center)", track_len, track_len > oil.radius + 1.0)
	await _ticks(int(_car.tuning.wheel_coating_time * 60.0))
	_check("the oil wears off after %.0f s" % _car.tuning.wheel_coating_time, "%s, drops %s" % [_car.wheel_oil, splatter.emitting],
		_car.coated_share(_car.wheel_oil) == 0.0 and not splatter.emitting)
	_check("the track stays on the ground a while longer", trail.chunk_count(), trail.chunk_count() > 0)

	# Glue: thrown, slows cars right down.
	_car.set_held_item(_item(&"sticky_glue"))
	var glue_at := Vector3(-22.0, 0.0, -25.0)
	_input.aim_point = glue_at
	await _ticks(10)
	_input.fire = true
	await _ticks(90)
	var glue := _puddle(ItemDef.Kind.GLUE)
	_check("glue lands as a puddle", glue != null, glue != null)
	_check("every puddle gets its own random shape", "%d / %d blobs" % [oil.blob_count(), glue.blob_count()],
		oil.blob_count() != glue.blob_count() or oil._blob_radii[0] != glue._blob_radii[0])
	await _place(Vector3(-22.0, 0.8, -25.0), Vector3.FORWARD)
	_input.throttle = 1.0
	var glued_speed := 0.0
	var in_glue_ticks := 0
	for i in 120:
		await get_tree().physics_frame
		if _car.coated_share(_car.wheel_glue) == 1.0:
			in_glue_ticks += 1
			glued_speed = maxf(glued_speed, _car.linear_velocity.length())
	_input.throttle = 0.0
	_check("full throttle on glued tires stays slow (top speed × %.1f)" % _car.tuning.glue_speed_mult, glued_speed,
		in_glue_ticks == 120 and glued_speed < _car.tuning.max_speed * (_car.tuning.glue_speed_mult + 0.05))
	_check("…even after driving off the glue", _flat_dist(_car.global_position, glue_at), _flat_dist(_car.global_position, glue_at) > glue.radius)

	# Shocker: slows cars within its reach.
	await _place(Vector3(-30.0, 0.8, -12.0), Vector3.FORWARD)
	var near := await _dummy(Vector3(-25.0, 0.8, -12.0))
	var far := await _dummy(Vector3(-17.0, 0.8, -12.0))
	_car.set_held_item(_item(&"shocker"))
	_effects.clear()
	var shock_score0: int = _m.scores[_car.player_id]
	_input.fire = true
	await _ticks(3)
	var shock_time := _item(&"shocker").effect_time
	_check("a shocker hit scores a point for the user", _m.scores[_car.player_id] - shock_score0, _m.scores[_car.player_id] - shock_score0 == 1)
	_check("shocker stalls the car 5 m away for %.0f s, not the one 13 m away" % shock_time,
		"%.2f / %.2f s" % [near.shock_left, far.shock_left], near.shock_left > shock_time - 0.1 and far.shock_left == 0.0)
	var arc_to_near := false
	for e in _effects:
		if e["kind"] == &"shock_arc" and _flat_dist(e["pos"], near.global_position) < 1.0:
			arc_to_near = true
	_check("flash + an electric bolt to the shocked car only", "%d bolt(s)" % _count(&"shock_arc"),
		_count(&"shock") == 1 and _count(&"shock_arc") == 1 and arc_to_near)
	var bolts := _m.find_children("*", "ShockArc", true, false).size()
	await _ticks(int(Effects.SHOCK_ARC_TIME * 60.0) + 5)
	_check("bolts crackle briefly, then vanish", "%d → %d" % [bolts, _m.find_children("*", "ShockArc", true, false).size()],
		bolts > Effects.SHOCK_CRACKLES and _m.find_children("*", "ShockArc", true, false).is_empty())

	# Blast: throws nearby cars away and up, not the user.
	near.teleport_to(Transform3D(Basis.IDENTITY, Vector3(-27.0, 0.8, -12.0)))   # 3 m away
	await _ticks(30)
	_car.set_held_item(_item(&"blast"))
	_input.fire = true
	await _ticks(3)
	_check("blast throws the car 3 m away off and up", near.linear_velocity, near.linear_velocity.length() > 6.0 and near.linear_velocity.y > 2.0)
	_check("the user is not blasted", _car.linear_velocity.length(), _car.linear_velocity.length() < 1.0)
	for d: Car in [near, far]:
		_remove(d)

	_press("debug_give_item_2")
	await get_tree().physics_frame
	_check("debug key 2 gives the water balloon", _car.held_item.id if _car.held_item != null else &"none", _car.held_item != null and _car.held_item.id == &"water_balloon")
	_car.set_held_item(null)

func _oil_handling() -> void:
	_header("Oiled tires: faster spin, sliding on slopes, tracks on slopes")
	var clean := await _turn_test(false)
	var oiled := await _turn_test(true)
	_check("oiled: spins faster in a turn (peak yaw rad/s, clean → oiled)", "%.2f → %.2f" % [clean.x, oiled.x],
		oiled.x > clean.x * 1.3)
	_check("oiled: keeps spinning after the turn (yaw rad/s 1/3 s later)", "%.2f → %.2f" % [clean.y, oiled.y],
		oiled.y > 0.3 and oiled.y > clean.y * 3.0)

	# Shocker stall: full throttle (and boost) from standstill gives nothing for the shock time, then the car
	# pulls away at full strength; a car already moving keeps its speed (no top speed limit).
	var shock_time := _item(&"shocker").effect_time
	await _place(Vector3(28.0, 0.8, 30.0), Vector3.FORWARD)
	_car.apply_shock(shock_time)
	_input.throttle = 1.0
	await _ticks(int(shock_time * 60.0) - 2)
	var stalled_speed := _car.linear_velocity.length()
	await _ticks(30)
	var moving_speed := _car.linear_velocity.length()
	_input.throttle = 0.0
	_check("shocked: no drive for %.0f s, then it pulls away (m/s)" % shock_time,
		"%.2f → %.2f" % [stalled_speed, moving_speed], stalled_speed < 0.1 and moving_speed > 2.0)
	await _place(Vector3(28.0, 0.8, 30.0), Vector3.FORWARD)
	_car.linear_velocity = Vector3.FORWARD * 16.0
	await _ticks(2)
	var hit_speed := _car.forward_speed
	_car.apply_shock(shock_time)
	_input.throttle = 1.0
	await _ticks(int(shock_time * 30.0))
	var half_speed := _car.forward_speed
	await _ticks(int(shock_time * 30.0) - 2)
	var end_speed := _car.forward_speed
	_input.throttle = 0.0
	_check("shocked at speed: runs down linearly to 0 over %.0f s, even on full throttle (m/s)" % shock_time,
		"%.1f → %.1f → %.1f" % [hit_speed, half_speed, end_speed],
		absf(half_speed - hit_speed * 0.5) < 1.5 and end_speed < 1.0)

	# A puddle on ramp A lies on the slope.
	var slope_puddle_at := Vector3(0.0, 1.5, 0.0)
	_m.spawn_puddle(_item(&"oil_slick"), slope_puddle_at)
	var slope_puddle: Puddle = null
	for n in _m.get_node("Projectiles").get_children():
		if n is Puddle and (n as Puddle).global_position.distance_to(slope_puddle_at) < 1.0:
			slope_puddle = n as Puddle
	var tilt := rad_to_deg(slope_puddle._blob_normals[0].angle_to(Vector3.UP)) if slope_puddle != null else 0.0
	var space0 := get_viewport().world_3d.direct_space_state
	var uphill_hit := space0.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0.0, 10.0, -1.0), Vector3(0.0, -1.0, -1.0), Layers.WORLD))
	_check("a puddle on the 14° ramp lies on the slope (tilt °, covers the ramp 1 m uphill)", "%.1f" % tilt,
		slope_puddle != null and absf(tilt - 14.0) < 1.0 and slope_puddle.covers(uphill_hit.position))
	if slope_puddle != null:
		slope_puddle.queue_free()
	await _ticks(2)

	# Parked on ramp A (14°): facing uphill, then across it.
	for facing: Vector3 in [Vector3.FORWARD, Vector3.RIGHT]:
		await _place_on_surface(Vector3(0.0, 0.0, 1.0), facing)
		var start := _car.global_position
		await _ticks(30)
		var clean_slide := _car.global_position.distance_to(start)
		_car.wheel_oil.fill(_car.tuning.wheel_coating_time)
		start = _car.global_position
		await _ticks(60)
		var oiled_slide := _car.global_position.distance_to(start)
		var downhill := _car.global_position.z > start.z
		_check("parked %s the 14° ramp: clean holds, oiled slides downhill (m in 1 s)" % ("up" if facing == Vector3.FORWARD else "across"),
			"%.2f / %.2f" % [clean_slide, oiled_slide], clean_slide < 0.05 and oiled_slide > 0.5 and downhill)

	# Tracks lie on the slope: drive oiled up ramp A.
	await _place_on_surface(Vector3(0.0, 0.0, 5.0), Vector3.FORWARD)
	_car.wheel_oil.fill(_car.tuning.wheel_coating_time)
	_input.throttle = 0.7
	await _ticks(45)
	_input.throttle = 0.0
	await _ticks(5)
	var space := get_viewport().world_3d.direct_space_state
	var worst := 0.0
	var highest := 0.0
	for i in Car.WHEELS:
		var trail := _car.visual.get_node("TireTrail%d" % i) as TireTrail
		for v in trail.vertices():
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(v + Vector3.UP, v + Vector3.DOWN, Layers.WORLD))
			if not hit.is_empty():
				worst = maxf(worst, absf(v.y - (hit.position as Vector3).y - TireTrail.LIFT))
				highest = maxf(highest, v.y)
	_check("tracks follow the ramp surface (worst height error m)", "%.3f, up to y %.1f" % [worst, highest],
		worst < 0.06 and highest > 0.8)
	_car.wheel_oil.fill(0.0)

## A car position (facing −Z) where both left wheel contacts are on the puddle and both right ones are not.
func _half_on_spot(p: Puddle) -> Vector3:
	var c := p.global_position
	for dz: float in [0.0, 0.6, -0.6, 1.2, -1.2]:
		for step in 120:
			var x := c.x + step * 0.05
			var spot := Vector3(x, c.y, c.z + dz)
			if p.covers(spot + Vector3(-0.5, 0.0, -0.7)) and p.covers(spot + Vector3(-0.5, 0.0, 0.7)) \
					and not p.covers(spot + Vector3(0.5, 0.0, -0.7)) and not p.covers(spot + Vector3(0.5, 0.0, 0.7)):
				return spot
	return Vector3.INF

## Full steer at speed on open floor. Returns (peak yaw rate while steering, yaw rate 20 ticks after letting go).
func _turn_test(oiled: bool) -> Vector2:
	await _place(Vector3(28.0, 0.8, 30.0), Vector3.FORWARD)
	_input.throttle = 1.0
	await _ticks(40)
	if oiled:
		_car.wheel_oil.fill(_car.tuning.wheel_coating_time)
	_input.steer = 1.0
	var peak := 0.0
	for i in 40:
		await get_tree().physics_frame
		peak = maxf(peak, absf(_car.angular_velocity.y))
	_input.steer = 0.0
	_input.throttle = 0.0
	await _ticks(20)
	var after := absf(_car.angular_velocity.y)
	_car.wheel_oil.fill(0.0)
	return Vector2(peak, after)

func _puddle(kind: ItemDef.Kind) -> Puddle:
	for n in _m.get_node("Projectiles").get_children():
		if n is Puddle and (n as Puddle).kind == kind:
			return n as Puddle
	return null

func _catch_up_weights() -> void:
	_header("Catch-up roll weights")
	var other := await _dummy(Vector3(-20.0, 0.8, -20.0))
	_m.scores[_car.player_id] = 5
	_m.scores[other.player_id] = 0
	var trio := _m.item_defs.find(_item(&"rocket_trio"))
	_check("leading: rocket_trio weight 0", _m.item_weights(_car), _m.item_weights(_car)[trio] == 0.0)
	_m.scores[_car.player_id] = 0
	_m.scores[other.player_id] = 5
	var w := _m.item_weights(_car)
	var total := 0.0
	var expected_total := 0.0
	for x in w:
		total += x
	for d in _m.item_defs:
		expected_total += d.weight_last
	_check("last: weights are the weight_last values", w[trio] / total, absf(w[trio] / total - _item(&"rocket_trio").weight_last / expected_total) < 0.001)
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
	var barrel := v.to_local(v.muzzle.global_position) - v.item_mount
	var to_aim := v.to_local(_car.last_aim_point) - v.item_mount
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
