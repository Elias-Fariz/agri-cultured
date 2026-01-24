# HeartProgress.gd
# Autoload name: HeartProgress
extends Node

signal changed
signal milestone_completed(domain_id: String, milestone_id: String)

# You said these paths are correct in your project
const DEF_PATH := "res://data/heart/heart_definition.tres"
const SAVE_PATH := "res://data/heart/heart_progress.tres"

var definition: Resource = null
var progress: Resource = null

# Canonical action counters (match Quest system action ids!)
# e.g. "harvest", "ship", "craft", "gift", "chop_tree", etc.
var counters: Dictionary = {}

# Optional: per-item breakdown (handy later for milestones like "harvest 10 strawberries")
var item_counters: Dictionary = {} # item_id -> int


func _ready() -> void:
	_load_resources()
	_connect_signals()
	emit_signal("changed")


# -----------------------------------------------------------------------------
# Loading
# -----------------------------------------------------------------------------
func _load_resources() -> void:
	definition = load(DEF_PATH)
	if definition == null:
		push_error("HeartProgress: Could not load definition: %s" % DEF_PATH)

	progress = load(SAVE_PATH)
	if progress == null:
		push_warning("HeartProgress: Could not load progress: %s (runtime only for now)" % SAVE_PATH)

	# Pull existing counters if your progress resource has them
	if progress != null:
		if "counters" in progress:
			counters = progress.get("counters")
		elif "action_counts" in progress:
			counters = progress.get("action_counts")

		if "item_counters" in progress:
			item_counters = progress.get("item_counters")

	if counters == null:
		counters = {}
	if item_counters == null:
		item_counters = {}

	# Normalize to ints
	for k in counters.keys():
		counters[k] = int(counters[k])
	for k2 in item_counters.keys():
		item_counters[k2] = int(item_counters[k2])

	print("[HeartProgress] Loaded. counters=", counters, " item_counters=", item_counters)


# -----------------------------------------------------------------------------
# Signal wiring (matches YOUR QuestEvents.gd)
# -----------------------------------------------------------------------------
func _connect_signals() -> void:
	var qe := get_tree().root.get_node_or_null("/root/QuestEvents")
	if qe == null:
		push_warning("HeartProgress: QuestEvents autoload not found at /root/QuestEvents")
		return

	# ✅ This is your real harvest signal
	if qe.has_signal("crop_harvested"):
		var cb := Callable(self, "_on_crop_harvested")
		if not qe.is_connected("crop_harvested", cb):
			qe.connect("crop_harvested", cb)
			print("[HeartProgress] Connected: QuestEvents.crop_harvested")

	# Optional: future-proof hooks (only connect if they exist)
	_try_connect(qe, "item_shipped", "_on_item_shipped")     # (item_id, qty)
	_try_connect(qe, "item_crafted", "_on_item_crafted")     # (item_id, qty)
	_try_connect(qe, "item_gifted", "_on_item_gifted")       # (npc_id, item_id, qty)

func _try_connect(obj: Object, sig: String, method: String) -> void:
	if obj == null:
		return
	if not obj.has_signal(sig):
		return
	var cb := Callable(self, method)
	if obj.is_connected(sig, cb):
		return
	obj.connect(sig, cb)
	print("[HeartProgress] Connected: QuestEvents.%s" % sig)


# -----------------------------------------------------------------------------
# Incoming events -> canonical action ids
# -----------------------------------------------------------------------------
func _on_crop_harvested(item_id: String, amount: int) -> void:
	# Your quest system uses action id "harvest"
	_add_action("harvest", amount)
	_add_item(item_id, amount)

	# Minimal “first sprout” rule (safe starter)
	# Once your heart_definition milestones are fully wired, we can remove this.
	if get_count("harvest") >= 1:
		_mark_milestone_done_if_supported("land", "sprout_1_harvest_1")

	emit_signal("changed")

func _on_item_shipped(item_id: String, amount: int) -> void:
	_add_action("ship", amount)
	_add_item(item_id, amount)
	emit_signal("changed")

func _on_item_crafted(item_id: String, amount: int) -> void:
	_add_action("craft", amount)
	_add_item(item_id, amount)
	emit_signal("changed")

func _on_item_gifted(_npc_id: String, item_id: String, amount: int) -> void:
	_add_action("gift", amount)
	_add_item(item_id, amount)
	emit_signal("changed")


# -----------------------------------------------------------------------------
# Counters
# -----------------------------------------------------------------------------
func _add_action(action_id: String, amount: int) -> void:
	action_id = action_id.strip_edges()
	if action_id == "" or amount <= 0:
		return

	counters[action_id] = int(counters.get(action_id, 0)) + int(amount)
	_mirror_into_progress()
	_save_progress_if_possible()

func _add_item(item_id: String, amount: int) -> void:
	item_id = item_id.strip_edges()
	if item_id == "" or amount <= 0:
		return

	item_counters[item_id] = int(item_counters.get(item_id, 0)) + int(amount)
	_mirror_into_progress()
	_save_progress_if_possible()

func get_count(action_id: String) -> int:
	return int(counters.get(action_id, 0))

func get_item_count(item_id: String) -> int:
	return int(item_counters.get(item_id, 0))


# -----------------------------------------------------------------------------
# Milestone tracking (compatible with your “completed_milestones” style if present)
# -----------------------------------------------------------------------------
func _mark_milestone_done_if_supported(domain_id: String, milestone_id: String) -> void:
	if domain_id == "" or milestone_id == "":
		return

	# Preferred: progress.completed_milestones[domain_id] = [milestone_ids...]
	if progress != null and ("completed_milestones" in progress):
		var cm: Dictionary = progress.get("completed_milestones")
		if cm == null:
			cm = {}

		var arr: Array = cm.get(domain_id, [])
		if arr == null:
			arr = []

		if not arr.has(milestone_id):
			arr.append(milestone_id)
			cm[domain_id] = arr
			progress.set("completed_milestones", cm)
			_save_progress_if_possible()
			emit_signal("milestone_completed", domain_id, milestone_id)
		return

	# Fallback: store done milestones in memory
	var key := "__milestones_done__%s" % domain_id
	var done: Array = counters.get(key, [])
	if done == null:
		done = []
	if not done.has(milestone_id):
		done.append(milestone_id)
		counters[key] = done
		emit_signal("milestone_completed", domain_id, milestone_id)

func has_milestone(domain_id: String, milestone_id: String) -> bool:
	if progress != null and ("completed_milestones" in progress):
		var cm: Dictionary = progress.get("completed_milestones")
		if cm != null:
			var arr: Array = cm.get(domain_id, [])
			return arr != null and arr.has(milestone_id)

	var key := "__milestones_done__%s" % domain_id
	var done: Array = counters.get(key, [])
	return done != null and done.has(milestone_id)


# -----------------------------------------------------------------------------
# Persist (editor-friendly; later we migrate to user://)
# -----------------------------------------------------------------------------
func _mirror_into_progress() -> void:
	if progress == null:
		return
	if "counters" in progress:
		progress.set("counters", counters)
	if "item_counters" in progress:
		progress.set("item_counters", item_counters)

func _save_progress_if_possible() -> void:
	if progress == null:
		return
	var err := ResourceSaver.save(progress, SAVE_PATH)
	if err != OK:
		push_warning("HeartProgress: Could not save progress to %s (err=%s)" % [SAVE_PATH, str(err)])
