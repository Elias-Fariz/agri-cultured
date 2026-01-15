extends Node2D

func interact() -> void:
	var ui := get_tree().get_first_node_in_group("quest_board_ui")
	if ui:
		print("QuestBoardUI FOUND:", ui.name, " path:", ui.get_path())
		if ui.has_method("debug_print_available_quests"):
			ui.debug_print_available_quests()
		ui.show_overlay()

func can_player_interact(player: Node) -> bool:
	return true

func get_interact_prompt(player: Node) -> String:
	return "E: Read Board"

func get_interact_priority() -> int:
	return 5
