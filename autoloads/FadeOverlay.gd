# res://autoload/FadeOverlay.gd
extends CanvasLayer

@export var default_duration: float = 0.35

var _rect: ColorRect
var _tween: Tween

func _ready() -> void:
	# Always on top
	layer = 200

	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.anchor_left = 0
	_rect.anchor_top = 0
	_rect.anchor_right = 1
	_rect.anchor_bottom = 1
	_rect.offset_left = 0
	_rect.offset_top = 0
	_rect.offset_right = 0
	_rect.offset_bottom = 0

	# Start invisible and non-blocking.
	_rect.modulate.a = 0.0
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(_rect)

func fade_out(duration: float = -1.0) -> void:
	await _fade_to(1.0, duration)

func fade_in(duration: float = -1.0) -> void:
	await _fade_to(0.0, duration)

func set_black() -> void:
	_kill_tween()
	_rect.modulate.a = 1.0

func set_clear() -> void:
	_kill_tween()
	_rect.modulate.a = 0.0

func _fade_to(target_alpha: float, duration: float) -> void:
	if duration < 0.0:
		duration = default_duration

	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", clampf(target_alpha, 0.0, 1.0), max(duration, 0.01))
	await _tween.finished

func _kill_tween() -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = null
