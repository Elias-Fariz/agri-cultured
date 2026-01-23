extends Resource
class_name QuestStepData

@export var type: String = "ship"          # "ship", "go_to", "chop_tree", etc.

# Primary target meaning depends on type.
# For "gift": target = item_id (e.g. "Shell Necklace")  [optional]
@export var target: String = ""            # "Strawberry", "farm", "npc_alex"
# Secondary target (only used by certain types).
# For "gift": target2 = npc_id (e.g. "npc_fisherman")   [optional]
@export var target2: String = ""

@export var amount: int = 1
@export_multiline var text: String = ""    # what the tracker shows for this step

func to_dict() -> Dictionary:
	return {
		"type": type,
		"target": target,
		"amount": amount,
		"progress": 0,
		"text": text,
	}
