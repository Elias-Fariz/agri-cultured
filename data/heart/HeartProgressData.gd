# HeartProgressData.gd
extends Resource
class_name HeartProgressData

@export var domains: Array[HeartDomainData] = []

# ✅ Add this (the real source of truth)
@export var completed_milestones: Dictionary = {} # domain_id -> Array[String]

# Presentation layer: "Have we already played the reveal moment?"
# Key format: "domain_id:milestone_id" -> true
@export var revealed_milestones: Dictionary = {}

# ✅ Optional but recommended if you're doing rewards
@export var unlocked_rewards: Dictionary = {}     # reward_id -> bool

# Persistent counters (save-like)
@export var counters: Dictionary = {}   # e.g. { "harvest": 7, "gift": 2 }

# Optional: if you later want per-item persistence here too
@export var item_counters: Dictionary = {}  # item_id -> int


func get_domain(domain_id: String) -> HeartDomainData:
	for d in domains:
		if d != null and d.id == domain_id:
			return d
	return null


func inc_counter(key: String, amount: int = 1) -> int:
	key = key.strip_edges()
	if key == "":
		return 0
	counters[key] = int(counters.get(key, 0)) + int(amount)
	return int(counters[key])


func get_counter(key: String) -> int:
	key = key.strip_edges()
	if key == "":
		return 0
	return int(counters.get(key, 0))
