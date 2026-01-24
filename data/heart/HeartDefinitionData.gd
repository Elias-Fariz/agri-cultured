# res://data/heart/HeartDefinitionData.gd
extends Resource
class_name HeartDefinitionData

@export var milestones: Array[HeartMilestoneData] = []

func get_next_milestone(domain_id: String, kind: String, done_count: int) -> HeartMilestoneData:
	# next one is done_count + 1 in order
	var wanted_order := done_count + 1
	for m in milestones:
		if m == null:
			continue
		if m.domain_id == domain_id and m.kind == kind and m.order == wanted_order:
			return m
	return null
