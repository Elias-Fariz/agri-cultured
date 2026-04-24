extends Node

@export var rule_db: CutsceneRuleDB

func _ready() -> void:
	if QuestEvents != null:
		QuestEvents.went_to.connect(_on_location_entered)

func _on_location_entered(location_id: String) -> void:
	print("CutsceneRouter: entered location:", location_id)
	if rule_db == null:
		push_warning("CutsceneEventRouter: rule_db is not assigned!")
		return
	
	print("kept going")
	
	for rule in rule_db.rules:
		print("Checking rule:", rule.rule_id)
		if not _matches_location(rule, location_id):
			continue

		if not _passes_conditions(rule):
			continue

		if _should_skip_one_shot(rule):
			continue

		print("TRIGGERING CUTSCENE:", rule.cutscene_id)
		_trigger_rule(rule)
		return  # first match wins (your preference!)

func _matches_location(rule: CutsceneRuleData, location_id: String) -> bool:
	return rule.location_id == location_id

func _passes_conditions(rule: CutsceneRuleData) -> bool:
	if rule.required_day > 0 and TimeManager != null:
		if int(TimeManager.day) < rule.required_day:
			return false

	for qid in rule.required_completed_quests:
		if GameState == null:
			return false
		if not GameState.completed_quests.has(qid):
			return false

	if rule.required_festival_id.strip_edges() != "":
		if FestivalManager == null:
			return false
		if not FestivalManager.is_festival_today():
			return false
		if FestivalManager.get_current_festival_id() != rule.required_festival_id:
			return false

	return true

func _should_skip_one_shot(rule: CutsceneRuleData) -> bool:
	if not rule.one_shot:
		return false

	if GameState != null and GameState.has_method("has_played_cutscene"):
		return GameState.has_played_cutscene(rule.cutscene_id)

	return false

func _trigger_rule(rule: CutsceneRuleData) -> void:
	if rule.play_immediately and _can_play_now():
		_play_now(rule)
	else:
		_queue(rule)

func _can_play_now() -> bool:
	if CutsceneDirector == null:
		return false

	if CutsceneDirector.has_method("is_playing_cutscene"):
		if CutsceneDirector.is_playing_cutscene():
			return false

	if GameState != null and GameState.has_method("is_gameplay_locked"):
		if GameState.is_gameplay_locked():
			return false

	return true
	
func _play_now(rule: CutsceneRuleData) -> void:
	CutsceneDirector.play_cutscene(rule.cutscene_id)

	if rule.one_shot:
		GameState.mark_cutscene_played(rule.cutscene_id)
		
func _queue(rule: CutsceneRuleData) -> void:
	GameState.queue_pending_cutscene(rule.cutscene_id, rule.one_shot)
