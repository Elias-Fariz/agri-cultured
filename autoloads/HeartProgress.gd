# HeartProgress.gd
# Autoload name: HeartProgress
extends Node

signal changed
signal milestone_completed(domain_id: String, milestone_id: String)

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
# Definition lives in res:// (read-only in export, that's fine)
const DEF_PATH := "res://data/heart/heart_definition.tres"

# A default/template progress resource in res:// (ships with the game)
# This is used to create the first user save.
const DEFAULT_PROGRESS_TEMPLATE_PATH := "res://data/heart/heart_progress.tres"

# The actual save path MUST be user:// (writable in export)
const USER_SAVE_PATH := "user://heart_progress.tres"

# -----------------------------------------------------------------------------
# DEV / TESTING SWITCHES
# -----------------------------------------------------------------------------
# If true: never save progress to disk.
const DEV_DISABLE_SAVE := true

# If true: ignore user save and start fresh each run (in-memory).
const DEV_FORCE_FRESH_ON_START := false

# If true: when starting fresh, also clear completed milestones.
const DEV_CLEAR_MILESTONES_ON_FRESH := true

# -----------------------------------------------------------------------------

var definition: Resource = null
var progress: Resource = null

# Canonical counters (quests/actions)
var counters: Dictionary = {}
var item_counters: Dictionary = {} # item_id -> int

# NEW: long-term “stats” for non-action progress (money, friendship, etc.)
# Example keys:
#   "money_earned_total"
#   "friendship:Mayor"
#   "days_played"
var stats: Dictionary = {}


func _ready() -> void:
	_load_resources()
	_connect_signals()
	emit_signal("changed")


# -----------------------------------------------------------------------------
# Loading / initialization
# -----------------------------------------------------------------------------
func _load_resources() -> void:
	definition = load(DEF_PATH)
	if definition == null:
		push_error("HeartProgress: Could not load definition: %s" % DEF_PATH)

	# If we're forcing fresh, do not load user save
	if DEV_FORCE_FRESH_ON_START:
		progress = _make_fresh_progress_resource()
		_reset_progress_in_memory()
		print("[HeartProgress] DEV_FORCE_FRESH_ON_START: using fresh in-memory progress.")
		return

	# Try to load user save; if missing, create it from template (unless DEV_DISABLE_SAVE)
	progress = _load_or_create_user_progress()

	# Pull dictionaries out safely
	_ingest_progress_dicts()
	_normalize_numeric_dicts()

	print("[HeartProgress] Loaded. counters=", counters, " item_counters=", item_counters, " stats=", stats)


func _load_or_create_user_progress() -> Resource:
	# In DEV_DISABLE_SAVE mode, we can just load template into memory and never write.
	if DEV_DISABLE_SAVE:
		var tmpl := load(DEFAULT_PROGRESS_TEMPLATE_PATH)
		if tmpl == null:
			push_warning("HeartProgress: Could not load template progress: %s" % DEFAULT_PROGRESS_TEMPLATE_PATH)
			return _make_fresh_progress_resource()
		return tmpl.duplicate(true)

	# Real mode: load user save if exists
	if ResourceLoader.exists(USER_SAVE_PATH):
		var user_res := load(USER_SAVE_PATH)
		if user_res != null:
			return user_res

	# If it doesn't exist, create from template and save once
	var template := load(DEFAULT_PROGRESS_TEMPLATE_PATH)
	if template == null:
		push_warning("HeartProgress: Could not load template progress: %s" % DEFAULT_PROGRESS_TEMPLATE_PATH)
		return _make_fresh_progress_resource()

	var created := template.duplicate(true)
	_ensure_required_fields(created)

	var err := ResourceSaver.save(created, USER_SAVE_PATH)
	if err != OK:
		push_warning("HeartProgress: Could not write initial user save to %s (err=%s)" % [USER_SAVE_PATH, str(err)])
		# Still return in-memory progress so game runs
	return created


func _make_fresh_progress_resource() -> Resource:
	# Best effort: duplicate template; if missing, just return null.
	var template := load(DEFAULT_PROGRESS_TEMPLATE_PATH)
	if template != null:
		var created := template.duplicate(true)
		_ensure_required_fields(created)
		return created

	# If there's no template, we still run without persistence.
	return null


func _ensure_required_fields(res: Resource) -> void:
	if res == null:
		return
	# Make sure these dictionaries exist (matching your HeartProgressData extensions)
	if not ("counters" in res):
		res.set("counters", {})
	if not ("item_counters" in res):
		res.set("item_counters", {})
	if not ("revealed_milestones" in res):
		res.set("revealed_milestones", {})
	if not ("completed_milestones" in res):
		res.set("completed_milestones", {})
	if not ("stats" in res):
		res.set("stats", {})


func _ingest_progress_dicts() -> void:
	# Start clean
	counters = {}
	item_counters = {}
	stats = {}

	if progress == null:
		return

	_ensure_required_fields(progress)

	counters = progress.get("counters") if ("counters" in progress) else {}
	item_counters = progress.get("item_counters") if ("item_counters" in progress) else {}
	stats = progress.get("stats") if ("stats" in progress) else {}

	if counters == null: counters = {}
	if item_counters == null: item_counters = {}
	if stats == null: stats = {}


func _normalize_numeric_dicts() -> void:
	# Normalize numeric-ish values to ints, but don’t destroy non-numeric variants.
	for k in counters.keys():
		if typeof(counters[k]) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			counters[k] = int(counters[k])

	for k2 in item_counters.keys():
		if typeof(item_counters[k2]) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			item_counters[k2] = int(item_counters[k2])

	for k3 in stats.keys():
		if typeof(stats[k3]) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			stats[k3] = int(stats[k3])


# -----------------------------------------------------------------------------
# Public: reset (testing)
# -----------------------------------------------------------------------------
func reset_progress_runtime(save_after: bool = false) -> void:
	_reset_progress_in_memory()
	if save_after:
		_save_progress_if_possible()
	print("[HeartProgress] reset_progress_runtime(save_after=%s)" % str(save_after))


func _reset_progress_in_memory() -> void:
	counters = {}
	item_counters = {}
	stats = {}

	if progress != null:
		_ensure_required_fields(progress)
		progress.set("counters", {})
		progress.set("item_counters", {})
		progress.set("stats", {})
		progress.set("revealed_milestones", {})

		if DEV_CLEAR_MILESTONES_ON_FRESH:
			progress.set("completed_milestones", {})

	emit_signal("changed")


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


# -----------------------------------------------------------------------------
# Incoming events -> canonical action ids
# -----------------------------------------------------------------------------
func _on_crop_harvested(item_id: String, amount: int) -> void:
	_add_action("harvest", amount)
	_add_item(item_id, amount)

	# Starter milestone hook (keep as-is for now)
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
# NEW: long-term stats API (money, friendship, etc.)
# -----------------------------------------------------------------------------
func get_stat(stat_key: String) -> int:
	return int(stats.get(stat_key, 0))

func add_stat(stat_key: String, amount: int) -> int:
	stat_key = stat_key.strip_edges()
	if stat_key == "":
		return 0
	stats[stat_key] = int(stats.get(stat_key, 0)) + int(amount)
	_mirror_into_progress()
	_save_progress_if_possible()
	emit_signal("changed")
	return int(stats[stat_key])

func set_stat_max(stat_key: String, value: int) -> int:
	stat_key = stat_key.strip_edges()
	if stat_key == "":
		return 0
	stats[stat_key] = max(int(stats.get(stat_key, 0)), int(value))
	_mirror_into_progress()
	_save_progress_if_possible()
	emit_signal("changed")
	return int(stats[stat_key])


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
	_ensure_required_fields(progress)

	var rm: Dictionary = progress.get("revealed_milestones")
	if rm == null:
		rm = {}
		progress.set("revealed_milestones", rm)

	var key := _make_reveal_key(domain_id, milestone_id)
	return rm.get(key, false) == true


func mark_revealed(domain_id: String, milestone_id: String) -> void:
	if progress == null:
		return
	_ensure_required_fields(progress)

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
# Persist
# -----------------------------------------------------------------------------
func _mirror_into_progress() -> void:
	if progress == null:
		return
	_ensure_required_fields(progress)

	progress.set("counters", counters)
	progress.set("item_counters", item_counters)
	progress.set("stats", stats)


func _save_progress_if_possible() -> void:
	if progress == null:
		return
	if DEV_DISABLE_SAVE:
		return

	var err := ResourceSaver.save(progress, USER_SAVE_PATH)
	if err != OK:
		push_warning("HeartProgress: Could not save progress to %s (err=%s)" % [USER_SAVE_PATH, str(err)])

func get_friendship_level(npc_id: String) -> int:
	return get_stat("friendship:%s" % npc_id)

func set_friendship_level(npc_id: String, level: int) -> int:
	# Friendship is usually “highest achieved”
	return set_stat_max("friendship:%s" % npc_id, level)
