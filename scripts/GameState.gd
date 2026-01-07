# GameState.gd
extends Node

var next_spawn_name: String = ""

enum ToolType { AXE, PICKAXE, HOE }
const TOOL_COUNT := 3

@export var starting_tool: ToolType = ToolType.HOE
var current_tool: ToolType = ToolType.HOE

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
	# Tools later would be shippable: false
}

func get_sell_price(item_name: String) -> int:
	var data = item_db.get(item_name, null)
	if data == null:
		return 0
	return int(data.get("sell_price", 0))

func is_shippable(item_name: String) -> bool:
	var data = item_db.get(item_name, null)
	if data == null:
		return false
	return bool(data.get("shippable", false))

# -------------------------
# SHIPPING BIN HELPERS
# -------------------------
# shipping_bin already exists and persists globally

func shipping_add(item_name: String, qty: int = 1) -> void:
	if item_name.is_empty() or qty <= 0:
		return
	shipping_bin[item_name] = int(shipping_bin.get(item_name, 0)) + qty

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
	var payout := shipping_calculate_payout()
	if payout > 0:
		MoneySystem.add(payout)
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


func _ready() -> void:
	reset_energy()
	current_tool = starting_tool

func cycle_tool_next() -> void:
	current_tool = (int(current_tool) + 1) % TOOL_COUNT

func get_tool_name() -> String:
	match current_tool:
		ToolType.AXE: return "Axe"
		ToolType.PICKAXE: return "Pickaxe"
		ToolType.HOE: return "Hoe"
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
