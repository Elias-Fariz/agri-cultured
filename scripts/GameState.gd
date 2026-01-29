# GameState.gd
extends Node

enum ToolType { AXE, PICKAXE, HOE, BUCKET, HAND, WATERING_CAN }
const TOOL_COUNT := 6  # <- THIS MUST BE UPDATED

@export var starting_tool: ToolType = ToolType.HAND
var current_tool: ToolType = ToolType.HAND

# ----------------------------
# Inventory (already working)
# ----------------------------
var inventory: Dictionary = {}  # { "Wood": 3, "Stone": 2 }
	
# -------------------------
# INVENTORY HELPERS
# -------------------------
# inventory is already: { "Wood": 3, ... }

func inventory_add(item_name: String, qty: int = 1) -> void:
	if item_name.is_empty() or qty <= 0:
		return
	inventory[item_name] = int(inventory.get(item_name, 0)) + qty
	print("Added to inventory:", item_name, " Inventory now:", inventory)

func inventory_has(item_name: String, qty: int = 1) -> bool:
	return int(inventory.get(item_name, 0)) >= qty

func inventory_remove(item_name: String, qty: int = 1) -> bool:
	if item_name.is_empty() or qty <= 0:
		return false
	var current := int(inventory.get(item_name, 0))
	if current < qty:
		return false
	var new_qty := current - qty
	if new_qty <= 0:
		inventory.erase(item_name)
	else:
		inventory[item_name] = new_qty
	return true

func consume_item(item_id: String) -> bool:
	item_id = item_id.strip_edges()
	if item_id == "":
		return false

	# Must have item
	if not inventory_has(item_id, 1):
		return false

	# Look up ItemData
	var data = null
	if ItemDb != null and ItemDb.has_method("get_item"):
		data = ItemDb.get_item(item_id)

	if data == null:
		print("consume_item: No ItemData found for:", item_id)
		return false

	# Must be edible
	var restore := int(data.energy_restore)
	if restore <= 0:
		return false

	# If already full, don't waste it (feels nicer)
	if energy >= max_energy:
		return false

	var before := energy
	energy = min(max_energy, energy + restore)

	# If no change, do not consume
	if energy == before:
		return false

	# Consume one
	var removed := inventory_remove(item_id, 1)
	if not removed:
		return false

	# Optional toast (only if you have it)
	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit("+" + str(restore) + " Energy")

	return true

# --- Shipping / Sell Box global state ---
var shipping_bin: Dictionary = {}  # { "Wood": 5, "Watermelon": 2 }

var sell_box: SellBox;

# -------------------------
# ITEM DATABASE (simple)
# -------------------------
var item_db := {
	"Wood": {
		"sell_price": 2,
		"shippable": true,
	},
	"Stone": {
		"sell_price": 2,
		"shippable": true,
	},
	"Watermelon": {
		"sell_price": 35,
		"shippable": true,
	},
	"Egg": {
		"sell_price": 15,
		"shippable": true,
	},
	"Milk": {
		"sell_price": 20,
		"shippable": true,
	},
	"Animal Feed": {
		"sell_price": 3,
		"shippable": true,
	},
	"Blueberry": {
		"sell_price": 12,
		"shippable": true,
	},
	"Strawberry": {
		"sell_price": 18,
		"shippable": true,
	},
	"Avocado": {
		"sell_price": 30,
		"shippable": true,
	},
	"Overripe Avocado": {
		"sell_price": 10,
		"shippable": true,
	}
	# Tools later would be shippable: false
}

# -------------------------
# Selected item (future hotbar will drive this)
# -------------------------
var selected_item_id: String = ""   # e.g. "Watermelon Seeds"

# Seed mapping (fast/simple for now)
var seed_to_crop := {
	"Watermelon Seeds": "watermelon",
	"Blueberry Seeds": "blueberry",
	"Strawberry Seeds": "strawberry",
	"Avocado Seeds": "avocado"
}

var tracked_quest_id: String = ""  # "" means no quest tracked

# --- Scene spawning ---
var next_spawn_name: String = ""      # your existing system
var pending_spawn_tag: String = ""    # optional future tag system


func is_seed_item(item_id: String) -> bool:
	return seed_to_crop.has(item_id)

func get_crop_for_seed(item_id: String) -> String:
	return String(seed_to_crop.get(item_id, ""))

func set_selected_item(item_id: String) -> void:
	selected_item_id = item_id
	print("Selected item:", selected_item_id)

func get_all_seed_ids_in_inventory() -> Array[String]:
	var seeds: Array[String] = []
	for k in inventory.keys():
		var id := String(k)
		if inventory_has(id, 1) and is_seed_item(id):
			seeds.append(id)
	seeds.sort()
	return seeds

func cycle_seed_next() -> void:
	var seeds := get_all_seed_ids_in_inventory()
	if seeds.is_empty():
		selected_item_id = ""
		print("No seeds in inventory to select.")
		return

	# If current selection isn't a seed (or empty), pick first seed
	if not is_seed_item(selected_item_id) or not seeds.has(selected_item_id):
		set_selected_item(seeds[0])
		return

	var idx := seeds.find(selected_item_id)
	idx = (idx + 1) % seeds.size()
	set_selected_item(seeds[idx])

func get_sell_price(item_name: String) -> int:
	return ItemDb.get_sell_price(item_name)

func is_shippable(item_name: String) -> bool:
	return ItemDb.is_shippable(item_name)

# -------------------------
# SHIPPING BIN HELPERS
# -------------------------
# shipping_bin already exists and persists globally

func shipping_add(item_name: String, qty: int = 1) -> void:
	if item_name.is_empty() or qty <= 0:
		return
	shipping_bin[item_name] = int(shipping_bin.get(item_name, 0)) + qty
	
func report_item_shipped(item_name: String, qty: int) -> void:
	# OLD: directly increments quest progress
	# NEW: emit the canonical quest event
	QuestEvents.shipped.emit(item_name, qty)
	QuestEvents.quest_state_changed.emit()

func report_action(action: String, amount: int = 1) -> void:
	# If you used report_action("chop_tree"), map it to the new signal
	if action == "chop_tree":
		QuestEvents.chopped_tree.emit(amount)
	elif action == "break_rock":
		QuestEvents.broke_rock.emit(amount)
	else:
		# Optional: a generic event later, but for now:
		print("Unknown quest action:", action)

func shipping_remove(item_name: String, qty: int = 1) -> bool:
	if item_name.is_empty() or qty <= 0:
		return false
	var current := int(shipping_bin.get(item_name, 0))
	if current < qty:
		return false
	var new_qty := current - qty
	if new_qty <= 0:
		shipping_bin.erase(item_name)
	else:
		shipping_bin[item_name] = new_qty
	return true

# -------------------------
# MOVE BETWEEN INVENTORY <-> SHIPPING
# -------------------------
func ship_from_inventory(item_name: String, qty: int = 1) -> bool:
	if not is_shippable(item_name):
		return false
	if not inventory_remove(item_name, qty):
		return false
	shipping_add(item_name, qty)
	return true

func unship_to_inventory(item_name: String, qty: int = 1) -> bool:
	if not shipping_remove(item_name, qty):
		return false
	inventory_add(item_name, qty)
	return true

# -------------------------
# PAYOUT
# -------------------------
func shipping_calculate_payout() -> int:
	var total := 0
	for item_name in shipping_bin.keys():
		var qty := int(shipping_bin[item_name])
		total += get_sell_price(String(item_name)) * qty

	var mul := 1.0
	var hp := get_node_or_null("/root/HeartProgress")
	if hp != null and hp.has_method("get_sell_multiplier"):
		mul = float(hp.call("get_sell_multiplier"))

	total = int(round(float(total) * mul))
	print("[Ship] base_total=", total, " mul=", mul, " final=", total)

	return total

func shipping_payout_and_clear() -> int:
	# --- Capture shipped items BEFORE we clear the bin ---
	var shipped_copy: Dictionary = {}
	for item_name_any in shipping_bin.keys():
		var item_name := String(item_name_any)
		var qty := int(shipping_bin[item_name_any])
		if qty > 0:
			shipped_copy[item_name] = qty

	# 1) Report shipping for quests FIRST (based on what is actually in the bin overnight)
	for item_name_any in shipping_bin.keys():
		var item_name := String(item_name_any)
		var qty := int(shipping_bin[item_name_any])
		if qty > 0:
			report_item_shipped(item_name, qty)

	# 2) Pay out money
	var payout := shipping_calculate_payout()
	if payout > 0:
		MoneySystem.add(payout)

	# --- Finalize yesterday summary BEFORE clearing ---
	# TimeManager.day has already been incremented in start_new_day(),
	# so "yesterday" is (TimeManager.day - 1)
	finalize_yesterday_summary(TimeManager.day, payout, shipped_copy)

	# Prepare tracking for the NEW day
	reset_today_tracking()

	# 3) Clear the bin
	shipping_bin.clear()
	return payout

# ----------------------------
# Energy / Stamina (NEW)
# ----------------------------
@export var max_energy: int = 5
@export var tool_action_cost: int = 1

var energy: int = 5  # will be set on _ready
var exhausted: bool = false

# ----------------------------
# World State (runtime persistence across scenes)
# ----------------------------
var world_state: Dictionary = {}
# Example:
# world_state["Farm"] = { ...data... }

# ----------------------------
# NPC Friending (runtime persistence across scenes)
# ----------------------------

# npc_id -> friendship int
var npc_friendship: Dictionary = {}

# npc_id -> last day index talked (to prevent spam)
var npc_last_talk_day: Dictionary = {}

func get_friendship(npc_id: String) -> int:
	return int(npc_friendship.get(npc_id, 0))

func add_friendship(npc_id: String, amount: int) -> void:
	npc_friendship[npc_id] = get_friendship(npc_id) + amount
	var new_level := clampi(npc_friendship[npc_id] / 10, 0, 10)
	HeartProgress.set_friendship_level(npc_id, new_level)

func can_gain_talk_friendship(npc_id: String, current_day: int) -> bool:
	return int(npc_last_talk_day.get(npc_id, -999999)) != current_day

func mark_talked_today(npc_id: String, current_day: int) -> void:
	npc_last_talk_day[npc_id] = current_day
	
# -------------------------
# QUEST SYSTEM
# -------------------------

var active_quests: Dictionary = {}    # id -> quest dict
var completed_quests: Dictionary = {} # id -> quest dict


var _talked_block_by_npc: Dictionary = {}  # npc_id -> String "day:morning" etc.

const TUTORIAL_QUEST_ID := "tutorial_day1"
const TUTORIAL_QUEST_RES_PATH := "res://data/quests/tutorial_day1.tres"

var unlocked_travel: Dictionary = {}  # e.g. "animal_keeper" -> true

var pending_spawns: Array[Dictionary] = []

var today_tracking: Dictionary = {
	"shipped": {},              # item_id -> qty
	"money_earned": 0,
	"quests_accepted": [],
	"quests_completed": [],
	"areas_unlocked": [],
	"pass_out": false,
	"energy_penalty": 0,
}

var yesterday_summary: Dictionary = {}  # what the overlay displays

var _rested_block_by_id: Dictionary = {}  # rest_id -> "day:morning" etc.

@export var farm_scene_path: String = "res://tscn/Farm.tscn"
@export var passout_spawn_tag: String = "passout_spawn"
var _day_start_toast_queue: Array[Dictionary] = []

# --- World pickup persistence (per-day) ---
var _picked_up_day_by_id: Dictionary = {}  # pickup_id -> int day number

func mark_pickup_collected(pickup_id: String) -> void:
	if pickup_id.strip_edges() == "":
		return
	_picked_up_day_by_id[pickup_id] = int(TimeManager.day)

func was_pickup_collected_today(pickup_id: String) -> bool:
	if pickup_id.strip_edges() == "":
		return false
	var d := int(_picked_up_day_by_id.get(pickup_id, -1))
	return d == int(TimeManager.day)

# Optional: you can call this at day start if you ever want to clean old entries
func cleanup_old_pickup_records(keep_days: int = 7) -> void:
	var today := int(TimeManager.day)
	for k in _picked_up_day_by_id.keys():
		var d := int(_picked_up_day_by_id.get(k, -999999))
		if today - d > keep_days:
			_picked_up_day_by_id.erase(k)
			
# --- Crafting recipe unlocks ---
var unlocked_recipes: Dictionary = {}  # recipe_id -> true

func unlock_recipe(recipe_id: String) -> void:
	if recipe_id.strip_edges() == "":
		return
	unlocked_recipes[recipe_id] = true
	print("Unlocked: " + recipe_id)

func get_unlocked_recipe_ids() -> Dictionary:
	# Return dictionary so we can do unlocked.has(id)
	return unlocked_recipes

# --- Small toast helper (uses your existing toast system) ---
func toast_info(msg: String, duration: float = 2.0) -> void:
	if msg.strip_edges() == "":
		return
	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(msg, "info", duration)

var _gifted_day_by_npc: Dictionary = {}      # npc_id -> int day last gifted
var _gifted_week_count_by_npc: Dictionary = {} # npc_id -> Dictionary{ week_key: int count }

var pending_cutscene_id: String = ""
var _heart_intro_queued: bool = false

var heart_stats: Dictionary = {}   # e.g. { "sell_multiplier": 1.05 }
var heart_flags: Dictionary = {}   # e.g. { "heart_pond_unlocked": true }

func _ready() -> void:
	reset_energy()
	current_tool = starting_tool
	
	QuestEvents.talked_to.connect(_on_quest_talked_to)
	QuestEvents.went_to.connect(_on_quest_went_to)

	QuestEvents.shipped.connect(_on_quest_shipped)
	QuestEvents.chopped_tree.connect(_on_quest_chopped_tree)
	QuestEvents.broke_rock.connect(_on_quest_broke_rock)
	QuestEvents.item_purchased.connect(_on_item_purchased)
	
	QuestEvents.item_picked_up.connect(_on_item_picked_up)
	QuestEvents.item_crafted.connect(_on_item_crafted)
	QuestEvents.item_gifted.connect(_on_item_gifted)
	
	QuestEvents.crop_harvested.connect(_on_crop_harvested)
	
	QuestEvents.ui_opened.connect(_on_quest_ui_opened)
	var tm := get_node_or_null("/root/TimeManager")
	if tm:
		tm.day_changed.connect(_on_day_changed)
	
	unlock_recipe("shell_necklace")
	unlock_recipe("flower_headband")


func cycle_tool_next() -> void:
	current_tool = (int(current_tool) + 1) % TOOL_COUNT

func get_tool_name() -> String:
	match current_tool:
		ToolType.AXE: return "Axe"
		ToolType.PICKAXE: return "Pickaxe"
		ToolType.HOE: return "Hoe"
		ToolType.BUCKET: return "Bucket"
		ToolType.HAND: return "Hands"
		ToolType.WATERING_CAN: return "Watering Can"
	return "?"

func reset_energy() -> void:
	energy = max_energy
	exhausted = false

func can_spend(cost: int) -> bool:
	return energy >= cost

# Returns true if spent successfully, false if not enough energy
func spend_energy(cost: int) -> bool:
	if energy < cost:
		exhausted = true
		return false

	energy -= cost
	if energy <= 0:
		energy = 0
		exhausted = true
	return true
	
func get_map_state(map_name: String) -> Dictionary:
	if not world_state.has(map_name):
		world_state[map_name] = {
			"has_initialized": false,
			"ground": {},   # cell_key -> tile info
			"objects": {},  # cell_key -> tile info
			"crops": {},    # cell_key -> crop info
			"hits": {}
		}
	return world_state[map_name]

func cell_to_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func key_to_cell(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))

# ----------------------------
# Gameplay Lock (UI / Dialogue / Quests)
# ----------------------------
var lock_count: int = 0

func lock_gameplay() -> void:
	lock_count += 1

func unlock_gameplay() -> void:
	lock_count = max(0, lock_count - 1)

func is_gameplay_locked() -> bool:
	return lock_count > 0

var active_warning: String = ""

func set_warning(msg: String) -> void:
	active_warning = msg

func clear_warning() -> void:
	active_warning = ""
	
# ----------------------------
# Quests
# ----------------------------

func add_quest(quest: Dictionary) -> void:
	var id := String(quest.get("id", ""))
	if id == "":
		return
	if active_quests.has(id) or completed_quests.has(id):
		return

	var q := quest.duplicate(true)
	q["progress"] = int(q.get("progress", 0))
	q["amount"] = int(q.get("amount", 1))
	q["completed"] = bool(q.get("completed", false))
	q["claimed"] = bool(q.get("claimed", false))

	active_quests[id] = q
	print("Quest accepted: ", id)
	
	if tracked_quest_id == "":
		tracked_quest_id = String(quest.get("id",""))
	
	# Unlock travel when accepting specific quest(s)
	var qid := String(q.get("id", ""))
	if qid == "unlock_animal_keeper":
		unlock_travel("animal_keeper")
	
	var title := String(q.get("title", "Quest"))
	QuestEvents.toast_requested.emit("New Quest: " + title, "info", 2.5)
	
	if qid != "":
		(today_tracking["quests_accepted"] as Array).append(title)
	
	QuestEvents.quest_state_changed.emit()

func complete_quest(quest_id: String) -> void:
	if not active_quests.has(quest_id):
		return

	var quest: Dictionary = active_quests[quest_id]
	quest["completed"] = true
	quest["claimed"] = false
	active_quests.erase(quest_id)
	completed_quests[quest_id] = quest
	print("Quest completed: ", quest_id)
	
	var q: Dictionary = completed_quests.get(quest_id, {})
	var title := String(q.get("title", "Quest"))
	
	(today_tracking["quests_completed"] as Array).append(title)
	QuestEvents.toast_requested.emit("Quest Completed: " + title, "success", 3.0)

	
func claim_quest_reward(quest_id: String) -> void:
	print("[Reward] claim_quest_reward:", quest_id)
	
	if not completed_quests.has(quest_id):
		return

	var quest: Dictionary = completed_quests[quest_id]
	if bool(quest.get("claimed", false)):
		return

	var reward: Dictionary = Dictionary(quest.get("reward", {}))
	print("Claiming reward for ", quest_id, " -> ", reward)

	# Money reward
	if reward.has("money"):
		MoneySystem.add(int(reward["money"]))

	# Item rewards: { "items": { "Watermelon": 1, "Wood": 5 } }
	if reward.has("items"):
		var items_reward: Dictionary = Dictionary(reward["items"])
		for item_name_any in items_reward.keys():
			var item_name := String(item_name_any)
			var qty := int(items_reward[item_name_any])
			inventory_add(item_name, qty)

	quest["claimed"] = true
	
	if quest_id == "keeper_cow_quest":
		print("[Reward] Queuing cow spawn!")
		queue_spawn_reward("farm", "res://tscn/Cow.tscn", "cow_pen_spawn")
		print("[Reward] pending_spawns now:", pending_spawns)
	
	QuestEvents.quest_state_changed.emit()

	print("Quest reward claimed for ", quest_id)

func _on_quest_talked_to(npc_id: String) -> void:
	_debug_chain("BEFORE talk " + npc_id)

	#_increment_matching_quests("talk_to", npc_id, 1)
	_try_advance_chain_quest("main_mayor_strawberry", "talk_to", npc_id, 1)

	_debug_chain("AFTER  talk " + npc_id)
	
	GameState.apply_quest_event("talk_to", npc_id, 1)
	QuestEvents.quest_state_changed.emit()
	# chain quests
	#for qid in active_quests.keys():
	#	_try_advance_chain_quest(String(qid), "talk_to", npc_id, 1)

func _on_quest_went_to(location_id: String) -> void:
	_debug_chain("BEFORE go_to " + location_id)

	#_increment_matching_quests("go_to", location_id, 1)
	_try_advance_chain_quest("main_mayor_strawberry", "go_to", location_id, 1)

	_debug_chain("AFTER  go_to " + location_id)
	
	GameState.apply_quest_event("go_to", location_id, 1)
	QuestEvents.quest_state_changed.emit()
	#for qid in active_quests.keys():
	#	_try_advance_chain_quest(String(qid), "go_to", location_id, 1)

func _on_quest_shipped(item_id: String, amount: int) -> void:
	_debug_chain("BEFORE ship " + item_id)

	#_increment_matching_quests("ship", item_id, amount)
	_try_advance_chain_quest("main_mayor_strawberry", "ship", item_id, amount)
	#for qid in active_quests.keys():
	#	_try_advance_chain_quest(String(qid), "ship", item_id, amount)
	
	GameState.apply_quest_event("ship", item_id, amount)
	QuestEvents.quest_state_changed.emit()

func _on_item_purchased(item_id: String, qty: int) -> void:
	apply_quest_event("buy", item_id, qty)
	QuestEvents.quest_state_changed.emit()
	# apply_quest_event already emits quest_state_changed when changed

func _on_quest_chopped_tree(amount: int) -> void:
	#_increment_matching_quests("chop_tree", "", amount)
	GameState.apply_quest_event("chop_tree", "", amount)
	QuestEvents.quest_state_changed.emit()

func _on_quest_broke_rock(amount: int) -> void:
	#_increment_matching_quests("break_rock", "", amount)
	GameState.apply_quest_event("break_rock", "", amount)
	QuestEvents.quest_state_changed.emit()

func _on_crop_harvested(item_id: String, qty: int) -> void:
	apply_quest_event("harvest", item_id, qty)
	QuestEvents.quest_state_changed.emit()
	
	# Only queue once, ever (or you can reset later if you want)
	if _heart_intro_queued:
		return
	_heart_intro_queued = true

	# Queue the cutscene for the next morning
	pending_cutscene_id = "heart_intro"

	# Optional: a tiny hint toast (can be subtle)
	QuestEvents.toast_requested.emit("Something stirs in the valley...")

func _on_quest_ui_opened(ui_id: String) -> void:
	GameState.apply_quest_event("ui_open", ui_id, 1)
	QuestEvents.quest_state_changed.emit()

func _on_item_picked_up(item_id: String, qty: int) -> void:
	GameState.apply_quest_event("pickup", item_id, qty)
	QuestEvents.quest_state_changed.emit()
	# If your apply_quest_event already emits quest_state_changed (it does),
	# you do NOT need to emit it again here.

func _on_item_crafted(item_id: String, qty: int) -> void:
	GameState.apply_quest_event("craft", item_id, qty)
	QuestEvents.quest_state_changed.emit()
	# If your apply_quest_event already emits quest_state_changed (it does),
	# you do NOT need to emit it again here.

func _on_item_gifted(npc_id: String, item_id: String, qty: int) -> void:
	# You can choose the target format you prefer.
	# Option A (simple): target is item_id only, use a separate "talk_to" step for NPC.
	GameState.apply_quest_event("gift", item_id, qty, npc_id)
	QuestEvents.quest_state_changed.emit()

	# Option B (more specific): target includes npc and item:
	# GameState.apply_quest_event("gift", npc_id + ":" + item_id, qty)

func _increment_matching_quests(qtype: String, target: String, delta: int) -> void:
	# active_quests is assumed to be a Dictionary: id -> quest Dictionary
	for id in active_quests.keys():
		var q: Dictionary = active_quests[id]

		if String(q.get("type", "")) != qtype:
			continue

		# Some types use target, some don't (like chop_tree)
		var q_target := String(q.get("target", ""))
		if target != "" and q_target != target:
			continue

		var progress := int(q.get("progress", 0))
		var amount := int(q.get("amount", 1))

		progress = clamp(progress + delta, 0, amount)
		q["progress"] = progress

		if progress >= amount:
			q["completed"] = true
			# move to completed_quests
			active_quests.erase(id)
			completed_quests[id] = q

		else:
			# write back updated quest
			active_quests[id] = q

func _try_advance_chain_quest(qid: String, event_type: String, target: String, delta: int) -> void:
	if not active_quests.has(qid):
		return

	var q: Dictionary = active_quests[qid]
	if String(q.get("type", "")) != "chain":
		return

	var steps: Array = q.get("steps", [])
	var step_index: int = int(q.get("step_index", 0))
	if step_index < 0 or step_index >= steps.size():
		return

	var step: Dictionary = steps[step_index]
	if qid == "tutorial_day1":
		print("[Tutorial] waiting step_index=", step_index, " step_type=", String(step.get("type","")), " step_target=", String(step.get("target","")))

	if String(step.get("type", "")) != event_type:
		return

	var step_target: String = String(step.get("target", ""))
	if step_target != "" and step_target != target:
		return

	var progress: int = int(step.get("progress", 0))
	var amount: int = int(step.get("amount", 1))

	progress = clamp(progress + delta, 0, amount)
	step["progress"] = progress
	steps[step_index] = step

	if progress >= amount:
		step_index += 1
		q["step_index"] = step_index

	q["steps"] = steps
	
	var changed := true  # set this only when a match occurs

	if step_index >= steps.size():
		q["completed"] = true
		active_quests.erase(qid)
		completed_quests[qid] = q

		# ✅ Emit AFTER moving to completed
		QuestEvents.quest_state_changed.emit()
		return
	else:
		active_quests[qid] = q

		# ✅ Emit AFTER writing back
		QuestEvents.quest_state_changed.emit()
		return

func get_chain_step_text(qid: String) -> String:
	if not active_quests.has(qid):
		return ""
	var q: Dictionary = active_quests[qid]
	if String(q.get("type","")) != "chain":
		return ""
	var steps: Array = q.get("steps", [])
	var idx: int = int(q.get("step_index", 0))
	if idx < 0 or idx >= steps.size():
		return ""
	return String(steps[idx].get("text", ""))

func _debug_chain(tag: String) -> void:
	var q: Dictionary = active_quests.get("main_mayor_strawberry", {}) as Dictionary
	if q.is_empty():
		print(tag, " CHAIN not active")
		return

	var idx: int = int(q.get("step_index", -1))
	var steps: Array = q.get("steps", [])
	var step_desc := "(no step)"
	if idx >= 0 and idx < steps.size():
		var step: Dictionary = steps[idx]
		step_desc = "%s %s (%d/%d)" % [
			String(step.get("type","?")),
			String(step.get("target","?")),
			int(step.get("progress",0)),
			int(step.get("amount",1))
		]

	print(tag, " step_index=", idx, " current=", step_desc)

func is_quest_available_to_accept(quest_id: String) -> bool:
	return not active_quests.has(quest_id) and not completed_quests.has(quest_id)

func has_turn_in_ready(npc_id: String) -> bool:
	for qid_any in completed_quests.keys():
		var qid := String(qid_any)
		var q: Dictionary = completed_quests[qid]

		if bool(q.get("claimed", false)):
			continue

		# Preferred: explicit turn_in_id
		var turn_in := String(q.get("turn_in_id", ""))
		if turn_in != "" and turn_in == npc_id:
			return true

		# Fallback for chain quests: infer from last step if it’s a talk_to
		if String(q.get("type", "")) == "chain":
			var steps: Array = q.get("steps", [])
			if steps.size() > 0:
				var last: Dictionary = steps[steps.size() - 1]
				if String(last.get("type", "")) == "talk_to" and String(last.get("target", "")) == npc_id:
					return true

	return false

func get_all_active_quest_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in active_quests.keys():
		ids.append(String(k))
	ids.sort()
	return ids

func set_tracked_quest(id: String) -> void:
	tracked_quest_id = id
	QuestEvents.quest_state_changed.emit()

func clear_tracked_quest() -> void:
	tracked_quest_id = ""
	QuestEvents.quest_state_changed.emit()

func get_tracked_quest() -> Dictionary:
	if tracked_quest_id == "":
		return {}

	if active_quests.has(tracked_quest_id):
		return active_quests[tracked_quest_id]

	if completed_quests.has(tracked_quest_id):
		return completed_quests[tracked_quest_id]

	return {}
	
func get_tracked_objective_text() -> String:
	var quest := get_tracked_quest()
	if quest.is_empty():
		return ""

	# If completed but unclaimed -> show turn-in guidance
	var is_completed := bool(quest.get("completed", false))
	var claimed := bool(quest.get("claimed", false))
	if is_completed and not claimed:
		var turn_text := String(quest.get("turn_in_text", ""))
		if turn_text.strip_edges() != "":
			return turn_text

		var turn_id := String(quest.get("turn_in_id", ""))
		if turn_id.strip_edges() != "":
			return "Turn in: " + turn_id

		return "Turn in to claim your reward."

	# Otherwise (active quest) -> show current step objective with progress when relevant
	if String(quest.get("type", "")) == "chain":
		var steps: Array = quest.get("steps", [])
		var step_index: int = int(quest.get("step_index", 0))
		if step_index >= 0 and step_index < steps.size():
			var step: Dictionary = steps[step_index]

			var amount := int(step.get("amount", 1))
			var progress := int(step.get("progress", 0))

			# Base text: prefer stored step text, otherwise fallback
			var base_text := String(step.get("text", ""))
			if base_text.strip_edges() == "":
				var t := String(step.get("type", ""))
				var target := String(step.get("target", ""))
				base_text = _format_objective_fallback(t, target, amount, progress)

			# Append (x/y) if it’s a counted objective
			if amount > 1:
				return "%s (%d/%d)" % [base_text, progress, amount]
			return base_text

		# If step_index is out of range, show something gentle
		return "…"

	# ONESHOT fallback (also support progress display)
	var amount2 := int(quest.get("amount", 1))
	var progress2 := int(quest.get("progress", 0))

	# Prefer a stored text if your quest dict includes one
	var base2 := String(quest.get("text", ""))
	if base2.strip_edges() == "":
		# optional: if your oneshot dict uses a different field name sometimes
		base2 = String(quest.get("oneshot_text", ""))
	if base2.strip_edges() == "":
		var t2 := String(quest.get("type", ""))
		var target2 := String(quest.get("target", ""))
		base2 = _format_objective_fallback(t2, target2, amount2, progress2)

	if amount2 > 1:
		return "%s (%d/%d)" % [base2, progress2, amount2]
	return base2

func _format_objective_fallback(t: String, target: String, amount: int, progress: int) -> String:
	match t:
		"ui_open":
			return "Open: " + target
		"talk_to":
			return "Talk to: " + target
		"go_to":
			return "Go to: " + target
		"ship":
			return "Ship: %s (%d/%d)" % [target, progress, amount]
		"action":
			return "Do: " + target
		_:
			return "Objective: "


func get_quest_objective_text(q: Dictionary) -> String:
	if q.is_empty():
		return ""

	# Completed but unclaimed -> show turn-in guidance
	var is_completed := bool(q.get("completed", false))
	var claimed := bool(q.get("claimed", false))
	if is_completed and not claimed:
		var turn_text := String(q.get("turn_in_text", ""))
		if turn_text.strip_edges() != "":
			return turn_text
		var turn_id := String(q.get("turn_in_id", ""))
		if turn_id.strip_edges() != "":
			return "Turn in: " + turn_id
		return "Turn in to claim your reward."

	# Chain quest -> show current step text + progress
	if String(q.get("type", "")) == "chain":
		var steps: Array = q.get("steps", [])
		var step_index: int = int(q.get("step_index", 0))
		if step_index < 0 or step_index >= steps.size():
			return "…"

		var step: Dictionary = steps[step_index]

		var base_text := String(step.get("text", ""))
		if base_text.strip_edges() == "":
			# fallback if no custom text
			base_text = _format_step_fallback(step)

		var amount := int(step.get("amount", 1))
		var progress := int(step.get("progress", 0))

		# Only show x/y when it actually makes sense
		if amount > 1:
			return "%s (%d/%d)" % [base_text, progress, amount]
		return base_text

	# Oneshot -> similar progress formatting
	var base := String(q.get("text", ""))
	if base.strip_edges() == "":
		base = _format_oneshot_fallback(q)

	var amt := int(q.get("amount", 1))
	var prog := int(q.get("progress", 0))
	if amt > 1:
		return "%s (%d/%d)" % [base, prog, amt]
	return base

func get_all_trackable_quest_ids() -> Array[String]:
	var ids: Array[String] = []

	# active quests
	for k in active_quests.keys():
		ids.append(String(k))

	# completed but unclaimed quests (turn-ins)
	for k in completed_quests.keys():
		var qid := String(k)
		var q: Dictionary = completed_quests[qid]
		if not bool(q.get("claimed", false)):
			ids.append(qid)

	ids.sort()
	return ids

func apply_quest_event(action: String, target: String = "", amount: int = 1, target2: String = "") -> void:
	var changed: bool = false
	var to_complete: Array[String] = []

	for qid_any in active_quests.keys():
		var qid: String = String(qid_any)
		var quest: Dictionary = active_quests[qid]

		# ----- CHAIN QUESTS -----
		if String(quest.get("type", "")) == "chain":
			var steps: Array = quest.get("steps", [])
			var step_index: int = int(quest.get("step_index", 0))
			if step_index < 0 or step_index >= steps.size():
				continue

			var step: Dictionary = steps[step_index]

			if String(step.get("type", "")) != action:
				continue

			# --- Matching rules ---
			# For most actions, only target matters.
			# For "gift", we support matching item_id (target) and npc_id (target2).
			var step_target := String(step.get("target", ""))
			var step_target2 := String(step.get("target2", ""))

			if action == "gift":
				# target = item_id (optional), target2 = npc_id (optional)
				if step_target != "" and target != "" and step_target != target:
					continue
				if step_target2 != "" and target2 != "" and step_target2 != target2:
					continue
				# If caller passed empty target/target2, that means "any" on that axis.
				# If step requires something but caller didn't provide it, don't match.
				if step_target != "" and target == "":
					continue
				if step_target2 != "" and target2 == "":
					continue
			else:
				# Existing behavior
				if target != "" and step_target != target:
					continue

			changed = true

			step["progress"] = int(step.get("progress", 0)) + amount
			steps[step_index] = step
			quest["steps"] = steps

			if int(step["progress"]) >= int(step.get("amount", 0)):
				quest["step_index"] = step_index + 1
				if int(quest["step_index"]) >= steps.size():
					to_complete.append(qid)

			active_quests[qid] = quest
			continue

		# ----- ONESHOT QUESTS -----
		if String(quest.get("type", "")) != action:
			continue

		var q_target := String(quest.get("target", ""))
		var q_target2 := String(quest.get("target2", ""))

		if action == "gift":
			if q_target != "" and target != "" and q_target != target:
				continue
			if q_target2 != "" and target2 != "" and q_target2 != target2:
				continue
			if q_target != "" and target == "":
				continue
			if q_target2 != "" and target2 == "":
				continue
		else:
			if target != "" and q_target != target:
				continue

		changed = true

		quest["progress"] = int(quest.get("progress", 0)) + amount
		if int(quest["progress"]) >= int(quest.get("amount", 0)):
			to_complete.append(qid)

		active_quests[qid] = quest

	for qid in to_complete:
		complete_quest(qid)
		changed = true

	if changed:
		QuestEvents.quest_state_changed.emit()

func get_first_turn_in_ready_id_for(npc_id: String) -> String:
	for qid_any in completed_quests.keys():
		var qid: String = String(qid_any)
		var q: Dictionary = completed_quests[qid]
		if bool(q.get("claimed", false)):
			continue
		if String(q.get("turn_in_id", "")) == npc_id:
			return qid
	return ""

func _current_talk_block_stamp() -> String:
	return "%d:%s" % [int(TimeManager.day), TimeManager.get_time_block_key(TimeManager.minutes)]

func can_talk_to_npc(npc_id: String) -> bool:
	var stamp: String = _current_talk_block_stamp()
	return String(_talked_block_by_npc.get(npc_id, "")) != stamp

func mark_talked_to_npc(npc_id: String) -> void:
	_talked_block_by_npc[npc_id] = _current_talk_block_stamp()

func _on_day_started(day: int) -> void:
	if day == 1:
		ensure_tutorial_day1_started()

func ensure_tutorial_day1_started() -> void:
	# If already active or completed, do nothing.
	if _is_quest_active(TUTORIAL_QUEST_ID) or _is_quest_completed(TUTORIAL_QUEST_ID):
		return

	var qres := load(TUTORIAL_QUEST_RES_PATH)
	if qres == null:
		push_warning("Tutorial quest resource not found at: " + TUTORIAL_QUEST_RES_PATH)
		return

	# qres is QuestData
	var qdict: Dictionary = qres.to_dict()

	add_quest(qdict)
	set_tracked_quest(TUTORIAL_QUEST_ID)

	QuestEvents.quest_state_changed.emit()

func _is_quest_active(quest_id: String) -> bool:
	return active_quests.has(quest_id)

func _is_quest_completed(quest_id: String) -> bool:
	return completed_quests.has(quest_id)

func _on_day_changed(new_day: int) -> void:
	print("Day changed:", new_day)
	if new_day != 1:
		return

	# Only add once: if already active or completed, do nothing.
	if active_quests.has(TUTORIAL_QUEST_ID) or completed_quests.has(TUTORIAL_QUEST_ID):
		return

	var qres := load(TUTORIAL_QUEST_RES_PATH)
	if qres == null:
		push_warning("Tutorial quest resource missing: " + TUTORIAL_QUEST_RES_PATH)
		return

	add_quest(qres.to_dict())
	set_tracked_quest(TUTORIAL_QUEST_ID)

	QuestEvents.quest_state_changed.emit()

func is_travel_unlocked(travel_id: String) -> bool:
	return bool(unlocked_travel.get(travel_id, false))

func unlock_travel(travel_id: String) -> void:
	unlocked_travel[travel_id] = true
	
	(today_tracking["areas_unlocked"] as Array).append(travel_id)

	var msg := "New area unlocked!"
	if travel_id == "animal_keeper":
		msg = "New area unlocked: Animal Keeper"
	elif travel_id == "valley_heart":
		msg = "New area unlocked: Valley Heart"

	QuestEvents.toast_requested.emit(msg, "success", 3.0)

func queue_spawn_reward(scene_id: String, prefab_path: String, marker_tag: String) -> void:
	pending_spawns.append({
		"scene_id": scene_id,
		"prefab": prefab_path,
		"marker_tag": marker_tag,
	})

func _format_step_fallback(step: Dictionary) -> String:
	var t := String(step.get("type", ""))
	var target := String(step.get("target", ""))
	match t:
		"chop_wood":
			return "Chop wood"
		"buy":
			return "Buy: " + target
		"go_to":
			return "Go to: " + target
		"talk_to":
			return "Talk to: " + target
		_:
			return "Objective"

func _format_oneshot_fallback(q: Dictionary) -> String:
	var t := String(q.get("type", ""))
	var target := String(q.get("target", ""))
	match t:
		"buy":
			return "Buy: " + target
		"ship":
			return "Ship: " + target
		_:
			return "Objective"

func reset_today_tracking() -> void:
	today_tracking = {
		"shipped": {},
		"money_earned": 0,
		"quests_accepted": [],
		"quests_completed": [],
		"areas_unlocked": [],
		"pass_out": false,
		"energy_penalty": 0,
	}

func finalize_yesterday_summary(new_day: int, payout: int, shipped_copy: Dictionary) -> void:
	# This summary represents the day that just ended.
	yesterday_summary = {
		"day_ended": new_day - 1,
		"money_earned": payout,
		"shipped": shipped_copy,
		"quests_accepted": today_tracking.get("quests_accepted", []),
		"quests_completed": today_tracking.get("quests_completed", []),
		"areas_unlocked": today_tracking.get("areas_unlocked", []),
		"pass_out": today_tracking.get("pass_out", false),
		"energy_penalty": today_tracking.get("energy_penalty", 0),
	}

func _current_time_block_stamp() -> String:
	# Same idea as your talk block stamp: day + timeblock key
	var block_key := TimeManager.get_time_block_key(TimeManager.minutes)
	return str(TimeManager.day) + ":" + block_key


func can_rest_at(rest_id: String) -> bool:
	if rest_id.strip_edges() == "":
		return false
	var stamp := _current_time_block_stamp()
	return String(_rested_block_by_id.get(rest_id, "")) != stamp

func mark_rested_at(rest_id: String) -> void:
	if rest_id.strip_edges() == "":
		return
	_rested_block_by_id[rest_id] = _current_time_block_stamp()

func apply_passout_penalty() -> void:
	# Half energy next day
	energy = int(floor(max_energy * 0.5))
	if energy < 1:
		energy = 1

	# Being passed out shouldn't permanently lock you
	exhausted = false

func warp_to_farm_after_passout() -> void:
	# If you don’t want warping yet, just return here.
	# return

	if farm_scene_path.strip_edges() == "":
		return

	# Use your existing spawn-tag system
	pending_spawn_tag = passout_spawn_tag

	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_file(farm_scene_path)

func request_end_of_day_summary() -> void:
	# Defer so it works even if we're in the middle of a scene change.
	call_deferred("_show_end_of_day_summary_deferred")


func _show_end_of_day_summary_deferred() -> void:
	# Wait 1–2 frames so the new scene + HUD overlays are fully in the tree.
	await get_tree().process_frame
	await get_tree().process_frame

	var ui := get_tree().get_first_node_in_group("end_of_day_ui")
	if ui != null and ui.has_method("show_overlay"):
		ui.show_summary()

func queue_day_start_toast(msg: String, kind: String = "warning", duration: float = 3.0) -> void:
	if msg.strip_edges() == "":
		return
	_day_start_toast_queue.append({
		"msg": msg,
		"kind": kind,
		"duration": duration
	})

func flush_day_start_toasts() -> void:
	if _day_start_toast_queue.is_empty():
		return

	var eod := get_tree().get_first_node_in_group("end_of_day_ui")
	if eod != null and eod.has_method("is_open") and bool(eod.call("is_open")):
		# Summary is open — try again later
		call_deferred("flush_day_start_toasts")
		return

	# Emit all queued day-start toasts
	for t in _day_start_toast_queue:
		var msg := String(t.get("msg", ""))
		var kind := String(t.get("kind", "info"))
		var duration := float(t.get("duration", 2.5))

		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit(msg, kind, duration)

	_day_start_toast_queue.clear()

func _current_week_key() -> int:
	# Week 1 = days 1-7, week 2 = 8-14, etc.
	return int(((TimeManager.day - 1) / 7) + 1)

func can_gift_to_npc(npc_id: String) -> bool:
	npc_id = npc_id.strip_edges()
	if npc_id == "":
		return false

	var today := TimeManager.day
	if int(_gifted_day_by_npc.get(npc_id, -1)) == today:
		return false  # already gifted today

	var wk := _current_week_key()
	var wk_map: Dictionary = _gifted_week_count_by_npc.get(npc_id, {})
	var count_this_week := int(wk_map.get(wk, 0))

	# 2 gifts per week max
	return count_this_week < 2

func mark_gifted_to_npc(npc_id: String) -> void:
	npc_id = npc_id.strip_edges()
	if npc_id == "":
		return

	var today := TimeManager.day
	_gifted_day_by_npc[npc_id] = today

	var wk := _current_week_key()
	var wk_map: Dictionary = _gifted_week_count_by_npc.get(npc_id, {})
	var count_this_week := int(wk_map.get(wk, 0))
	wk_map[wk] = count_this_week + 1
	_gifted_week_count_by_npc[npc_id] = wk_map

func try_play_pending_cutscene() -> void:
	if pending_cutscene_id == "":
		return

	var id := pending_cutscene_id
	pending_cutscene_id = ""

	# For now: dialogue-only cutscene stub.
	# We'll replace this later with a proper CutsceneDirector.
	if id == "heart_intro":
		_play_heart_intro_stub()

func _play_heart_intro_stub() -> void:
	lock_gameplay()
	
	var lines: Array[String] = []
	lines.append("Good morning…")
	lines.append("I need to show you something special.")
	lines.append("Meet me at the Heart of the Valley.")
	
	var mayor_id := "npc_mayor" # or whatever ID you use consistently
	var f := GameState.get_friendship(mayor_id) # should return int

	# Show dialogue through your existing dialogue UI
	var ui := get_tree().get_first_node_in_group("dialogue_ui")
	if ui and ui.has_method("show_dialogue"):
		ui.show_dialogue("Mayor", lines, f)

	# SAFEST: unlock after a short delay for now.
	# Later we'll unlock exactly when dialogue ends (via a dialogue_finished signal).
	await get_tree().create_timer(0.25).timeout

	# Unlock Heart travel now (or after quest add)
	unlock_travel("valley_heart") # rename to match your travel unlock API
	unlock_gameplay()

func _connect_cutscene_finish(ui: Node) -> void:
	# Only connect if the UI actually has the signal
	if ui.has_signal("dialogue_closed"):
		# Avoid double-connecting if something weird happens
		var cb := Callable(self, "_on_heart_intro_dialogue_closed")
		if not ui.is_connected("dialogue_closed", cb):
			ui.connect("dialogue_closed", cb, CONNECT_ONE_SHOT)
	else:
		# Fallback: if no signal exists, just clear pending so you don’t soft-lock
		_clear_pending_cutscene()

func _on_heart_intro_dialogue_closed() -> void:
	GameState.unlock_travel("valley_heart")
	_clear_pending_cutscene()


func _clear_pending_cutscene() -> void:
	pending_cutscene_id = ""

func apply_heart_reward(r) -> void:
	# r is HeartRewardDefinition
	if r == null:
		return

	match r.kind:
		r.RewardKind.STAT_ADD:
			var k := str(r.stat_key)
			heart_stats[k] = float(heart_stats.get(k, 0.0)) + float(r.amount)

		r.RewardKind.STAT_MULTIPLY:
			var k := str(r.stat_key)
			var cur := float(heart_stats.get(k, 1.0))
			heart_stats[k] = cur * float(r.amount)

		r.RewardKind.FLAG_SET:
			heart_flags[str(r.flag_key)] = bool(r.flag_value)

		_:
			pass

	print("[GameState] Applied Heart reward:", r.id, " stats=", heart_stats, " flags=", heart_flags)
