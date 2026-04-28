extends BaseOverlay
class_name CutsceneIllustrationOverlay

@export var visuals_path: NodePath = NodePath("Visuals")
@export var illustration_path: NodePath = NodePath("Visuals/Illustration")
@export var fade_seconds_default: float = 0.25

@onready var visuals: Control = get_node_or_null(visuals_path) as Control
@onready var illustration: TextureRect = get_node_or_null(illustration_path) as TextureRect

func _ready() -> void:
	super._ready()
	add_to_group("cutscene_illustration_overlay")

	if not Engine.is_editor_hint():
		hide_overlay()
		if visuals != null:
			visuals.modulate.a = 0.0

func show_illustration(texture: Texture2D, fade_seconds: float = -1.0) -> void:
	if illustration != null:
		illustration.texture = texture

	var fade_time := fade_seconds_default if fade_seconds < 0.0 else fade_seconds

	show_overlay()

	if visuals == null:
		return

	visuals.modulate.a = 0.0

	if fade_time <= 0.01:
		visuals.modulate.a = 1.0
		return

	var tween := create_tween()
	tween.tween_property(visuals, "modulate:a", 1.0, fade_time)
	await tween.finished

func hide_illustration(fade_seconds: float = -1.0) -> void:
	var fade_time := fade_seconds_default if fade_seconds < 0.0 else fade_seconds

	if visuals == null:
		hide_overlay()
		return

	if fade_time <= 0.01:
		visuals.modulate.a = 0.0
		hide_overlay()
		return

	var tween := create_tween()
	tween.tween_property(visuals, "modulate:a", 0.0, fade_time)
	await tween.finished

	hide_overlay()
