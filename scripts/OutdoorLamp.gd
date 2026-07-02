extends Node2D
class_name OutdoorLamp

enum ScheduleMode {
	FOLLOW_TIME,
	ALWAYS_ON,
	ALWAYS_OFF
}

@export_category("Schedule")

## FOLLOW_TIME uses the on/off times below.
## ALWAYS_ON and ALWAYS_OFF ignore the current time.
@export var schedule_mode: ScheduleMode = ScheduleMode.FOLLOW_TIME

@export_range(0, 23, 1) var turn_on_hour: int = 18
@export_range(0, 59, 1) var turn_on_minute: int = 0

@export_range(0, 23, 1) var turn_off_hour: int = 6
@export_range(0, 59, 1) var turn_off_minute: int = 0


@export_category("Lamp Nodes")

## Parent containing the glow sprite, PointLight2D, flame, etc.
@export var lit_visual_path: NodePath = ^"LitVisual"

## Optional visual shown only while the lamp is off.
@export var unlit_visual_path: NodePath = ^"UnlitVisual"

## The actual PointLight2D.
@export var point_light_path: NodePath = ^"LitVisual/PointLight2D"


@export_category("Debug")

@export var debug_enabled: bool = false


var _is_on: bool = false


func _ready() -> void:
	if TimeManager != null:
		if not TimeManager.time_changed.is_connected(_on_time_changed):
			TimeManager.time_changed.connect(_on_time_changed)

		_refresh_for_time(TimeManager.minutes)
	else:
		push_warning("OutdoorLamp: TimeManager was not available.")
		_apply_lamp_state(schedule_mode == ScheduleMode.ALWAYS_ON)


func _exit_tree() -> void:
	if TimeManager != null:
		if TimeManager.time_changed.is_connected(_on_time_changed):
			TimeManager.time_changed.disconnect(_on_time_changed)


func _on_time_changed(current_minutes: int) -> void:
	_refresh_for_time(current_minutes)


func _refresh_for_time(current_minutes: int) -> void:
	var should_be_on := _should_be_on(current_minutes)
	_apply_lamp_state(should_be_on)


func _should_be_on(current_minutes: int) -> bool:
	match schedule_mode:
		ScheduleMode.ALWAYS_ON:
			return true

		ScheduleMode.ALWAYS_OFF:
			return false

		ScheduleMode.FOLLOW_TIME:
			var on_minutes := _get_turn_on_minutes()
			var off_minutes := _get_turn_off_minutes()

			return _is_time_between(
				current_minutes,
				on_minutes,
				off_minutes
			)

	return false


## Supports schedules that pass through midnight.
##
## Example:
## Start = 18:00
## End   = 06:00
##
## This correctly treats 22:00, 01:00, and 05:30 as active.
func _is_time_between(
	current_minutes: int,
	start_minutes: int,
	end_minutes: int
) -> bool:
	current_minutes = wrapi(current_minutes, 0, 24 * 60)
	start_minutes = wrapi(start_minutes, 0, 24 * 60)
	end_minutes = wrapi(end_minutes, 0, 24 * 60)

	# Equal times are treated as an always-on schedule.
	# Use ALWAYS_OFF when a lamp should remain disabled.
	if start_minutes == end_minutes:
		return true

	# Normal same-day range, such as 08:00 to 17:00.
	if start_minutes < end_minutes:
		return (
			current_minutes >= start_minutes
			and current_minutes < end_minutes
		)

	# Overnight range, such as 18:00 to 06:00.
	return (
		current_minutes >= start_minutes
		or current_minutes < end_minutes
	)


func _apply_lamp_state(value: bool) -> void:
	if _is_on == value:
		# Still refresh once in case this was called during _ready().
		_refresh_visual_nodes()
		return

	_is_on = value
	_refresh_visual_nodes()

	if debug_enabled:
		print(
			"[OutdoorLamp] ",
			name,
			" is now ",
			"ON" if _is_on else "OFF",
			" at ",
			TimeManager.get_time_string()
			if TimeManager != null
			else "unknown time"
		)


func _refresh_visual_nodes() -> void:
	var lit_visual := get_node_or_null(lit_visual_path)
	var unlit_visual := get_node_or_null(unlit_visual_path)
	var point_light := get_node_or_null(point_light_path) as PointLight2D

	if lit_visual is CanvasItem:
		(lit_visual as CanvasItem).visible = _is_on

	if unlit_visual is CanvasItem:
		(unlit_visual as CanvasItem).visible = not _is_on

	if point_light != null:
		point_light.enabled = _is_on


func set_lamp_on(value: bool) -> void:
	_apply_lamp_state(value)


func refresh_from_current_time() -> void:
	if TimeManager != null:
		_refresh_for_time(TimeManager.minutes)


func is_lamp_on() -> bool:
	return _is_on


func _get_turn_on_minutes() -> int:
	return (turn_on_hour * 60) + turn_on_minute


func _get_turn_off_minutes() -> int:
	return (turn_off_hour * 60) + turn_off_minute
