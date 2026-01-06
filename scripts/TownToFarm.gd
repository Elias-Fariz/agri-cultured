extends Area2D

@export var target_scene_path: String = "res://tscn/Farm.tscn"

func interact() -> void:
	get_tree().change_scene_to_file(target_scene_path)
