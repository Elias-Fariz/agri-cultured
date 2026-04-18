extends Resource
class_name QuestData

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""

# "oneshot" or "chain"
@export var quest_type: String = "oneshot"

# For oneshot quests
@export var oneshot_action: String = "ship"
@export var oneshot_target: String = ""
@export var oneshot_amount: int = 1
@export_multiline var oneshot_text: String = ""

# For chain quests
@export var steps: Array[QuestStepData] = []

# Turn-in info
@export var turn_in_id: String = ""
@export_multiline var turn_in_text: String = ""

# Rewards
@export var reward_money: int = 0
@export var reward_items: Dictionary[String, int] = {}

# --- Prerequisites ---
@export var requires_completed: Array[String] = []
@export var requires_day: int = 0
@export var requires_friendship: Dictionary = {}

@export var required_festival_id: String = ""
@export var festival_day_only: bool = false

# Optional friendly metadata
@export var giver_id: String = ""

# Existing quest dialogue
@export var offer_lines: Array[String] = []
@export var in_progress_lines: Array[String] = []
@export var turn_in_lines: Array[String] = []
@export var after_thanks_lines: Array[String] = []

@export var locked_lines: Array[String] = []
@export_range(0.0, 1.0) var locked_bark_chance: float = 0.2

# -------------------------------------------------------------------
# NEW: participant / override data
# -------------------------------------------------------------------

# NPCs involved in the emotional/social flow of this quest
@export var participant_ids: PackedStringArray = PackedStringArray()

# Optional richer dialogue overrides for specific NPCs while this quest is active
@export var npc_overrides: Array[QuestNpcOverrideData] = []

func to_dict() -> Dictionary:
	var reward: Dictionary = {}
	if reward_money > 0:
		reward["money"] = reward_money
	if reward_items.size() > 0:
		reward["items"] = reward_items

	# Chain quest
	if quest_type == "chain":
		var step_dicts: Array = []
		for s in steps:
			if s != null:
				step_dicts.append(s.to_dict())

		return {
			"id": id,
			"title": title,
			"description": description,
			"type": "chain",
			"step_index": 0,
			"steps": step_dicts,
			"turn_in_id": turn_in_id,
			"turn_in_text": turn_in_text,
			"reward": reward,
			"completed": false,
			"claimed": false,
		}

	# Oneshot quest
	return {
		"id": id,
		"title": title,
		"description": description,
		"type": oneshot_action,
		"target": oneshot_target,
		"amount": oneshot_amount,
		"progress": 0,
		"text": oneshot_text,
		"turn_in_id": turn_in_id,
		"turn_in_text": turn_in_text,
		"reward": reward,
		"completed": false,
		"claimed": false,
	}

func is_unlocked() -> bool:
	# Day gate
	if requires_day > 0 and TimeManager.day < requires_day:
		return false

	# Completed quest prereqs
	for qid in requires_completed:
		if not GameState.completed_quests.has(qid):
			return false

	# Friendship prereqs
	for npc_id_any in requires_friendship.keys():
		var npc_id: String = String(npc_id_any)
		var needed: int = int(requires_friendship[npc_id_any])
		if GameState.get_friendship(npc_id) < needed:
			return false

	# Festival gate
	if festival_day_only:
		if required_festival_id.strip_edges() == "":
			return false
		if FestivalManager == null:
			return false
		if not FestivalManager.is_festival_today():
			return false
		if FestivalManager.get_current_festival_id() != required_festival_id:
			return false

	return true

# -------------------------------------------------------------------
# NEW: helper methods for participant overrides
# -------------------------------------------------------------------

func has_participant(npc_id: String) -> bool:
	if npc_id.strip_edges() == "":
		return false
	return participant_ids.has(npc_id)

func get_override_for_npc(npc_id: String, phase: String, step_index: int = -1) -> QuestNpcOverrideData:
	if npc_id.strip_edges() == "":
		return null

	for ov in npc_overrides:
		if ov == null:
			continue
		if ov.npc_id != npc_id:
			continue
		if ov.matches_phase(phase, step_index):
			return ov

	return null

func get_override_lines_for_npc(npc_id: String, phase: String, step_index: int = -1) -> Array[String]:
	var ov := get_override_for_npc(npc_id, phase, step_index)
	if ov == null:
		return []

	return ov.lines

func get_override_dialogue_entries_for_npc(npc_id: String, phase: String, step_index: int = -1) -> Array[QuestDialogueEntryData]:
	var ov := get_override_for_npc(npc_id, phase, step_index)
	if ov == null:
		return []

	return ov.dialogue_entries

func get_best_override_lines_for_npc(npc_id: String, quest_state: Dictionary) -> Array[String]:
	if npc_id.strip_edges() == "":
		return []

	var qid := String(quest_state.get("id", id))
	var completed := bool(quest_state.get("completed", false))
	var claimed := bool(quest_state.get("claimed", false))

	# NEW: ready-to-turn-in state lives in active_quests + GameState flag
	if GameState != null and GameState.is_quest_ready_to_turn_in(qid):
		return get_override_lines_for_npc(npc_id, "turn_in_ready")

	# Completed and already claimed
	if completed and claimed:
		return get_override_lines_for_npc(npc_id, "completed_claimed")

	# Active chain step
	if quest_type == "chain":
		var step_index := int(quest_state.get("step_index", 0))

		var step_lines := get_override_lines_for_npc(npc_id, "active_step", step_index)
		if not step_lines.is_empty():
			return step_lines

	# Generic active fallback
	return get_override_lines_for_npc(npc_id, "active_any")
