extends Resource
class_name HeartRewardCatalog

@export var rewards: Array[HeartRewardDefinition] = []

func get_reward_by_id(reward_id: StringName) -> HeartRewardDefinition:
	if reward_id == StringName(""):
		return null
	for r in rewards:
		if r == null:
			continue
		if r.id == reward_id:
			return r
	return null
