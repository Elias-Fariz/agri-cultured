extends Node

@export var required_travel_id: String = "animal_keeper"
@export var fallback_scene_path: String = "res://tscn/Town.tscn"

# Standardized tag name (matches your older convention)
@export var fallback_spawn_tag: String = "from_keeper"

func _ready() -> void:
	# If the keeper area isn't unlocked, bounce to fallback.
	if not GameState.is_travel_unlocked(required_travel_id):
		GameState.pending_spawn_tag = fallback_spawn_tag
		get_tree().change_scene_to_file(fallback_scene_path)
