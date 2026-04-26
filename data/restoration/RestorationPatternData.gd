extends Resource
class_name RestorationPatternData

enum PatternType {
	CIRCLE_AT_PLAYER,
	CIRCLE_NEAR_CORE,
	LINE_FROM_CORE
}

@export var pattern_id: String = "circle_at_player"
@export var pattern_type: PatternType = PatternType.CIRCLE_AT_PLAYER

# How long the warning appears before it becomes dangerous.
@export var warning_seconds: float = 0.8

# How long the danger remains active.
@export var active_seconds: float = 0.35

# How much Resolve the player loses if hit.
@export var resolve_damage: int = 1

# Circle pattern size.
@export var radius: float = 28.0

# Line pattern size.
@export var line_length: float = 160.0
@export var line_width: float = 28.0

# How many zones to spawn for this pattern.
# For first beta tests, keep this at 1.
@export var spawn_count: int = 1

# Small delay between repeated zones if spawn_count > 1.
@export var spacing_seconds: float = 0.18
