class_name Podium
extends Node3D
## End-of-round ceremony: a three-step podium (1st in the middle, 2nd left, 3rd right as seen from the camera).
## The top three stand on it facing the camera, the winner keeps hopping; everybody else lies on their roof in a
## row in front of it. Created by Match when the round ends (authority moves the cars).

const STEP_SIZE := Vector2(2.8, 3.2)        # width (x), depth (z)
const STEP_HEIGHTS: Array[float] = [1.6, 1.1, 0.7]
const STEP_X: Array[float] = [0.0, -3.0, 3.0]   # camera looks north, so −x is screen-left
const STEP_COLORS: Array[Color] = [Color(1.0, 0.8, 0.2), Color(0.78, 0.8, 0.85), Color(0.8, 0.5, 0.25)]
const NUMBER_FONT_SIZE := 256
const NUMBER_PIXEL_SIZE := 0.004
const CAR_LIFT := 0.7                       # car origin above the step top
const ROW_OFFSET := 5.0                     # flipped losers lie this far in front (toward the camera)
const ROW_SPACING := 2.4
const ROOF_LIFT := 1.0                      # upside-down cars are dropped from slightly above the floor
const HOP_SPEED := 6.0                      # m/s up → ~0.9 m hop (gravity × 2)
const HOP_INTERVAL := 1.0
const HOP_SPIN := 1.2                       # rad/s yaw twist per hop, alternating direction
const WOBBLE_ANGLE := 0.14                  # rad; 2nd and 3rd place rock from side to side (visual only)
const WOBBLE_SPEED := 3.0
const CONFETTI_AMOUNT := 160                # per cannon
const CONFETTI_CANNONS: Array[float] = [-4.0, 0.0, 4.0]   # x of the cannons behind the podium
const CONFETTI_BEHIND := -3.0               # −z = behind the podium as seen from the camera
const CONFETTI_SPEED := Vector2(9.0, 14.0)  # launch speed range (m/s), straight up with some spread

var winner: Car = null
var _runners_up: Array[Car] = []      # 2nd and 3rd: their visuals wobble
var _time: float = 0.0
var _hop_left: float = 0.0
var _hop_dir: float = 1.0

func _ready() -> void:
	for i in STEP_HEIGHTS.size():
		var h := STEP_HEIGHTS[i]
		ArenaBuilder.box(self, Vector3(STEP_X[i], h * 0.5, 0.0), Vector3(STEP_SIZE.x, h, STEP_SIZE.y), STEP_COLORS[i])
		var number := Label3D.new()
		number.text = str(i + 1)
		number.font_size = NUMBER_FONT_SIZE
		number.pixel_size = NUMBER_PIXEL_SIZE
		number.outline_size = 24
		number.position = Vector3(STEP_X[i], h * 0.5, STEP_SIZE.y * 0.5 + 0.02)   # on the front face
		add_child(number)
	# Confetti cannons behind the podium shoot flakes up into the air; they flutter down over the podium.
	for x in CONFETTI_CANNONS:
		var confetti := Effects.confetti_particles(Color.WHITE)
		confetti.name = "ConfettiCannon"
		confetti.amount = CONFETTI_AMOUNT
		confetti.lifetime = 4.5
		confetti.direction = Vector3(0.0, 1.0, 0.25)   # up and slightly toward the camera
		confetti.spread = 18.0
		confetti.initial_velocity_min = CONFETTI_SPEED.x
		confetti.initial_velocity_max = CONFETTI_SPEED.y
		confetti.gravity = Vector3(0.0, -6.0, 0.0)
		confetti.damping_min = 2.0
		confetti.damping_max = 3.5
		confetti.position = Vector3(x, 0.3, CONFETTI_BEHIND)
		add_child(confetti)
		confetti.emitting = true

## ranking is best first. Places the top three on the steps and lays everyone else on their roof in front.
func place_cars(ranking: Array[Car]) -> void:
	var facing_camera := Basis.looking_at(Vector3.BACK, Vector3.UP)   # +Z, toward the camera
	var upside_down := facing_camera * Basis(Vector3.FORWARD, PI)
	var rest := ranking.size() - mini(ranking.size(), STEP_HEIGHTS.size())
	for i in ranking.size():
		var car := ranking[i]
		var xf: Transform3D
		if i < STEP_HEIGHTS.size():
			xf = Transform3D(facing_camera, to_global(Vector3(STEP_X[i], STEP_HEIGHTS[i] + CAR_LIFT, 0.0)))
		else:
			var slot := i - STEP_HEIGHTS.size()
			var x := (slot - (rest - 1) * 0.5) * ROW_SPACING
			xf = Transform3D(upside_down, to_global(Vector3(x, ROOF_LIFT, ROW_OFFSET)))
		car.teleport_to(xf)
	for car in ranking:
		car.visual.mute_engine = true   # quiet ceremony
	winner = ranking[0] if not ranking.is_empty() else null
	_runners_up.assign(ranking.slice(1, 3))
	_hop_left = HOP_INTERVAL

func _process(delta: float) -> void:
	_time += delta
	for i in _runners_up.size():
		var car := _runners_up[i]
		if is_instance_valid(car):
			car.visual.body_roll = sin(_time * WOBBLE_SPEED + i * PI) * WOBBLE_ANGLE

## The winner hops whenever it is standing on all four wheels.
func _physics_process(delta: float) -> void:
	if winner == null or not is_instance_valid(winner) or not Net.is_authority():
		return
	_hop_left -= delta
	if _hop_left <= 0.0 and winner.grounded_count == Car.WHEELS:
		_hop_left = HOP_INTERVAL
		_hop_dir = -_hop_dir
		winner.apply_knockback(Vector3.UP * HOP_SPEED, HOP_SPIN * _hop_dir)
