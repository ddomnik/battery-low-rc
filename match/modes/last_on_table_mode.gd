class_name LastOnTableMode
extends GameMode
## Last on table: the arena has no outer walls; whoever falls off the map is out for good. Last car left wins.
## Damage %: every ram and blast a car takes raises its percentage, and each percent adds 1 % to the knockback it
## receives from then on (100 % = double knockback), so battered cars fly off the table more easily.

const PERCENT_PER_DAMAGE := 1.0      # % added per unit of bump strength / blast knockback (m/s)

var _percent: Dictionary = {}        # player_id → float

func arena_has_walls() -> bool:
	return false

func on_damage(car: Car, amount: float) -> void:
	if not Net.is_authority() or match_node.state != Match.State.PLAYING or car.eliminated:
		return
	var p: float = _percent.get(car.player_id, 0.0) + amount * PERCENT_PER_DAMAGE
	_percent[car.player_id] = p
	car.knockback_multiplier = 1.0 + p / 100.0
	match_node.scores_changed.emit()

func on_fell_off(car: Car) -> bool:
	match_node.eliminate(car)
	return false

func score_text(car: Car) -> String:
	if match_node.eliminated_order.has(car):
		return "OUT"
	return "%d%%" % roundi(_percent.get(car.player_id, 0.0))

func status_text() -> String:
	return "%d left" % match_node.alive_cars().size()
