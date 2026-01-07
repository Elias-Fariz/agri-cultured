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
var inventory: Array[String] = []

func add_item(item: String) -> void:
	inventory.append(item)
	print("Added to inventory:", item, " Inventory now:", inventory)

var sell_prices := {
	"Watermelon": 35,
	"Stone": 5,
	"Wood": 10
}

var sell_box: SellBox

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

func get_sell_price(item_id: String) -> int:
	return int(sell_prices.get(item_id, 0))
