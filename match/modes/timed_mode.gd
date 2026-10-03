class_name TimedMode
extends GameMode
## Time deathmatch: score points (hits +1, knockouts +10) until the round timer runs out. Everyone respawns.

func uses_round_timer() -> bool:
	return true

func is_round_over() -> bool:
	return match_node.time_left <= 0.0

func ranking() -> Array[Car]:
	var ranked: Array[Car] = match_node.cars.duplicate()
	ranked.sort_custom(_by_score)
	return ranked

func score_text(car: Car) -> String:
	return str(match_node.scores.get(car.player_id, 0))
