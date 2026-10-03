extends CarInputProvider
## Scripted input for the headless probes: set the fields, the car reads them every tick.
## fire / reset are one-tick pulses, consumed by get_car_input like PlayerInput's latches.

var mode: CarInput.DriveMode = CarInput.DriveMode.CLASSIC
var move: Vector3 = Vector3.ZERO
var throttle: float = 0.0
var steer: float = 0.0
var handbrake: bool = false
var boost: bool = false
var aim_point: Vector3 = Vector3.ZERO
var fire: bool = false
var reset: bool = false

func get_car_input(_car: Car) -> CarInput:
	var i := CarInput.new()
	i.drive_mode = mode
	i.move_world = move
	i.throttle = throttle
	i.steer = steer
	i.handbrake = handbrake
	i.boost = boost
	i.aim_point = aim_point
	i.fire = fire
	i.reset = reset
	fire = false
	reset = false
	return i
