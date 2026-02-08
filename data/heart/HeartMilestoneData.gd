# res://data/heart/HeartMilestoneData.gd
extends Resource
class_name HeartMilestoneData

@export var id: String = ""                 # unique: "land_sprout_2"
@export var domain_id: String = "land"      # "land", "sea", etc.
@export var kind: String = "sprout"         # "sprout" or "root"

# Used for BOTH:
# 1) sequencing progression (unlock gate)
# 2) visuals like Sprout1, Sprout2... Root1, Root2...
@export var order: int = 1                  # 1..N

@export var counter_key: String = ""        # "harvest", "ship", "go_to", "pickup", etc.
@export var required_amount: int = 1

@export var filter_item_id: String = ""     # optional: "Strawberry", "Shell", or "beach" for go_to
@export var filter_npc_id: String = ""      # optional: "npc_mayor" or ""

@export var hint: String = ""               # shown in UI when next
@export var reward_travel_unlock: String = ""  # optional unlock id, like "valley_heart"
@export var reward_ids: Array[StringName] = []

# ------------------------------------------------------------------
# NEW: ordering controls (optional, safe defaults)
# ------------------------------------------------------------------

# If true, this milestone cannot complete until all lower orders in the SAME domain+kind are complete.
@export var enforce_sequential_in_lane: bool = true

# Optional explicit prerequisites (lets you build “trees” later)
# Example: sprout milestone requires "sea_root_1"
@export var prerequisite_ids: Array[String] = []

# Optional cross-lane gating:
# Example: sprouts require root tier 1 before they can complete
@export var requires_kind: String = ""        # "root" or "sprout" or ""
@export var requires_order_at_least: int = 0  # 0 = ignore
