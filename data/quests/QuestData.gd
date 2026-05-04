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

@export var reward_crafting_recipe_ids: Array[String] = []
@export var reward_cooking_recipe_ids: Array[String] = []

# Optional system/story rewards
@export var reward_flags: Array[String] = []

# Use stable string IDs instead of enum numbers.
# Recommended values for now:
# - "bucket"
# - "fishing_rod"
@export var reward_tool_ids: Array[String] = []

# Optional scene spawns, such as giving the player a cow on the farm.
@export var reward_spawns: Array[QuestSpawnRewardData] = []

# Rewards granted immediately when the quest is accepted.
# Useful when the NPC gives you the tool needed for the quest.
@export var accept_reward_money: int = 0
@export var accept_reward_items: Dictionary[String, int] = {}
@export var accept_reward_flags: Array[String] = []
@export var accept_reward_tool_ids: Array[String] = []

@export var accept_reward_crafting_recipe_ids: Array[String] = []
@export var accept_reward_cooking_recipe_ids: Array[String] = []

# Optional prerequisite flags.
# Example: fishing_intro requires "fishing_unlocked"
@export var requires_flags: Array[String] = []

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

	if reward_flags.size() > 0:
		reward["flags"] = reward_flags.duplicate()

	if reward_tool_ids.size() > 0:
		reward["tools"] = reward_tool_ids.duplicate()
	
	if reward_crafting_recipe_ids.size() > 0:
		reward["crafting_recipes"] = reward_crafting_recipe_ids.duplicate()

	if reward_cooking_recipe_ids.size() > 0:
		reward["cooking_recipes"] = reward_cooking_recipe_ids.duplicate()
		
	var accept_reward: Dictionary = {}

	if accept_reward_money > 0:
		accept_reward["money"] = accept_reward_money

	if accept_reward_items.size() > 0:
		accept_reward["items"] = accept_reward_items

	if accept_reward_flags.size() > 0:
		accept_reward["flags"] = accept_reward_flags.duplicate()

	if accept_reward_tool_ids.size() > 0:
		accept_reward["tools"] = accept_reward_tool_ids.duplicate()
		
	if accept_reward_crafting_recipe_ids.size() > 0:
		accept_reward["crafting_recipes"] = accept_reward_crafting_recipe_ids.duplicate()

	if accept_reward_cooking_recipe_ids.size() > 0:
		accept_reward["cooking_recipes"] = accept_reward_cooking_recipe_ids.duplicate()

	var spawn_dicts: Array = []
	for spawn_reward in reward_spawns:
		if spawn_reward != null and spawn_reward.is_valid():
			spawn_dicts.append(spawn_reward.to_dict())

	if spawn_dicts.size() > 0:
		reward["spawns"] = spawn_dicts

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
			"accept_reward": accept_reward,
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
		"accept_reward": accept_reward,
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
	
	# Flag prereqs
	for flag_id in requires_flags:
		var flag := String(flag_id).strip_edges()
		if flag == "":
			continue

		var has_it := false

		if GameState != null and GameState.has_method("has_flag"):
			has_it = bool(GameState.has_flag(flag))

		# Also allow HeartProgress reward flags to unlock quests.
		if not has_it and HeartProgress != null and HeartProgress.has_method("get_reward_flag"):
			has_it = bool(HeartProgress.get_reward_flag(flag, false))

		if not has_it:
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

	return ov.get_best_plain_lines()

#func get_override_dialogue_entries_for_npc(npc_id: String, phase: String, step_index: int = -1) -> Array[QuestDialogueEntryData]:
	#var ov := get_override_for_npc(npc_id, phase, step_index)
	#if ov == null:
		#return []
#
	#return ov.dialogue_entries

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

func get_override_sequence_for_npc(npc_id: String, phase: String, step_index: int = -1) -> DialogueSequenceData:
	var ov := get_override_for_npc(npc_id, phase, step_index)
	if ov == null:
		return null
	return ov.get_sequence()
	
	
