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

signal reward_unlocked(reward_id: StringName)

const REWARD_PATH := "res://data/heart/heart_rewards.tres"
var reward_catalog: HeartRewardCatalog = null

# -----------------------------------------------------------------------------
# DEV / TESTING SWITCHES
# -----------------------------------------------------------------------------
# If true: never save progress to disk.
const DEV_DISABLE_SAVE := false

# If true: ignore user save and start fresh each run (in-memory).
const DEV_FORCE_FRESH_ON_START := true

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
	_load_reward_catalog()
	_connect_signals()
	emit_signal("changed")
	
	dev_dump_progress_state("BEFORE CLEAR")
	dev_clear_milestones_and_reveals_runtime()
	dev_dump_progress_state("AFTER CLEAR")
	dev_clear_rewards_runtime(true)



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
	
	if progress != null:
		# Ensure dictionaries exist (prevents Nil issues)
		if not ("completed_milestones" in progress) or progress.get("completed_milestones") == null:
			progress.set("completed_milestones", {})
		if not ("revealed_milestones" in progress) or progress.get("revealed_milestones") == null:
			progress.set("revealed_milestones", {})
		if not ("unlocked_rewards" in progress) or progress.get("unlocked_rewards") == null:
			progress.set("unlocked_rewards", {})
	
	if progress != null:
		print("[HP] completed_milestones=", progress.get("completed_milestones"))
	print("[HP] legacy land=", counters.get("__milestones_done__land", null))
	print("[HP] harvest count=", counters.get("harvest", 0), " ship=", counters.get("ship", 0))
	
	# Pull dictionaries out safely
	_ingest_progress_dicts()
	_normalize_numeric_dicts()

	print("[HeartProgress-BEFORE] Loaded. counters=", counters, " item_counters=", item_counters, " stats=", stats) 
	
	_dev_clear_legacy_milestone_keys()
	_clear_legacy_milestone_lists()
	
	print("[HeartProgress-AFTER] Loaded. counters=", counters, " item_counters=", item_counters, " stats=", stats) 
	
	_evaluate_definition_milestones()


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
	if not ("unlocked_rewards" in res):
		res.set("unlocked_rewards", {})
	if not ("reward_stats" in res):
		res.set("reward_stats", {})
	if not ("reward_flags" in res):
		res.set("reward_flags", {})
	if not ("location_counters" in res):
		res.set("location_counters", {})


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
	location_counters = progress.get("location_counters") if ("location_counters" in progress) else {}
	if location_counters == null: location_counters = {}
	if counters == null: counters = {}
	if item_counters == null: item_counters = {}
	if stats == null: stats = {}
	
	# Keep reward stats inside the resource (not in-memory only)
# We will read/write them via get_reward_stat / _set_reward_stat_* helpers.
	if progress != null:
		if not ("reward_stats" in progress) or progress.get("reward_stats") == null:
			progress.set("reward_stats", {})


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
			
	for k4 in location_counters.keys():
		if typeof(location_counters[k4]) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			location_counters[k4] = int(location_counters[k4])



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

	_clear_legacy_milestone_lists()

	if progress != null:
		if "counters" in progress: progress.set("counters", {})
		if "item_counters" in progress: progress.set("item_counters", {})
		if "revealed_milestones" in progress: progress.set("revealed_milestones", {})
		if "completed_milestones" in progress: progress.set("completed_milestones", {})
		if "unlocked_rewards" in progress: progress.set("unlocked_rewards", {})
		if "reward_stats" in progress: progress.set("reward_stats", {})

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

	_try_connect(qe, "shipped", "_on_item_shipped")
	_try_connect(qe, "item_crafted", "_on_item_crafted")
	_try_connect(qe, "item_gifted", "_on_item_gifted")
	_try_connect(qe, "went_to", "_on_went_to")
	_try_connect(qe, "item_picked_up", "_on_item_picked_up")
	
	# ADD THESE PRINTS:
	if qe.has_signal("went_to"):
		print("[HP SIG] went_to connections: ", qe.get_signal_connection_list("went_to"))
	else:
		print("[HP SIG] QuestEvents is missing signal: went_to")

	if qe.has_signal("item_picked_up"):
		print("[HP SIG] item_picked_up connections: ", qe.get_signal_connection_list("item_picked_up"))
	else:
		print("[HP SIG] QuestEvents is missing signal: item_picked_up")
	
	print("crop_harvested connections:", qe.get_signal_connection_list("crop_harvested"))


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
	# Track total produce harvested (quantity)
	_add_action("harvest", amount)

	# Track distinct harvest events (one per plant harvest action)
	_add_action("harvest_actions", 1)

	_add_item(item_id, amount)
	
	print("[HP] crop_harvested item=", item_id, " amount=", amount)
	
	_evaluate_definition_milestones()
	emit_signal("changed")

func _on_item_shipped(item_id: String, amount: int) -> void:
	_add_action("ship", amount)
	_add_item(item_id, amount)
	
	_evaluate_definition_milestones()
	emit_signal("changed")


func _on_item_crafted(item_id: String, amount: int) -> void:
	_add_action("craft", amount)
	_add_item(item_id, amount)
	
	_evaluate_definition_milestones()
	emit_signal("changed")


func _on_item_gifted(_npc_id: String, item_id: String, amount: int) -> void:
	_add_action("gift", amount)
	_add_item(item_id, amount)
	
	_evaluate_definition_milestones()
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

	# --- Persisted path ---
	if progress != null and ("completed_milestones" in progress):
		var cm_any: Variant = progress.get("completed_milestones")
		if cm_any == null or typeof(cm_any) != TYPE_DICTIONARY:
			cm_any = {}
			progress.set("completed_milestones", cm_any)

		var cm: Dictionary = cm_any
		var arr_any: Variant = cm.get(domain_id, [])
		if arr_any == null or typeof(arr_any) != TYPE_ARRAY:
			arr_any = []

		var arr: Array = arr_any

		if arr.has(milestone_id):
			print("[HP REWARD DBG] milestone already in completed_milestones domain=", domain_id, " id=", milestone_id)
			return

		# Mark complete
		arr.append(milestone_id)
		cm[domain_id] = arr
		progress.set("completed_milestones", cm)

		print("[HP REWARD DBG] milestone completed NOW domain=", domain_id, " id=", milestone_id, " completed_list=", arr)

		_save_progress_if_possible()
		emit_signal("milestone_completed", domain_id, milestone_id)

		# Grant rewards from definition and apply them
		print("[HP REWARD DBG] calling _apply_rewards_for_milestone domain=", domain_id, " id=", milestone_id)
		_apply_rewards_for_milestone(domain_id, milestone_id)

		emit_signal("changed")
		return

	# --- Fallback path (no progress resource) ---
	var key := "__milestones_done__%s" % domain_id
	var done_any: Variant = counters.get(key, [])
	if done_any == null or typeof(done_any) != TYPE_ARRAY:
		done_any = []

	var done: Array = done_any

	if done.has(milestone_id):
		print("[HP REWARD DBG] milestone already in legacy done list domain=", domain_id, " id=", milestone_id)
		return

	done.append(milestone_id)
	counters[key] = done

	print("[HP REWARD DBG] milestone completed NOW (legacy) domain=", domain_id, " id=", milestone_id, " done_list=", done)

	emit_signal("milestone_completed", domain_id, milestone_id)
	print("[HP REWARD DBG] calling _apply_rewards_for_milestone domain=", domain_id, " id=", milestone_id)
	_apply_rewards_for_milestone(domain_id, milestone_id)

	emit_signal("changed")

func has_milestone(domain_id: String, milestone_id: String) -> bool:
	var cm_val = null
	if progress != null and ("completed_milestones" in progress):
		cm_val = progress.get("completed_milestones")

	var legacy_key := "__milestones_done__%s" % domain_id
	var legacy_val = counters.get(legacy_key, null)

	print("[HP] has_milestone ", domain_id, "/", milestone_id,
		" completed_milestones=", cm_val,
		" legacy_done=", legacy_val)

	# ✅ Use the real persisted dictionary whenever possible
	if progress != null and ("completed_milestones" in progress):
		var cm: Dictionary = progress.get("completed_milestones")
		if cm == null:
			cm = {}
			progress.set("completed_milestones", cm)

		var arr: Array = cm.get(domain_id, [])
		return arr != null and arr.has(milestone_id)

	# Only fall back if we truly have no progress resource
	var done: Array = counters.get(legacy_key, [])
	return done != null and done.has(milestone_id)

# -----------------------------------------------------------------------------
# Reveal history (presentation layer)
# -----------------------------------------------------------------------------
func _make_reveal_key(domain_id: String, milestone_id: String) -> String:
	return "%s:%s" % [domain_id, milestone_id]


func is_revealed(domain_id: String, milestone_id: String) -> bool:
	if progress == null:
		return false

	# Ensure dictionary exists and is actually a Dictionary
	var rm: Variant = null
	if "revealed_milestones" in progress:
		rm = progress.get("revealed_milestones")

	if typeof(rm) != TYPE_DICTIONARY or rm == null:
		rm = {}
		progress.set("revealed_milestones", rm)

	var key := "%s:%s" % [domain_id, milestone_id]
	return (rm as Dictionary).get(key, false) == true


func mark_revealed(domain_id: String, milestone_id: String) -> void:
	if progress == null:
		return

	var rm: Variant = null
	if "revealed_milestones" in progress:
		rm = progress.get("revealed_milestones")

	if typeof(rm) != TYPE_DICTIONARY or rm == null:
		rm = {}
		progress.set("revealed_milestones", rm)

	var key := "%s:%s" % [domain_id, milestone_id]
	if (rm as Dictionary).get(key, false) == true:
		return

	(rm as Dictionary)[key] = true
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
	progress.set("location_counters", location_counters)

	# ✅ Ensure reward_stats exists but don't overwrite it
	if progress.get("reward_stats") == null or typeof(progress.get("reward_stats")) != TYPE_DICTIONARY:
		progress.set("reward_stats", {})



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

func _apply_reward(r: HeartRewardDefinition) -> void:
	if r == null:
		return
	if r.id == StringName(""):
		return
	if has_unlocked_reward(r.id):
		return

	# Mark unlocked first (so even if the game crashes mid-apply, it won't double-apply later)
	_mark_reward_unlocked(r.id)

	var gs := get_node_or_null("/root/GameState")

	match r.kind:
		HeartRewardDefinition.RewardKind.UNLOCK_TRAVEL:
			if gs != null and gs.has_method("unlock_travel") and str(r.travel_id) != "":
				gs.call("unlock_travel", str(r.travel_id))

		HeartRewardDefinition.RewardKind.TOAST:
			var qe := get_node_or_null("/root/QuestEvents")
			if qe != null and qe.has_signal("toast_requested"):
				qe.call("toast_requested").emit(r.description if r.description != "" else "A blessing has awakened.")

		_:
			# ✅ If the reward definition contains numeric stats, store them into reward_stats.
			# We will support stacking in a predictable way.
			if "stats" in r:
				var s_any: Variant = r.get("stats")
				if s_any != null and typeof(s_any) == TYPE_DICTIONARY:
					var s: Dictionary = s_any
					# Multipliers stack multiplicatively; energy bonus stacks additively.
					if s.has("sell_multiplier"):
						_mul_reward_stat("sell_multiplier", float(s["sell_multiplier"]))
					if s.has("shop_discount_multiplier"):
						_mul_reward_stat("shop_discount_multiplier", float(s["shop_discount_multiplier"]))
					if s.has("energy_bonus_on_sleep"):
						_add_reward_stat("energy_bonus_on_sleep", int(s["energy_bonus_on_sleep"]))

					# If you want, you can also store any unknown keys literally:
					# (Safe for future expansion — you can interpret later.)
					for k in s.keys():
						var ks := String(k)
						if ks == "sell_multiplier" or ks == "shop_discount_multiplier" or ks == "energy_bonus_on_sleep":
							continue
						_set_reward_stat(ks, s[k])

			# Keep your existing behavior too (so UI/toasts/etc keep working)
			if gs != null and gs.has_method("apply_heart_reward"):
				gs.call("apply_heart_reward", r)
			else:
				print("[HeartProgress] Reward unlocked: ", r.id, " kind=", r.kind, " desc=", r.description)

func _evaluate_definition_milestones() -> void:
	if definition == null:
		return
	if progress == null:
		return

	# HeartDefinitionData should expose "milestones: Array[HeartMilestone]"
	if not ("milestones" in definition):
		return

	var list: Array = definition.get("milestones")
	if list == null or list.is_empty():
		return

	for m in list:
		if m == null:
			continue

		# Expected fields from your HeartMilestone resource:
		# id, domain_id, counter_key, required_amount, filter_item_id, filter_npc_id
		var domain_id := str(m.get("domain_id"))
		var milestone_id := str(m.get("id"))

		if domain_id == "" or milestone_id == "":
			continue

		# Already completed? skip
		if has_milestone(domain_id, milestone_id):
			print("[HP REWARD DBG] milestone already completed, skipping grant domain=", domain_id, " id=", milestone_id)
			continue

		var counter_key := str(m.get("counter_key"))
		var required := int(m.get("required_amount"))

		if counter_key == "" or required <= 0:
			continue

		# --- base counter check ---
		var have := 0

		# If filter_item_id is set, interpret it based on counter_key
		var filter_item := str(m.get("filter_item_id")).strip_edges()

		if filter_item != "":
			if counter_key == "pickup":
				# "pickup" milestones filtered by item_id (Shell, Flower, etc.)
				have = get_item_count(filter_item)
			elif counter_key == "go_to":
				# "go_to" milestones filtered by location_id (beach, town, etc.)
				have = get_location_count(filter_item)
			else:
				# default fallback: treat filter as item counter
				have = get_item_count(filter_item)
		else:
			# No filter: use generic action counter
			have = get_count(counter_key)
		
		print("[HP CHECK] %s/%s key=%s filter=%s have=%d req=%d" %
			[domain_id, milestone_id, counter_key, filter_item, have, required])

		if have >= required:
			_mark_milestone_done_if_supported(domain_id, milestone_id)

func dev_dump_progress_state(tag: String = "") -> void:
	if progress == null:
		print("[HP DUMP] progress=null ", tag)
		return
	
	var cm = null
	var rm = null
	
	if ("completed_milestones" in progress):
		cm = progress.get("completed_milestones")
	
	if ("revealed_milestones" in progress):
		rm = progress.get("revealed_milestones")

	print("[HP DUMP] ", tag,
		" completed_milestones=", cm,
		" revealed_milestones=", rm,
		" counters=", counters,
		" item_counters=", item_counters)


func dev_clear_milestones_and_reveals_runtime() -> void:
	if progress != null:
		if "completed_milestones" in progress:
			progress.set("completed_milestones", {})
		if "revealed_milestones" in progress:
			progress.set("revealed_milestones", {})

	# Clear fallback “done” list too (so definition drives completion cleanly)
	for k in counters.keys():
		if str(k).begins_with("__milestones_done__"):
			counters.erase(k)
	
	if "reward_stats" in progress: progress.set("reward_stats", {})
	
	emit_signal("changed")
	print("[HeartProgress] DEV cleared completed_milestones + revealed_milestones + fallback done lists.")

func _get_milestone(domain_id: String, milestone_id: String) -> Resource:
	# heart_definition.tres should have domains with milestones; adapt if your structure differs.
	if definition == null:
		return null

	# Common pattern: definition.domains -> HeartDomainData with id + milestones array
	if "domains" in definition:
		for d in definition.get("domains"):
			if d != null and ("id" in d) and d.get("id") == domain_id:
				if "milestones" in d:
					for m in d.get("milestones"):
						if m != null and ("id" in m) and m.get("id") == milestone_id:
							return m

	# Fallback if definition stores milestones flat
	if "milestones" in definition:
		for m in definition.get("milestones"):
			if m != null and ("domain_id" in m) and ("id" in m):
				if m.get("domain_id") == domain_id and m.get("id") == milestone_id:
					return m

	return null


func is_milestone_completed_by_definition(domain_id: String, milestone_id: String) -> bool:
	var m := _get_milestone(domain_id, milestone_id)
	if m == null:
		# If no definition, we can't evaluate it.
		return false

	var key := ""
	var req := 1
	var filter_item := ""
	var filter_npc := ""

	if "counter_key" in m:
		key = str(m.get("counter_key")).strip_edges()
	if "required_amount" in m:
		req = int(m.get("required_amount"))
	if "filter_item_id" in m:
		filter_item = str(m.get("filter_item_id")).strip_edges()
	if "filter_npc_id" in m:
		filter_npc = str(m.get("filter_npc_id")).strip_edges()

	if key == "":
		return false

	# For now: if you set filter_item_id, we evaluate against item_counters.
	# Otherwise we evaluate against counters[key].
	if filter_item != "":
		return int(item_counters.get(filter_item, 0)) >= req

	# Later: add npc friendship checks, money earned, etc. by interpreting key prefixes.
	return int(counters.get(key, 0)) >= req

func get_milestone_kind(domain_id: String, milestone_id: String) -> String:
	var m := _get_milestone(domain_id, milestone_id)
	if m != null and ("kind" in m):
		return str(m.get("kind"))
	return "sprout"

# HeartProgress.gd

func _load_reward_catalog() -> void:
	reward_catalog = load(REWARD_PATH)
	if reward_catalog == null:
		push_warning("[HeartProgress] Could not load reward catalog at %s" % REWARD_PATH)

func get_reward_stat(key: String, default_value) -> Variant:
	if progress == null:
		return default_value
	var rs := _ensure_reward_stats_dict()
	return rs.get(key, default_value)

func get_reward_flag(key: String, default_value: bool = false) -> bool:
	if progress == null:
		return default_value

	if not ("reward_flags" in progress):
		progress.set("reward_flags", {})

	var rf_any: Variant = progress.get("reward_flags")
	if rf_any == null or typeof(rf_any) != TYPE_DICTIONARY:
		rf_any = {}
		progress.set("reward_flags", rf_any)

	var rf: Dictionary = rf_any
	return bool(rf.get(key, default_value))

func _apply_reward_definition(r: HeartRewardDefinition) -> void:
	if r == null:
		return
	if r.id == StringName(""):
		return

	# If you want “only apply once”, gate using unlocked_rewards:
	if has_unlocked_reward(r.id):
		print("[HP REWARD DBG] already unlocked, skipping apply id=", str(r.id))
		return

	# Mark unlocked first
	_mark_reward_unlocked(r.id)

	print("[HP REWARD DBG] APPLY reward id=", str(r.id),
		" kind=", int(r.kind),
		" stat_key=", str(r.stat_key),
		" amount=", r.amount,
		" flag_key=", str(r.flag_key),
		" flag_value=", r.flag_value)

	var gs := get_node_or_null("/root/GameState")

	match r.kind:
		HeartRewardDefinition.RewardKind.STAT_ADD:
			var rs := _ensure_reward_stats_dict()
			var key := str(r.stat_key)
			if key == "":
				print("[HP REWARD DBG] STAT_ADD missing stat_key for id=", str(r.id))
			else:
				var cur := float(rs.get(key, 0.0))
				rs[key] = cur + float(r.amount)
				progress.set("reward_stats", rs)
				_save_progress_if_possible()
				emit_signal("changed")
				print("[HP REWARD DBG] STAT_ADD wrote reward_stats[", key, "]=", rs[key])

		HeartRewardDefinition.RewardKind.STAT_MULTIPLY:
			var rs := _ensure_reward_stats_dict()
			var key := str(r.stat_key)
			if key == "":
				print("[HP REWARD DBG] STAT_MULTIPLY missing stat_key for id=", str(r.id))
			else:
				var cur := float(rs.get(key, 1.0))
				rs[key] = cur * float(r.amount)
				progress.set("reward_stats", rs)
				_save_progress_if_possible()
				emit_signal("changed")
				print("[HP REWARD DBG] STAT_MULTIPLY wrote reward_stats[", key, "]=", rs[key])

		HeartRewardDefinition.RewardKind.FLAG_SET:
			var rf := _ensure_reward_flags_dict()
			var fkey := str(r.flag_key)
			if fkey == "":
				print("[HP REWARD DBG] FLAG_SET missing flag_key for id=", str(r.id))
			else:
				rf[fkey] = bool(r.flag_value)
				progress.set("reward_flags", rf)
				_save_progress_if_possible()
				emit_signal("changed")
				print("[HP REWARD DBG] FLAG_SET wrote reward_flags[", fkey, "]=", rf[fkey])

		HeartRewardDefinition.RewardKind.UNLOCK_TRAVEL:
			if gs != null and gs.has_method("unlock_travel") and str(r.travel_id) != "":
				gs.call("unlock_travel", str(r.travel_id))
				_save_progress_if_possible()
				emit_signal("changed")

		HeartRewardDefinition.RewardKind.TOAST:
			var qe := get_node_or_null("/root/QuestEvents")
			if qe != null and qe.has_signal("toast_requested"):
				qe.toast_requested.emit(r.description if r.description != "" else "A blessing has awakened.", "success", 3.0)

func _apply_rewards_for_milestone(domain_id: String, milestone_id: String) -> void:
	print("[HP REWARD DBG] apply_rewards begin domain=", domain_id, " id=", milestone_id)
	
	if progress == null:
		print("[HP REWARD DBG] progress is null, cannot persist rewards")
		return

	if reward_catalog == null:
		print("[HP REWARD DBG] reward_catalog is null, cannot lookup reward ids")
		return

	var m := _get_milestone(domain_id, milestone_id)
	if m == null:
		print("[HP REWARD DBG] _get_milestone returned null for domain=", domain_id, " id=", milestone_id)
		return

	# Safe read of reward_ids from Resource
	var ids_any: Variant = null
	# Prefer direct property access when possible
	# (Resource exported vars are usually accessible as fields)
	if m.has_method("get"):
		ids_any = m.get("reward_ids")
	else:
		# last resort: try property access
		ids_any = m.reward_ids

	if ids_any == null:
		print("[HP REWARD DBG] milestone has reward_ids=null domain=", domain_id, " id=", milestone_id)
		return

	if typeof(ids_any) != TYPE_ARRAY:
		print("[HP REWARD DBG] milestone reward_ids not an Array. type=", typeof(ids_any), " value=", ids_any)
		return

	var ids: Array = ids_any
	print("[HP REWARD DBG] milestone reward_ids=", ids)

	if ids.is_empty():
		print("[HP REWARD DBG] milestone reward_ids is empty, nothing to apply")
		return

	for rid_any in ids:
		var rid := StringName(str(rid_any))
		print("[HP REWARD DBG] attempting reward id=", str(rid))

		var defn: HeartRewardDefinition = reward_catalog.get_reward_by_id(rid)
		if defn == null:
			print("[HP REWARD DBG] MISSING reward definition for id=", str(rid))
			continue

		print("[HP REWARD DBG] found reward def id=", str(defn.id), " kind=", int(defn.kind), " stat_key=", str(defn.stat_key), " amount=", defn.amount)
		_apply_reward_definition(defn)

	# After applying, dump reward_stats so you can see if it persisted
	var rs_any: Variant = progress.get("reward_stats") if ("reward_stats" in progress) else null
	var rf_any: Variant = progress.get("reward_flags") if ("reward_flags" in progress) else null
	var ur_any: Variant = progress.get("unlocked_rewards") if ("unlocked_rewards" in progress) else null

	print("[HP REWARD DBG] after apply reward_stats=", rs_any)
	print("[HP REWARD DBG] after apply reward_flags=", rf_any)
	print("[HP REWARD DBG] after apply unlocked_rewards=", ur_any)

	print("[HP REWARD DBG] apply_rewards end domain=", domain_id, " id=", milestone_id)

func _ensure_unlocked_rewards_dict() -> Dictionary:
	if progress == null:
		return {}
	if not ("unlocked_rewards" in progress) or progress.get("unlocked_rewards") == null:
		progress.set("unlocked_rewards", {})
	var ur_any: Variant = progress.get("unlocked_rewards")
	if ur_any == null or typeof(ur_any) != TYPE_DICTIONARY:
		ur_any = {}
		progress.set("unlocked_rewards", ur_any)
	return ur_any as Dictionary

func _ensure_reward_stats_dict() -> Dictionary:
	if progress == null:
		return {}
	if not ("reward_stats" in progress):
		progress.set("reward_stats", {})
	var rs_any: Variant = progress.get("reward_stats")
	if rs_any == null or typeof(rs_any) != TYPE_DICTIONARY:
		rs_any = {}
		progress.set("reward_stats", rs_any)
	return rs_any

func _ensure_reward_flags_dict() -> Dictionary:
	if progress == null:
		return {}
	if not ("reward_flags" in progress):
		progress.set("reward_flags", {})
	var rf_any: Variant = progress.get("reward_flags")
	if rf_any == null or typeof(rf_any) != TYPE_DICTIONARY:
		rf_any = {}
		progress.set("reward_flags", rf_any)
	return rf_any

func has_unlocked_reward(reward_id: StringName) -> bool:
	if progress == null:
		return false
	var ur := _ensure_unlocked_rewards_dict()
	return ur.get(str(reward_id), false) == true

func _mark_reward_unlocked(reward_id: StringName) -> void:
	if progress == null:
		return
	var ur := _ensure_unlocked_rewards_dict()
	ur[str(reward_id)] = true
	progress.set("unlocked_rewards", ur)
	_save_progress_if_possible()
	reward_unlocked.emit(reward_id)

func unlock_reward(reward_id: StringName) -> void:
	if progress == null:
		return
	var ur := _ensure_unlocked_rewards_dict()
	var key := str(reward_id)
	if ur.get(key, false) == true:
		return
	ur[key] = true
	progress.set("unlocked_rewards", ur)
	_save_progress_if_possible()
	emit_signal("changed")

func _unlock_rewards_for_milestone(domain_id: String, milestone_id: String) -> void:
	# This expects you already have _get_milestone(domain_id, milestone_id)
	# that searches heart_definition.tres.
	var m := _get_milestone(domain_id, milestone_id)
	if m == null:
		return

	# Supports either reward_ids (Array) or a single reward_id (if you ever add it)
	if "reward_ids" in m:
		var arr :Variant= m.get("reward_ids")
		if arr != null and typeof(arr) == TYPE_ARRAY:
			for rid in arr:
				if rid == null:
					continue
				unlock_reward(StringName(str(rid)))

func _dev_clear_legacy_milestone_keys() -> void:
	# Removes old fallback milestone arrays that can cause false unlocks
	var keys := counters.keys()
	for k in keys:
		var ks := str(k)
		if ks.begins_with("__milestones_done__"):
			counters.erase(k)

func _clear_legacy_milestone_lists() -> void:
	var keys := counters.keys()
	for k in keys:
		var ks := str(k)
		if ks.begins_with("__milestones_done__"):
			counters.erase(k)

func get_sell_multiplier() -> float:
	return float(get_reward_stat("sell_multiplier", 1.0))

func get_shop_discount_multiplier() -> float:
	return float(get_reward_stat("shop_discount_multiplier", 1.0))

func get_energy_bonus_on_sleep() -> int:
	return int(get_reward_stat("energy_bonus_on_sleep", 0))

func _set_reward_stat(key: String, value) -> void:
	if progress == null:
		return
	var rs := _ensure_reward_stats_dict()
	rs[key] = value
	progress.set("reward_stats", rs)
	_save_progress_if_possible()
	emit_signal("changed")


func _mul_reward_stat(key: String, factor: float) -> void:
	if progress == null:
		return
	if factor <= 0.0:
		return
	var rs := _ensure_reward_stats_dict()
	var cur := float(rs.get(key, 1.0))
	rs[key] = cur * factor
	progress.set("reward_stats", rs)
	_save_progress_if_possible()
	emit_signal("changed")


func _add_reward_stat(key: String, delta: int) -> void:
	if progress == null:
		return
	if delta == 0:
		return
	var rs := _ensure_reward_stats_dict()
	var cur := int(rs.get(key, 0))
	rs[key] = cur + delta
	progress.set("reward_stats", rs)
	_save_progress_if_possible()
	emit_signal("changed")

func dev_clear_rewards_runtime(save_after: bool = false) -> void:
	if progress == null:
		return
	if "reward_stats" in progress:
		progress.set("reward_stats", {})
	if "reward_flags" in progress:
		progress.set("reward_flags", {})
	if "unlocked_rewards" in progress:
		progress.set("unlocked_rewards", {})

	if save_after:
		_save_progress_if_possible()

	print("[HP REWARD DBG] dev_clear_rewards_runtime completed. reward_stats/reward_flags/unlocked_rewards cleared.")
	emit_signal("changed")

func _on_went_to(location_id: String) -> void:
	location_id = location_id.strip_edges()
	if location_id == "":
		return

	print("[HP EVT] went_to:", location_id, " -> counters[go_to] + location_counters[%s]" % location_id)

	# ✅ Your quest keyword
	_add_action("go_to", 1)

	# ✅ Enables filter_item_id="beach"
	_add_location(location_id, 1)

	_evaluate_definition_milestones()
	emit_signal("changed")


func _on_item_picked_up(item_id: String, qty: int) -> void:
	item_id = item_id.strip_edges()
	if item_id == "" or qty <= 0:
		return

	print("[HP EVT] item_picked_up:", item_id, " qty=", qty, " -> counters[pickup] + item_counters[%s]" % item_id)

	# ✅ Your quest keyword
	_add_action("pickup", qty)

	# ✅ Enables filter_item_id="Shell"
	_add_item(item_id, qty)

	_evaluate_definition_milestones()
	emit_signal("changed")

var location_counters: Dictionary = {}  # location_id -> int

func _add_location_visit(location_id: String, amount: int) -> void:
	location_id = location_id.strip_edges()
	if location_id == "" or amount <= 0:
		return
	location_counters[location_id] = int(location_counters.get(location_id, 0)) + int(amount)
	_mirror_into_progress()
	_save_progress_if_possible()

func _add_pickup(item_id: String, amount: int) -> void:
	item_id = item_id.strip_edges()
	if item_id == "" or amount <= 0:
		return
	# You already have item_counters and _add_item — perfect:
	_add_item(item_id, amount)

func get_location_count(location_id: String) -> int:
	return int(location_counters.get(location_id, 0))

func _add_location(location_id: String, amount: int) -> void:
	location_id = location_id.strip_edges()
	if location_id == "" or amount <= 0:
		return
	location_counters[location_id] = int(location_counters.get(location_id, 0)) + int(amount)
	_mirror_into_progress()
	_save_progress_if_possible()

func is_fishing_unlocked() -> bool:
	return bool(get_reward_flag("fishing_unlocked", false))
