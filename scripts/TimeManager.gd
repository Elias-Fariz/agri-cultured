extends Node

signal time_changed(minutes: int)
signal day_changed(day: int)

@export var minutes_per_day: int = 24 * 60
@export var start_minutes: int = 6 * 60  # 6:00 AM
@export var minutes_per_real_second: float = 60.0  # tune later, 10 originally

@export var morning_start_minutes: int = 6 * 60

var running: bool = true

var day: int = 1
var minutes_float: float = start_minutes
var minutes: int = start_minutes

enum TimeBlock { MORNING, DAY, EVENING, NIGHT }

@export var morning_start_hour: int = 6
@export var day_start_hour: int = 10
@export var evening_start_hour: int = 18
@export var night_start_hour: int = 22

@export var passout_hour: int = 2                # 2 AM
@export var enable_passout: bool = true

var _did_passout_today: bool = false

func _ready() -> void:
	# Bootstrap: let listeners (HUD, quests, etc.) know the initial day.
	emit_signal("day_changed", day)
	emit_signal("time_changed", minutes)

func _process(delta: float) -> void:
	if not running:
		return
	advance_time(delta * minutes_per_real_second)

func advance_time(delta_minutes: float) -> void:
	minutes_float += delta_minutes
	var new_minutes := int(minutes_float)

	# Pass out at 2 AM (internally: 24:00 -> 26:00 window)
	if enable_passout and not _did_passout_today and new_minutes >= _passout_cutoff_minutes():
		_did_passout_today = true
		_trigger_passout()
		return

	# Only emit when visible time changes (VISIBLE time wraps at 24h)
	var display_minutes := new_minutes % minutes_per_day
	if display_minutes != minutes:
		minutes = display_minutes
		emit_signal("time_changed", minutes)
		
func start_new_day() -> void:
	day += 1
	minutes_float = morning_start_minutes
	minutes = int(minutes_float)
	
	WeatherChange.roll_new_day_weather()
	print("Weather today:", WeatherChange.get_weather_name())
	
	emit_signal("day_changed", day)
	emit_signal("time_changed", minutes)

	# Always pay out shipping, regardless of scene
	GameState.shipping_payout_and_clear()
	_did_passout_today = false

func get_time_string() -> String:
	var h := minutes / 60
	var m := minutes % 60
	return "%02d:%02d" % [h, m]

func pause_time() -> void:
	running = false

func resume_time() -> void:
	running = true

func set_paused(paused: bool) -> void:
	running = not paused

func get_time_block(minutes: int) -> int:
	var hour: int = int(minutes / 60)

	if hour >= morning_start_hour and hour < day_start_hour:
		return TimeBlock.MORNING
	if hour >= day_start_hour and hour < evening_start_hour:
		return TimeBlock.DAY
	if hour >= evening_start_hour and hour < night_start_hour:
		return TimeBlock.EVENING
	return TimeBlock.NIGHT

func get_time_block_key(minutes: int) -> String:
	match get_time_block(minutes):
		TimeBlock.MORNING: return "morning"
		TimeBlock.DAY: return "day"
		TimeBlock.EVENING: return "evening"
		_: return "night"

func _passout_cutoff_minutes() -> int:
	return (24 * 60) + (passout_hour * 60)  # e.g. 1440 + 120 = 1560

func _trigger_passout() -> void:
	# Run the passout sequence as a coroutine
	_passout_sequence()

func _passout_sequence() -> void:
	# Lock everything so the player can't move during the "oops" moment
	GameState.lock_gameplay()
	pause_time()

	# Immediate toast at 2:00 AM
	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit("You’re getting really sleepy…", "warning", 1.5)

	# Let the player actually see it
	await get_tree().create_timer(1.2).timeout

	# Now do the actual rollover
	start_new_day()
	GameState.apply_passout_penalty()

	# Queue the morning reminder (you already have this working)
	GameState.queue_day_start_toast("You passed out last night… Energy reduced today. Try sleeping earlier.", "warning", 3.5)

	# Warp home (your existing function)
	GameState.warp_to_farm_after_passout()

	# Show summary (you said your method is show_summary, and group is end_of_day_ui)
	GameState.request_end_of_day_summary()
	
	GameState.unlock_gameplay()

	# Unlock + resume time AFTER the summary closes (we'll do that in Part B)
	# For now, keep it locked; the summary is modal anyway.


func _flush_day_start_toasts_deferred() -> void:
	# Wait 1–2 frames so HUD/toast UI is in-tree after scene changes
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.flush_day_start_toasts()
