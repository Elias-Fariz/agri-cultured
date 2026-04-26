extends Resource
class_name RestorationEncounterData

@export var encounter_id: String = "fearroot_01"
@export var display_name: String = "Fearroot Disturbance"

# Story encounters should usually restore once and stay restored.
# Repeatable encounters can return after respawn_days.
@export var story_one_shot: bool = true
@export var respawn_days: int = 2

# Player combat steadiness.
@export var max_resolve: int = 4

# Core restoration amount.
# Think of this as "how many successful Heartblade openings are needed."
@export var max_instability: int = 3

# Core timing.
@export var core_open_duration: float = 1.2
@export var time_between_patterns: float = 0.35

# If true, the encounter pauses world time without freezing player movement.
@export var pause_time_during_encounter: bool = true

# Gentle failure penalty.
@export var failure_energy_loss: int = 1

# Adaptive kindness.
@export var adaptive_difficulty_enabled: bool = true
@export var easier_after_failures: int = 2

# Pattern list for this encounter.
@export var patterns: Array[RestorationPatternData] = []

# Rewards: { "Calm Root Fiber": 2, "Heart Sap": 1 }
@export var rewards: Dictionary = {}

@export var failure_time_loss_minutes: int = 20
