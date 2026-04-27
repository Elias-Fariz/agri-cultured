extends BaseOverlay
class_name PlayerResolveUI

@export var title_label_path: NodePath = NodePath("Panel/MarginContainer/VBoxContainer/TitleLabel")
@export var resolve_bar_path: NodePath = NodePath("Panel/MarginContainer/VBoxContainer/ResolveBar")
@export var resolve_text_label_path: NodePath = NodePath("Panel/MarginContainer/VBoxContainer/ResolveTextLabel")

@onready var title_label: Label = get_node_or_null(title_label_path) as Label
@onready var resolve_bar: ProgressBar = get_node_or_null(resolve_bar_path) as ProgressBar
@onready var resolve_text_label: Label = get_node_or_null(resolve_text_label_path) as Label

func _ready() -> void:
	super._ready()
	add_to_group("player_resolve_ui")

	if not Engine.is_editor_hint():
		hide_overlay()

func show_resolve(current_value: int, max_value: int) -> void:
	_update_internal(current_value, max_value)
	show_overlay()

func update_resolve(current_value: int, max_value: int) -> void:
	_update_internal(current_value, max_value)

func hide_resolve() -> void:
	hide_overlay()

func _update_internal(current_value: int, max_value: int) -> void:
	max_value = max(1, max_value)
	current_value = clampi(current_value, 0, max_value)

	if title_label != null:
		title_label.text = "Resolve"

	if resolve_bar != null:
		resolve_bar.min_value = 0
		resolve_bar.max_value = max_value
		resolve_bar.value = current_value

	if resolve_text_label != null:
		resolve_text_label.text = "%d / %d" % [current_value, max_value]
