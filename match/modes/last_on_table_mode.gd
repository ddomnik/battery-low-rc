class_name LastOnTableMode
extends GameMode
## Last on table: the arena has no outer walls; whoever falls off the map is out for good. Last car left wins.

func arena_has_walls() -> bool:
	return false

func on_fell_off(car: Car) -> bool:
	match_node.eliminate(car)
	return false

func status_text() -> String:
	return "%d left" % match_node.alive_cars().size()
