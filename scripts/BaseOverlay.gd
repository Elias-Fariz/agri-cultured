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

# Optional ID used by GameState's modal guard.
# Leave blank and it will use this node's path/name.
@export var modal_overlay_id: String = ""

@export var tutorial_ui_id: String = ""

var _is_open: bool = false
var _modal_registered: bool = false


func _enter_tree() -> void:
	_apply_visibility()


func _ready() -> void:
	_apply_visibility()

	# Track initial runtime state for toggled overlays / HUD.
	if not Engine.is_editor_hint():
		_is_open = start_visible_in_game


func _exit_tree() -> void:
	# Safety: if a modal overlay is removed while open, release its modal ownership.
	if Engine.is_editor_hint():
		return

	if is_modal and _modal_registered:
		_release_modal_ownership()


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
	if is_open() and tutorial_ui_id != "":
		QuestEvents.ui_opened.emit(tutorial_ui_id)


func hide_overlay() -> void:
	_set_overlay_visible(false)


func toggle_overlay() -> void:
	if is_open():
		hide_overlay()
	else:
		show_overlay()


func is_open() -> bool:
	return _is_open


# --- Internal implementation ---

func _set_overlay_visible(visible: bool) -> void:
	if Engine.is_editor_hint():
		return

	var node := get_node_or_null(visual_node_path)
	if node == null or not (node is CanvasItem):
		return

	# Avoid double work / double lock-unlock.
	if _is_open == visible:
		(node as CanvasItem).visible = visible
		return

	if visible:
		if is_modal:
			if not _try_claim_modal_ownership():
				return

		_is_open = true
		(node as CanvasItem).visible = true

		if is_modal:
			GameState.lock_gameplay()
			TimeManager.pause_time()

	else:
		_is_open = false
		(node as CanvasItem).visible = false

		if is_modal and _modal_registered:
			_release_modal_ownership()
			GameState.unlock_gameplay()
			TimeManager.resume_time()


func _try_claim_modal_ownership() -> bool:
	if not is_modal:
		return true

	var id := _get_modal_overlay_id()

	if GameState != null and GameState.has_method("try_open_modal_overlay"):
		var ok := bool(GameState.try_open_modal_overlay(id))
		if not ok:
			return false

	_modal_registered = true
	return true


func _release_modal_ownership() -> void:
	var id := _get_modal_overlay_id()

	if GameState != null and GameState.has_method("close_modal_overlay"):
		GameState.close_modal_overlay(id)

	_modal_registered = false


func _get_modal_overlay_id() -> String:
	var id := modal_overlay_id.strip_edges()
	if id != "":
		return id

	if is_inside_tree():
		return str(get_path())

	return name
