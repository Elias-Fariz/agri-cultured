extends Resource
class_name QuestStepData

@export var type: String = "ship"          # "ship", "go_to", "chop_tree", "catch_fish", etc.

# Primary target meaning depends on type.
# For "gift": target = item_id.
# For "talk_to": target = npc_id.
# For "catch_fish": target can be fish item id, or blank for any fish.
@export var target: String = ""

# Secondary target, only used by certain types.
# For "gift": target2 = npc_id.
@export var target2: String = ""

@export var amount: int = 1
@export_multiline var text: String = ""

# Optional rewards granted when THIS STEP completes.
# Useful for moments like:
# "Talk to Fisher" -> unlock Fishing Rod.
@export var reward_money: int = 0
@export var reward_items: Dictionary[String, int] = {}
@export var reward_flags: Array[String] = []
@export var reward_tool_ids: Array[String] = []

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

	return {
		"type": type,
		"target": target,
		"target2": target2,
		"amount": amount,
		"progress": 0,
		"text": text,
		"reward": reward,
		"reward_claimed": false,
	}
