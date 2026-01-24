# HeartVisualBinding.gd
extends Resource
class_name HeartVisualBinding

@export var node_path: NodePath

# Option A: milestone check (best long-term)
@export var domain_id: String = ""       # e.g. "land"
@export var milestone_id: String = ""    # e.g. "sprout_1_harvest_1"

# Option B: action counter check (useful while definitions are still evolving)
@export var action_id: String = ""       # e.g. "harvest"
@export var amount_required: int = 0     # e.g. 1
