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

# -------------------------------------------------------------------
# Optional conditions
# -------------------------------------------------------------------
#
# These are ALL optional.
# Leaving them at their defaults preserves the old override behavior.

@export_group("Conditions")

# If non-empty, this override can check the player's inventory.
@export var condition_item_id: String = ""

# Minimum amount used by the inventory check.
@export_range(1, 999, 1)
var condition_item_amount: int = 1

# If true, the player must NOT have condition_item_id.
@export var require_item_missing: bool = false

# If > 0, this override only applies when the player CANNOT afford
# this amount.
#
# 0 = ignore money completely.
@export var require_cannot_afford: int = 0

# Optional required flag.
@export var require_flag: String = ""

# Optional blocking flag.
# Useful for one-shot safety nets.
@export var blocked_by_flag: String = ""

# -------------------------------------------------------------------
# Legacy/simple content
# -------------------------------------------------------------------

# Simple current-use lines (works with your current DialogueUI)
@export var lines: Array[String] = []

# Slightly richer per-line entries (future-friendly, but still lightweight)
@export var dialogue_entries: Array[DialogueBeatData] = []

# -------------------------------------------------------------------
# Preferred richer content
# -------------------------------------------------------------------

# Full authored sequence for this override.
# This is the best place for special quest scenes and staged exchanges.
@export var sequence: DialogueSequenceData

func matches_phase(
	query_phase: String,
	query_step_index: int = -1
) -> bool:
	if phase != query_phase:
		return false

	if phase == "active_step":
		if (
			step_index != -1
			and query_step_index != step_index
		):
			return false

	if not conditions_met():
		return false

	return true

func has_any_content() -> bool:
	if sequence != null and sequence.has_beats():
		return true

	if not dialogue_entries.is_empty():
		return true

	if not lines.is_empty():
		return true

	return false

func get_best_plain_lines() -> Array[String]:
	# 1) Best: full sequence flattened to plain lines
	if sequence != null and sequence.has_beats():
		return sequence.to_plain_lines()

	# 2) Next: dialogue entries flattened to plain lines
	if not dialogue_entries.is_empty():
		var out: Array[String] = []
		for beat in dialogue_entries:
			if beat == null:
				continue
			if not beat.has_text():
				continue
			out.append(beat.text)
		if not out.is_empty():
			return out

	# 3) Fallback: plain lines
	return lines

func get_sequence() -> DialogueSequenceData:
	return sequence

func conditions_met() -> bool:
	# -------------------------------------------------
	# Required flag
	# -------------------------------------------------
	var needed_flag := require_flag.strip_edges()

	if needed_flag != "":
		if GameState == null:
			return false

		if not GameState.has_flag(needed_flag):
			return false


	# -------------------------------------------------
	# Blocking / already-used flag
	# -------------------------------------------------
	var blocked_flag := blocked_by_flag.strip_edges()

	if blocked_flag != "":
		if GameState != null and GameState.has_flag(blocked_flag):
			return false


	# -------------------------------------------------
	# Inventory condition
	# -------------------------------------------------
	var item_id := condition_item_id.strip_edges()

	if item_id != "" and require_item_missing:
		if GameState == null:
			return false

		if GameState.inventory_has(
			item_id,
			max(1, condition_item_amount)
		):
			return false


	# -------------------------------------------------
	# Money condition
	# -------------------------------------------------
	if require_cannot_afford > 0:
		if MoneySystem == null:
			return false

		if MoneySystem.can_afford(require_cannot_afford):
			return false


	return true
