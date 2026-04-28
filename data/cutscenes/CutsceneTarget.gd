extends Node
class_name CutsceneTarget

@export var cutscene_id: String = ""

func _ready() -> void:
	add_to_group("cutscene_target")
