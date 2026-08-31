extends Node


const QUEST_RULE_SET_PATH := (
	"res://data/quests/slice/quest_rules.tres"
)


var _rule_set: QuestRuleSetData = null


func _ready() -> void:
	_load_rule_set()

	if TimeManager != null:
		if not TimeManager.day_changed.is_connected(
			_on_day_changed
		):
			TimeManager.day_changed.connect(
				_on_day_changed
			)

	# Important:
	# TimeManager may have emitted its initial day_changed signal
	# before this autoload connected.
	#
	# Evaluate once manually so direct Day 2/debug starts still work.
	call_deferred("_evaluate_current_day")


func _load_rule_set() -> void:
	var loaded := load(QUEST_RULE_SET_PATH)

	if loaded == null:
		push_warning(
			"QuestRuleManager: Could not load quest rule set: "
			+ QUEST_RULE_SET_PATH
		)
		return

	if not loaded is QuestRuleSetData:
		push_warning(
			"QuestRuleManager: Resource is not QuestRuleSetData: "
			+ QUEST_RULE_SET_PATH
		)
		return

	_rule_set = loaded as QuestRuleSetData


func _on_day_changed(new_day: int) -> void:
	# Give other new-day systems one frame to finish their work first.
	call_deferred(
		"_evaluate_rules_for_day",
		new_day
	)


func _evaluate_current_day() -> void:
	if TimeManager == null:
		return

	await get_tree().process_frame

	_evaluate_rules_for_day(
		int(TimeManager.day)
	)


func _evaluate_rules_for_day(day_value: int) -> void:
	if _rule_set == null:
		return

	for rule in _rule_set.rules:
		if rule == null:
			continue

		if not rule.can_grant(day_value):
			continue

		_grant_rule_quest(rule)


func _grant_rule_quest(rule: QuestRuleData) -> void:
	if rule == null:
		return

	if rule.quest == null:
		return

	var quest_id := String(
		rule.quest.id
	).strip_edges()

	if quest_id == "":
		return

	GameState.add_quest(
		rule.quest.to_dict()
	)
