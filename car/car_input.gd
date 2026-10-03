class_name CarInput
extends RefCounted
## One tick of intent. Produced by PlayerInput (local), BotInput (AI) or, later, received over the network.
## World space only, so a server never needs the client's camera.

## CLASSIC: car-relative throttle / steer (players, both camera modes).
## DIRECTIONAL: drive toward a world direction with auto U-turn and stuck assist (bots).
enum DriveMode { DIRECTIONAL, CLASSIC }

var drive_mode: DriveMode = DriveMode.CLASSIC
var move_world: Vector3 = Vector3.ZERO   # DIRECTIONAL: desired direction on the XZ plane, length 0..1
var throttle: float = 0.0                # CLASSIC: -1..1 (+ = forward)
var steer: float = 0.0                   # CLASSIC: -1..1 (+ = left / counter-clockwise)
var handbrake: bool = false
var boost: bool = false
var fire: bool = false                   # one-tick pulse; producer latches until consumed
var reset: bool = false                  # one-tick pulse
var aim_point: Vector3 = Vector3.ZERO    # world position under the cursor (or bot target)

static func neutral(keep_aim: Vector3 = Vector3.ZERO) -> CarInput:
	var i := CarInput.new()
	i.aim_point = keep_aim
	return i

func to_dict() -> Dictionary:
	return {"m": drive_mode, "mw": move_world, "t": throttle, "s": steer,
		"hb": handbrake, "b": boost, "f": fire, "r": reset, "a": aim_point}

static func from_dict(d: Dictionary) -> CarInput:
	var i := CarInput.new()
	i.drive_mode = d.get("m", DriveMode.CLASSIC)
	i.move_world = d.get("mw", Vector3.ZERO)
	i.throttle = d.get("t", 0.0)
	i.steer = d.get("s", 0.0)
	i.handbrake = d.get("hb", false)
	i.boost = d.get("b", false)
	i.fire = d.get("f", false)
	i.reset = d.get("r", false)
	i.aim_point = d.get("a", Vector3.ZERO)
	return i
