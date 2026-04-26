extends BaseOverlay
class_name RestorationCombatUI

@export var title_label_path: NodePath = NodePath("Panel/MarginContainer/VBoxContainer/TitleLabel")
@export var resolve_label_path: NodePath = NodePath("Panel/MarginContainer/VBoxContainer/ResolveLabel")
@export var instability_label_path: NodePath = NodePath("Panel/MarginContainer/VBoxContainer/InstabilityLabel")

@onready var title_label: Label = get_node_or_null(title_label_path) as Label
@onready var resolve_label: Label = get_node_or_null(resolve_label_path) as Label
@onready var instability_label: Label = get_node_or_null(instability_label_path) as Label

func _ready() -> void:
	super._ready()
	add_to_group("restoration_combat_ui")

	# This is a temporary combat HUD, so it should begin hidden.
	if not Engine.is_editor_hint():
		hide_overlay()

func show_encounter(
	encounter_name: String,
	resolve: int,
	max_resolve: int,
	instability: int,
	max_instability: int
) -> void:
	if title_label != null:
		title_label.text = encounter_name

	update_values(resolve, max_resolve, instability, max_instability)
	show_overlay()

func update_values(
	resolve: int,
	max_resolve: int,
	instability: int,
	max_instability: int
) -> void:
	if resolve_label != null:
		resolve_label.text = "Resolve: %d / %d" % [resolve, max_resolve]

	if instability_label != null:
		instability_label.text = "Instability: %d / %d" % [instability, max_instability]

func hide_ui() -> void:
	hide_overlay()
