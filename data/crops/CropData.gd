# res://crops/CropData.gd
extends Resource
class_name CropData

@export var crop_id: String = ""  # e.g. "watermelon" (lowercase key)
@export var display_name: String = "" # optional, for UI later

# IMPORTANT:
# This lets you avoid the "one huge atlas forever" problem.
# You can put different crops in different TileSet atlas sources (different textures),
# and just set source_id per crop here.
@export var tile_source_id: int = 1  # default: your crops_source_id

# Stages in the atlas (Vector2i coords)
@export var stage_atlas_coords: Array[Vector2i] = []
@export var days_per_stage: Array[int] = []   # same length as stage_atlas_coords

# Water rules
@export var ignore_water_after_stage: int = -1  # -1 means never ignore

# Harvest rules (simple + advanced)
@export var harvest_item: String = ""
@export var harvest_yield: int = 1
@export var harvest_yield_min: int = 0
@export var harvest_yield_max: int = 0

@export var harvestable_stages: Array[int] = []  # if empty, final stage harvestable
@export var harvest_items_by_stage: Dictionary = {}   # { stage(int): "ItemID" }
@export var harvest_yields_by_stage: Dictionary = {}  # { stage(int): yield(int) }

# Regrow
@export var regrow_to_stage: int = -1  # -1 means no regrow
@export var regrow_days: int = 1

# Ripe/overripe indicators
@export var ripe_stage: int = -1
@export var overripe_stage: int = -1

# Seasonal tuning (gentle knobs)
@export var allowed_seasons: Array[String] = ["Sunwake", "Duskhaven"]  # keep cozy: allow both unless you WANT gating
@export var duskhaven_chill_chance: float = 0.0  # 0.0..1.0 (chance to "not tick" a day)
@export var sunwake_stage_days_bonus: int = 0     # subtract days (min 1)
@export var duskhaven_stage_days_penalty: int = 0 # add days

@export var sunwake_yield_multiplier: float = 1.0
@export var duskhaven_yield_multiplier: float = 1.0

func is_valid() -> bool:
	return crop_id.strip_edges() != "" and stage_atlas_coords.size() > 0 and days_per_stage.size() == stage_atlas_coords.size()
