class_name GameMode
extends Node
## Rules of one game mode. Match owns one (child node "Mode") and asks it about scoring, eliminations,
## respawns, ranking, HUD texts and when the round is over. Everything that changes state runs on the authority.

enum Kind { TIMED, LAST_ON_TABLE, LIVES, STICKY_BOMB }

const LABELS: Array[String] = ["Time deathmatch", "Last on table", "Deathmatch (lives)", "Sticky bomb"]
const CLI_NAMES: Array[String] = ["timed", "table", "lives", "bomb"]

var match_node: Match = null

static func create(kind: Kind) -> GameMode:
	match kind:
		Kind.LAST_ON_TABLE:
			return LastOnTableMode.new()
		Kind.LIVES:
			return LivesMode.new()
		Kind.STICKY_BOMB:
			return StickyBombMode.new()
		_:
			return TimedMode.new()

## True: the round timer runs and ends the round. False: the mode ends it (last car standing).
func uses_round_timer() -> bool:
	return false

## False removes the arena's outer walls (cars can be pushed off the map).
func arena_has_walls() -> bool:
	return true

## Called once when the countdown ends.
func on_round_start() -> void:
	pass

## Called when the round ends (before the podium): remove mode visuals.
func on_round_end() -> void:
	pass

## A scoring hit (strong ram or blast) — after Match has awarded the point.
func on_scoring_hit(_attacker: Car, _victim: Car) -> void:
	pass

## The car took damage: a ram (amount = bump strength) or a blast (amount = horizontal knockback at its distance).
func on_damage(_car: Car, _amount: float) -> void:
	pass

## The car fell off the map. Return true to respawn it, false if the mode eliminated it.
func on_fell_off(_car: Car) -> bool:
	return true

## Checked every tick while playing.
func is_round_over() -> bool:
	return match_node.alive_cars().size() <= (1 if match_node.cars.size() > 1 else 0)

## Best first. Default: cars still in by score, then eliminated cars (out last = better). Uses the elimination
## record (not Car.eliminated), so it stays right during the ceremony, when every car is back.
func ranking() -> Array[Car]:
	var alive := survivors()
	alive.sort_custom(_by_score)
	var out := match_node.eliminated_order.duplicate()
	out.reverse()
	alive.append_array(out)
	return alive

## Value shown next to a car on the scoreboard and results.
func score_text(car: Car) -> String:
	return "OUT" if match_node.eliminated_order.has(car) else "IN"

## Cars that were never eliminated this round.
func survivors() -> Array[Car]:
	var out: Array[Car] = []
	for car in match_node.cars:
		if not match_node.eliminated_order.has(car):
			out.append(car)
	return out

## Text for the top of the HUD when the mode has no round timer ("" = nothing).
func status_text() -> String:
	return ""

func _by_score(a: Car, b: Car) -> bool:
	var sa: int = match_node.scores.get(a.player_id, 0)
	var sb: int = match_node.scores.get(b.player_id, 0)
	return sa > sb if sa != sb else a.player_id < b.player_id
