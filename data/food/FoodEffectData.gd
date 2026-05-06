extends Resource
class_name FoodEffectData

enum EffectKey {
	NONE,

	# Fishing
	FISHING_TIME_BONUS,
	FISHING_MISTAKE_BONUS,
	FISHING_SEQUENCE_REDUCTION,

	# Mining
	MINING_HARMONY_BONUS,
	MINING_FORGIVE_MISTAKE,
	MINING_BONUS_DROP_CHANCE,

	# Restoration combat
	COMBAT_RESOLVE_BONUS,
	COMBAT_FIRST_HIT_SHIELD,

	# General tools / farming
	TOOL_ENERGY_DISCOUNT,
	
	# General player/day buffs
	MOVEMENT_SPEED_MULTIPLIER,
	MAX_ENERGY_BONUS,
	ENERGY_SOFT_RECOVERY,
}

enum DurationMode {
	NEXT_USE,       # consumed on one matching use
	NEXT_N_USES,    # consumed after N matching uses
	NEXT_SESSION,   # consumed by next chamber/encounter/session
	TIMED,          # lasts for in-game minutes; wired later
	UNTIL_SLEEP,    # lasts until day changes; wired later
}

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export var effect_key: EffectKey = EffectKey.NONE

# Generic value.
# Examples:
# +1 second fishing time
# +1 resolve
# +5% bonus drop chance
@export var amount: float = 0.0

@export var duration_mode: DurationMode = DurationMode.NEXT_USE

# Used when duration_mode == NEXT_N_USES.
@export var uses: int = 1

# Used when duration_mode == TIMED.
# Example: 180 = 3 in-game hours, depending on your TimeManager minute scale.
@export var duration_minutes: int = 0

# Optional category.
# This lets us later prevent stacking too many similar buffs.
# Examples: "fishing", "mining", "combat", "tool"
@export var category: String = ""


func is_valid() -> bool:
	return id.strip_edges() != "" and effect_key != EffectKey.NONE


func get_effect_key_name() -> String:
	match effect_key:
		EffectKey.FISHING_TIME_BONUS:
			return "Fishing Time Bonus"
		EffectKey.FISHING_MISTAKE_BONUS:
			return "Fishing Mistake Bonus"
		EffectKey.FISHING_SEQUENCE_REDUCTION:
			return "Fishing Sequence Reduction"
		EffectKey.MINING_HARMONY_BONUS:
			return "Mining Harmony Bonus"
		EffectKey.MINING_FORGIVE_MISTAKE:
			return "Mining Mistake Forgiveness"
		EffectKey.MINING_BONUS_DROP_CHANCE:
			return "Mining Bonus Drop Chance"
		EffectKey.COMBAT_RESOLVE_BONUS:
			return "Resolve Bonus"
		EffectKey.COMBAT_FIRST_HIT_SHIELD:
			return "First Hit Shield"
		EffectKey.TOOL_ENERGY_DISCOUNT:
			return "Tool Energy Discount"
		FoodEffectData.EffectKey.MOVEMENT_SPEED_MULTIPLIER:
			return "Bright Step"
		FoodEffectData.EffectKey.MAX_ENERGY_BONUS:
			return "Gentle Endurance"
		FoodEffectData.EffectKey.ENERGY_SOFT_RECOVERY:
			return "Soft Recovery"
		_:
			return "Effect"


func get_duration_text() -> String:
	match duration_mode:
		DurationMode.NEXT_USE:
			return "Next use"
		DurationMode.NEXT_N_USES:
			return "Next %d uses" % max(1, uses)
		DurationMode.NEXT_SESSION:
			return "Next session"
		DurationMode.TIMED:
			return "%d in-game minutes" % max(1, duration_minutes)
		DurationMode.UNTIL_SLEEP:
			return "Until sleep"
		_:
			return ""


func get_display_line() -> String:
	var name := display_name
	if name.strip_edges() == "":
		name = get_effect_key_name()

	var duration := get_duration_text()

	if duration.strip_edges() == "":
		return "%s" % name

	return "%s — %s" % [name, duration]
