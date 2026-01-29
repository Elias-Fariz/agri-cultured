extends Resource
class_name HeartRewardDefinition

enum RewardKind {
	STAT_ADD,        # +X to a stat (e.g. inventory slots +1)
	STAT_MULTIPLY,   # multiply a stat (e.g. sell multiplier 1.05)
	FLAG_SET,        # set a boolean flag
	UNLOCK_TRAVEL,   # calls GameState.unlock_travel(travel_id)
	TOAST            # just shows a toast (useful while prototyping)
}

@export var id: StringName
@export var kind: RewardKind = RewardKind.STAT_ADD

# Which milestone grants this reward
@export var domain_id: String = ""
@export var milestone_id: String = ""

# Generic payload (keeps this future-proof)
@export var stat_key: StringName = &""
@export var amount: float = 0.0
@export var flag_key: StringName = &""
@export var flag_value: bool = true
@export var travel_id: StringName = &""

@export_multiline var description: String = ""
