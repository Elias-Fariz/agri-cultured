extends Resource
class_name MiningNodeData

enum MechanicType {
	BASIC,
	DIRECTIONAL,
	PULSE
}

@export var node_id: String = "mineral_common"
@export var display_name: String = "Common Mineral Node"

# What special behavior this node uses when active.
@export var mechanic_type: MechanicType = MechanicType.BASIC

# Tool / durability
@export var required_tool: int = 1 # GameState.ToolType.PICKAXE = 1 in your enum
@export var hits_to_break: int = 2

# -------------------------------------------------------------------
# Basic tile visuals
# -------------------------------------------------------------------
@export var dormant_source_id: int = -1
@export var dormant_atlas: Vector2i = Vector2i.ZERO

@export var active_source_id: int = -1
@export var active_atlas: Vector2i = Vector2i.ZERO

# Optional tile after break. If source_id = -1, tile is erased.
@export var depleted_source_id: int = -1
@export var depleted_atlas: Vector2i = Vector2i.ZERO

# -------------------------------------------------------------------
# Directional node visuals
#
# For DIRECTIONAL nodes, the chamber will randomly choose a required
# hit direction from allowed_directions and then display the matching tile.
#
# Direction means the direction the PLAYER is facing when striking.
# Example:
# required_direction = Vector2i(0, -1)
# means the player must face UP while hitting the node.
# -------------------------------------------------------------------
@export var allowed_directions: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(-1, 0),
	Vector2i(1, 0)
]

@export var direction_up_source_id: int = -1
@export var direction_up_atlas: Vector2i = Vector2i.ZERO

@export var direction_down_source_id: int = -1
@export var direction_down_atlas: Vector2i = Vector2i.ZERO

@export var direction_left_source_id: int = -1
@export var direction_left_atlas: Vector2i = Vector2i.ZERO

@export var direction_right_source_id: int = -1
@export var direction_right_atlas: Vector2i = Vector2i.ZERO

# -------------------------------------------------------------------
# Pulse node tuning
#
# For PULSE nodes, a hit succeeds if it happens near the brightest
# part of the pulse.
# -------------------------------------------------------------------
@export var pulse_period_seconds: float = 1.6
@export_range(0.05, 0.45, 0.01) var pulse_success_window: float = 0.18

# Optional pulse visual tile.
# Best used with an animated TileSet tile.
@export var pulse_source_id: int = -1
@export var pulse_atlas: Vector2i = Vector2i.ZERO

# -------------------------------------------------------------------
# Drops
# Dormant nodes still give something cozy and useful.
# -------------------------------------------------------------------
@export var dormant_drop_item: String = "Stone"
@export var dormant_drop_qty_min: int = 1
@export var dormant_drop_qty_max: int = 1

@export var active_drop_item: String = "Stone"
@export var active_drop_qty_min: int = 2
@export var active_drop_qty_max: int = 3

# Optional bonus drop from successful active/special break.
@export var active_bonus_drop_item: String = ""
@export var active_bonus_drop_chance: float = 0.25
@export var active_bonus_qty_min: int = 1
@export var active_bonus_qty_max: int = 1

# Harmony effects
@export var harmony_on_active_break: int = 4
@export var harmony_on_dormant_break: int = -2

# If the player hits a special node incorrectly, it still breaks,
# but it gives dormant-style reward and this softer harmony adjustment.
@export var harmony_on_special_miss: int = -1

func get_tile_for_state(state: String, required_direction: Vector2i = Vector2i.ZERO) -> Dictionary:
	match state:
		"active":
			if mechanic_type == MechanicType.DIRECTIONAL:
				return get_direction_tile(required_direction)
			if mechanic_type == MechanicType.PULSE:
				if pulse_source_id >= 0:
					return {
						"source_id": pulse_source_id,
						"atlas": pulse_atlas
					}

			return {
				"source_id": active_source_id,
				"atlas": active_atlas
			}

		"dormant":
			return {
				"source_id": dormant_source_id,
				"atlas": dormant_atlas
			}

		"depleted":
			return {
				"source_id": depleted_source_id,
				"atlas": depleted_atlas
			}

		_:
			return {
				"source_id": -1,
				"atlas": Vector2i.ZERO
			}

func get_direction_tile(required_direction: Vector2i) -> Dictionary:
	match required_direction:
		Vector2i(0, -1):
			return {
				"source_id": direction_up_source_id if direction_up_source_id >= 0 else active_source_id,
				"atlas": direction_up_atlas if direction_up_source_id >= 0 else active_atlas
			}
		Vector2i(0, 1):
			return {
				"source_id": direction_down_source_id if direction_down_source_id >= 0 else active_source_id,
				"atlas": direction_down_atlas if direction_down_source_id >= 0 else active_atlas
			}
		Vector2i(-1, 0):
			return {
				"source_id": direction_left_source_id if direction_left_source_id >= 0 else active_source_id,
				"atlas": direction_left_atlas if direction_left_source_id >= 0 else active_atlas
			}
		Vector2i(1, 0):
			return {
				"source_id": direction_right_source_id if direction_right_source_id >= 0 else active_source_id,
				"atlas": direction_right_atlas if direction_right_source_id >= 0 else active_atlas
			}
		_:
			return {
				"source_id": active_source_id,
				"atlas": active_atlas
			}

func pick_required_direction() -> Vector2i:
	if allowed_directions.is_empty():
		return Vector2i(0, 1)

	var safe_dirs: Array[Vector2i] = []
	for d in allowed_directions:
		if d == Vector2i(0, -1) or d == Vector2i(0, 1) or d == Vector2i(-1, 0) or d == Vector2i(1, 0):
			safe_dirs.append(d)

	if safe_dirs.is_empty():
		return Vector2i(0, 1)

	return safe_dirs[randi_range(0, safe_dirs.size() - 1)]

func roll_dormant_drop() -> Dictionary:
	return {
		"item_id": dormant_drop_item,
		"qty": _roll_qty(dormant_drop_qty_min, dormant_drop_qty_max)
	}

func roll_active_drops(harmony: int = 50, bonus_drop_chance_bonus: float = 0.0) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []

	var main_qty := _roll_qty(active_drop_qty_min, active_drop_qty_max)
	if active_drop_item.strip_edges() != "" and main_qty > 0:
		drops.append({
			"item_id": active_drop_item,
			"qty": main_qty
		})

	if active_bonus_drop_item.strip_edges() != "":
		var chance := clampf(
			active_bonus_drop_chance + _get_harmony_bonus_chance(harmony) + bonus_drop_chance_bonus,
			0.0,
			1.0
		)

		if randf() <= chance:
			var bonus_qty := _roll_qty(active_bonus_qty_min, active_bonus_qty_max)
			if bonus_qty > 0:
				drops.append({
					"item_id": active_bonus_drop_item,
					"qty": bonus_qty
				})

	return drops

func _roll_qty(min_qty: int, max_qty: int) -> int:
	var a :Variant= max(0, min_qty)
	var b :Variant= max(a, max_qty)
	if a == b:
		return a
	return randi_range(a, b)

func _get_harmony_bonus_chance(harmony: int) -> float:
	# Gentle influence only — cozy, not swingy.
	if harmony >= 80:
		return 0.20
	if harmony >= 60:
		return 0.10
	if harmony >= 40:
		return 0.05
	return 0.0
