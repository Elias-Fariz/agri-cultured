extends Area2D

@export var target_scene_path: String = ""
@export var target_spawn_tag: String = ""

# Travel unlock ID.
# If set, this pad can be unlocked by GameState.unlock_travel(travel_id)
@export var travel_id: String = ""

# Locking rules
@export var required_completed_quests: Array[String] = []
@export var require_claimed: bool = true

# Prompt text
@export var prompt_travel: String = "E: Travel"
@export var prompt_locked: String = "E: Check"

# Prompt priority
@export var prompt_priority: int = 30
@export_multiline var locked_text: String = "This path is locked for now."

# Transition feel
@export var use_custom_fade_times: bool = false
@export var fade_out_time: float = 0.18
@export var fade_in_time: float = 0.24
@export var frames_to_wait_after_scene_change: int = 4


func get_interact_priority(_context: Node = null) -> int:
	return prompt_priority


func get_interact_prompt(_context: Node = null) -> String:
	return prompt_travel if _is_unlocked() else prompt_locked


func interact() -> void:
	if GameState != null and "is_scene_traveling" in GameState:
		if GameState.is_scene_traveling:
			return

	if not _is_unlocked():
		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit(locked_text, "info", 2.5)
		return

	if target_scene_path.strip_edges() == "":
		return

	if GameState == null or not GameState.has_method("travel_to_scene"):
		push_warning("SceneTravelArea: GameState.travel_to_scene() is missing.")
		return

	if use_custom_fade_times:
		GameState.travel_to_scene(
			target_scene_path,
			target_spawn_tag,
			fade_out_time,
			fade_in_time,
			frames_to_wait_after_scene_change
		)
	else:
		GameState.travel_to_scene(target_scene_path, target_spawn_tag)


func _is_unlocked() -> bool:
	# 1) If a travel_id is set, it can unlock via GameState.unlock_travel()
	var tid := travel_id.strip_edges()
	if tid != "":
		if GameState != null and GameState.has_method("is_travel_unlocked"):
			if bool(GameState.call("is_travel_unlocked", tid)):
				return true

	# 2) Otherwise, fall back to quest-based gating.
	if required_completed_quests.is_empty():
		# If there is no travel_id unlock AND no quest requirements, it's open.
		return tid == ""

	for qid in required_completed_quests:
		var id := String(qid).strip_edges()
		if id == "":
			continue

		if not GameState.completed_quests.has(id):
			return false

		if require_claimed:
			var q: Dictionary = GameState.completed_quests[id]
			if not bool(q.get("claimed", false)):
				return false

	return true
