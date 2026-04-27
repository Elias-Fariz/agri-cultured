extends Node2D
class_name RestorationInstabilityBar

@export var segment_width: float = 18.0
@export var segment_height: float = 7.0
@export var segment_gap: float = 3.0

@export var filled_color: Color = Color(0.65, 0.25, 1.0, 0.95)
@export var empty_color: Color = Color(0.18, 0.12, 0.24, 0.75)
@export var border_color: Color = Color(0.9, 0.8, 1.0, 0.9)

@export var background_padding: float = 4.0
@export var background_color: Color = Color(0.05, 0.03, 0.08, 0.65)

@export var start_hidden: bool = true

var current_value: int = 0
var max_value: int = 3

func _ready() -> void:
	visible = not start_hidden
	queue_redraw()

func show_bar(p_current: int, p_max: int) -> void:
	set_values(p_current, p_max)
	visible = true

func hide_bar() -> void:
	visible = false

func set_values(p_current: int, p_max: int) -> void:
	max_value = max(1, p_max)
	current_value = clampi(p_current, 0, max_value)
	queue_redraw()

func _draw() -> void:
	if max_value <= 0:
		return

	var total_width := float(max_value) * segment_width + float(max_value - 1) * segment_gap
	var total_height := segment_height

	var start_x := -total_width * 0.5
	var start_y := -total_height * 0.5

	var bg_rect := Rect2(
		Vector2(start_x - background_padding, start_y - background_padding),
		Vector2(total_width + background_padding * 2.0, total_height + background_padding * 2.0)
	)

	draw_rect(bg_rect, background_color, true)
	draw_rect(bg_rect, border_color, false, 1.5)

	for i in range(max_value):
		var x := start_x + float(i) * (segment_width + segment_gap)
		var rect := Rect2(Vector2(x, start_y), Vector2(segment_width, segment_height))

		var color := filled_color if i < current_value else empty_color
		draw_rect(rect, color, true)
		draw_rect(rect, border_color, false, 1.0)
