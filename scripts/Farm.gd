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

# --- Crop system ---
@export var crops_source_id: int = 1  # IMPORTANT: set this to crops.png source ID in the Objects TileSet

# Crop definitions: add new crops here later.
# - stages: atlas coords in crops.png
# - days: how many days each stage lasts (final stage can be huge like 9999)
# - harvest_item: what to add to inventory on harvest
var crop_defs := {
	"watermelon": {
		"stages": [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0)],   # seed, stalk, ripe
		"days":   [1, 1, 9999],                                   # tune this
		"harvest_item": "Watermelon",
	}
}

# crop_state[cell] = { "type": String, "stage": int, "days_left": int }
var crop_state: Dictionary = {}
# --- Crop system ---

func _ready() -> void:
	TimeManager.day_changed.connect(_on_day_changed)
	
func _on_day_changed(_day: int) -> void:
	_advance_all_crops_one_day()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("tool"):
		_tool_action()
	if event.is_action_pressed("plant_seed"):
		_try_plant_crop("watermelon")

func _tool_action() -> void:
	if GameState.is_gameplay_locked():
		return

	# If exhausted, block tool use
	if GameState.exhausted and GameState.energy <= 0:
		print("Too exhausted to use tools!")
		return

	var player_cell: Vector2i = ground.local_to_map(ground.to_local(player.global_position))
	var step := Vector2i(int(player.facing.x), int(player.facing.y))
	var target_cell := player_cell + step

	# 1) Trees/rocks first
	if _cell_has_tree(target_cell):
		if not GameState.spend_energy(GameState.tool_action_cost):
			print("No energy to chop!")
			return
		_chop_tree(target_cell)
		return

	# 2) Harvest ripe crops
	if _is_crop_ripe(target_cell):
		if not GameState.spend_energy(GameState.tool_action_cost):
			print("No energy to harvest!")
			return
		_harvest_crop(target_cell)
		return

	# 3) Otherwise till
	if _can_till_ground(target_cell):
		if not GameState.spend_energy(GameState.tool_action_cost):
			print("No energy to till!")
			return
		_try_till_ground(target_cell)
	else:
		print("Nothing to do here.")

func _try_plant_crop(crop_name: String) -> void:
	if GameState.is_gameplay_locked():
		return
	if not crop_defs.has(crop_name):
		print("Unknown crop: ", crop_name)
		return

	var player_cell: Vector2i = ground.local_to_map(ground.to_local(player.global_position))
	var step := Vector2i(int(player.facing.x), int(player.facing.y))
	var cell := player_cell + step

	# Must be tilled soil
	var src := ground.get_cell_source_id(0, cell)
	var atlas := ground.get_cell_atlas_coords(0, cell)
	if not (src == ground_source_id and atlas == tilled_coords):
		print("Not tilled soil; can't plant.")
		return

	# Must not already have an object/crop there
	if objects.get_cell_source_id(0, cell) != -1:
		print("Something already on that tile.")
		return

	var def: Dictionary = crop_defs[crop_name]
	var stages: Array = def["stages"]
	var days: Array = def["days"]

	# Plant stage 0
	objects.set_cell(0, cell, crops_source_id, stages[0])

	crop_state[cell] = {
		"type": crop_name,
		"stage": 0,
		"days_left": int(days[0])
	}

	print("Planted ", crop_name, " at ", cell)

	
func _advance_all_crops_one_day() -> void:
	var cells := crop_state.keys()

	for cell in cells:
		var data: Dictionary = crop_state[cell]
		var crop_name := String(data["type"])

		# Crop definition might be missing if you renamed stuff
		if not crop_defs.has(crop_name):
			continue

		var def: Dictionary = crop_defs[crop_name]
		var stages: Array = def["stages"]
		var days: Array = def["days"]

		var stage: int = int(data["stage"])
		var days_left: int = int(data["days_left"]) - 1
		data["days_left"] = days_left

		if days_left > 0:
			crop_state[cell] = data
			continue

		# Stage finished, try to advance
		var next_stage := stage + 1

		# If already final stage, keep it there
		if next_stage >= stages.size():
			data["stage"] = stages.size() - 1
			data["days_left"] = 9999
			crop_state[cell] = data
			continue

		# Advance stage
		data["stage"] = next_stage
		data["days_left"] = int(days[next_stage])
		crop_state[cell] = data

		objects.set_cell(0, cell, crops_source_id, stages[next_stage])
		print(crop_name, " grew to stage ", next_stage, " at ", cell)

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
	
func _get_crop_at(cell: Vector2i) -> Dictionary:
	if not crop_state.has(cell):
		return {}
	return crop_state[cell]

func _is_crop_ripe(cell: Vector2i) -> bool:
	if not crop_state.has(cell):
		return false

	var data: Dictionary = crop_state[cell]
	var crop_name := String(data["type"])
	if not crop_defs.has(crop_name):
		return false

	var def: Dictionary = crop_defs[crop_name]
	var stages: Array = def["stages"]
	var stage: int = int(data["stage"])

	return stage >= (stages.size() - 1)

func _harvest_crop(cell: Vector2i) -> void:
	var data: Dictionary = crop_state[cell]
	var crop_name := String(data["type"])
	var def: Dictionary = crop_defs[crop_name]

	# Remove the crop tile and its state
	objects.erase_cell(0, cell)
	crop_state.erase(cell)

	# Add harvest item to inventory
	var item := String(def["harvest_item"])
	GameState.add_item(item)

	print("Harvested ", crop_name, " at ", cell, " -> +1 ", item)
