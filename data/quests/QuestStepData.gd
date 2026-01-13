extends Resource
class_name QuestStepData

@export var type: String = "ship"          # "ship", "go_to", "chop_tree", etc.
@export var target: String = ""            # "Strawberry", "farm", "npc_alex"
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
