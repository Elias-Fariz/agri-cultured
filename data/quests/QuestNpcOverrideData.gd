extends Resource
class_name QuestNpcOverrideData

# Which NPC this override is for
@export var npc_id: String = ""

# What phase of the quest this applies to.
# Recommended values:
# - "active_any"
# - "active_step"
# - "turn_in_ready"
# - "completed_unclaimed"
# - "completed_claimed"
@export var phase: String = "active_any"

# If phase == "active_step", this can target a specific chain step.
# -1 means "any step"
@export var step_index: int = -1

# Simple current-use lines (works with your current DialogueUI)
@export var lines: Array[String] = []

# Future-friendly staged/voiced entries
@export var dialogue_entries: Array[QuestDialogueEntryData] = []

func matches_phase(query_phase: String, query_step_index: int = -1) -> bool:
	if phase != query_phase:
		return false

	if phase == "active_step":
		if step_index != -1 and query_step_index != step_index:
			return false

	return true

func has_any_content() -> bool:
	return not lines.is_empty() or not dialogue_entries.is_empty()
