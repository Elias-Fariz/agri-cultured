@tool
extends CanvasLayer
class_name BaseOverlay

# Drag the Control/Panel/ColorRect you want hidden during editing into this slot.
@export var visual_node_path: NodePath

# For always-on UI (HUD), set true.
# For toggled UI (Inventory, Quest board, Dialogue), set false.
@export var start_visible_in_game: bool = true

# If true, opening this overlay locks gameplay + pauses time.
# HUD should be false. Inventory/Shipping/QuestBoard should be true.
@export var is_modal: bool = false

var _is_open: bool = false

func _enter_tree() -> void:
	_apply_visibility()

func _ready() -> void:
	_apply_visibility()
	# Track initial runtime state for toggled overlays / HUD
	if not Engine.is_editor_hint():
		_is_open = start_visible_in_game

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

# --- Public overlay API ---

func show_overlay() -> void:
	_set_overlay_visible(true)

func hide_overlay() -> void:
	_set_overlay_visible(false)

func toggle_overlay() -> void:
	_set_overlay_visible(not _is_open)

func is_open() -> bool:
	return _is_open

# --- Internal implementation ---

func _set_overlay_visible(visible: bool) -> void:
	if Engine.is_editor_hint():
		return

	# If no visual node configured, we can't do much safely.
	var node := get_node_or_null(visual_node_path)
	if node == null or not (node is CanvasItem):
		return

	# Avoid double work / double lock-unlock
	if _is_open == visible:
		(node as CanvasItem).visible = visible
		return

	_is_open = visible
	(node as CanvasItem).visible = visible

	# Modal behavior: lock gameplay + pause time while open
	if is_modal:
		if visible:
			GameState.lock_gameplay()
			TimeManager.pause_time()
		else:
			GameState.unlock_gameplay()
			TimeManager.resume_time()
