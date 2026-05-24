# res://scripts/ui/OverheadBubbleController.gd
extends Node2D
class_name OverheadBubbleController

@export var default_duration: float = 1.0
@export var float_distance: float = 8.0
@export var fade_in_time: float = 0.08
@export var fade_out_time: float = 0.18

# Bubble sizing.
@export var min_width: float = 34.0
@export var max_width: float = 160.0
@export var padding_x: float = 10.0
@export var padding_y: float = 6.0

# Keeps the bubble centered over the actor.
@export var center_above_anchor: bool = true

@onready var bubble_root: Control = $BubbleRoot
@onready var bubble_panel: PanelContainer = $BubbleRoot/BubblePanel
@onready var bubble_label: Label = $BubbleRoot/BubblePanel/BubbleLabel

var _tween: Tween = null
var _hide_token: int = 0


func _ready() -> void:
	hide_bubble(true)


func show_text(text: String, duration: float = -1.0, offset: Vector2 = Vector2.ZERO) -> void:
	text = text.strip_edges()
	if text == "":
		hide_bubble()
		return

	if duration <= 0.0:
		duration = default_duration

	_hide_token += 1
	var token := _hide_token

	if _tween != null:
		_tween.kill()
		_tween = null

	bubble_label.text = text
	bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	bubble_root.visible = true
	bubble_panel.visible = true

	await _apply_size_and_centering(text, offset)

	bubble_root.modulate.a = 0.0
	bubble_root.position = _get_centered_position(offset) + Vector2(0, float_distance * 0.5)

	_tween = create_tween()
	_tween.tween_property(bubble_root, "modulate:a", 1.0, fade_in_time)
	_tween.parallel().tween_property(
		bubble_root,
		"position",
		_get_centered_position(offset),
		fade_in_time
	)

	await _tween.finished

	await get_tree().create_timer(duration).timeout

	if token != _hide_token:
		return

	hide_bubble()


func hide_bubble(instant: bool = false) -> void:
	_hide_token += 1

	if _tween != null:
		_tween.kill()
		_tween = null

	if bubble_root == null:
		return

	if instant:
		bubble_root.visible = false
		bubble_root.modulate.a = 0.0
		return

	if not bubble_root.visible:
		return

	_tween = create_tween()
	_tween.tween_property(bubble_root, "position", bubble_root.position + Vector2(0, -float_distance), fade_out_time)
	_tween.parallel().tween_property(bubble_root, "modulate:a", 0.0, fade_out_time)

	await _tween.finished

	bubble_root.visible = false


func _apply_size_and_centering(text: String, offset: Vector2) -> void:
	# Approximate text width. This is intentionally simple and reliable.
	# Later, you can replace this with font.get_string_size(...) if you want pixel-perfect sizing.
	var estimated_text_width := float(text.length()) * 8.0
	var desired_width :Variant= clamp(estimated_text_width + padding_x * 2.0, min_width, max_width)

	bubble_panel.custom_minimum_size = Vector2(desired_width, 0.0)
	bubble_label.custom_minimum_size = Vector2(max(1.0, desired_width - padding_x * 2.0), 0.0)

	# Let Godot update the Control sizes before we center.
	await get_tree().process_frame

	bubble_root.position = _get_centered_position(offset)


func _get_centered_position(offset: Vector2 = Vector2.ZERO) -> Vector2:
	if not center_above_anchor:
		return offset

	var size := Vector2.ZERO

	if bubble_panel != null:
		size = bubble_panel.size

	# The key centering line:
	# Put the panel's horizontal center over this Node2D's origin.
	return offset + Vector2(-size.x * 0.5, -size.y * 0.5)
