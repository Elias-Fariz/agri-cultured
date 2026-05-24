extends Resource
class_name CutsceneRuleData

@export var rule_id: String = ""

# -------------------------------------------------------------------
# Trigger
# -------------------------------------------------------------------

# Existing field, kept for backward compatibility.
# Example: "farm", "town_square", "connector_heart_path"
@export var location_id: String = ""

# New clearer alias.
# If trigger_id is filled in, it is used instead of location_id.
@export var trigger_id: String = ""

# -------------------------------------------------------------------
# Cutscene
# -------------------------------------------------------------------

@export var cutscene_id: String = ""

# -------------------------------------------------------------------
# Behavior
# -------------------------------------------------------------------

@export var play_immediately: bool = true
@export var one_shot: bool = true

# If > 0, the rule waits this many in-game days after its required flags
# were set before it can play.
#
# Example:
# - 0 = can play today
# - 1 = can play starting tomorrow
#
# For rules with required_flags, delay is based on the newest required flag day.
# For rules without required_flags, the router arms the rule the first time
# conditions pass and uses that day.
@export var wait_days_after_conditions_met: int = 0

# -------------------------------------------------------------------
# Conditions: quests
# -------------------------------------------------------------------

@export var required_completed_quests: Array[String] = []
@export var blocked_completed_quests: Array[String] = []

# -------------------------------------------------------------------
# Conditions: flags
# -------------------------------------------------------------------

@export var required_flags: Array[String] = []
@export var blocked_flags: Array[String] = []

# -------------------------------------------------------------------
# Conditions: cutscenes
# -------------------------------------------------------------------

@export var required_played_cutscenes: Array[String] = []
@export var blocked_played_cutscenes: Array[String] = []

# -------------------------------------------------------------------
# Conditions: day / time / festival
# -------------------------------------------------------------------

# 0 means no minimum day.
@export var required_day: int = 0

# 0 means no maximum day.
@export var max_day: int = 0

# Optional. Recommended values:
# "", "morning", "day", "evening", "night"
@export var required_time_block: String = ""

@export var required_festival_id: String = ""


func get_effective_trigger_id() -> String:
	var t := trigger_id.strip_edges()
	if t != "":
		return t
	return location_id.strip_edges()


func is_valid() -> bool:
	return get_effective_trigger_id() != "" and cutscene_id.strip_edges() != ""
