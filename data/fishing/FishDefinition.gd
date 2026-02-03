extends Resource
class_name FishDefinition

@export var fish_item_id: String = "Fish"
@export var display_name: String = "Fish"

# Difficulty knobs (scales beautifully later)
@export var sequence_len: int = 3
@export var time_limit: float = 3.0
@export var mistakes_allowed: int = 1

# Optional: chance weighting per spot
@export var weight: int = 10
