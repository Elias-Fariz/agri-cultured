extends Resource
class_name MiningChamberData

@export var chamber_id: String = "mineral_chamber_01"

# Which cells in the dedicated mining objects TileMap are valid spawn spots.
@export var spawn_cells: Array[Vector2i] = []

# Node pool for this chamber. For now, even one entry is enough.
@export var node_pool: Array[MiningNodeData] = []

# How many nodes spawn per refresh
@export var spawn_count_min: int = 4
@export var spawn_count_max: int = 6

# Harmony defaults
@export var starting_harmony: int = 50
@export var min_harmony: int = 0
@export var max_harmony: int = 100

# Refresh cadence
@export var refresh_on_time_block_change: bool = true

# Active node counts based on harmony band
@export var low_harmony_active_min: int = 1
@export var low_harmony_active_max: int = 2

@export var mid_harmony_active_min: int = 2
@export var mid_harmony_active_max: int = 3

@export var high_harmony_active_min: int = 3
@export var high_harmony_active_max: int = 4

# Optional chamber bonus for a "good read"
@export var bonus_drop_item: String = ""
@export var bonus_drop_qty_min: int = 1
@export var bonus_drop_qty_max: int = 1
@export var bonus_drop_chance_low: float = 0.05
@export var bonus_drop_chance_mid: float = 0.12
@export var bonus_drop_chance_high: float = 0.22

func get_spawn_count() -> int:
	var a :Variant= max(0, spawn_count_min)
	var b :Variant= max(a, spawn_count_max)
	if a == b:
		return a
	return randi_range(a, b)

func get_active_count_for_harmony(harmony: int, spawned_count: int) -> int:
	var min_count := 1
	var max_count := 1

	if harmony >= 70:
		min_count = high_harmony_active_min
		max_count = high_harmony_active_max
	elif harmony >= 40:
		min_count = mid_harmony_active_min
		max_count = mid_harmony_active_max
	else:
		min_count = low_harmony_active_min
		max_count = low_harmony_active_max

	min_count = clampi(min_count, 0, spawned_count)
	max_count = clampi(max_count, min_count, spawned_count)

	if min_count == max_count:
		return min_count
	return randi_range(min_count, max_count)

func get_bonus_drop_chance_for_harmony(harmony: int) -> float:
	if harmony >= 70:
		return bonus_drop_chance_high
	if harmony >= 40:
		return bonus_drop_chance_mid
	return bonus_drop_chance_low

func roll_bonus_drop() -> Dictionary:
	var qty := _roll_qty(bonus_drop_qty_min, bonus_drop_qty_max)
	return {
		"item_id": bonus_drop_item,
		"qty": qty
	}

func _roll_qty(min_qty: int, max_qty: int) -> int:
	var a :Variant= max(0, min_qty)
	var b :Variant= max(a, max_qty)
	if a == b:
		return a
	return randi_range(a, b)
