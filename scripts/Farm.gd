# Farm.gd (Godot 4.x) - Ground TileMap + Objects TileMap
extends Node2D

@onready var ground: TileMap = $Ground
@onready var objects: TileMap = $Objects
@onready var player := $Player as CharacterBody2D  # you said this cast works

# --- Tile IDs / atlas coords ---
# Ground tileset info (grass + tilled) in Ground TileMap
@export var ground_source_id: int = 0
@export var grass_coords: Vector2i = Vector2i(0, 0)
@export var tilled_coords: Vector2i = Vector2i(1, 0)

# Tree tileset info in Objects TileMap (tree.png atlas)
@export var tree_source_id: int = 0        # likely 0 inside Objects TileMap
@export var tree_coords: Vector2i = Vector2i(0, 0)

# Chop settings
@export var chops_to_fell: int = 3
var tree_chops: Dictionary = {}  # { Vector2i: int }

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("tool"):
		_tool_action()

func _tool_action() -> void:
	if GameState.is_gameplay_locked():
		return

	# If player is exhausted, block tool use completely
	if GameState.exhausted and GameState.energy <= 0:
		print("Too exhausted to use tools!")
		return

	var player_cell: Vector2i = ground.local_to_map(ground.to_local(player.global_position))
	var step := Vector2i(int(player.facing.x), int(player.facing.y))
	var target_cell := player_cell + step

	# Priority 1: chop tree if present
	if _cell_has_tree(target_cell):
		if not GameState.spend_energy(GameState.tool_action_cost):
			print("No energy to chop!")
			return
		_chop_tree(target_cell)
		return

	# Priority 2: till ground (only if it actually changes a tile)
	if _can_till_ground(target_cell):
		if not GameState.spend_energy(GameState.tool_action_cost):
			print("No energy to till!")
			return
		_try_till_ground(target_cell)
	else:
		print("Nothing to till here.")

func _cell_has_tree(cell: Vector2i) -> bool:
	# Objects TileMap uses the same cell coordinates if both TileMaps share tile size/origin
	var src := objects.get_cell_source_id(0, cell)
	if src != tree_source_id:
		return false
	var atlas := objects.get_cell_atlas_coords(0, cell)
	return atlas == tree_coords

func _chop_tree(cell: Vector2i) -> void:
	var current := int(tree_chops.get(cell, 0)) + 1
	tree_chops[cell] = current
	print("Chop ", current, "/", chops_to_fell, " at ", cell)

	if current >= chops_to_fell:
		objects.erase_cell(0, cell)  # remove tree ONLY from Objects TileMap
		tree_chops.erase(cell)
		GameState.add_item("Wood")
		print("Tree felled at ", cell)

func _try_till_ground(cell: Vector2i) -> void:
	var src := ground.get_cell_source_id(0, cell)
	var atlas := ground.get_cell_atlas_coords(0, cell)

	if src == ground_source_id and atlas == grass_coords:
		ground.set_cell(0, cell, ground_source_id, tilled_coords)
		print("Tilled tile at cell: ", cell) 

func _can_till_ground(cell: Vector2i) -> bool:
	var src := ground.get_cell_source_id(0, cell)
	var atlas := ground.get_cell_atlas_coords(0, cell)
	return (src == ground_source_id and atlas == grass_coords)
