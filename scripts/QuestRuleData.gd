extends Resource
class_name QuestRuleData


@export var rule_id: String = ""

@export var quest: QuestData


@export_group("Automatic Grant")

# If greater than 0, this quest is automatically granted
# only when this exact day begins.
#
# 0 means the rule can be evaluated on any day.
@export var grant_on_day: int = 0

# Whether this rule is currently enabled.
@export var enabled: bool = true


func can_grant(current_day: int) -> bool:
	if not enabled:
		return false

	if quest == null:
		return false

	var quest_id := String(quest.id).strip_edges()

	if quest_id == "":
		return false

	# Exact-day rule.
	if grant_on_day > 0:
		if current_day != grant_on_day:
			return false

	# Never grant duplicates.
	if GameState.active_quests.has(quest_id):
		return false

	if GameState.completed_quests.has(quest_id):
		return false

	# Let QuestData handle its normal prerequisites:
	# day minimum, completed quests, flags, friendship, festival, etc.
	if not quest.is_unlocked():
		return false

	return true
