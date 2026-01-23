extends Area2D

@export var target_scene_path: String = ""
@export var target_spawn_tag: String = ""

# NEW: Travel unlock ID (optional)
# If set, this pad can be unlocked by GameState.unlock_travel(travel_id)
@export var travel_id: String = ""   # e.g. "valley_heart", "animal_keeper"

# Locking rules
@export var required_completed_quests: Array[String] = []
@export var require_claimed: bool = true

# Prompt text
@export var prompt_travel: String = "E: Travel"
@export var prompt_locked: String = "Locked"

# Prompt priority (tune to your system)
@export var prompt_priority: int = 30


func get_interact_priority(_context :Node= null) -> int:
	return prompt_priority


func get_interact_prompt(_context :Node= null) -> String:
	return prompt_travel if _is_unlocked() else prompt_locked


func interact() -> void:
	if not _is_unlocked():
		# Optional: tiny toast feedback if you want
		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("This path is locked for now.", "info", 2.0)
		return

	if target_scene_path.strip_edges() == "":
		return

	GameState.pending_spawn_tag = target_spawn_tag
	get_tree().change_scene_to_file(target_scene_path)


func _is_unlocked() -> bool:
	# 1) If a travel_id is set, it can unlock via GameState.unlock_travel()
	var tid := travel_id.strip_edges()
	if tid != "":
		if GameState != null and GameState.has_method("is_travel_unlocked"):
			if bool(GameState.call("is_travel_unlocked", tid)):
				return true

	# 2) Otherwise (or additionally), fall back to quest-based gating
	if required_completed_quests.is_empty():
		# If there is no travel_id unlock AND no quest requirements, it's open
		return tid == ""  # if tid is set but not unlocked, keep it locked

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
