extends Resource
class_name CutsceneRuleData

@export var rule_id: String = ""

# What triggers it
@export var location_id: String = ""

# What to play
@export var cutscene_id: String = ""

# Behavior
@export var play_immediately: bool = true
@export var one_shot: bool = true

# Conditions
@export var required_completed_quests: Array[String] = []
@export var required_day: int = 0
@export var required_festival_id: String = ""
