extends Interactable
class_name FestivalDecoratable

@export var quest_interactable: bool = false
@export var quest_target_id: String = ""
@export var quest_amount: int = 1

@export var required_active_quest_id: String = ""
@export var required_festival_id: String = ""

@export var interact_toast_text: String = ""
@export var interact_toast_duration: float = 2.0

@export var disable_after_use: bool = true

# Optional visual swapping
@export var undecorated_node_path: NodePath
@export var decorated_node_path: NodePath

func _ready() -> void:
	_refresh_visual_state()

	# If this object was already interacted with earlier in this session,
	# restore its decorated/used appearance and optionally disable it.
	if interactable_id.strip_edges() != "" and GameState.has_object_been_interacted(interactable_id):
		_has_been_used = true
		if disable_after_use:
			interaction_enabled = false
		_refresh_visual_state()

func _do_interact() -> void:
	# Prevent double-counting across scene reloads in the same session
	if interactable_id.strip_edges() != "" and GameState.has_object_been_interacted(interactable_id):
		if disable_after_use:
			interaction_enabled = false
		_refresh_visual_state()
		return

	# Mark this specific object as used
	if interactable_id.strip_edges() != "":
		GameState.mark_object_interacted(interactable_id)

	# Quest progress
	if quest_interactable and quest_target_id.strip_edges() != "":
		if QuestEvents != null and QuestEvents.has_signal("object_interacted"):
			QuestEvents.object_interacted.emit(interactable_id, quest_target_id, quest_amount)

	# Optional toast
	if interact_toast_text.strip_edges() != "":
		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit(interact_toast_text, "success", interact_toast_duration)

	# Lock interaction if desired
	if disable_after_use:
		interaction_enabled = false

	_refresh_visual_state()

func _refresh_visual_state() -> void:
	var undecorated_node := get_node_or_null(undecorated_node_path)
	var decorated_node := get_node_or_null(decorated_node_path)

	var is_done := false
	if interactable_id.strip_edges() != "":
		is_done = GameState.has_object_been_interacted(interactable_id) or _has_been_used
	else:
		is_done = _has_been_used

	if undecorated_node != null and undecorated_node is CanvasItem:
		(undecorated_node as CanvasItem).visible = not is_done

	if decorated_node != null and decorated_node is CanvasItem:
		(decorated_node as CanvasItem).visible = is_done

func get_interact_prompt(_context: Node = null) -> String:
	if not can_interact():
		return ""
	return prompt_text

func can_interact() -> bool:
	if not super.can_interact():
		return false

	# Optional: only usable during a specific festival
	if required_festival_id.strip_edges() != "":
		if FestivalManager == null:
			return false
		if not FestivalManager.is_festival_today():
			return false
		if FestivalManager.get_current_festival_id() != required_festival_id:
			return false

	# Optional: only usable while a specific quest is active
	if required_active_quest_id.strip_edges() != "":
		if GameState == null:
			return false
		if not GameState.active_quests.has(required_active_quest_id):
			return false

	return true
