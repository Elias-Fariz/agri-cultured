extends Node
class_name WorldToolRouter

@export var world_node_path: NodePath

@onready var world := get_node_or_null(world_node_path)

func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return

	# Forward tool inputs to whatever world scene we're in,
	# so Farm / Keeper / Beach can each implement their own logic.
	if event.is_action_pressed("tool"):
		if world.has_method("tool_action"):
			world.call("tool_action")
	elif event.is_action_pressed("plant_seed"):
		if world.has_method("plant_seed_action"):
			world.call("plant_seed_action")
	elif event.is_action_pressed("seed_next"):
		if world.has_method("seed_next_action"):
			world.call("seed_next_action")
