extends Node

@export var required_travel_id: String = "animal_keeper"
@export var fallback_scene_path: String = "res://Scenes/Town.tscn"
@export var fallback_spawn_tag: String = "from_animal_keeper"

func _ready() -> void:
	if not GameState.is_travel_unlocked(required_travel_id):
		GameState.pending_spawn_tag = fallback_spawn_tag
		get_tree().change_scene_to_file(fallback_scene_path)
