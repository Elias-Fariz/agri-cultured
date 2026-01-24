extends Resource
class_name HeartProgressData

@export var domains: Array[HeartDomainData] = []

# NEW: counters persistently tracked (like save)
@export var counters: Dictionary = {}   # e.g. { "harvest_crop": 7, "gift_item": 2 }

func get_domain(domain_id: String) -> HeartDomainData:
	for d in domains:
		if d != null and d.id == domain_id:
			return d
	return null

func inc_counter(key: String, amount: int = 1) -> int:
	if key.strip_edges() == "":
		return 0
	counters[key] = int(counters.get(key, 0)) + amount
	return int(counters[key])

func get_counter(key: String) -> int:
	return int(counters.get(key, 0))
