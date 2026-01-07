extends Node2D

func interact() -> void:
	var ui := get_tree().get_first_node_in_group("quest_board_ui")
	if ui:
		ui.show_overlay()
