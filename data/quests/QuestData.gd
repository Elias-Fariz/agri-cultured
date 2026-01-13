extends Resource
class_name QuestData

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""

# "oneshot" or "chain"
@export var quest_type: String = "oneshot"

# For oneshot quests
@export var oneshot_action: String = "ship"     # matches your event types
@export var oneshot_target: String = ""
@export var oneshot_amount: int = 1
@export_multiline var oneshot_text: String = ""  # tracker text

# For chain quests
@export var steps: Array[QuestStepData] = []

# Turn-in info (NOT a quest step — this is your “return to X for reward” state)
@export var turn_in_id: String = ""             # "npc_mayor" or "town_board"
@export_multiline var turn_in_text: String = "" # "Return to the Mayor..."

# Rewards (keep it simple like you do now)
@export var reward_money: int = 0
@export var reward_items: Dictionary[String, int] = {}

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
		"type": oneshot_action,      # IMPORTANT: stays compatible with your system
		"target": oneshot_target,
		"amount": oneshot_amount,
		"progress": 0,
		"text": oneshot_text,        # optional
		"turn_in_id": turn_in_id,
		"turn_in_text": turn_in_text,
		"reward": reward,
		"completed": false,
		"claimed": false,
	}
