extends CanvasLayer
class_name RestorationFadeOverlay

@export var rect_path: NodePath = NodePath("ColorRect")
@export var fade_color: Color = Color(0.03, 0.02, 0.06, 1.0)

@onready var rect: ColorRect = get_node_or_null(rect_path) as ColorRect

func _ready() -> void:
	add_to_group("restoration_fade_overlay")

	if rect != null:
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
		rect.visible = false

func fade_out_in(
	fade_out_seconds: float = 0.25,
	hold_seconds: float = 0.15,
	fade_in_seconds: float = 0.35
) -> void:
	if rect == null:
		return

	rect.visible = true
	rect.color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)

	var tween := create_tween()
	tween.tween_property(rect, "color:a", 0.88, max(0.01, fade_out_seconds))
	tween.tween_interval(max(0.0, hold_seconds))
	tween.tween_property(rect, "color:a", 0.0, max(0.01, fade_in_seconds))

	await tween.finished

	if rect != null:
		rect.visible = false
