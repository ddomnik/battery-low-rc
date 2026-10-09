class_name LivesMode
extends GameMode
## Deathmatch with lives: every car carries its lives as balloons on its back. A scoring hit (strong ram, blast)
## or falling off the map pops one; after a pop the car is safe for a moment. No balloons left = out.
## Popped balloons fly up for a second and burst into confetti of their color. Taking someone's last balloon
## (or hitting them just before they fall off) counts as a kill. Last car with balloons wins.

const INVULNERABLE_TIME := 1.5
const BALLOON_RADIUS := 0.3
const BALLOON_SPACING := 0.45
const BALLOON_TOP := Vector3(0.0, 1.55, 1.25)     # car-local, behind and above the rear
const STRING_ANCHOR := Vector3(0.0, 0.3, 0.95)    # rear bumper
const STRING_RADIUS := 0.012
const BOB_SPEED := 2.2
const BOB_AMOUNT := 0.08
const LOST_COLOR := Color(1.0, 0.5, 0.4)
const POP_COLOR := Color(1.0, 0.9, 0.3)
const FLOAT_HEIGHT := 4.0            # a popped balloon rises this far …
const FLOAT_TIME := 1.0              # … in this time, then bursts into confetti

const HAZARD_PER_BALLOON := 10.0      # fluid damage points per popped balloon

var _lives: Dictionary = {}          # player_id → int
var _kills: Dictionary = {}          # player_id → int
var _safe_until: Dictionary = {}     # player_id → match time
var _balloons: Dictionary = {}       # player_id → Array[Node3D] (one per life, last = next to pop)
var _time: float = 0.0

var _hazard: Dictionary = {}          # player_id → fluid damage collected toward the next pop

func _ready() -> void:
	for car in match_node.cars:
		_lives[car.player_id] = match_node.config.lives
		_build_balloons(car)

func on_round_end() -> void:
	for list: Array in _balloons.values():
		for b: Node3D in list:
			b.queue_free()
	_balloons.clear()

func on_scoring_hit(attacker: Car, victim: Car) -> void:
	_pop(victim, attacker)

## Fluid damage adds up; every HAZARD_PER_BALLOON points pops a balloon (the usual safe time applies), credited to
## whoever pushed the car in.
func on_hazard_damage(car: Car, amount: float, attacker: Car) -> void:
	var total: float = _hazard.get(car.player_id, 0.0) + amount
	if total >= HAZARD_PER_BALLOON:
		total -= HAZARD_PER_BALLOON
		_pop(car, attacker)
	_hazard[car.player_id] = total

func on_fell_off(car: Car) -> bool:
	_pop(car, match_node.last_attacker(car), true)
	return not car.eliminated

func ranking() -> Array[Car]:
	var alive := survivors()
	alive.sort_custom(func(a: Car, b: Car) -> bool:
		var la: int = _lives.get(a.player_id, 0)
		var lb: int = _lives.get(b.player_id, 0)
		if la != lb:
			return la > lb
		var ka: int = _kills.get(a.player_id, 0)
		var kb: int = _kills.get(b.player_id, 0)
		return ka > kb if ka != kb else _by_score(a, b))
	var out := match_node.eliminated_order.duplicate()
	out.reverse()
	alive.append_array(out)
	return alive

func score_text(car: Car) -> String:
	var kill_count: int = _kills.get(car.player_id, 0)
	var lives_text := "out" if match_node.eliminated_order.has(car) else "%d lives" % _lives.get(car.player_id, 0)
	return "%s · %d %s" % [lives_text, kill_count, "kill" if kill_count == 1 else "kills"]

func status_text() -> String:
	return "%d left" % match_node.alive_cars().size()

## Pops one balloon (unless the car is still safe from the last pop). force: falling off always costs one.
func _pop(car: Car, attacker: Car, force: bool = false) -> void:
	if not Net.is_authority() or car.eliminated or match_node.state != Match.State.PLAYING:
		return
	if not force and match_node.time < float(_safe_until.get(car.player_id, -INF)):
		return
	var lives: int = _lives.get(car.player_id, 0) - 1
	_lives[car.player_id] = lives
	_safe_until[car.player_id] = match_node.time + INVULNERABLE_TIME
	var list: Array = _balloons.get(car.player_id, [])
	if not list.is_empty():
		_float_away(list.pop_back(), car.color)
	if car == match_node.local_car:
		match_node.popup("BALLOON LOST!", LOST_COLOR)
	elif attacker == match_node.local_car:
		match_node.popup("POP!", POP_COLOR)
	if lives <= 0:
		if attacker != null and attacker != car:
			_kills[attacker.player_id] = int(_kills.get(attacker.player_id, 0)) + 1
			if attacker == match_node.local_car:
				match_node.popup("KILL!", POP_COLOR)
		match_node.eliminate(car)
	match_node.scores_changed.emit()

## A popped balloon lets go of the car, rises for FLOAT_TIME, and bursts into confetti of its color.
func _float_away(balloon: Node3D, color: Color) -> void:
	balloon.reparent(match_node, true)
	balloon.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved per frame by the tween
	var tw := balloon.create_tween()
	tw.tween_property(balloon, "global_position", balloon.global_position + Vector3.UP * FLOAT_HEIGHT, FLOAT_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(balloon, "rotation:z", 0.4, FLOAT_TIME).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		match_node.play_effect(&"confetti", (balloon.get_child(0) as Node3D).global_position, 0.0, color)
		balloon.queue_free())

func _process(delta: float) -> void:
	_time += delta
	for pid: int in _balloons:
		var list: Array = _balloons[pid]
		for i in list.size():
			var b: Node3D = list[i]
			b.rotation.z = sin(_time * BOB_SPEED + i * 1.3) * BOB_AMOUNT
			b.rotation.x = cos(_time * BOB_SPEED * 0.8 + i) * BOB_AMOUNT

func _build_balloons(car: Car) -> void:
	var count: int = _lives[car.player_id]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = car.color
	mat.roughness = 0.25
	mat.metallic_specular = 0.8
	var string_mat := StandardMaterial3D.new()
	string_mat.albedo_color = Color(0.95, 0.95, 0.95)
	string_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var list: Array[Node3D] = []
	for i in count:
		var top := BALLOON_TOP + Vector3((i - (count - 1) * 0.5) * BALLOON_SPACING, 0.0, 0.0)
		# The balloon pivots around its string anchor so the bobbing sways the whole thing.
		var pivot := Node3D.new()
		pivot.name = "Balloon%d" % i
		pivot.position = STRING_ANCHOR
		car.visual.add_child(pivot)
		var to_top := top - STRING_ANCHOR
		var sphere := SphereMesh.new()
		sphere.radius = BALLOON_RADIUS
		sphere.height = BALLOON_RADIUS * 2.4
		var body := MeshInstance3D.new()
		body.mesh = sphere
		body.material_override = mat
		body.position = to_top
		body.layers = Layers.RENDER_CARS
		pivot.add_child(body)
		var cyl := CylinderMesh.new()
		cyl.top_radius = STRING_RADIUS
		cyl.bottom_radius = STRING_RADIUS
		cyl.height = to_top.length()
		var line := MeshInstance3D.new()
		line.mesh = cyl
		line.material_override = string_mat
		line.position = to_top * 0.5
		line.basis = Basis(Quaternion(Vector3.UP, to_top.normalized()))
		line.layers = Layers.RENDER_CARS
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(line)
		list.append(pivot)
	_balloons[car.player_id] = list
