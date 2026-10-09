class_name Main
extends Node
## Persistent root scene, never replaced. WorldRoot holds the active Match, UIRoot the main menu.

const MAIN_MENU_SCENE: PackedScene = preload("res://ui/main_menu.tscn")
const MATCH_SCENE: PackedScene = preload("res://match/match.tscn")

var world_root: Node3D
var ui_root: CanvasLayer

func _ready() -> void:
	world_root = Node3D.new()
	world_root.name = "WorldRoot"
	add_child(world_root)
	ui_root = CanvasLayer.new()
	ui_root.name = "UIRoot"
	add_child(ui_root)
	Game.register_main(self)
	if not Game.start_pending_match():
		show_menu()

func show_match(config: MatchConfig) -> void:
	_clear()
	var m := MATCH_SCENE.instantiate() as Match
	world_root.add_child(m)
	m.setup(config)

func show_menu() -> void:
	_clear()
	ui_root.add_child(MAIN_MENU_SCENE.instantiate())

func _clear() -> void:
	for parent: Node in [world_root, ui_root]:
		for child: Node in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
