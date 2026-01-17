extends Area2D
class_name SceneTravelArea

@export_file("*.tscn") var target_scene_path: String = ""
@export var spawn_tag: String = ""  # e.g. "from_farm", "from_town"

@export var requires_travel_unlock: bool = false
@export var travel_unlock_id: String = ""   # ex: "animal_keeper"
@export var locked_prompt_text: String = "Locked"


func interact() -> void:
	if target_scene_path == "":
		push_warning("SceneTravelArea: target_scene_path is empty on " + name)
		return

	if requires_travel_unlock and travel_unlock_id != "":
		if not GameState.is_travel_unlocked(travel_unlock_id):
			# Optional: you can play a little “locked” sound or show a brief message later
			return
	
	# Store which entrance we want to use in the next scene
	if spawn_tag != "":
		var gs := get_node_or_null("/root/GameState")
		if gs != null:
			gs.pending_spawn_tag = spawn_tag

	get_tree().change_scene_to_file(target_scene_path)
	print("Traveling to:", target_scene_path, " spawn tag:", spawn_tag)

func can_player_interact(player: Node) -> bool:
	if requires_travel_unlock and travel_unlock_id != "":
		return GameState.is_travel_unlocked(travel_unlock_id)
	return true

func get_interact_prompt(player: Node) -> String:
	if requires_travel_unlock and travel_unlock_id != "":
		if not GameState.is_travel_unlocked(travel_unlock_id):
			return locked_prompt_text
	return "E: Travel"

func get_interact_priority() -> int:
	return 5
