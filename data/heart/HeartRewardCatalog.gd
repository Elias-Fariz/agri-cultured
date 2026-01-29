extends Resource
class_name HeartRewardCatalog

@export var rewards: Array[HeartRewardDefinition] = []

func get_rewards_for(domain_id: String, milestone_id: String) -> Array[HeartRewardDefinition]:
	var out: Array[HeartRewardDefinition] = []
	for r in rewards:
		if r == null:
			continue
		if r.domain_id == domain_id and r.milestone_id == milestone_id:
			out.append(r)
	return out
