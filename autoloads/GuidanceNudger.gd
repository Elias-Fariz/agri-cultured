extends Node

# Prevent spam
var _last_nudge_day: int = -1

func queue_daily_nudge() -> void:
	# Only one nudge per day
	var today := int(TimeManager.day)
	if _last_nudge_day == today:
		return
	_last_nudge_day = today

	var msg := _pick_best_nudge()
	if msg.strip_edges() == "":
		return

	# Use your known-good toast API
	GameState.queue_day_start_toast(msg, "info", 3.5)

func push_nudge_now_after_summary() -> void:
	# Optional: call this when End of Day UI closes instead of morning.
	var msg := _pick_best_nudge()
	if msg.strip_edges() == "":
		return

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(msg, "info", 3.0)

# ------------------------------------------------------------
# Nudge selection logic
# ------------------------------------------------------------
func _pick_best_nudge() -> String:
	# 1) Completed quests that are NOT claimed yet
	var unclaimed := _find_unclaimed_completed_quest_id()
	if unclaimed != "":
		return "💛 A reward is waiting: claim your completed quest when you’re ready."

	# 2) Active quest “next step” (best effort; depends on your quest structure)
	var active_hint := _best_active_quest_hint()
	if active_hint != "":
		return active_hint

	# 3) Valley Heart “next milestone” hint (best effort; depends on helper functions)
	var heart_hint := _best_heart_hint()
	if heart_hint != "":
		return heart_hint

	# 4) Fallback cozy guidance
	return "🌿 A gentle day awaits. Explore, forage, or visit the Heart whenever you feel ready."

func _find_unclaimed_completed_quest_id() -> String:
	# You already have: GameState.completed_quests[id] = { claimed: bool, ... }
	if GameState == null:
		return ""

	if not ("completed_quests" in GameState):
		return ""

	var cq: Dictionary = GameState.completed_quests
	for qid in cq.keys():
		var q :Variant= cq[qid]
		if typeof(q) == TYPE_DICTIONARY:
			if not bool(q.get("claimed", false)):
				return str(qid)
	return ""

func _best_active_quest_hint() -> String:
	if GameState != null and GameState.has_method("get_primary_quest_hint"):
		var hint := str(GameState.call("get_primary_quest_hint")).strip_edges()
		if hint != "":
			return "🧭 " + hint
	return ""

func _best_heart_hint() -> String:
	# Suggested contract:
	# - HeartProgress.get_best_next_hint() -> String
	if HeartProgress != null and HeartProgress.has_method("get_best_next_hint"):
		var hint := str(HeartProgress.call("get_best_next_hint"))
		if hint.strip_edges() != "":
			return "💙 " + hint
	return ""
