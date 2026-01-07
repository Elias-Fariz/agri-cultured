extends Node

signal time_changed(minutes: int)
signal day_changed(day: int)

@export var minutes_per_day: int = 24 * 60
@export var start_minutes: int = 6 * 60  # 6:00 AM
@export var minutes_per_real_second: float = 10.0  # tune later

@export var morning_start_minutes: int = 6 * 60

var running: bool = true

var day: int = 1
var minutes_float: float = start_minutes
var minutes: int = start_minutes

func _process(delta: float) -> void:
	if not running:
		return
	advance_time(delta * minutes_per_real_second)

func advance_time(delta_minutes: float) -> void:
	minutes_float += delta_minutes

	var new_minutes := int(minutes_float)

	# Day rollover
	if new_minutes >= minutes_per_day:
		minutes_float -= minutes_per_day
		new_minutes = int(minutes_float)
		day += 1
		emit_signal("day_changed", day)

	# Only emit when visible time changes
	if new_minutes != minutes:
		minutes = new_minutes
		emit_signal("time_changed", minutes)
		
func start_new_day() -> void:
	day += 1
	minutes_float = morning_start_minutes
	minutes = int(minutes_float)
	emit_signal("day_changed", day)
	emit_signal("time_changed", minutes)

	# Always pay out shipping, regardless of scene
	GameState.shipping_payout_and_clear()

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
