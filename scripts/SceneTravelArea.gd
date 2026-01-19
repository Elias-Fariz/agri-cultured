extends Area2D

@export var target_scene_path: String = ""
@export var target_spawn_tag: String = ""

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
	if required_completed_quests.is_empty():
		return true

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
