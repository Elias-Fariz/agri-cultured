# GameState.gd
extends Node

enum ToolType { HAND, 
	HOE, 
	SEED_POUCH,
	WATERING_CAN , 
	AXE, 
	PICKAXE, 
	BUCKET,
	FISHING_ROD
}
const TOOL_COUNT := 8  # <- THIS MUST BE UPDATED

# ----------------------------
# Global crop-world processing
# ----------------------------

const FARM_WORLD_ID := "Farm"

# These must match Farm.gd's tile settings.
# If you later change Farm.gd's tile source/coords, update these too.
@export var farm_ground_source_id: int = 0
@export var farm_tilled_coords: Vector2i = Vector2i(1, 0)
@export var farm_wet_tilled_coords: Vector2i = Vector2i(2, 0)

@export var starting_tool: ToolType = ToolType.HAND
var current_tool: ToolType = ToolType.HAND

signal tool_changed(tool_type: int, tool_name: String)
signal tool_list_changed()

signal inventory_changed()
signal seed_selection_changed(seed_id: String, display_text: String, quantity: int)

# Tools the player currently owns/unlocked.
# Bucket and Fishing Rod are intentionally not here yet.
var owned_tools: Array[int] = []

var game_flags: Dictionary = {}

# flag_id -> day number when the flag was set true.
# Used by cutscene rules that wait N days after a flag is set.
var game_flag_set_days: Dictionary = {}

# rule_id -> day number when all non-flag conditions first passed.
# Used as fallback delay tracking for rules without required flags.
var cutscene_rule_ready_days: Dictionary = {}

var default_owned_tools: Array[int] = [
	ToolType.HAND,
	ToolType.HOE,
	ToolType.SEED_POUCH,
	ToolType.WATERING_CAN,
	ToolType.AXE,
	ToolType.PICKAXE,
]

# This is the preferred display order.
# The UI will only show tools that are also in owned_tools.
var tool_display_order: Array[int] = [
	ToolType.HAND,
	ToolType.HOE,
	ToolType.SEED_POUCH,
	ToolType.WATERING_CAN,
	ToolType.AXE,
	ToolType.PICKAXE,
	ToolType.BUCKET,
	ToolType.FISHING_ROD,
]

# ----------------------------
# Inventory (already working)
# ----------------------------
var inventory: Dictionary = {}  # { "Wood": 3, "Stone": 2 }
var _consume_item_locked: bool = false
	
# -------------------------
# INVENTORY HELPERS
# -------------------------
# inventory is already: { "Wood": 3, ... }

func inventory_add(item_name: String, qty: int = 1) -> void:
	if item_name.is_empty() or qty <= 0:
		return

	inventory[item_name] = int(inventory.get(item_name, 0)) + qty

	inventory_changed.emit()
	_refresh_selected_seed_after_inventory_change()

	# print("Added to inventory:", item_name, " Inventory now:", inventory)

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
	
	inventory_changed.emit()
	_refresh_selected_seed_after_inventory_change()
	
	return true

func _finish_consume_item(result: bool) -> bool:
	_consume_item_locked = false
	return result

func consume_item(item_id: String) -> bool:
	if _consume_item_locked:
		return _finish_consume_item(false)

	_consume_item_locked = true
	
	item_id = item_id.strip_edges()
	if item_id == "":
		return _finish_consume_item(false)

	# Must have item
	if not inventory_has(item_id, 1):
		return _finish_consume_item(false)

	# Look up ItemData
	var data = null
	if ItemDb != null and ItemDb.has_method("get_item"):
		data = ItemDb.get_item(item_id)

	if data == null:
		# print("consume_item: No ItemData found for:", item_id)
		return _finish_consume_item(false)

	var restore := int(data.energy_restore)

	# Food effects are optional.
	# Use data.get() so this does not explode if an older ItemData resource/script
	# does not have food_effects set up yet.
	var effects: Array = []
	var raw_effects = data.get("food_effects")
	if raw_effects is Array:
		effects = raw_effects

	var has_effects := false
	for effect in effects:
		if effect == null:
			continue
		if effect is FoodEffectData and effect.is_valid():
			has_effects = true
			break

	var can_restore_energy := restore > 0 and energy < max_energy

	# If the item gives neither usable energy nor a buff, don't consume it.
	if not can_restore_energy and not has_effects:
		# print("consume_item: Item is not currently useful to consume:", item_id)
		return _finish_consume_item(false)

	# Apply energy restore if useful.
	if can_restore_energy:
		energy = min(max_energy, energy + restore)

	# Apply food effects if any.
	if has_effects:
		for effect in effects:
			if effect == null:
				continue
			if effect is FoodEffectData and effect.is_valid():
				apply_food_effect(effect)

	# Consume one item only after we know it did something useful.
	var removed := inventory_remove(item_id, 1)
	if not removed:
		return _finish_consume_item(false)

	# Cozy feedback
	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		if can_restore_energy and has_effects:
			QuestEvents.toast_requested.emit("+" + str(restore) + " Energy, and you feel prepared.", "success", 2.5)
		elif can_restore_energy:
			QuestEvents.toast_requested.emit("+" + str(restore) + " Energy", "success", 2.0)
		elif has_effects:
			QuestEvents.toast_requested.emit("You feel prepared.", "success", 2.0)

	return _finish_consume_item(true)

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

var animal_states: Dictionary = {}

var tracked_quest_id: String = ""  # "" means no quest tracked

var ready_to_turn_in: Dictionary = {}

# --- Scene spawning ---
var next_spawn_name: String = ""      # your existing system
var pending_spawn_tag: String = ""    # optional future tag system

var is_scene_traveling: bool = false

@export var travel_fade_out_time: float = 0.18
@export var travel_fade_in_time: float = 0.24
@export var travel_frames_after_scene_change: int = 4


func is_seed_item(item_id: String) -> bool:
	return seed_to_crop.has(item_id)

func get_crop_for_seed(item_id: String) -> String:
	return String(seed_to_crop.get(item_id, ""))

func set_selected_item(item_id: String) -> void:
	selected_item_id = item_id
	# print("Selected item:", selected_item_id)
	_emit_seed_selection_changed()

func get_selected_seed_quantity() -> int:
	if selected_item_id.strip_edges() == "":
		return 0
	return int(inventory.get(selected_item_id, 0))


func get_selected_seed_display_text() -> String:
	if selected_item_id.strip_edges() == "":
		return "No seeds"

	if not is_seed_item(selected_item_id):
		return "No seeds"

	var qty := get_selected_seed_quantity()
	return "%s x%d" % [selected_item_id, qty]


func get_selected_seed_short_text() -> String:
	if selected_item_id.strip_edges() == "":
		return "Seeds\nNone"

	if not is_seed_item(selected_item_id):
		return "Seeds\nNone"

	var qty := get_selected_seed_quantity()
	var name := selected_item_id

	# Keep the tool belt slot readable.
	name = name.replace(" Seeds", "")

	return "Seeds\n%s x%d" % [name, qty]

func apply_dialogue_sequence_rewards(sequence: DialogueSequenceData, source_id: String = "") -> void:
	if sequence == null:
		return

	if not sequence.has_completion_rewards():
		return

	var sequence_id := String(sequence.sequence_id).strip_edges()

	var reward_flag := ""
	if sequence_id != "":
		reward_flag = "dialogue_reward_claimed:" + sequence_id
	elif source_id.strip_edges() != "":
		reward_flag = "dialogue_reward_claimed:" + source_id

	# Prevent repeated rewards if requested.
	if sequence.rewards_once and reward_flag != "":
		if has_flag(reward_flag):
			return

	var reward := sequence.get_completion_reward_dict()
	if not reward.is_empty():
		apply_reward_dict(reward, "dialogue:%s" % (sequence_id if sequence_id != "" else source_id))

	# Add quest rewards, if any.
	for qd in sequence.reward_quests:
		if qd == null:
			continue

		var quest_id := String(qd.id).strip_edges()
		if quest_id == "":
			continue

		if active_quests.has(quest_id):
			continue
		if completed_quests.has(quest_id):
			continue

		add_quest(qd.to_dict())

	if sequence.rewards_once and reward_flag != "":
		set_flag(reward_flag, true)

	if sequence.show_reward_toast:
		_show_dialogue_reward_toast(sequence)

	if QuestEvents != null and QuestEvents.has_signal("quest_state_changed"):
		QuestEvents.quest_state_changed.emit()


func _show_dialogue_reward_toast(sequence: DialogueSequenceData) -> void:
	if QuestEvents == null:
		return
	if not QuestEvents.has_signal("toast_requested"):
		return

	# Keep this gentle and not too spammy.
	if not sequence.reward_items.is_empty():
		for item_id_any in sequence.reward_items.keys():
			var item_id := String(item_id_any)
			var qty := int(sequence.reward_items[item_id_any])
			if qty > 0:
				QuestEvents.toast_requested.emit("Received: %s x%d" % [item_id, qty], "success", 2.5)
				return

	if sequence.reward_money > 0:
		QuestEvents.toast_requested.emit("Received: %d coins" % sequence.reward_money, "success", 2.5)
		return

	if not sequence.reward_crafting_recipe_ids.is_empty():
		QuestEvents.toast_requested.emit("New crafting idea learned.", "success", 2.5)
		return

	if not sequence.reward_cooking_recipe_ids.is_empty():
		QuestEvents.toast_requested.emit("New recipe learned.", "success", 2.5)
		return

	if not sequence.reward_flags.is_empty():
		# Help page flags already get their own toast from set_flag(), if you added that patch.
		var has_only_help_pages := true
		for flag_any in sequence.reward_flags:
			var flag_id := String(flag_any)
			if not flag_id.begins_with("help_page:"):
				has_only_help_pages = false
				break

		if not has_only_help_pages:
			QuestEvents.toast_requested.emit("Something changed.", "info", 2.0)

func cycle_seed_previous() -> void:
	var seeds := get_all_seed_ids_in_inventory()
	if seeds.is_empty():
		selected_item_id = ""
		# print("No seeds in inventory to select.")
		_emit_seed_selection_changed()
		return

	if not is_seed_item(selected_item_id) or not seeds.has(selected_item_id):
		set_selected_item(seeds[seeds.size() - 1])
		return

	var idx := seeds.find(selected_item_id)
	idx -= 1
	if idx < 0:
		idx = seeds.size() - 1

	set_selected_item(seeds[idx])


func _refresh_selected_seed_after_inventory_change() -> void:
	var seeds := get_all_seed_ids_in_inventory()

	# If there are no seeds at all, clear the selected seed.
	if seeds.is_empty():
		if selected_item_id != "":
			selected_item_id = ""
		_emit_seed_selection_changed()
		return

	# If nothing is selected, automatically select the first available seed.
	if selected_item_id.strip_edges() == "":
		set_selected_item(seeds[0])
		return

	# If the selected item is not a seed, switch to the first available seed.
	if not is_seed_item(selected_item_id):
		set_selected_item(seeds[0])
		return

	# If the selected seed still exists, keep it and just refresh quantity.
	if inventory_has(selected_item_id, 1):
		_emit_seed_selection_changed()
		return

	# If the selected seed ran out, move to the next available seed.
	set_selected_item(seeds[0])

func _emit_seed_selection_changed() -> void:
	var qty := get_selected_seed_quantity()
	seed_selection_changed.emit(selected_item_id, get_selected_seed_display_text(), qty)

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
		# print("No seeds in inventory to select.")
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
	action = action.strip_edges()
	if action == "":
		return

	if action == "chop_tree":
		QuestEvents.chopped_tree.emit(amount)
	elif action == "break_rock":
		QuestEvents.broke_rock.emit(amount)
	else:
		QuestEvents.action_done.emit(action, amount)

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
	var b := shipping_calculate_payout_breakdown()
	return int(b.get("final", 0))

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
	var breakdown := shipping_calculate_payout_breakdown()
	var payout := int(breakdown["final"])
	if payout > 0:
		MoneySystem.add(payout)

	finalize_yesterday_summary(TimeManager.day, payout, shipped_copy)


	# Prepare tracking for the NEW day
	reset_today_tracking()

	# 3) Clear the bin
	shipping_bin.clear()
	return payout

func shipping_calculate_payout_breakdown() -> Dictionary:
	# Returns:
	# { "base": int, "mul": float, "bonus": int, "final": int }
	var base_total := 0
	for item_name in shipping_bin.keys():
		var qty := int(shipping_bin[item_name])
		base_total += get_sell_price(String(item_name)) * qty

	var mul := 1.0
	if has_node("/root/HeartProgress"):
		mul = float(get_node("/root/HeartProgress").call("get_sell_multiplier"))

	var final_total := int(round(float(base_total) * mul))
	var bonus := final_total - base_total

	return {
		"base": base_total,
		"mul": mul,
		"bonus": bonus,
		"final": final_total,
	}

# ----------------------------
# Energy / Stamina (NEW)
# ----------------------------
@export var max_energy: int = 10
@export var tool_action_cost: int = 1

var energy: int = 10  # will be set on _ready
var exhausted: bool = false

# ----------------------------
# World State (runtime persistence across scenes)
# ----------------------------
var world_state: Dictionary = {}
# Example:
# world_state["Farm"] = { ...data... }

var mining_food_bonus_applied_today: Dictionary = {}

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

var ready_to_turn_in_quests: Dictionary = {}     # quest_id -> true
var recently_claimed_quests: Dictionary = {}     # quest_id -> day number

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

var _last_animal_day_processed: int = -1

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
			

# --- Tile destructible regrowth persistence ---
# spot_id -> {
#   "kind": String,                 # "tree", "rock", etc.
#   "scene_path": String,           # current scene path/name marker
#   "objects_path": String,         # node path to the objects TileMap inside scene
#   "cell": Vector2i,               # tile cell
#   "respawn_day": int,             # day full resource returns
#   "sprout_day": int,              # day regrowth visual begins (-1 if unused)
# }
var _regrowing_destructibles: Dictionary = {}

func make_destructible_spot_id(scene_path: String, objects_path: String, cell: Vector2i) -> String:
	return "%s|%s|%d,%d" % [scene_path, objects_path, cell.x, cell.y]

func mark_destructible_regrowing(
	spot_id: String,
	kind: String,
	scene_path: String,
	objects_path: String,
	cell: Vector2i,
	respawn_day: int,
	sprout_day: int = -1
) -> void:
	if spot_id.strip_edges() == "":
		return

	_regrowing_destructibles[spot_id] = {
		"kind": kind,
		"scene_path": scene_path,
		"objects_path": objects_path,
		"cell": cell,
		"respawn_day": respawn_day,
		"sprout_day": sprout_day,
	}
	
	# ----------------------------
# Modal Overlay Guard
# ----------------------------
# This prevents multiple modal UI overlays from opening at the same time.
# Examples: Inventory, Shop, Crafting, Cooking, Dialogue, Quest Board, Fishing UI.

var active_modal_overlay_id: String = ""
var _modal_overlay_block_until_msec: int = 0

func block_modal_overlays_for(seconds: float = 0.35) -> void:
	var duration_msec := int(max(0.0, seconds) * 1000.0)
	_modal_overlay_block_until_msec = max(
		_modal_overlay_block_until_msec,
		Time.get_ticks_msec() + duration_msec
	)

func are_modal_overlays_temporarily_blocked() -> bool:
	return Time.get_ticks_msec() < _modal_overlay_block_until_msec

func can_open_modal_overlay(overlay_id: String) -> bool:
	overlay_id = overlay_id.strip_edges()

	if are_modal_overlays_temporarily_blocked():
		return false

	if active_modal_overlay_id == "":
		return true

	# Allow the same overlay to refresh/re-show itself safely.
	return active_modal_overlay_id == overlay_id

func try_open_modal_overlay(overlay_id: String) -> bool:
	overlay_id = overlay_id.strip_edges()
	if overlay_id == "":
		overlay_id = "unnamed_modal_overlay"

	if not can_open_modal_overlay(overlay_id):
		return false

	active_modal_overlay_id = overlay_id
	return true

func close_modal_overlay(overlay_id: String) -> void:
	overlay_id = overlay_id.strip_edges()

	if active_modal_overlay_id == "":
		return

	if active_modal_overlay_id == overlay_id:
		active_modal_overlay_id = ""

func get_active_modal_overlay_id() -> String:
	return active_modal_overlay_id

# ----------------------------
# Item Use Safety Guard
# ----------------------------
# Prevents item consumption during tiny cleanup windows after cutscenes/dialogues.

var _item_use_block_until_msec: int = 0

func block_item_use_for(seconds: float = 0.75) -> void:
	var duration_msec := int(max(0.0, seconds) * 1000.0)
	_item_use_block_until_msec = max(
		_item_use_block_until_msec,
		Time.get_ticks_msec() + duration_msec
	)

func can_use_items_now() -> bool:
	return Time.get_ticks_msec() >= _item_use_block_until_msec

func get_destructible_regrowth_record(spot_id: String) -> Dictionary:
	return _regrowing_destructibles.get(spot_id, {})

func is_destructible_regrowing(spot_id: String) -> bool:
	return _regrowing_destructibles.has(spot_id)

func clear_destructible_regrowth_record(spot_id: String) -> void:
	if _regrowing_destructibles.has(spot_id):
		_regrowing_destructibles.erase(spot_id)

func get_regrowth_stage_for_day(spot_id: String, today: int = -1) -> String:
	if today < 0:
		today = int(TimeManager.day)

	var rec: Dictionary = get_destructible_regrowth_record(spot_id)
	if rec.is_empty():
		return "grown"

	var respawn_day := int(rec.get("respawn_day", today))
	var sprout_day := int(rec.get("sprout_day", -1))

	if today >= respawn_day:
		return "grown"

	if sprout_day >= 0 and today >= sprout_day:
		return "regrowing"

	return "empty"

func cleanup_finished_destructible_regrowth(today: int = -1) -> void:
	if today < 0:
		today = int(TimeManager.day)

	var to_remove: Array = []
	for spot_id in _regrowing_destructibles.keys():
		var rec: Dictionary = _regrowing_destructibles[spot_id]
		var respawn_day := int(rec.get("respawn_day", today))
		if today >= respawn_day:
			to_remove.append(spot_id)

	for spot_id in to_remove:
		_regrowing_destructibles.erase(spot_id)

func get_destructible_regrowth_records_for_world(scene_path: String, objects_path: String = "") -> Dictionary:
	var out: Dictionary = {}

	for spot_id in _regrowing_destructibles.keys():
		var rec: Dictionary = _regrowing_destructibles[spot_id]

		if String(rec.get("scene_path", "")) != scene_path:
			continue

		if objects_path != "" and String(rec.get("objects_path", "")) != objects_path:
			continue

		out[spot_id] = rec

	return out

var played_cutscenes: Dictionary = {}

# --- Crafting recipe unlocks ---
var unlocked_recipes: Dictionary = {}  # recipe_id -> true

var unlocked_cooking_recipe_ids: Dictionary = {}

func unlock_cooking_recipe(recipe_id: String) -> void:
	recipe_id = recipe_id.strip_edges()
	if recipe_id == "":
		return

	if unlocked_cooking_recipe_ids.has(recipe_id):
		return

	unlocked_cooking_recipe_ids[recipe_id] = true
	# print("[Cooking] Recipe unlocked:", recipe_id)

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit("Recipe learned: " + recipe_id, "success", 2.5)

	if QuestEvents != null and QuestEvents.has_signal("quest_state_changed"):
		QuestEvents.quest_state_changed.emit()


func has_cooking_recipe(recipe_id: String) -> bool:
	recipe_id = recipe_id.strip_edges()
	if recipe_id == "":
		return false

	return bool(unlocked_cooking_recipe_ids.get(recipe_id, false))


func get_unlocked_cooking_recipe_ids() -> Dictionary:
	return unlocked_cooking_recipe_ids.duplicate(true)

func unlock_recipe(recipe_id: String) -> void:
	if recipe_id.strip_edges() == "":
		return
	unlocked_recipes[recipe_id] = true
	# print("Unlocked: " + recipe_id)

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
var has_played_greeting_intro: bool = false

var heart_stats: Dictionary = {}   # e.g. { "sell_multiplier": 1.05 }
var heart_flags: Dictionary = {}   # e.g. { "heart_pond_unlocked": true }

var interacted_object_ids: Dictionary = {}

var active_food_buffs: Dictionary = {}

func _ready() -> void:
	reset_energy()
	_ensure_default_owned_tools()
	current_tool = starting_tool
	if not has_tool(int(current_tool)):
		current_tool = ToolType.HAND
	
	# QuestEvents.gd is now the central place that maps gameplay signals
	# into GameState.apply_quest_event(...).
	#
	# GameState should only connect to QuestEvents when it needs special
	# side effects beyond normal quest progress.

	QuestEvents.crop_harvested.connect(_on_first_harvest_heart_intro_check)
	
	var tm := get_node_or_null("/root/TimeManager")
	if tm:
		if not tm.day_changed.is_connected(_on_day_changed):
			tm.day_changed.connect(_on_day_changed)

		if tm.has_signal("time_changed") and not tm.time_changed.is_connected(_on_time_changed):
			tm.time_changed.connect(_on_time_changed)
	
	#unlock_recipe("shell_necklace")
	#unlock_recipe("flower_headband")
	
	#unlock_cooking_recipe("warm_milk")
	
	if not has_played_greeting_intro:
		pending_cutscene_id = "greeting_intro"
		has_played_greeting_intro = true

var _last_buff_tick_minute: int = -1

func _on_time_changed(current_minutes: int) -> void:
	if _last_buff_tick_minute < 0:
		_last_buff_tick_minute = current_minutes
		return

	var delta := current_minutes - _last_buff_tick_minute

	# If time wrapped or jumped due sleep/passout, don't tick here.
	# start_new_day() clears buffs separately.
	if delta < 0:
		_last_buff_tick_minute = current_minutes
		return

	if delta > 0:
		tick_timed_food_buffs(delta)

	_last_buff_tick_minute = current_minutes


func _ensure_default_owned_tools() -> void:
	if owned_tools.is_empty():
		owned_tools = default_owned_tools.duplicate()


func has_tool(tool_type: int) -> bool:
	_ensure_default_owned_tools()
	return owned_tools.has(tool_type)


func unlock_tool(tool_type: int) -> void:
	if tool_type < 0 or tool_type >= TOOL_COUNT:
		return

	_ensure_default_owned_tools()

	if owned_tools.has(tool_type):
		return

	owned_tools.append(tool_type)
	tool_list_changed.emit()

	var msg := "New tool unlocked: " + get_tool_name_for(tool_type)
	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(msg, "success", 2.5)


func get_owned_tool_order() -> Array[int]:
	_ensure_default_owned_tools()

	var out: Array[int] = []
	for t in tool_display_order:
		if owned_tools.has(t):
			out.append(t)

	return out


func cycle_tool_next() -> void:
	var tools := get_owned_tool_order()
	if tools.is_empty():
		return

	var idx := tools.find(int(current_tool))
	if idx < 0:
		set_current_tool(int(tools[0]))
		return

	idx = (idx + 1) % tools.size()
	set_current_tool(int(tools[idx]))


func cycle_tool_previous() -> void:
	var tools := get_owned_tool_order()
	if tools.is_empty():
		return

	var idx := tools.find(int(current_tool))
	if idx < 0:
		set_current_tool(int(tools[0]))
		return

	idx -= 1
	if idx < 0:
		idx = tools.size() - 1

	set_current_tool(int(tools[idx]))


func set_current_tool(tool_type: int) -> void:
	if tool_type < 0 or tool_type >= TOOL_COUNT:
		return

	if not has_tool(tool_type):
		return

	current_tool = tool_type
	tool_changed.emit(int(current_tool), get_tool_name())


func get_tool_name_for(tool_type: int) -> String:
	match tool_type:
		ToolType.AXE:
			return "Axe"
		ToolType.PICKAXE:
			return "Pickaxe"
		ToolType.HOE:
			return "Hoe"
		ToolType.BUCKET:
			return "Bucket"
		ToolType.HAND:
			return "Hands"
		ToolType.WATERING_CAN:
			return "Watering Can"
		ToolType.SEED_POUCH:
			return "Seeds"
		ToolType.FISHING_ROD:
			return "Fishing Rod"
	return "?"


func get_tool_name() -> String:
	return get_tool_name_for(int(current_tool))

func reset_energy() -> void:
	energy = max_energy
	exhausted = false

	# Valley Heart blessing: bonus energy ONLY when you sleep (since passout uses apply_passout_penalty)
	var bonus := 0
	if has_node("/root/HeartProgress"):
		bonus = int(get_node("/root/HeartProgress").call("get_energy_bonus_on_sleep"))

	if bonus > 0:
		energy = min(max_energy + bonus, energy + bonus)
		# If you prefer a hard cap at max_energy, use:
		# energy = min(max_energy, energy + bonus)

		# Optional cozy feedback (safe)
		if has_node("/root/QuestEvents"):
			var qe := get_node("/root/QuestEvents")
			if qe != null and qe.has_signal("toast_requested"):
				QuestEvents.toast_requested.emit("Valley Heart Blessing: +" + str(bonus) + " energy", "success", 2.5)

func can_spend(cost: int) -> bool:
	return energy >= cost

# Returns true if spent successfully, false if not enough energy
func spend_energy(cost: int) -> bool:
	cost = max(0, cost)

	if cost <= 0:
		return true

	if energy < cost:
		exhausted = true
		return false

	energy -= cost

	if energy <= 0:
		energy = 0

		if _try_soft_recovery():
			return true

		exhausted = true

	return true

func _try_soft_recovery() -> bool:
	var recovery := get_food_buff_amount(FoodEffectData.EffectKey.ENERGY_SOFT_RECOVERY)
	if recovery <= 0.0:
		return false

	var recovered :Variant= max(1, int(round(recovery)))
	energy = min(max_energy, recovered)
	exhausted = false

	if has_method("consume_food_buff_use"):
		consume_food_buff_use(FoodEffectData.EffectKey.ENERGY_SOFT_RECOVERY)

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit("Soft Recovery helped you catch your breath.", "success", 2.5)

	return true

func get_map_state(map_name: String) -> Dictionary:
	if not world_state.has(map_name):
		world_state[map_name] = {
			"has_initialized": false,
			"ground": {},          # cell_key -> tile info
			"objects": {},         # cell_key -> tile info
			"crops": {},           # cell_key -> crop info
			"hits": {},
			"watered_today": {},   # cell_key -> true
			"rained_today": false
		}

	var map: Dictionary = world_state[map_name]

	# Backward-compatible safety for older saved state.
	if not map.has("ground"):
		map["ground"] = {}
	if not map.has("objects"):
		map["objects"] = {}
	if not map.has("crops"):
		map["crops"] = {}
	if not map.has("hits"):
		map["hits"] = {}
	if not map.has("watered_today"):
		map["watered_today"] = {}
	if not map.has("rained_today"):
		map["rained_today"] = false
	if not map.has("has_initialized"):
		map["has_initialized"] = false

	world_state[map_name] = map
	return map

func process_crop_worlds_new_day() -> void:
	# If the current scene is Farm and has unsaved changes, save them first.
	# This protects the case where the player sleeps/passes out while Farm is loaded.
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("_save_farm_state"):
		scene.call("_save_farm_state")

	_process_farm_crops_new_day()


func _process_farm_crops_new_day() -> void:
	if not world_state.has(FARM_WORLD_ID):
		return

	var map: Dictionary = get_map_state(FARM_WORLD_ID)

	if not bool(map.get("has_initialized", false)):
		return

	var crops: Dictionary = Dictionary(map.get("crops", {}))
	if crops.is_empty():
		# Clear old watering and dry any wet tilled soil,
		# even if there are no crops planted.
		map["watered_today"] = {}
		_dry_farm_ground_tiles(map)

		var raining_now := _is_raining_today_global()
		map["rained_today"] = raining_now

		# If it is raining today, re-wet saved farm visuals.
		if raining_now:
			_apply_farm_rain_wet_visuals_to_saved_map(map)

		world_state[FARM_WORLD_ID] = map
		return

	var watered_today: Dictionary = Dictionary(map.get("watered_today", {}))

	# This is the rain from the day that just ended.
	var grew_from_rain := bool(map.get("rained_today", false))

	# Extra safety if your WeatherChange autoload tracks yesterday.
	if WeatherChange != null and WeatherChange.has_method("was_raining_yesterday"):
		grew_from_rain = grew_from_rain or bool(WeatherChange.was_raining_yesterday())

	# print("[Crops] Processing Farm new day. grew_from_rain=", grew_from_rain, " crops=", crops.size())

	_advance_crop_map_one_day(FARM_WORLD_ID, map, grew_from_rain, watered_today)

	# Overnight: old watering dries.
	map["watered_today"] = {}
	_dry_farm_ground_tiles(map)

	# New day rain state.
	var raining_now := _is_raining_today_global()
	map["rained_today"] = raining_now

	if raining_now:
		_apply_farm_rain_wet_visuals_to_saved_map(map)

	world_state[FARM_WORLD_ID] = map

	if QuestEvents != null and QuestEvents.has_signal("quest_state_changed"):
		QuestEvents.quest_state_changed.emit()


func _advance_crop_map_one_day(
	world_id: String,
	map: Dictionary,
	raining_previous_day: bool,
	watered_today: Dictionary
) -> void:
	var crops: Dictionary = Dictionary(map.get("crops", {}))
	var objects: Dictionary = Dictionary(map.get("objects", {}))
	var season_name := _get_current_season_name_global()

	for cell_key_any in crops.keys():
		var cell_key := String(cell_key_any)
		var data: Dictionary = Dictionary(crops[cell_key_any])

		var crop_name := String(data.get("type", ""))
		if crop_name == "":
			continue

		var crop :CropData= CropDb.get_crop(crop_name) if CropDb != null else null
		if crop == null or not crop.is_valid():
			continue

		var stage := int(data.get("stage", 0))
		var watered := raining_previous_day or bool(watered_today.get(cell_key, false))

		var ignore_after := int(crop.ignore_water_after_stage)
		var needs_water := true
		if ignore_after != -1 and stage >= ignore_after:
			needs_water = false

		if needs_water and not watered:
			crops[cell_key_any] = data
			continue

		if CropDb != null and CropDb.should_chill_today(crop, season_name):
			crops[cell_key_any] = data
			continue

		var days_left := int(data.get("days_left", 1)) - 1
		data["days_left"] = days_left

		if days_left > 0:
			crops[cell_key_any] = data
			continue

		var next_stage := stage + 1

		if next_stage >= crop.stage_atlas_coords.size():
			data["stage"] = crop.stage_atlas_coords.size() - 1
			data["days_left"] = 9999
			crops[cell_key_any] = data
			continue

		data["stage"] = next_stage
		data["days_left"] = CropDb.get_effective_stage_days(crop, next_stage, season_name)
		crops[cell_key_any] = data

		objects[cell_key] = {
			"src": int(crop.tile_source_id),
			"atlas": crop.stage_atlas_coords[next_stage]
		}

		# print("[Crops] ", world_id, " ", crop_name, " grew to stage ", next_stage, " at ", cell_key)

	map["crops"] = crops
	map["objects"] = objects


func _dry_farm_ground_tiles(map: Dictionary) -> void:
	var ground: Dictionary = Dictionary(map.get("ground", {}))

	for cell_key_any in ground.keys():
		var entry: Dictionary = Dictionary(ground[cell_key_any])
		var src := int(entry.get("src", -1))
		var atlas := Vector2i(entry.get("atlas", Vector2i.ZERO))

		if src == farm_ground_source_id and atlas == farm_wet_tilled_coords:
			entry["atlas"] = farm_tilled_coords
			ground[cell_key_any] = entry

	map["ground"] = ground


func _apply_farm_rain_wet_visuals_to_saved_map(map: Dictionary) -> void:
	var ground: Dictionary = Dictionary(map.get("ground", {}))

	for cell_key_any in ground.keys():
		var entry: Dictionary = Dictionary(ground[cell_key_any])

		var src := int(entry.get("src", -1))
		var atlas := Vector2i(entry.get("atlas", Vector2i.ZERO))

		if src == farm_ground_source_id and atlas == farm_tilled_coords:
			entry["atlas"] = farm_wet_tilled_coords
			ground[cell_key_any] = entry

	map["ground"] = ground


func _is_raining_today_global() -> bool:
	if WeatherChange == null:
		return false
	if not WeatherChange.has_method("is_raining"):
		return false
	return bool(WeatherChange.is_raining())


func _get_current_season_name_global() -> String:
	if CalendarSystem != null and CalendarSystem.has_method("get_season_name"):
		return String(CalendarSystem.get_season_name())

	return "Sunwake"

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
	# print("Quest accepted: ", id)

	# NEW: rewards granted immediately when the quest is accepted.
	# This is what lets the Fisher give the Fishing Rod at quest start.
	var accept_reward: Dictionary = Dictionary(q.get("accept_reward", {}))
	if not accept_reward.is_empty():
		apply_reward_dict(accept_reward, "quest_accept:%s" % id)

	if tracked_quest_id == "":
		tracked_quest_id = id

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
	clear_quest_ready_to_turn_in(quest_id)

	# print("Quest completed: ", quest_id)

	var title := String(quest.get("title", "Quest"))
	if not (today_tracking["quests_completed"] as Array).has(title):
		(today_tracking["quests_completed"] as Array).append(title)

	QuestEvents.toast_requested.emit("Quest Completed: " + title, "success", 3.0)
	QuestEvents.quest_state_changed.emit()

func is_quest_ready_to_turn_in(quest_id: String) -> bool:
	if quest_id.strip_edges() == "":
		return false
	return ready_to_turn_in_quests.has(quest_id)

func mark_quest_ready_to_turn_in(quest_id: String) -> void:
	quest_id = quest_id.strip_edges()
	if quest_id == "":
		return

	if not active_quests.has(quest_id):
		return

	var quest: Dictionary = active_quests[quest_id]
	quest["ready_to_turn_in"] = true
	quest["completed"] = false
	quest["claimed"] = false

	active_quests[quest_id] = quest
	ready_to_turn_in_quests[quest_id] = true

	var title := String(quest.get("title", "Quest"))
	# print("Quest ready to turn in:", quest_id)

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit("Quest Ready: " + title, "success", 2.5)

	if QuestEvents != null and QuestEvents.has_signal("quest_state_changed"):
		QuestEvents.quest_state_changed.emit()

func clear_quest_ready_to_turn_in(quest_id: String) -> void:
	if quest_id.strip_edges() == "":
		return
	if ready_to_turn_in_quests.has(quest_id):
		ready_to_turn_in_quests.erase(quest_id)

func was_quest_claimed_today(quest_id: String) -> bool:
	if quest_id.strip_edges() == "":
		return false
	var d := int(recently_claimed_quests.get(quest_id, -1))
	return d == int(TimeManager.day)

func mark_quest_claimed_today(quest_id: String) -> void:
	if quest_id.strip_edges() == "":
		return
	recently_claimed_quests[quest_id] = int(TimeManager.day)

func cleanup_old_recently_claimed_quests(keep_days: int = 1) -> void:
	var today := int(TimeManager.day)
	for qid in recently_claimed_quests.keys():
		var d := int(recently_claimed_quests.get(qid, -999999))
		if today - d > keep_days:
			recently_claimed_quests.erase(qid)
	
func claim_quest_reward(quest_id: String) -> void:
	# print("[Reward] claim_quest_reward:", quest_id)
	
	if not completed_quests.has(quest_id):
		return

	var quest: Dictionary = completed_quests[quest_id]
	if bool(quest.get("claimed", false)):
		return

	var reward: Dictionary = Dictionary(quest.get("reward", {}))
	# print("Claiming reward for ", quest_id, " -> ", reward)

	apply_reward_dict(reward, "quest_claim:%s" % quest_id)
	
	quest["claimed"] = true
	
	completed_quests[quest_id] = quest
	clear_quest_ready_to_turn_in(quest_id)
	
	#if quest_id == "keeper_cow_quest":
		## print("[Reward] Queuing cow spawn!")
		#queue_spawn_reward("farm", "res://tscn/Cow.tscn", "cow_pen_spawn")
		## print("[Reward] pending_spawns now:", pending_spawns)
	
	QuestEvents.quest_state_changed.emit()

	# print("Quest reward claimed for ", quest_id)

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

func _on_first_harvest_heart_intro_check(_item_id: String, _qty: int) -> void:
	# Quest progress for harvesting is handled centrally in QuestEvents.gd.
	# This function only marks the world/story state for cutscene rules.

	if has_flag("first_crop_harvested"):
		return

	set_flag("first_crop_harvested", true)

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit("Something stirs beyond the path...", "info", 2.5)

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
	#if qid == "tutorial_day1":
		# print("[Tutorial] waiting step_index=", step_index, " step_type=", String(step.get("type","")), " step_target=", String(step.get("target","")))

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
		# print(tag, " CHAIN not active")
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

	# print(tag, " step_index=", idx, " current=", step_desc)

func is_quest_available_to_accept(quest_id: String) -> bool:
	return not active_quests.has(quest_id) and not completed_quests.has(quest_id)

func has_turn_in_ready(npc_id: String) -> bool:
	if npc_id.strip_edges() == "":
		return false

	for qid_any in ready_to_turn_in_quests.keys():
		var qid := String(qid_any)

		if not active_quests.has(qid):
			continue

		var quest: Dictionary = active_quests[qid]
		if String(quest.get("turn_in_id", "")) == npc_id:
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
	
	var qid := String(quest.get("id", ""))
	if is_quest_ready_to_turn_in(qid):
		var turn_text := String(quest.get("turn_in_text", "")).strip_edges()
		if turn_text != "":
			return turn_text

		var turn_id := String(quest.get("turn_in_id", "")).strip_edges()
		if turn_id != "":
			return "Return to %s to claim your reward." % turn_id

		return "Return to claim your reward."
	
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
		"till":
			return "Till soil"
		"plant":
			if target.strip_edges() != "":
				return "Plant: " + target
			return "Plant a seed"
		"water":
			if target.strip_edges() != "":
				return "Water: " + target
			return "Water a crop"
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
				# Blank step target means "any target" for this action.
				# Example:
				# type = "fish", target = ""        -> any fish counts
				# type = "fish", target = "Minnow"  -> only Minnow counts
				if step_target != "":
					if target == "":
						continue
					if step_target != target:
						continue

			changed = true

			step["progress"] = int(step.get("progress", 0)) + amount
			steps[step_index] = step
			quest["steps"] = steps

			if int(step["progress"]) >= int(step.get("amount", 0)):
				step = _apply_step_reward_once(qid, step_index, step)
				steps[step_index] = step
				quest["steps"] = steps

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
			# Blank quest target means "any target" for this action.
			if q_target != "":
				if target == "":
					continue
				if q_target != target:
					continue

		changed = true

		quest["progress"] = int(quest.get("progress", 0)) + amount
		if int(quest["progress"]) >= int(quest.get("amount", 0)):
			to_complete.append(qid)

		active_quests[qid] = quest

	for qid in to_complete:
		mark_quest_ready_to_turn_in(qid)
		changed = true

	if changed:
		QuestEvents.quest_state_changed.emit()
		
	GameState.debug_print_quest_state("tutorial_day1")

func get_first_turn_in_ready_id_for(npc_id: String) -> String:
	if npc_id.strip_edges() == "":
		return ""

	for qid_any in ready_to_turn_in_quests.keys():
		var qid := String(qid_any)

		if not active_quests.has(qid):
			continue

		var quest: Dictionary = active_quests[qid]
		if String(quest.get("turn_in_id", "")) == npc_id:
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
	mining_food_bonus_applied_today.clear()
	
	# print("Day changed:", new_day)
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
		"till":
			return "Till soil"
		"plant":
			if target.strip_edges() != "":
				return "Plant: " + target
			return "Plant a seed"
		"water":
			if target.strip_edges() != "":
				return "Water: " + target
			return "Water a crop"
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

func finalize_yesterday_summary(day_now: int, payout: int, shipped_copy: Dictionary) -> void:
	# "day_now" is the current day after TimeManager advanced.
	# The day that just ended is yesterday:
	var day_ended :Variant= max(0, int(day_now) - 1)

	# Defensive reads from today_tracking (your quest + unlock hooks write here)
	var accepted: Array = []
	var completed: Array = []
	var unlocked: Array = []

	if today_tracking is Dictionary:
		if today_tracking.has("quests_accepted") and today_tracking["quests_accepted"] is Array:
			accepted = (today_tracking["quests_accepted"] as Array).duplicate(true)
		if today_tracking.has("quests_completed") and today_tracking["quests_completed"] is Array:
			completed = (today_tracking["quests_completed"] as Array).duplicate(true)
		if today_tracking.has("areas_unlocked") and today_tracking["areas_unlocked"] is Array:
			unlocked = (today_tracking["areas_unlocked"] as Array).duplicate(true)

	# --- Build a COMPLETE summary dict (do not overwrite later with a smaller one) ---
	var s: Dictionary = {}

	# Core day + money
	s["day_ended"] = day_ended
	s["money_earned"] = int(payout)
	s["payout"] = int(payout) # optional alias

	# Shipping itemized list
	s["shipped"] = shipped_copy.duplicate(true)

	# Quests + unlocks for the EOD UI
	s["quests_accepted"] = accepted
	s["quests_completed"] = completed
	s["areas_unlocked"] = unlocked

	# --- Shipping blessing breakdown ---
	# Prefer values you already computed/logged; otherwise compute cleanly.
	var base_total := int(s.get("ship_base_total", -1))
	var final_total := int(s.get("ship_final_total", -1))
	var bonus := int(s.get("ship_heart_bonus", 0))
	var mul := float(s.get("ship_heart_mul", 1.0))

	# If you didn't set these earlier, compute from current payout + HeartProgress multiplier.
	final_total = int(payout)

	if has_node("/root/HeartProgress"):
		mul = float(get_node("/root/HeartProgress").call("get_sell_multiplier"))
	else:
		mul = 1.0

	# Best-effort base_total for display:
	if mul > 0.0:
		base_total = int(round(float(final_total) / mul))
	else:
		base_total = final_total

	bonus = max(0, final_total - base_total)

	s["ship_base_total"] = base_total
	s["ship_heart_mul"] = mul
	s["ship_heart_bonus"] = bonus
	s["ship_final_total"] = final_total

	# ✅ Assign once
	yesterday_summary = s

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

func _play_heart_intro_stub() -> void:
	lock_gameplay()
	
	var lines: Array[String] = []
	lines.append("Good morning…")
	lines.append("I need to show you something special.")
	lines.append("Meet me at the Heart of the Valley.")
	
	var mayor_id := "npc_mayor" # or whatever ID you use consistently
	var f : Variant= GameState.get_friendship(mayor_id) # should return int

	# Show dialogue through your existing dialogue UI
	var ui := get_tree().get_first_node_in_group("dialogue_ui")
	if ui and ui.has_method("show_dialogue"):
		ui.show_dialogue("Mayor", lines, f, mayor_id)

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

	# print("[GameState] Applied Heart reward:", r.id, " stats=", heart_stats, " flags=", heart_flags)

func get_shop_discount_multiplier() -> float:
	if has_node("/root/HeartProgress"):
		return float(get_node("/root/HeartProgress").call("get_shop_discount_multiplier"))
	return 1.0


func shop_calculate_buy_price(base_price: int) -> int:
	if base_price <= 0:
		return 0
	var mul := get_shop_discount_multiplier()
	if mul <= 0.0:
		mul = 1.0
	# Favor the player: floor keeps discounts feeling real
	var final_price := int(floor(float(base_price) * mul))
	return max(1, final_price)

func get_primary_quest_hint() -> String:
	# 1) Completed but unclaimed -> strongest nudge (turn-in)
	for qid_any in completed_quests.keys():
		var qid := String(qid_any)
		var q: Dictionary = completed_quests[qid]
		if bool(q.get("claimed", false)):
			continue

		# Prefer explicit turn-in text if present
		var turn_text := String(q.get("turn_in_text", "")).strip_edges()
		if turn_text != "":
			return turn_text

		var turn_id := String(q.get("turn_in_id", "")).strip_edges()
		if turn_id != "":
			return "Return to %s to claim your reward." % turn_id

		return "You have a reward waiting to be claimed."

	# 2) Tracked quest -> use your already-good tracker text
	var tracked := get_tracked_objective_text().strip_edges()
	if tracked != "":
		return tracked

	# 3) Any active quest -> show the first objective we can
	for qid_any in active_quests.keys():
		var qid := String(qid_any)
		var q: Dictionary = active_quests[qid]
		var text := get_quest_objective_text(q).strip_edges()
		if text != "":
			return text

	return ""

func has_object_been_interacted(interactable_id: String) -> bool:
	if interactable_id.strip_edges() == "":
		return false
	return interacted_object_ids.get(interactable_id, false) == true

func mark_object_interacted(interactable_id: String) -> void:
	if interactable_id.strip_edges() == "":
		return
	interacted_object_ids[interactable_id] = true

func reset_interacted_objects() -> void:
	interacted_object_ids.clear()

func mark_cutscene_played(cutscene_id: String) -> void:
	cutscene_id = cutscene_id.strip_edges()
	if cutscene_id == "":
		return
	
	# print("GameState: marking cutscene played:", cutscene_id)
	played_cutscenes[cutscene_id] = true
	
func has_seen_cutscene(cutscene_id: String) -> bool:
	return played_cutscenes.has(cutscene_id)

func has_played_cutscene(cutscene_id: String) -> bool:
	cutscene_id = cutscene_id.strip_edges()
	if cutscene_id == "":
		return false
	return bool(played_cutscenes.get(cutscene_id, false))

func set_flag(flag_id: String, value: bool = true) -> void:
	flag_id = flag_id.strip_edges()
	if flag_id == "":
		return

	var was_enabled := bool(game_flags.get(flag_id, false))

	game_flags[flag_id] = value

	if value:
		if TimeManager != null:
			game_flag_set_days[flag_id] = int(TimeManager.day)
		else:
			game_flag_set_days[flag_id] = 0
	else:
		if game_flag_set_days.has(flag_id):
			game_flag_set_days.erase(flag_id)

	# Tiny cozy feedback for newly unlocked Help Book pages.
	if value and not was_enabled and flag_id.begins_with("help_page:"):
		var page_name := flag_id.replace("help_page:", "").replace("_", " ").capitalize()

		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("New Help Book page: " + page_name, "success", 2.5)

	if QuestEvents != null and QuestEvents.has_signal("quest_state_changed"):
		QuestEvents.quest_state_changed.emit()

func has_flag(flag_id: String) -> bool:
	flag_id = flag_id.strip_edges()
	if flag_id == "":
		return false

	return bool(game_flags.get(flag_id, false))


func get_flag_set_day(flag_id: String) -> int:
	flag_id = flag_id.strip_edges()
	if flag_id == "":
		return -1

	if not has_flag(flag_id):
		return -1

	return int(game_flag_set_days.get(flag_id, 0))


func get_cutscene_rule_ready_day(rule_id: String) -> int:
	rule_id = rule_id.strip_edges()
	if rule_id == "":
		return -1

	return int(cutscene_rule_ready_days.get(rule_id, -1))


func mark_cutscene_rule_ready(rule_id: String, day_value: int) -> void:
	rule_id = rule_id.strip_edges()
	if rule_id == "":
		return

	cutscene_rule_ready_days[rule_id] = int(day_value)


func clear_cutscene_rule_ready(rule_id: String) -> void:
	rule_id = rule_id.strip_edges()
	if rule_id == "":
		return

	if cutscene_rule_ready_days.has(rule_id):
		cutscene_rule_ready_days.erase(rule_id)

func get_tool_type_from_id(tool_id: String) -> int:
	var id := tool_id.strip_edges().to_lower()

	match id:
		"axe":
			return ToolType.AXE
		"pickaxe":
			return ToolType.PICKAXE
		"hoe":
			return ToolType.HOE
		"bucket":
			return ToolType.BUCKET
		"hand", "hands":
			return ToolType.HAND
		"watering_can", "watering can":
			return ToolType.WATERING_CAN
		"seed_pouch", "seeds", "seed pouch":
			return ToolType.SEED_POUCH
		"fishing_rod", "fishing rod":
			return ToolType.FISHING_ROD

	return -1

func debug_print_quest_state(quest_id: String) -> void:
	# print("\n=== QUEST DEBUG:", quest_id, "===")

	if active_quests.has(quest_id):
		var q: Dictionary = active_quests[quest_id]
		# print("ACTIVE:", q)
		# print("step_index:", q.get("step_index", "none"))
		# print("steps size:", Array(q.get("steps", [])).size())
		# print("completed:", q.get("completed", "none"))
		# print("claimed:", q.get("claimed", "none"))
		# print("turn_in_id:", q.get("turn_in_id", "none"))
		# print("turn_in_text:", q.get("turn_in_text", "none"))
	else:
		print("Not in active_quests")

	if completed_quests.has(quest_id):
		var cq: Dictionary = completed_quests[quest_id]
		# print("COMPLETED:", cq)
		# print("completed claimed:", cq.get("claimed", "none"))
	else:
		print("Not in completed_quests")

	if has_method("is_quest_ready_to_turn_in"):
		print("ready_to_turn_in:", is_quest_ready_to_turn_in(quest_id))

	# print("==============================\n")

func complete_ready_quest_and_claim_reward(quest_id: String) -> void:
	quest_id = quest_id.strip_edges()
	if quest_id == "":
		return

	if not active_quests.has(quest_id):
		return

	var quest: Dictionary = active_quests[quest_id]
	quest["completed"] = true
	quest["claimed"] = false
	quest["ready_to_turn_in"] = false

	active_quests.erase(quest_id)
	completed_quests[quest_id] = quest
	clear_quest_ready_to_turn_in(quest_id)

	var title := String(quest.get("title", "Quest"))
	if not (today_tracking["quests_completed"] as Array).has(title):
		(today_tracking["quests_completed"] as Array).append(title)

	# Claim normally so money/items/tools/spawns/flags all still work.
	claim_quest_reward(quest_id)

	mark_quest_claimed_today(quest_id)

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit("Quest Completed: " + title, "success", 3.0)

	if QuestEvents != null and QuestEvents.has_signal("quest_state_changed"):
		QuestEvents.quest_state_changed.emit()

func get_animal_state(animal_id: String) -> Dictionary:
	animal_id = animal_id.strip_edges()
	if animal_id == "":
		return {}

	if not animal_states.has(animal_id):
		animal_states[animal_id] = {
			"fed_today": false,
			"has_product_ready": false,
			"last_pet_day": -999999
		}

	return animal_states[animal_id]


func set_animal_state_value(animal_id: String, key: String, value: Variant) -> void:
	animal_id = animal_id.strip_edges()
	key = key.strip_edges()

	if animal_id == "" or key == "":
		return

	var state := get_animal_state(animal_id)
	state[key] = value
	animal_states[animal_id] = state


func get_animal_state_value(animal_id: String, key: String, default_value: Variant = null) -> Variant:
	var state := get_animal_state(animal_id)
	return state.get(key, default_value)

func process_animal_new_day() -> void:
	var current_day := 0
	if TimeManager != null:
		current_day = int(TimeManager.day)

	# Prevent double-processing the same day.
	if _last_animal_day_processed == current_day:
		return

	_last_animal_day_processed = current_day

	for animal_id_any in animal_states.keys():
		var animal_id := String(animal_id_any)
		var state: Dictionary = animal_states[animal_id]

		if bool(state.get("fed_today", false)):
			state["has_product_ready"] = true

		state["fed_today"] = false
		animal_states[animal_id] = state

	# print("[Animals] Processed new day:", current_day, animal_states)

func apply_reward_dict(reward: Dictionary, source_id: String = "") -> void:
	if reward.is_empty():
		return

	# print("[Reward] apply_reward_dict source=", source_id, " reward=", reward)

	# Money
	if reward.has("money"):
		MoneySystem.add(int(reward["money"]))

	# Items
	if reward.has("items"):
		var items_reward: Dictionary = Dictionary(reward["items"])
		for item_name_any in items_reward.keys():
			var item_name := String(item_name_any)
			var qty := int(items_reward[item_name_any])
			inventory_add(item_name, qty)

	# Flags
	if reward.has("flags"):
		var flags_reward: Array = Array(reward["flags"])
		for flag_any in flags_reward:
			set_flag(String(flag_any), true)

	# Tools
	if reward.has("tools"):
		var tools_reward: Array = Array(reward["tools"])
		for tool_any in tools_reward:
			var tool_id := String(tool_any)
			var tool_type := get_tool_type_from_id(tool_id)

			if tool_type >= 0:
				unlock_tool(tool_type)
			else:
				push_warning("[Reward] Unknown tool id: " + tool_id)

		# Crafting recipe unlocks
	if reward.has("crafting_recipes"):
		var crafting_recipe_reward: Array = Array(reward["crafting_recipes"])
		for recipe_any in crafting_recipe_reward:
			var recipe_id := String(recipe_any).strip_edges()
			if recipe_id == "":
				continue

			if has_method("unlock_recipe"):
				unlock_recipe(recipe_id)
			else:
				push_warning("[Reward] GameState.unlock_recipe missing; cannot unlock crafting recipe: " + recipe_id)

	# Cooking recipe unlocks
	if reward.has("cooking_recipes"):
		var cooking_recipe_reward: Array = Array(reward["cooking_recipes"])
		for recipe_any in cooking_recipe_reward:
			var recipe_id := String(recipe_any).strip_edges()
			if recipe_id == "":
				continue

			if has_method("unlock_cooking_recipe"):
				unlock_cooking_recipe(recipe_id)
			else:
				push_warning("[Reward] GameState.unlock_cooking_recipe missing; cannot unlock cooking recipe: " + recipe_id)

	# Spawns
	if reward.has("spawns"):
		var spawns_reward: Array = Array(reward["spawns"])
		for spawn_any in spawns_reward:
			var spawn_dict: Dictionary = Dictionary(spawn_any)

			var scene_key := String(spawn_dict.get("scene_key", "")).strip_edges()
			var scene_path := String(spawn_dict.get("scene_path", "")).strip_edges()
			var marker_id := String(spawn_dict.get("marker_id", "")).strip_edges()

			if scene_key != "" and scene_path != "" and marker_id != "":
				queue_spawn_reward(scene_key, scene_path, marker_id)

func _apply_step_reward_once(quest_id: String, step_index: int, step: Dictionary) -> Dictionary:
	if bool(step.get("reward_claimed", false)):
		return step

	var reward: Dictionary = Dictionary(step.get("reward", {}))
	if reward.is_empty():
		step["reward_claimed"] = true
		return step

	apply_reward_dict(reward, "quest_step:%s:%d" % [quest_id, step_index])

	step["reward_claimed"] = true
	return step

func apply_food_effect(effect: FoodEffectData) -> void:
	if effect == null:
		return
	if not effect.is_valid():
		return

	var key := int(effect.effect_key)

	var remaining_uses := 1
	var remaining_minutes := 0

	match effect.duration_mode:
		FoodEffectData.DurationMode.NEXT_N_USES:
			remaining_uses = max(1, int(effect.uses))

		FoodEffectData.DurationMode.NEXT_USE:
			remaining_uses = 1

		FoodEffectData.DurationMode.NEXT_SESSION:
			remaining_uses = 1

		FoodEffectData.DurationMode.TIMED:
			remaining_uses = 999999
			remaining_minutes = max(1, int(effect.duration_minutes))

		FoodEffectData.DurationMode.UNTIL_SLEEP:
			remaining_uses = 999999

		_:
			remaining_uses = 1

	# If this is replacing an existing max-energy buff, undo the old bonus first.
	if key == FoodEffectData.EffectKey.MAX_ENERGY_BONUS and active_food_buffs.has(key):
		var old_buff: Dictionary = Dictionary(active_food_buffs[key])
		var old_bonus := int(round(float(old_buff.get("amount", 0.0))))
		if old_bonus > 0:
			max_energy = max(1, max_energy - old_bonus)
			energy = min(energy, max_energy)

	active_food_buffs[key] = {
		"id": effect.id,
		"display_name": effect.display_name if effect.display_name.strip_edges() != "" else effect.get_effect_key_name(),
		"amount": float(effect.amount),
		"remaining_uses": remaining_uses,
		"remaining_minutes": remaining_minutes,
		"duration_mode": int(effect.duration_mode),
		"category": effect.category,
	}

	# print("[FoodBuff] Applied:", active_food_buffs[key])
	
	# Apply immediate side effects.
	if key == FoodEffectData.EffectKey.MAX_ENERGY_BONUS:
		var bonus := int(round(float(effect.amount)))
		if bonus > 0:
			max_energy += bonus
			energy = min(max_energy, energy + bonus)

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		var label := effect.display_name
		if label.strip_edges() == "":
			label = effect.get_effect_key_name()
		QuestEvents.toast_requested.emit(label + " is active.", "success", 2.5)
	
	if QuestEvents != null and QuestEvents.has_signal("quest_state_changed"):
		QuestEvents.quest_state_changed.emit()


func get_food_buff_amount(effect_key: int) -> float:
	var key := int(effect_key)
	if not active_food_buffs.has(key):
		return 0.0

	var buff: Dictionary = Dictionary(active_food_buffs[key])
	return float(buff.get("amount", 0.0))


func consume_food_buff_use(effect_key: int) -> void:
	var key := int(effect_key)
	if not active_food_buffs.has(key):
		return

	var buff: Dictionary = Dictionary(active_food_buffs[key])
	var remaining := int(buff.get("remaining_uses", 0))

	# Timed / until-sleep buffs can be wired later.
	if remaining >= 999999:
		return

	remaining -= 1

	if remaining <= 0:
		active_food_buffs.erase(key)
		# print("[FoodBuff] Expired key:", key)
	else:
		buff["remaining_uses"] = remaining
		active_food_buffs[key] = buff
		# print("[FoodBuff] Remaining uses key=", key, " uses=", remaining)
		
	if QuestEvents != null and QuestEvents.has_signal("quest_state_changed"):
		QuestEvents.quest_state_changed.emit()


func has_food_buff(effect_key: int) -> bool:
	return active_food_buffs.has(int(effect_key))

func get_active_food_buff_display_lines() -> Array[String]:
	var lines: Array[String] = []

	for key_any in active_food_buffs.keys():
		var key := int(key_any)
		var buff: Dictionary = Dictionary(active_food_buffs[key_any])

		var name := String(buff.get("display_name", ""))
		if name.strip_edges() == "":
			name = _get_food_effect_key_display_name(key)

		var remaining := int(buff.get("remaining_uses", 0))
		var duration_mode := int(buff.get("duration_mode", FoodEffectData.DurationMode.NEXT_USE))

		var suffix := ""

		match duration_mode:
			FoodEffectData.DurationMode.NEXT_USE:
				suffix = "next use"
			FoodEffectData.DurationMode.NEXT_N_USES:
				suffix = "%d uses left" % max(0, remaining)
			FoodEffectData.DurationMode.NEXT_SESSION:
				suffix = "next session"
			FoodEffectData.DurationMode.TIMED:
				var remaining_minutes := int(buff.get("remaining_minutes", 0))
				var hours := int(remaining_minutes / 60)
				var mins := remaining_minutes % 60

				if hours > 0:
					suffix = "%dh %02dm left" % [hours, mins]
				else:
					suffix = "%dm left" % mins
			FoodEffectData.DurationMode.UNTIL_SLEEP:
				suffix = "until sleep"
			_:
				suffix = "active"

		lines.append("%s: %s" % [name, suffix])

	return lines

func _get_food_effect_key_display_name(effect_key: int) -> String:
	match effect_key:
		FoodEffectData.EffectKey.FISHING_TIME_BONUS:
			return "Fishing Focus"
		FoodEffectData.EffectKey.FISHING_MISTAKE_BONUS:
			return "Fishing Grace"
		FoodEffectData.EffectKey.FISHING_SEQUENCE_REDUCTION:
			return "Clear Rhythm"
		FoodEffectData.EffectKey.MINING_HARMONY_BONUS:
			return "Mining Harmony"
		FoodEffectData.EffectKey.MINING_FORGIVE_MISTAKE:
			return "Stone Patience"
		FoodEffectData.EffectKey.MINING_BONUS_DROP_CHANCE:
			return "Miner's Fortune"
		FoodEffectData.EffectKey.COMBAT_RESOLVE_BONUS:
			return "Root Courage"
		FoodEffectData.EffectKey.COMBAT_FIRST_HIT_SHIELD:
			return "Heart Guard"
		FoodEffectData.EffectKey.TOOL_ENERGY_DISCOUNT:
			return "Tool Ease"
		_:
			return "Food Buff"

func has_applied_mining_food_bonus_today(chamber_id: String, effect_key: int) -> bool:
	chamber_id = chamber_id.strip_edges()
	if chamber_id == "":
		return false

	var key := chamber_id + ":" + str(effect_key)
	return bool(mining_food_bonus_applied_today.get(key, false))


func mark_mining_food_bonus_applied_today(chamber_id: String, effect_key: int) -> void:
	chamber_id = chamber_id.strip_edges()
	if chamber_id == "":
		return

	var key := chamber_id + ":" + str(effect_key)
	mining_food_bonus_applied_today[key] = true


func clear_food_buffs_with_duration_mode(duration_mode: int) -> void:
	var to_remove: Array = []

	for key_any in active_food_buffs.keys():
		var buff: Dictionary = Dictionary(active_food_buffs[key_any])
		if int(buff.get("duration_mode", -1)) == int(duration_mode):
			to_remove.append(key_any)

	for key_any2 in to_remove:
		active_food_buffs.erase(key_any2)

	if not to_remove.is_empty():
		if QuestEvents != null and QuestEvents.has_signal("quest_state_changed"):
			QuestEvents.quest_state_changed.emit()

func clear_daily_food_buffs() -> void:
	if not ("active_food_buffs" in self):
		return

	var removed_names: Array[String] = []

	for key_any in active_food_buffs.keys():
		var buff: Dictionary = Dictionary(active_food_buffs[key_any])

		var name := String(buff.get("display_name", ""))
		if name.strip_edges() == "":
			name = "A food blessing"

		removed_names.append(name)

	var keys_to_clear := active_food_buffs.keys().duplicate()
	for key_any in keys_to_clear:
		_remove_food_buff_by_key(key_any)

	# Reset mining once-per-day food bonus tracking too.
	# This lets a new day receive Mountain Listening again.
	if "mining_food_bonus_applied_today" in self:
		mining_food_bonus_applied_today.clear()

	if not removed_names.is_empty():
		# print("[FoodBuff] Cleared daily food buffs:", removed_names)

		# Queue this so it appears after the new day/scene settles, if your queued toast helper exists.
		if has_method("queue_day_start_toast"):
			queue_day_start_toast("Yesterday’s food blessings have faded.", "info", 2.5)
		elif QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("Yesterday’s food blessings have faded.", "info", 2.5)

	if QuestEvents != null and QuestEvents.has_signal("quest_state_changed"):
		QuestEvents.quest_state_changed.emit()

func get_tool_energy_cost_with_food_discount(base_cost: int, tool_type: int = -1) -> int:
	var cost :Variant= max(0, int(base_cost))

	if not has_method("get_food_buff_amount"):
		return cost

	var discount := get_food_buff_amount(FoodEffectData.EffectKey.TOOL_ENERGY_DISCOUNT)
	if discount <= 0.0:
		return cost

	var final_cost :Variant= cost - int(round(discount))

	# For limited-use foods, letting cost reach 0 is okay.
	# If later this feels too strong, change this to max(1, final_cost).
	return max(0, final_cost)


func spend_tool_energy(base_cost: int, tool_type: int = -1) -> bool:
	var final_cost := get_tool_energy_cost_with_food_discount(base_cost, tool_type)

	# If final cost is 0, this action is free but still valid.
	if final_cost <= 0:
		_consume_tool_energy_discount_use_if_active()
		return true

	var spent := spend_energy(final_cost)
	if spent:
		_consume_tool_energy_discount_use_if_active()

	return spent


func _consume_tool_energy_discount_use_if_active() -> void:
	if not has_method("get_food_buff_amount"):
		return

	var discount := get_food_buff_amount(FoodEffectData.EffectKey.TOOL_ENERGY_DISCOUNT)
	if discount <= 0.0:
		return

	if has_method("consume_food_buff_use"):
		consume_food_buff_use(FoodEffectData.EffectKey.TOOL_ENERGY_DISCOUNT)

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit("Tool Ease softened the strain.", "info", 1.2)

func tick_timed_food_buffs(delta_minutes: int = 1) -> void:
	if active_food_buffs.is_empty():
		return

	var changed := false
	var to_remove: Array = []

	for key_any in active_food_buffs.keys():
		var buff: Dictionary = Dictionary(active_food_buffs[key_any])
		var duration_mode := int(buff.get("duration_mode", -1))

		if duration_mode != FoodEffectData.DurationMode.TIMED:
			continue

		var remaining := int(buff.get("remaining_minutes", 0))
		remaining -= max(1, delta_minutes)

		if remaining <= 0:
			to_remove.append(key_any)
		else:
			buff["remaining_minutes"] = remaining
			active_food_buffs[key_any] = buff

		changed = true

	for key_remove in to_remove:
		_remove_food_buff_by_key(key_remove)

	if changed and QuestEvents != null and QuestEvents.has_signal("quest_state_changed"):
		QuestEvents.quest_state_changed.emit()

func _remove_food_buff_by_key(key_any) -> void:
	if not active_food_buffs.has(key_any):
		return

	var key := int(key_any)
	var buff: Dictionary = Dictionary(active_food_buffs[key_any])

	# Undo max energy side effect if needed.
	if key == FoodEffectData.EffectKey.MAX_ENERGY_BONUS:
		var bonus := int(round(float(buff.get("amount", 0.0))))
		if bonus > 0:
			max_energy = max(1, max_energy - bonus)
			energy = min(energy, max_energy)

	active_food_buffs.erase(key_any)

	var name := String(buff.get("display_name", ""))
	if name.strip_edges() == "":
		name = "A food blessing"

	# print("[FoodBuff] Expired:", name)

func get_movement_speed_multiplier() -> float:
	var bonus := get_food_buff_amount(FoodEffectData.EffectKey.MOVEMENT_SPEED_MULTIPLIER)

	# amount is treated as an additive multiplier bonus.
	# Example: amount = 0.15 means 1.15x speed.
	if bonus <= 0.0:
		return 1.0

	return max(0.1, 1.0 + bonus)

func travel_to_scene(
	target_scene_path: String,
	target_spawn_tag: String = "",
	fade_out_time: float = -1.0,
	fade_in_time: float = -1.0,
	frames_after_scene_change: int = -1,
	travel_sfx: AudioStream = null,
	travel_sfx_volume_db: float = 0.0,
	travel_sfx_delay: float = 0.0
) -> void:
	target_scene_path = target_scene_path.strip_edges()
	target_spawn_tag = target_spawn_tag.strip_edges()

	if is_scene_traveling:
		return

	if target_scene_path == "":
		return

	is_scene_traveling = true

	if fade_out_time < 0.0:
		fade_out_time = travel_fade_out_time

	if fade_in_time < 0.0:
		fade_in_time = travel_fade_in_time

	if frames_after_scene_change < 0:
		frames_after_scene_change = travel_frames_after_scene_change

	lock_gameplay()

	# Optional travel sound.
	# Played from GameState so it survives the scene being unloaded.
	if travel_sfx != null:
		_play_travel_sfx(travel_sfx, travel_sfx_volume_db, travel_sfx_delay)

	if FadeOverlay != null:
		await FadeOverlay.fade_out(fade_out_time)

	pending_spawn_tag = target_spawn_tag

	var err := get_tree().change_scene_to_file(target_scene_path)
	if err != OK:
		push_warning("GameState.travel_to_scene: failed to change scene to: " + target_scene_path)

		pending_spawn_tag = ""

		if FadeOverlay != null:
			await FadeOverlay.fade_in(fade_in_time)

		unlock_gameplay()
		is_scene_traveling = false
		return

	for i in range(max(1, frames_after_scene_change)):
		await get_tree().process_frame

	# If entering this scene queued a cutscene while we were still faded out,
	# merge the travel fade directly into the cutscene reveal.
	if _can_merge_pending_cutscene_into_travel():
		unlock_gameplay()
		is_scene_traveling = false

		await get_tree().process_frame

		if _play_pending_cutscene_from_travel_black():
			return

	# Normal travel path: no immediate cutscene, so reveal gameplay.
	if FadeOverlay != null:
		await FadeOverlay.fade_in(fade_in_time)

	unlock_gameplay()
	is_scene_traveling = false

	call_deferred("_try_play_pending_cutscene_deferred")


func _play_travel_sfx(stream: AudioStream, volume_db: float = 0.0, delay: float = 0.0) -> void:
	if stream == null:
		return

	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)

	player.play()

	await player.finished

	if player != null and is_instance_valid(player):
		player.queue_free()

var pending_cutscene_one_shot: bool = true

func queue_pending_cutscene(cutscene_id: String, one_shot: bool = true) -> void:
	cutscene_id = cutscene_id.strip_edges()
	if cutscene_id == "":
		return

	if one_shot and has_method("has_played_cutscene"):
		if has_played_cutscene(cutscene_id):
			if cutscene_queue_debug_enabled:
				print("[GameState CutsceneQueue] Not queueing already-played cutscene:", cutscene_id)
			return

	pending_cutscene_id = cutscene_id
	pending_cutscene_one_shot = one_shot

	if cutscene_queue_debug_enabled:
		print("[GameState CutsceneQueue] Queued:", pending_cutscene_id, " one_shot=", pending_cutscene_one_shot)

	call_deferred("_try_play_pending_cutscene_deferred")


func _try_play_pending_cutscene_deferred() -> void:
	if _pending_cutscene_retry_active:
		return

	_pending_cutscene_retry_active = true

	for i in range(max(1, pending_cutscene_retry_frames)):
		await get_tree().process_frame

	_pending_cutscene_retry_active = false

	var played := try_play_pending_cutscene()

	# If it could not play because gameplay was still locked or a cutscene was active,
	# try again shortly. This prevents silent "queued forever" cutscenes.
	if not played and pending_cutscene_id.strip_edges() != "":
		call_deferred("_try_play_pending_cutscene_deferred")


func try_play_pending_cutscene() -> bool:
	var cutscene_id := pending_cutscene_id.strip_edges()
	if cutscene_id == "":
		return false

	if CutsceneDirector == null:
		if cutscene_queue_debug_enabled:
			print("[GameState CutsceneQueue] Cannot play; CutsceneDirector is null.")
		return false

	if CutsceneDirector.has_method("is_playing_cutscene"):
		if CutsceneDirector.is_playing_cutscene():
			if cutscene_queue_debug_enabled:
				print("[GameState CutsceneQueue] Waiting; director is already playing.")
			return false

	if has_method("is_gameplay_locked"):
		if is_gameplay_locked():
			if cutscene_queue_debug_enabled:
				print("[GameState CutsceneQueue] Waiting; gameplay is locked. lock_count=", lock_count)
			return false

	if not CutsceneDirector.has_method("play_cutscene"):
		push_warning("[GameState CutsceneQueue] CutsceneDirector.play_cutscene() missing.")
		return false

	if cutscene_queue_debug_enabled:
		print("[GameState CutsceneQueue] Playing queued cutscene:", cutscene_id)

	# Clear before play to avoid loops if the cutscene itself triggers state updates.
	pending_cutscene_id = ""
	pending_cutscene_one_shot = true

	CutsceneDirector.play_cutscene(cutscene_id)

	return true

@export var cutscene_queue_debug_enabled: bool = true
@export var pending_cutscene_retry_frames: int = 6

var _pending_cutscene_retry_active: bool = false

func _can_merge_pending_cutscene_into_travel() -> bool:
	var cutscene_id := pending_cutscene_id.strip_edges()
	if cutscene_id == "":
		return false

	if CutsceneDirector == null:
		return false

	# Important safety:
	# Only merge if this cutscene belongs in the scene we just loaded.
	# Otherwise we could keep the screen black for a cutscene that cannot play here.
	if CutsceneDirector.has_method("can_play_cutscene_in_current_scene"):
		return bool(CutsceneDirector.call("can_play_cutscene_in_current_scene", cutscene_id))

	return true


func _play_pending_cutscene_from_travel_black() -> bool:
	var cutscene_id := pending_cutscene_id.strip_edges()
	if cutscene_id == "":
		return false

	if CutsceneDirector == null:
		return false

	if CutsceneDirector.has_method("is_playing_cutscene"):
		if CutsceneDirector.is_playing_cutscene():
			return false

	# Clear before playing so retry loops do not double-start it.
	pending_cutscene_id = ""
	pending_cutscene_one_shot = true

	if cutscene_queue_debug_enabled:
		print("[GameState CutsceneQueue] Merging travel fade into cutscene:", cutscene_id)

	if CutsceneDirector.has_method("play_cutscene_from_black"):
		CutsceneDirector.call("play_cutscene_from_black", cutscene_id)
	else:
		CutsceneDirector.call("play_cutscene", cutscene_id)

	return true
