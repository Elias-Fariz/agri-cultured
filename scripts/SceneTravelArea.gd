extends Area2D
class_name SceneTravelArea

@export_file("*.tscn") var target_scene_path: String = ""
@export var spawn_tag: String = ""  # e.g. "from_farm", "from_town"

func interact() -> void:
	if target_scene_path == "":
		push_warning("SceneTravelArea: target_scene_path is empty on " + name)
		return

	# Store which entrance we want to use in the next scene
	if spawn_tag != "":
		var gs := get_node_or_null("/root/GameState")
		if gs != null:
			gs.pending_spawn_tag = spawn_tag

	get_tree().change_scene_to_file(target_scene_path)
	print("Traveling to:", target_scene_path, " spawn tag:", spawn_tag)
