extends Area2D

func interact() -> void:
	# Sleep: new day, reset time, restore energy
	TimeManager.start_new_day()
	GameState.reset_energy()
	print("Slept. Day:", TimeManager.day, " Time:", TimeManager.get_time_string(), " Energy:", GameState.energy)
