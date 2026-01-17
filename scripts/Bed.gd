extends Area2D

func interact() -> void:
	# Sleep: new day, reset time, restore energy
	TimeManager.start_new_day()
	GameState.reset_energy()
	print("Slept. Day:", TimeManager.day, " Time:", TimeManager.get_time_string(), " Energy:", GameState.energy)
	
	var summary_ui := get_tree().get_first_node_in_group("end_of_day_ui")
	if summary_ui and summary_ui.has_method("show_summary"):
		summary_ui.show_summary()
