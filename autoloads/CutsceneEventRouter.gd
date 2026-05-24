extends Node

@export var rule_db: CutsceneRuleDB
@export var debug_enabled: bool = false


func _ready() -> void:
	if QuestEvents != null:
		if not QuestEvents.went_to.is_connected(_on_location_entered):
			QuestEvents.went_to.connect(_on_location_entered)


func _on_location_entered(location_id: String) -> void:
	if rule_db == null:
		push_warning("CutsceneEventRouter: rule_db is not assigned!")
		return

	if debug_enabled:
		print("[CutsceneRouter] entered trigger/location:", location_id)

	for rule in rule_db.rules:
		if rule == null:
			continue

		if not rule.is_valid():
			continue

		if not _matches_location(rule, location_id):
			continue

		if not _passes_conditions(rule):
			continue

		if not _passes_delay(rule):
			continue

		if _should_skip_one_shot(rule):
			continue

		if debug_enabled:
			print("[CutsceneRouter] TRIGGERING CUTSCENE:", rule.cutscene_id, " from rule=", rule.rule_id)

		_trigger_rule(rule)
		return # first match wins


func _matches_location(rule: CutsceneRuleData, location_id: String) -> bool:
	return rule.get_effective_trigger_id() == location_id


func _passes_conditions(rule: CutsceneRuleData) -> bool:
	if GameState == null:
		return false

	# -------------------------
	# Day condition
	# -------------------------
	if TimeManager != null:
		var current_day := int(TimeManager.day)

		if rule.required_day > 0 and current_day < rule.required_day:
			return false

		if rule.max_day > 0 and current_day > rule.max_day:
			return false

	# -------------------------
	# Time block condition
	# -------------------------
	var required_block := rule.required_time_block.strip_edges().to_lower()
	if required_block != "":
		if TimeManager == null:
			return false

		if not TimeManager.has_method("get_time_block_key"):
			return false

		var current_block := String(TimeManager.get_time_block_key(TimeManager.minutes)).strip_edges().to_lower()
		if current_block != required_block:
			return false

	# -------------------------
	# Required completed quests
	# -------------------------
	for qid in rule.required_completed_quests:
		qid = qid.strip_edges()
		if qid == "":
			continue

		if not GameState.completed_quests.has(qid):
			return false

	# -------------------------
	# Blocked completed quests
	# -------------------------
	for qid in rule.blocked_completed_quests:
		qid = qid.strip_edges()
		if qid == "":
			continue

		if GameState.completed_quests.has(qid):
			return false

	# -------------------------
	# Required flags
	# -------------------------
	for flag_id in rule.required_flags:
		flag_id = flag_id.strip_edges()
		if flag_id == "":
			continue

		if not GameState.has_flag(flag_id):
			return false

	# -------------------------
	# Blocked flags
	# -------------------------
	for flag_id in rule.blocked_flags:
		flag_id = flag_id.strip_edges()
		if flag_id == "":
			continue

		if GameState.has_flag(flag_id):
			return false

	# -------------------------
	# Required played cutscenes
	# -------------------------
	for cutscene_id in rule.required_played_cutscenes:
		cutscene_id = cutscene_id.strip_edges()
		if cutscene_id == "":
			continue

		if not GameState.has_played_cutscene(cutscene_id):
			return false

	# -------------------------
	# Blocked played cutscenes
	# -------------------------
	for cutscene_id in rule.blocked_played_cutscenes:
		cutscene_id = cutscene_id.strip_edges()
		if cutscene_id == "":
			continue

		if GameState.has_played_cutscene(cutscene_id):
			return false

	# -------------------------
	# Festival condition
	# -------------------------
	if rule.required_festival_id.strip_edges() != "":
		if FestivalManager == null:
			return false

		if not FestivalManager.is_festival_today():
			return false

		if FestivalManager.get_current_festival_id() != rule.required_festival_id:
			return false

	return true


func _passes_delay(rule: CutsceneRuleData) -> bool:
	var wait_days :Variant= max(0, int(rule.wait_days_after_conditions_met))
	if wait_days <= 0:
		return true

	if TimeManager == null:
		return false

	var today := int(TimeManager.day)

	# Best case:
	# If this rule has required flags, use the newest day among those flags.
	# Example:
	# first_crop_harvested set on Day 3
	# wait_days_after_conditions_met = 1
	# cutscene can play on Day 4+
	var newest_flag_day := -1

	for flag_id in rule.required_flags:
		flag_id = flag_id.strip_edges()
		if flag_id == "":
			continue

		if GameState.has_method("get_flag_set_day"):
			var flag_day := int(GameState.get_flag_set_day(flag_id))
			if flag_day > newest_flag_day:
				newest_flag_day = flag_day

	if newest_flag_day >= 0:
		return today >= newest_flag_day + wait_days

	# Fallback:
	# For rules without required_flags, arm the rule the first time all other
	# conditions pass. Then wait from that day.
	var ready_day := -1
	if GameState.has_method("get_cutscene_rule_ready_day"):
		ready_day = int(GameState.get_cutscene_rule_ready_day(rule.rule_id))

	if ready_day < 0:
		if GameState.has_method("mark_cutscene_rule_ready"):
			GameState.mark_cutscene_rule_ready(rule.rule_id, today)

		if debug_enabled:
			print("[CutsceneRouter] Rule armed for later:", rule.rule_id, " day=", today)

		return false

	return today >= ready_day + wait_days


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

	if rule.one_shot and GameState != null:
		GameState.mark_cutscene_played(rule.cutscene_id)

	if GameState != null and GameState.has_method("clear_cutscene_rule_ready"):
		GameState.clear_cutscene_rule_ready(rule.rule_id)


func _queue(rule: CutsceneRuleData) -> void:
	if GameState == null:
		return

	GameState.queue_pending_cutscene(rule.cutscene_id, rule.one_shot)

	if GameState.has_method("clear_cutscene_rule_ready"):
		GameState.clear_cutscene_rule_ready(rule.rule_id)
