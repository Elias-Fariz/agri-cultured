# GameState.gd
extends Node

var next_spawn_name: String = ""

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
	return total

func shipping_payout_and_clear() -> int:
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

func can_gain_talk_friendship(npc_id: String, current_day: int) -> bool:
	return int(npc_last_talk_day.get(npc_id, -999999)) != current_day

func mark_talked_today(npc_id: String, current_day: int) -> void:
	npc_last_talk_day[npc_id] = current_day
	
# -------------------------
# QUEST SYSTEM
# -------------------------

var active_quests: Dictionary = {}    # id -> quest dict
var completed_quests: Dictionary = {} # id -> quest dict


func _ready() -> void:
	reset_energy()
	current_tool = starting_tool
	
	QuestEvents.talked_to.connect(_on_quest_talked_to)
	QuestEvents.went_to.connect(_on_quest_went_to)

	QuestEvents.shipped.connect(_on_quest_shipped)
	QuestEvents.chopped_tree.connect(_on_quest_chopped_tree)
	QuestEvents.broke_rock.connect(_on_quest_broke_rock)
	QuestEvents.harvested.connect(_on_quest_harvested)

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
	QuestEvents.quest_state_changed.emit()

func complete_quest(quest_id: String) -> void:
	if not active_quests.has(quest_id):
		return

	var quest: Dictionary = active_quests[quest_id]
	quest["completed"] = true
	active_quests.erase(quest_id)
	completed_quests[quest_id] = quest
	print("Quest completed: ", quest_id)
	
func claim_quest_reward(quest_id: String) -> void:
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
	
	QuestEvents.quest_state_changed.emit()

	print("Quest reward claimed for ", quest_id)

func _on_quest_talked_to(npc_id: String) -> void:
	_debug_chain("BEFORE talk " + npc_id)

	_increment_matching_quests("talk_to", npc_id, 1)
	_try_advance_chain_quest("main_mayor_strawberry", "talk_to", npc_id, 1)

	_debug_chain("AFTER  talk " + npc_id)
	
	GameState.apply_quest_event("talk_to", npc_id, 1)
	QuestEvents.quest_state_changed.emit()
	# chain quests
	#for qid in active_quests.keys():
	#	_try_advance_chain_quest(String(qid), "talk_to", npc_id, 1)

func _on_quest_went_to(location_id: String) -> void:
	_debug_chain("BEFORE go_to " + location_id)

	_increment_matching_quests("go_to", location_id, 1)
	_try_advance_chain_quest("main_mayor_strawberry", "go_to", location_id, 1)

	_debug_chain("AFTER  go_to " + location_id)
	
	GameState.apply_quest_event("go_to", location_id, 1)
	QuestEvents.quest_state_changed.emit()
	#for qid in active_quests.keys():
	#	_try_advance_chain_quest(String(qid), "go_to", location_id, 1)

func _on_quest_shipped(item_id: String, amount: int) -> void:
	_debug_chain("BEFORE ship " + item_id)

	_increment_matching_quests("ship", item_id, amount)
	_try_advance_chain_quest("main_mayor_strawberry", "ship", item_id, amount)
	#for qid in active_quests.keys():
	#	_try_advance_chain_quest(String(qid), "ship", item_id, amount)
	
	GameState.apply_quest_event("ship", item_id, amount)
	QuestEvents.quest_state_changed.emit()

func _on_quest_chopped_tree(amount: int) -> void:
	_increment_matching_quests("chop_tree", "", amount)

func _on_quest_broke_rock(amount: int) -> void:
	_increment_matching_quests("break_rock", "", amount)

func _on_quest_harvested(item_id: String, amount: int) -> void:
	_increment_matching_quests("harvest", item_id, amount)

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

func get_quest_objective_text(q: Dictionary) -> String:
	if q.is_empty():
		return ""

	# If completed but not claimed → show turn-in instruction
	if bool(q.get("completed", false)) and not bool(q.get("claimed", false)):
		var t: String = String(q.get("turn_in_text", ""))
		if t != "":
			return t

		# fallback if text not set
		var turn_in_id := String(q.get("turn_in_id", ""))
		if turn_in_id != "":
			return "Return to %s to collect your reward." % turn_in_id
		return "Collect your reward."

	# Chain quest: show current step text
	if String(q.get("type","")) == "chain":
		var steps: Array = q.get("steps", [])
		var idx: int = int(q.get("step_index", 0))
		if idx >= 0 and idx < steps.size():
			return String(steps[idx].get("text", ""))
		return ""

	# Single-step quest: show description or progress
	var title := String(q.get("title", "Quest"))
	var progress := int(q.get("progress", 0))
	var amount := int(q.get("amount", 0))
	if amount > 0:
		return "%s (%d/%d)" % [String(q.get("description", title)), progress, amount]
	return String(q.get("description", title))

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

func apply_quest_event(action: String, target: String = "", amount: int = 1) -> void:
	var changed: bool = false
	var to_complete: Array[String] = []

	# Iterate over KEYS (stable) instead of values (can break if dict mutates)
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
			if target != "" and String(step.get("target", "")) != target:
				continue

			# We matched a valid step → changed!
			changed = true

			step["progress"] = int(step.get("progress", 0)) + amount
			steps[step_index] = step
			quest["steps"] = steps

			if int(step["progress"]) >= int(step.get("amount", 0)):
				quest["step_index"] = step_index + 1

				# Done with all steps?
				if int(quest["step_index"]) >= steps.size():
					to_complete.append(qid)

			# write back (important!)
			active_quests[qid] = quest
			continue

		# ----- ONESHOT QUESTS -----
		if String(quest.get("type", "")) != action:
			continue
		if target != "" and String(quest.get("target", "")) != target:
			continue

		changed = true

		quest["progress"] = int(quest.get("progress", 0)) + amount
		if int(quest["progress"]) >= int(quest.get("amount", 0)):
			to_complete.append(qid)

		active_quests[qid] = quest

	# Complete AFTER iteration (safe)
	for qid in to_complete:
		complete_quest(qid)
		changed = true

	if changed:
		QuestEvents.quest_state_changed.emit()
