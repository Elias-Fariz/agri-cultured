# res://ui/SeasonChangeAnnouncer.gd
extends Node

@export var toast_duration: float = 5.0

func _ready() -> void:
	# Make sure we connect with the correct signature:
	# season_changed(new_season: int)
	var err := CalendarSystem.season_changed.connect(_on_season_changed)
	if err != OK:
		push_warning("SeasonChangeAnnouncer: failed to connect season_changed (err=%s)" % str(err))

func _on_season_changed(new_season: int) -> void:
	# Build the message based on the new season integer
	var msg := ""
	var kind := "info"

	if new_season == CalendarSystem.Season.SUNWAKE:
		msg = "🌿 Sunwake has arrived. Longer days and brighter skies."
		kind = "info"
	elif new_season == CalendarSystem.Season.DUSKHAVEN:
		msg = "🍂 Duskhaven is here. Cozy winds and fresh changes."
		kind = "info"
	else:
		msg = "The season has changed."
		kind = "info"

	# Queue at day start (matches your working pattern)
	if GameState != null and GameState.has_method("queue_day_start_toast"):
		GameState.queue_day_start_toast(msg, kind, toast_duration)
	else:
		# Fallback: still show immediately if queue system isn't available for some reason
		QuestEvents.toast_requested.emit(msg, kind, toast_duration)
