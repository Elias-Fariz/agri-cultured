# HeartProgress.gd
# Autoload name: HeartProgress
extends Node

signal changed
signal milestone_completed(domain_id: String, milestone_id: String)

const DEF_PATH := "res://data/heart/heart_definition.tres"
const SAVE_PATH := "res://data/heart/heart_progress.tres"

# -------------------------------------------------------------------------
# DEV / TESTING SWITCHES (flip these while you iterate)
# -------------------------------------------------------------------------
# If true: never save progress to disk. (Your reveal can be tested repeatedly.)
const DEV_DISABLE_SAVE := true

# If true: ignore what's in heart_progress.tres and start fresh each run.
# (Useful when the file already has old data.)
const DEV_FORCE_FRESH_ON_START := false

# If true: when starting fresh, also clear milestone completion.
const DEV_CLEAR_MILESTONES_ON_FRESH := true

# -------------------------------------------------------------------------

var definition: Resource = null
var progress: Resource = null

var counters: Dictionary = {}
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

	# Ensure revealed_milestones exists if the resource supports it
	if progress != null and not ("revealed_milestones" in progress):
		progress.set("revealed_milestones", {})

	# Optionally force a fresh start (for testing)
	if DEV_FORCE_FRESH_ON_START:
		_reset_progress_in_memory()
		print("[HeartProgress] DEV_FORCE_FRESH_ON_START enabled: starting with fresh progress.")
		return

	# Pull existing counters from progress resource
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

	# Normalize numeric counters only (avoid breaking any arrays you store)
	for k in counters.keys():
		if typeof(counters[k]) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			counters[k] = int(counters[k])

	for k2 in item_counters.keys():
		item_counters[k2] = int(item_counters[k2])

	print("[HeartProgress] Loaded. counters=", counters, " item_counters=", item_counters)


func _reset_progress_in_memory() -> void:
	counters = {}
	item_counters = {}

	if progress != null:
		# Clear persisted dictionaries (in-memory only unless you save)
		if "counters" in progress:
			progress.set("counters", {})
		if "item_counters" in progress:
			progress.set("item_counters", {})
		if "revealed_milestones" in progress:
			progress.set("revealed_milestones", {})

		if DEV_CLEAR_MILESTONES_ON_FRESH and ("completed_milestones" in progress):
			progress.set("completed_milestones", {})

	emit_signal("changed")


# -----------------------------------------------------------------------------
# Public: reset (for testing)
# -----------------------------------------------------------------------------
func reset_progress_runtime(save_after: bool = false) -> void:
	_reset_progress_in_memory()
	if save_after:
		_save_progress_if_possible()
	print("[HeartProgress] reset_progress_runtime(save_after=%s)" % str(save_after))


# -----------------------------------------------------------------------------
# Signal wiring (matches YOUR QuestEvents.gd)
# -----------------------------------------------------------------------------
func _connect_signals() -> void:
	var qe := get_tree().root.get_node_or_null("/root/QuestEvents")
	if qe == null:
		push_warning("HeartProgress: QuestEvents autoload not found at /root/QuestEvents")
		return

	if qe.has_signal("crop_harvested"):
		var cb := Callable(self, "_on_crop_harvested")
		if not qe.is_connected("crop_harvested", cb):
			qe.connect("crop_harvested", cb)
			print("[HeartProgress] Connected: QuestEvents.crop_harvested")

	_try_connect(qe, "item_shipped", "_on_item_shipped")
	_try_connect(qe, "item_crafted", "_on_item_crafted")
	_try_connect(qe, "item_gifted", "_on_item_gifted")


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
	_add_action("harvest", amount)
	_add_item(item_id, amount)

	# Starter milestone hook (keep as-is)
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
# Milestone tracking
# -----------------------------------------------------------------------------
func _mark_milestone_done_if_supported(domain_id: String, milestone_id: String) -> void:
	if domain_id == "" or milestone_id == "":
		return

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
# Reveal history (presentation layer)
# -----------------------------------------------------------------------------
func _make_reveal_key(domain_id: String, milestone_id: String) -> String:
	return "%s:%s" % [domain_id, milestone_id]


func is_revealed(domain_id: String, milestone_id: String) -> bool:
	if progress == null:
		return false
	if not ("revealed_milestones" in progress):
		progress.set("revealed_milestones", {})

	var rm: Dictionary = progress.get("revealed_milestones")
	if rm == null:
		rm = {}
		progress.set("revealed_milestones", rm)

	var key := _make_reveal_key(domain_id, milestone_id)
	return rm.get(key, false) == true


func mark_revealed(domain_id: String, milestone_id: String) -> void:
	if progress == null:
		return
	if not ("revealed_milestones" in progress):
		progress.set("revealed_milestones", {})

	var rm: Dictionary = progress.get("revealed_milestones")
	if rm == null:
		rm = {}
		progress.set("revealed_milestones", rm)

	var key := _make_reveal_key(domain_id, milestone_id)
	if rm.get(key, false) == true:
		return

	rm[key] = true
	progress.set("revealed_milestones", rm)
	_save_progress_if_possible()
	emit_signal("changed")


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
	if DEV_DISABLE_SAVE:
		# DEV: do not persist while testing
		return

	var err := ResourceSaver.save(progress, SAVE_PATH)
	if err != OK:
		push_warning("HeartProgress: Could not save progress to %s (err=%s)" % [SAVE_PATH, str(err)])
