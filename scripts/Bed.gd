extends Area2D

@export var confirm_title: String = "Sleep"
@export_multiline var confirm_message: String = "Sleep until morning?"
@export var yes_text: String = "Sleep"
@export var no_text: String = "Stay Awake"

@export var fade_out_time: float = 0.35
@export var fade_into_summary_time: float = 0.20

var _sleeping: bool = false


func interact() -> void:
	if _sleeping:
		return

	_sleeping = true

	var confirmed := await _ask_sleep_confirmation()
	if not confirmed:
		_sleeping = false
		return

	await _sleep_sequence()

	_sleeping = false


func _ask_sleep_confirmation() -> bool:
	var confirm_ui := get_tree().get_first_node_in_group("confirm_ui")

	if confirm_ui != null and confirm_ui.has_method("ask"):
		return await confirm_ui.ask(
			confirm_title,
			confirm_message,
			yes_text,
			no_text
		)

	# If the confirm overlay is missing, fail safely by not sleeping.
	push_warning("Bed: confirm_ui not found. Sleep cancelled.")
	return false


func _sleep_sequence() -> void:
	if GameState != null and GameState.has_method("lock_gameplay"):
		GameState.lock_gameplay()

	if TimeManager != null:
		TimeManager.pause_time()

	if FadeOverlay != null:
		await FadeOverlay.fade_out(fade_out_time)

	# Process the new day while the screen is black.
	# This creates yesterday_summary, advances crops, pays shipping, etc.
	TimeManager.start_new_day()
	GameState.reset_energy()

	var summary_ui := get_tree().get_first_node_in_group("end_of_day_ui")
	if summary_ui != null and summary_ui.has_method("show_summary"):
		summary_ui.show_summary()

		# Reveal the summary screen, not gameplay.
		if FadeOverlay != null:
			await FadeOverlay.fade_in(fade_into_summary_time)
	else:
		# Fallback if summary is missing.
		if FadeOverlay != null:
			await FadeOverlay.fade_in(0.25)

		if TimeManager != null:
			TimeManager.resume_time()

		if GameState != null and GameState.has_method("unlock_gameplay"):
			GameState.unlock_gameplay()
