extends Node2D
class_name OutdoorLamp

enum ScheduleMode {
	FOLLOW_TIME,
	ALWAYS_ON,
	ALWAYS_OFF
}

enum TransitionMode {
	INSTANT,
	FADE
}

@export_category("Schedule")

@export var schedule_mode: ScheduleMode = ScheduleMode.FOLLOW_TIME

@export_range(0, 23, 1)
var turn_on_hour: int = 18

@export_range(0, 59, 1)
var turn_on_minute: int = 0

@export_range(0, 23, 1)
var turn_off_hour: int = 6

@export_range(0, 59, 1)
var turn_off_minute: int = 0


@export_category("Transition")

@export var transition_mode: TransitionMode = TransitionMode.FADE

@export_range(0.0, 5.0, 0.05)
var fade_duration: float = 1.0


@export_category("Visual Nodes")

@export var lit_visual_path: NodePath = ^"LitVisual"
@export var unlit_visual_path: NodePath = ^"UnlitVisual"
@export var glow_sprite_path: NodePath = ^"LitVisual/GlowSprite"
@export var point_light_path: NodePath = ^"LitVisual/PointLight2D"


@export_category("Debug")

@export var debug_enabled: bool = false


var _is_on: bool = false
var _light_tween: Tween = null

var _base_glow_modulate: Color = Color.WHITE
var _base_light_energy: float = 1.0


func _ready() -> void:
	_cache_base_values()

	if TimeManager != null:
		if not TimeManager.time_changed.is_connected(_on_time_changed):
			TimeManager.time_changed.connect(_on_time_changed)

		_refresh_for_time(TimeManager.minutes, true)
	else:
		push_warning("OutdoorLamp: TimeManager not found.")
		_apply_lamp_state(schedule_mode == ScheduleMode.ALWAYS_ON, true)


func _exit_tree() -> void:
	if TimeManager != null:
		if TimeManager.time_changed.is_connected(_on_time_changed):
			TimeManager.time_changed.disconnect(_on_time_changed)

	if _light_tween != null:
		_light_tween.kill()
		_light_tween = null


func _cache_base_values() -> void:
	var glow_sprite := get_node_or_null(glow_sprite_path) as CanvasItem
	if glow_sprite != null:
		_base_glow_modulate = glow_sprite.modulate

	var point_light := get_node_or_null(point_light_path) as PointLight2D
	if point_light != null:
		_base_light_energy = point_light.energy


func _on_time_changed(current_minutes: int) -> void:
	_refresh_for_time(current_minutes, false)


func _refresh_for_time(current_minutes: int, instant: bool = false) -> void:
	var should_be_on := _should_be_on(current_minutes)
	_apply_lamp_state(should_be_on, instant)


func _should_be_on(current_minutes: int) -> bool:
	match schedule_mode:
		ScheduleMode.ALWAYS_ON:
			return true

		ScheduleMode.ALWAYS_OFF:
			return false

		ScheduleMode.FOLLOW_TIME:
			return _is_time_between(
				current_minutes,
				_get_turn_on_minutes(),
				_get_turn_off_minutes()
			)

	return false


func _is_time_between(
	current: int,
	start: int,
	end: int
) -> bool:
	current = wrapi(current, 0, 24 * 60)
	start = wrapi(start, 0, 24 * 60)
	end = wrapi(end, 0, 24 * 60)

	# Same start/end means always on.
	if start == end:
		return true

	# Same-day range.
	if start < end:
		return current >= start and current < end

	# Overnight range.
	return current >= start or current < end


func _apply_lamp_state(value: bool, instant: bool = false) -> void:
	if _is_on == value and not instant:
		return

	_is_on = value

	if debug_enabled:
		print("[OutdoorLamp] ", name, " on = ", _is_on)

	if transition_mode == TransitionMode.INSTANT or instant or fade_duration <= 0.01:
		_apply_instant_state()
	else:
		_apply_faded_state()


func _apply_instant_state() -> void:
	if _light_tween != null:
		_light_tween.kill()
		_light_tween = null

	var alpha := 1.0 if _is_on else 0.0

	_set_lit_amount(alpha)

	var lit_visual := get_node_or_null(lit_visual_path)
	if lit_visual is CanvasItem:
		(lit_visual as CanvasItem).visible = _is_on

	var unlit_visual := get_node_or_null(unlit_visual_path)
	if unlit_visual is CanvasItem:
		(unlit_visual as CanvasItem).visible = not _is_on


func _apply_faded_state() -> void:
	if _light_tween != null:
		_light_tween.kill()
		_light_tween = null

	var lit_visual := get_node_or_null(lit_visual_path)
	if lit_visual is CanvasItem:
		(lit_visual as CanvasItem).visible = true

	var unlit_visual := get_node_or_null(unlit_visual_path)
	if unlit_visual is CanvasItem:
		(unlit_visual as CanvasItem).visible = not _is_on

	var target_amount := 1.0 if _is_on else 0.0
	var current_amount := _get_current_lit_amount()

	_light_tween = create_tween()
	_light_tween.tween_method(
		_set_lit_amount,
		current_amount,
		target_amount,
		fade_duration
	)

	await _light_tween.finished

	_light_tween = null

	if not _is_on:
		if lit_visual is CanvasItem:
			(lit_visual as CanvasItem).visible = false


func _set_lit_amount(amount: float) -> void:
	amount = clamp(amount, 0.0, 1.0)

	var glow_sprite := get_node_or_null(glow_sprite_path) as CanvasItem
	if glow_sprite != null:
		var c := _base_glow_modulate
		c.a *= amount
		glow_sprite.modulate = c

	var point_light := get_node_or_null(point_light_path) as PointLight2D
	if point_light != null:
		point_light.enabled = amount > 0.01
		point_light.energy = _base_light_energy * amount


func _get_current_lit_amount() -> float:
	var point_light := get_node_or_null(point_light_path) as PointLight2D
	if point_light != null and _base_light_energy > 0.001:
		return clamp(point_light.energy / _base_light_energy, 0.0, 1.0)

	var glow_sprite := get_node_or_null(glow_sprite_path) as CanvasItem
	if glow_sprite != null and _base_glow_modulate.a > 0.001:
		return clamp(glow_sprite.modulate.a / _base_glow_modulate.a, 0.0, 1.0)

	return 1.0 if _is_on else 0.0


func refresh_from_current_time() -> void:
	if TimeManager != null:
		_refresh_for_time(TimeManager.minutes, true)


func set_lamp_on(value: bool) -> void:
	schedule_mode = ScheduleMode.ALWAYS_ON if value else ScheduleMode.ALWAYS_OFF
	_apply_lamp_state(value, false)


func is_lamp_on() -> bool:
	return _is_on


func _get_turn_on_minutes() -> int:
	return turn_on_hour * 60 + turn_on_minute


func _get_turn_off_minutes() -> int:
	return turn_off_hour * 60 + turn_off_minute
