# Farm.gd (Godot 4.x) - Ground TileMap + Objects TileMap
extends Node2D

@onready var spawn_from_town := $Spawn_FromTown

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

# --- Destructibles (Objects TileMap) ---
# Each destructible is defined by: source_id + atlas_coords -> behavior
# hits: how many tool uses to destroy
# drop: what goes into inventory
var destructible_defs := {
	"tree": {
		"source_id": 0,
		"atlas": Vector2i(0, 0),
		"hits": 3,
		"drop": "Wood",
		"tool": GameState.ToolType.AXE,
	},
	"rock": {
		"source_id": 2,
		"atlas": Vector2i(0, 0),
		"hits": 2,
		"drop": "Stone",
		"tool": GameState.ToolType.PICKAXE,
	},
}
# Chop settings
@export var chops_to_fell: int = 3
var destructible_hits: Dictionary = {} # { Vector2i: int }
# --- Destructibles ---

func _ready() -> void:
	_load_farm_state()
	TimeManager.day_changed.connect(_on_day_changed)
	
	if GameState.next_spawn_name != "":
		var marker := get_node_or_null(GameState.next_spawn_name)
		if marker and marker is Marker2D:
			player.global_position = (marker as Marker2D).global_position
		GameState.next_spawn_name = ""

	
func _on_day_changed(_day: int) -> void:
	_advance_all_crops_one_day()

func _load_farm_state() -> void:
	var map := GameState.get_map_state("Farm")

	# -------- FIRST RUN: capture the painted world as the baseline --------
	if not bool(map.get("has_initialized", false)):
		print("Farm state not initialized yet. Capturing baseline from painted scene...")

		# Capture whatever is currently painted in the scene
		map["ground"] = {}
		_save_tilemap_non_default(ground, map["ground"])

		map["objects"] = {}
		_save_tilemap_non_default(objects, map["objects"])

		# Crop state starts empty unless you already planted some before saving
		map["crops"] = {}
		map["hits"] = {}

		map["has_initialized"] = true

		# Also ensure our runtime dictionaries start clean
		crop_state.clear()
		destructible_hits.clear()

		print("Baseline captured. Ground:", map["ground"].size(), " Objects:", map["objects"].size())
		return

	# -------- NORMAL LOAD: clear and rebuild from saved state --------
	ground.clear_layer(0)
	objects.clear_layer(0)

	_load_tilemap_from_dict(ground, map["ground"])
	_load_tilemap_from_dict(objects, map["objects"])

	# Restore crop_state dictionary
	crop_state.clear()
	for key in map["crops"].keys():
		var cell := GameState.key_to_cell(key)
		crop_state[cell] = map["crops"][key]

	# Restore partial hits
	destructible_hits.clear()
	for key in map["hits"].keys():
		var cell := GameState.key_to_cell(key)
		destructible_hits[cell] = int(map["hits"][key])

	print("Loaded Farm state. Ground:", map["ground"].size(), " Objects:", map["objects"].size(), " Crops:", map["crops"].size(), " Hits:", map["hits"].size())

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

	var dkey := _get_destructible_key_at(target_cell)
	if dkey != "":
		var def: Dictionary = destructible_defs[dkey]
		var required_tool := int(def["tool"])

		if int(GameState.current_tool) != required_tool:
			print("Wrong tool! Need ", dkey, " tool.")
			return

		if not GameState.spend_energy(GameState.tool_action_cost):
			print("No energy to use tools!")
			return

		_hit_destructible(target_cell, dkey)
		return

	# 2) Harvest ripe crops
	if _is_crop_ripe(target_cell):
		if GameState.current_tool != GameState.ToolType.HOE:
			print("Need Hoe to harvest.")
			return
		if not GameState.spend_energy(GameState.tool_action_cost):
			print("No energy to harvest!")
			return
		_harvest_crop(target_cell)
		return

	# 3) Otherwise till
	if _can_till_ground(target_cell):
		if GameState.current_tool != GameState.ToolType.HOE:
			print("Need Hoe to till.")
			return
		if not GameState.spend_energy(GameState.tool_action_cost):
			print("No energy to till!")
			return
		_try_till_ground(target_cell)
		return

	else:
		print("Nothing to do here.")

func _get_destructible_key_at(cell: Vector2i) -> String:
	var src := objects.get_cell_source_id(0, cell)
	if src == -1:
		return ""

	var atlas := objects.get_cell_atlas_coords(0, cell)

	for key in destructible_defs.keys():
		var def: Dictionary = destructible_defs[key]
		if int(def["source_id"]) == src and Vector2i(def["atlas"]) == atlas:
			return String(key)

	return ""

func _hit_destructible(cell: Vector2i, key: String) -> void:
	var def: Dictionary = destructible_defs[key]
	var needed: int = int(def["hits"])

	var current := int(destructible_hits.get(cell, 0)) + 1
	destructible_hits[cell] = current

	print("Hit ", key, " ", current, "/", needed, " at ", cell)

	if current >= needed:
		objects.erase_cell(0, cell)
		destructible_hits.erase(cell)

		var drop := String(def["drop"])
		GameState.inventory_add(drop, 1)

		print(key, " destroyed at ", cell, " -> +1 ", drop)

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
	GameState.inventory_add(item, 1)

	print("Harvested ", crop_name, " at ", cell, " -> +1 ", item) 
	
func _exit_tree() -> void:
	_save_farm_state()
	
func _save_farm_state() -> void:
	var map := GameState.get_map_state("Farm")

	# Save tilled cells (only save non-default tiles)
	map["ground"] = {}
	_save_tilemap_non_default(ground, map["ground"])

	# Save objects placed (trees/rocks/crops tiles etc.)
	map["objects"] = {}
	_save_tilemap_non_default(objects, map["objects"])

	# Save crop growth state (your dictionary)
	map["crops"] = {}
	for cell in crop_state.keys():
		var key := GameState.cell_to_key(cell)
		map["crops"][key] = crop_state[cell]
		
	# Save partial hits on destructibles (so half-mined rocks persist)
	map["hits"] = {}
	for cell in destructible_hits.keys():
		var key := GameState.cell_to_key(cell)
		map["hits"][key] = int(destructible_hits[cell])

	print("Saved Farm state. Ground:", map["ground"].size(), " Objects:", map["objects"].size(), " Crops:", map["crops"].size())

func _save_tilemap_non_default(tilemap: TileMap, out_dict: Dictionary) -> void:
	var used_cells := tilemap.get_used_cells(0)
	for cell in used_cells:
		var src := tilemap.get_cell_source_id(0, cell)
		if src == -1:
			continue
		var atlas := tilemap.get_cell_atlas_coords(0, cell)
		# Store source + atlas for each used cell
		out_dict[GameState.cell_to_key(cell)] = { "src": src, "atlas": atlas }

func _load_tilemap_from_dict(tilemap: TileMap, data: Dictionary) -> void:
	for key in data.keys():
		var cell := GameState.key_to_cell(key)
		var entry: Dictionary = data[key]
		var src := int(entry["src"])
		var atlas := Vector2i(entry["atlas"])
		tilemap.set_cell(0, cell, src, atlas)
