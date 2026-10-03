class_name CarInputProvider
extends Node
## Base for everything that drives a car: PlayerInput, BotInput and, later, a network input.
## Providers run with process_physics_priority = -10 so the car reads fresh input every tick.

var car: Car = null

func _ready() -> void:
	process_physics_priority = -10

## Called by the car once per physics tick. Edge-triggered actions are consumed here.
func get_car_input(_car: Car) -> CarInput:
	return CarInput.new()
