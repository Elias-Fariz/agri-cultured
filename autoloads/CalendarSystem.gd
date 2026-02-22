# res://autoloads/CalendarSystem.gd
extends Node

signal calendar_changed
signal season_changed(new_season: int)

# 28-day seasons, 7-day weeks (your preference)
@export var days_per_week: int = 7
@export var days_per_season: int = 28

# Optional: start-of-game baseline
# Day 1 is the first day of Sunwake by default.
@export var start_season: int = 0  # 0=Sunwake, 1=Duskhaven

enum Season { SUNWAKE, DUSKHAVEN }

const SEASON_NAMES := {
	Season.SUNWAKE: "Sunwake",
	Season.DUSKHAVEN: "Duskhaven",
}

const DAY_NAMES := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

var _current_season: int = Season.SUNWAKE

func _ready() -> void:
	_current_season = start_season
	# Hook into TimeManager
	if TimeManager != null and TimeManager.has_signal("day_changed"):
		TimeManager.day_changed.connect(_on_day_changed)

	# Bootstrap
	_recompute_and_emit(true)

func _on_day_changed(_day: int) -> void:
	_recompute_and_emit(false)

func _recompute_and_emit(is_bootstrap: bool) -> void:
	var old_season := _current_season
	_current_season = get_season()

	if _current_season != old_season and not is_bootstrap:
		season_changed.emit(_current_season)

	calendar_changed.emit()

# -----------------------------------------------------------------------------
# Core calendar math (based purely on TimeManager.day)
# -----------------------------------------------------------------------------

func get_total_day_index() -> int:
	# Convert TimeManager.day (1-based) -> 0-based index
	if TimeManager == null:
		return 0
	return max(0, int(TimeManager.day) - 1)

func get_season() -> int:
	# Two-season loop: 28 days each => 56-day cycle
	var day_index := get_total_day_index()
	var cycle_len := days_per_season * 2
	var in_cycle := day_index % cycle_len
	return Season.SUNWAKE if in_cycle < days_per_season else Season.DUSKHAVEN

func get_season_name() -> String:
	return String(SEASON_NAMES.get(get_season(), "Unknown"))

func get_day_in_season() -> int:
	# 1..28
	return get_season_day_index() + 1

func get_season_day_index() -> int:
	# 0..27
	var day_index := get_total_day_index()
	var cycle_len := days_per_season * 2
	var in_cycle := day_index % cycle_len
	if in_cycle >= days_per_season:
		in_cycle -= days_per_season
	return in_cycle

func get_week_in_season() -> int:
	# 1..4 for a 28-day season with 7-day weeks
	return int(get_season_day_index() / max(1, days_per_week)) + 1

func get_day_of_week_index() -> int:
	# 0..6
	return get_total_day_index() % max(1, days_per_week)

func get_day_of_week_name() -> String:
	var idx := get_day_of_week_index()
	if idx >= 0 and idx < DAY_NAMES.size():
		return DAY_NAMES[idx]
	return "Day"

func get_calendar_string_short() -> String:
	# Example: "Sunwake • W2 • Thu"
	return "%s • W%d • %s" % [get_season_name(), get_week_in_season(), get_day_of_week_name()]

func get_calendar_string_long() -> String:
	# Example: "Sunwake — Week 2 — Thu — Day 10/28"
	return "%s — Week %d — %s — Day %d/%d" % [
		get_season_name(),
		get_week_in_season(),
		get_day_of_week_name(),
		get_day_in_season(),
		days_per_season
	]
