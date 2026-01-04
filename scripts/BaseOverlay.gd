@tool
extends CanvasLayer
class_name BaseOverlay

# Drag the Control/Panel/ColorRect you want hidden during editing into this slot.
@export var visual_node_path: NodePath

# For always-on UI (HUD), set true.
# For toggled UI (Inventory, Quest log, Dialogue), set false.
@export var start_visible_in_game: bool = true

func _enter_tree() -> void:
	_apply_visibility()

func _ready() -> void:
	_apply_visibility()

func _apply_visibility() -> void:
	var node := get_node_or_null(visual_node_path)
	if node == null:
		return
	if not (node is CanvasItem):
		return

	if Engine.is_editor_hint():
		(node as CanvasItem).visible = false
	else:
		(node as CanvasItem).visible = start_visible_in_game
