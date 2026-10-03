class_name StickyBombMode
extends GameMode
## Sticky bomb: a random car carries a bomb with a countdown and passes it on by touching another car.
## At zero it explodes: the holder is out and a fresh bomb goes to a random survivor. Last car left wins.

const PASS_COOLDOWN := 1.0           # s after a hand-over before the bomb can move again (no instant pass-back)
const BLAST_RADIUS := 5.0
const BLAST_KNOCKBACK := 12.0
const BLAST_UP := 9.0
const BOMB_RADIUS := 0.5
const BOMB_HEIGHT := 1.35            # car-local, on the roof
const FUSE_BLINK_FAST_BELOW := 3.0   # s left when the light starts blinking fast
const LABEL_FONT_SIZE := 48
const LABEL_PIXEL_SIZE := 0.0009
const LABEL_HEIGHT := 2.6
const GOT_IT_COLOR := Color(1.0, 0.35, 0.25)
const PASSED_COLOR := Color(0.5, 1.0, 0.5)

var holder: Car = null
var time_left: float = 0.0

var _cooldown: float = 0.0
var _bomb: Node3D = null
var _light_mat: StandardMaterial3D = null
var _label: Label3D = null
var _blink: float = 0.0

func _ready() -> void:
	for car in match_node.cars:
		car.touched.connect(_on_touched)
	_build_bomb()

func on_round_start() -> void:
	_give_to_random()

func on_round_end() -> void:
	if _bomb != null:
		_bomb.queue_free()
		_bomb = null

func score_text(car: Car) -> String:
	if match_node.eliminated_order.has(car):
		return "OUT"
	return "BOMB" if car == holder else "IN"

func status_text() -> String:
	if holder == null:
		return ""
	return "BOMB: %s  %d" % [holder.display_name, ceili(time_left)]

func _physics_process(delta: float) -> void:
	if not Net.is_authority() or match_node.state != Match.State.PLAYING or holder == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	time_left -= delta
	if time_left <= 0.0:
		_explode()

func _process(delta: float) -> void:
	if _bomb == null or holder == null:
		return
	_label.text = str(ceili(maxf(time_left, 0.0)))
	_blink += delta * (10.0 if time_left < FUSE_BLINK_FAST_BELOW else 3.0)
	_light_mat.emission_energy_multiplier = 3.0 if fmod(_blink, 1.0) < 0.5 else 0.2

## Touching passes the bomb (either car may report the contact).
func _on_touched(car: Car, other: Car) -> void:
	if not Net.is_authority() or match_node.state != Match.State.PLAYING or _cooldown > 0.0:
		return
	if car == holder and not other.eliminated:
		_hand_over(other)
	elif other == holder and not car.eliminated:
		_hand_over(car)

func _hand_over(to: Car) -> void:
	var from := holder
	_attach(to)
	_cooldown = PASS_COOLDOWN
	if to == match_node.local_car:
		match_node.popup("YOU HAVE THE BOMB!", GOT_IT_COLOR)
	elif from == match_node.local_car:
		match_node.popup("PASSED!", PASSED_COLOR)
	match_node.scores_changed.emit()

func _explode() -> void:
	var victim := holder
	holder = null
	match_node.explode(victim.global_position, BLAST_RADIUS, BLAST_KNOCKBACK, BLAST_UP, null)
	match_node.eliminate(victim)
	if match_node.alive_cars().size() >= 2:
		_give_to_random()
	else:
		_bomb.visible = false
	match_node.scores_changed.emit()

func _give_to_random() -> void:
	var alive := match_node.alive_cars()
	if alive.is_empty():
		return
	time_left = match_node.config.bomb_time
	_attach(alive[match_node.rng.randi() % alive.size()])
	if holder == match_node.local_car:
		match_node.popup("YOU HAVE THE BOMB!", GOT_IT_COLOR)

func _attach(car: Car) -> void:
	holder = car
	_bomb.reparent(car.visual, false)
	_bomb.position = Vector3(0.0, BOMB_HEIGHT, 0.0)
	_bomb.visible = true

func _build_bomb() -> void:
	_bomb = Node3D.new()
	_bomb.name = "StickyBomb"
	_bomb.visible = false
	add_child(_bomb)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.08, 0.08, 0.1)
	body_mat.roughness = 0.35
	var sphere := SphereMesh.new()
	sphere.radius = BOMB_RADIUS
	sphere.height = BOMB_RADIUS * 2.0
	var body := MeshInstance3D.new()
	body.mesh = sphere
	body.material_override = body_mat
	body.layers = Layers.RENDER_CARS
	_bomb.add_child(body)
	_light_mat = StandardMaterial3D.new()
	_light_mat.albedo_color = Color(1.0, 0.15, 0.1)
	_light_mat.emission_enabled = true
	_light_mat.emission = Color(1.0, 0.15, 0.1)
	var light_mesh := SphereMesh.new()
	light_mesh.radius = 0.09
	light_mesh.height = 0.18
	var light := MeshInstance3D.new()
	light.mesh = light_mesh
	light.material_override = _light_mat
	light.position = Vector3(0.0, BOMB_RADIUS, 0.0)
	light.layers = Layers.RENDER_CARS
	_bomb.add_child(light)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.no_depth_test = true
	_label.font_size = LABEL_FONT_SIZE
	_label.pixel_size = LABEL_PIXEL_SIZE
	_label.outline_size = 12
	_label.modulate = Color(1.0, 0.3, 0.2)
	_label.position = Vector3(0.0, LABEL_HEIGHT - BOMB_HEIGHT, 0.0)
	_bomb.add_child(_label)
