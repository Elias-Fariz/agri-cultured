# res://data/heart/HeartMilestoneData.gd
extends Resource
class_name HeartMilestoneData

@export var id: String = ""                 # unique: "land_sprout_2"
@export var domain_id: String = "land"      # "land", "sea", etc.
@export var kind: String = "sprout"         # "sprout" or "root"
@export var order: int = 1                  # 1..N for visuals like Sprout1, Sprout2...

@export var counter_key: String = ""        # "harvest_crop", "craft_item", "gift_item"
@export var required_amount: int = 1

@export var filter_item_id: String = ""     # optional: "Strawberry" or ""
@export var filter_npc_id: String = ""      # optional: "npc_mayor" or ""
@export var hint: String = ""               # shown in UI when next
@export var reward_travel_unlock: String = ""  # optional unlock id, like "valley_heart"
