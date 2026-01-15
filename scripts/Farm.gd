# Farm.gd (Godot 4.x) - Ground TileMap + Objects TileMap
extends Node2D

@onready var ground: TileMap = $TileMaps/Ground
@onready var objects: TileMap = $TileMaps/Objects
@onready var player := $Player as CharacterBody2D  # you said this cast works

# --- Tile IDs / atlas coords ---
# Ground tileset info (grass + tilled) in Ground TileMap
@export var ground_source_id: int = 0
@export var grass_coords: Vector2i = Vector2i(0, 0)
@export var tilled_coords: Vector2i = Vector2i(1, 0)
@export var wet_tilled_coords: Vector2i = Vector2i(2, 0)  # your new darker square

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
		"stages": [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0)],
		"days":   [1, 1, 9999],
		"harvest_item": "Watermelon",
		"harvest_yield": 1,
		# no regrow
	},

	# 4-stage blueberry bush, regrows forever.
	# Harvest gives multiple berries, then bush drops back one stage to regrow.
	"blueberry": {
		"stages": [Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(3,1)],
		"days":   [1, 1, 1, 9999],
		"harvest_item": "Blueberry",

		# NEW: random harvest range
		"harvest_yield_min": 2,
		"harvest_yield_max": 4,

		"regrow_to_stage": 2,
		"regrow_days": 1,
	},

	# 3-stage strawberry, harvest drops it back a stage so it can re-ripen.
	"strawberry": {
		"stages": [Vector2i(0,2), Vector2i(1,2), Vector2i(2,2), Vector2i(3,2)],
		"days":   [1, 1, 1, 9999],
		"harvest_item": "Strawberry",
		"harvest_yield": 1,

		# after harvest, drop to stage 1 and take 1 day to become ripe again
		"regrow_to_stage": 1,
		"regrow_days": 1,
	},

	# Avocado: 2-stage plant PLUS an optional "overripe" stage.
	# If you don't want a 3rd tile visually, you can reuse the ripe tile for stage 2.
	"avocado": {
		# stage0 = growing, stage1 = ripe, stage2 = overripe
		"stages": [Vector2i(0,3), Vector2i(1,3), Vector2i(2,3)], # if you only have 2 tiles, make stage2 coords same as stage1
		"days":   [2, 2, 9999],

		# Here’s the key: harvest item depends on stage
		"harvest_items_by_stage": {
			1: "Avocado",
			2: "Overripe Avocado",
		},
		"harvest_yields_by_stage": {
			1: 1,
			2: 1,
		},

		# You can harvest at ripe OR overripe
		"harvestable_stages": [1, 2],

		# Rot should advance even if you don't water anymore once ripe:
		# (when stage >= 1, ignore watering requirement)
		"ignore_water_after_stage": 1,
		
		"ripe_stage": 1,
		"overripe_stage": 2,
	},
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

var watered_today: Dictionary = {}  # cell_key -> true
var rained_today: bool = false

@export var water_splash_scene: PackedScene

@export var ripe_indicator_scene: PackedScene
@export var overripe_indicator_scene: PackedScene

var _crop_indicators: Dictionary = {} 
# cell_key -> { "state": String, "node": Node2D }

@onready var sfx_player: AudioStreamPlayer2D = $SfxPlayer2D

@export var sfx_water_splash: AudioStream
@export var sfx_seed_plant: AudioStream
@export var sfx_harvest: AudioStream
@export var sfx_hit_tree: AudioStream
@export var sfx_hit_rock: AudioStream

@onready var ambience_player: AudioStreamPlayer2D = $AmbiencePlayer

@onready var life_player: AudioStreamPlayer2D = $LifePlayer
@onready var life_timer: Timer = $LifeTimer

@export var bird_chirps: Array[AudioStream] = []
@export var leaf_rustles: Array[AudioStream] = []

@export var life_interval_min: float = 10.0
@export var life_interval_max: float = 30.0

func _ready() -> void:
	_load_farm_state()
	if ambience_player and not ambience_player.playing:
		ambience_player.play()
	life_timer.timeout.connect(_on_life_timer_timeout)
	_schedule_next_life_sound()
	
	TimeManager.day_changed.connect(_on_day_changed)
	
	if GameState.next_spawn_name != "":
		var marker := get_node_or_null(GameState.next_spawn_name)
		if marker and marker is Marker2D:
			player.global_position = (marker as Marker2D).global_position
		GameState.next_spawn_name = ""
		
	var wc := get_node_or_null("/root/WeatherChange")
	if wc != null and wc.has_signal("weather_changed"):
		wc.weather_changed.connect(_on_weather_changed)

	# If we enter the scene and it's already raining, wet the visuals now
	if _is_raining_today():
		_apply_rain_wet_visuals_today()
	
func _on_day_changed(_day: int) -> void:
	var grew_from_rain := rained_today  # rain that happened during the previous day

	print("DAY CHANGED: grew_from_rain=", grew_from_rain, " is_raining_today=", _is_raining_today())

	# 1) Grow crops if they were watered yesterday OR it rained yesterday
	_advance_all_crops_one_day(grew_from_rain)

	# new day reset
	watered_today.clear()
	# 2) Clear yesterday wet state (tiles + dictionary)
	_clear_watered_visuals_and_state()
	# IMPORTANT: dry visuals now so you can water again today
	_dry_wet_tiles_under_crops()

	# 3) Reset daily rain flag (we are starting a brand new day)
	rained_today = false

	# 4) If it's raining today, wet visuals for today (but no growth credit yet)
	if _is_raining_today():
		rained_today = true
		_apply_rain_wet_visuals_today()

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
		_try_plant_selected_seed()
	if event.is_action_pressed("seed_next"):
		GameState.cycle_seed_next()

func _try_plant_selected_seed() -> void:
	if GameState.is_gameplay_locked():
		return

	var seed_id := GameState.selected_item_id
	if seed_id.is_empty():
		print("No seed selected. (Tip: use your seed cycle key after buying seeds.)")
		return

	if not GameState.is_seed_item(seed_id):
		print("Selected item is not a seed:", seed_id)
		return

	if not GameState.inventory_has(seed_id, 1):
		print("You don't have any", seed_id, "left.")
		return

	var crop_name := GameState.get_crop_for_seed(seed_id)
	if crop_name.is_empty():
		print("Seed has no crop mapping:", seed_id)
		return

	# Attempt to plant crop first; only consume seed if planting succeeds
	var planted := _try_plant_crop_return_success(crop_name)
	if planted:
		GameState.inventory_remove(seed_id, 1)
		print("Planted", crop_name, "using", seed_id)

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

		# 2) Watering (Watering Can)
	if GameState.current_tool == GameState.ToolType.WATERING_CAN:
		# Optional rules:
		# - water only tilled soil
		# - OR water only if crop exists
		var src := ground.get_cell_source_id(0, target_cell)
		var atlas := ground.get_cell_atlas_coords(0, target_cell)

		var is_tilled_or_wet := (src == ground_source_id and (atlas == tilled_coords or atlas == wet_tilled_coords))
		if not is_tilled_or_wet:
			print("Can't water here (not tilled soil).")
			return

		# If it's already wet-looking, treat it as already watered (optional behavior)
		if atlas == wet_tilled_coords:
			print("This tile is already wet.")
			return

		if not GameState.spend_energy(GameState.tool_action_cost):
			print("No energy to water!")
			return

		water_cell(target_cell)
		return
	
	# 3) Harvest ripe crops
	if _is_crop_harvestable(target_cell):
		if GameState.current_tool != GameState.ToolType.HOE:
			print("Need Hoe to harvest.")
			return
		if not GameState.spend_energy(GameState.tool_action_cost):
			print("No energy to harvest!")
			return
		_harvest_crop(target_cell)
		return

	# 4) Otherwise till
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
	
	match key:
		"tree":
			_play_sfx(sfx_hit_tree, _cell_to_world_center(cell))
			player.camera_shake(200.0, 0.12, 32.0, 10.0)
		"rock":
			_play_sfx(sfx_hit_rock, _cell_to_world_center(cell))
			player.camera_shake(300.0, 0.16, 35.0, 9.0)

	if current >= needed:
		objects.erase_cell(0, cell)
		destructible_hits.erase(cell)

		var drop := String(def["drop"])
		GameState.inventory_add(drop, 1)

		print(key, " destroyed at ", cell, " -> +1 ", drop)
		# Report a distinct action based on what was destroyed
		match key:
			"tree":
				GameState.report_action("chop_tree", 1)
			"rock":
				GameState.report_action("break_rock", 1)
			_:
				GameState.report_action("break_object", 1)

func _try_plant_crop_return_success(crop_name: String) -> bool:
	if GameState.is_gameplay_locked():
		return false
	if not crop_defs.has(crop_name):
		print("Unknown crop: ", crop_name)
		return false

	var player_cell: Vector2i = ground.local_to_map(ground.to_local(player.global_position))
	var step := Vector2i(int(player.facing.x), int(player.facing.y))
	var cell := player_cell + step

	# Must be tilled soil (dry OR wet tilled)
	var src := ground.get_cell_source_id(0, cell)
	var atlas := ground.get_cell_atlas_coords(0, cell)

	var is_dry_tilled := (src == ground_source_id and atlas == tilled_coords)
	var is_wet_tilled := false
	is_wet_tilled = (src == ground_source_id and atlas == wet_tilled_coords)

	if not (is_dry_tilled or is_wet_tilled):
		print("Not tilled soil; can't plant.")
		return false

	# Must not already have an object/crop there
	if objects.get_cell_source_id(0, cell) != -1:
		print("Something already on that tile.")
		return false

	var def: Dictionary = crop_defs[crop_name]
	var stages: Array = def["stages"]
	var days: Array = def["days"]

	objects.set_cell(0, cell, crops_source_id, stages[0])

	crop_state[cell] = {
		"type": crop_name,
		"stage": 0,
		"days_left": int(days[0])
	}

	print("Planted ", crop_name, " at ", cell)
	_play_sfx(sfx_seed_plant, _cell_to_world_center(cell))
	_update_crop_indicator(cell)
	return true
	
func _advance_all_crops_one_day(raining: bool = false) -> void:
	var cells := crop_state.keys()

	for cell in cells:
		var data: Dictionary = crop_state[cell]
		var crop_name := String(data["type"])

		if not crop_defs.has(crop_name):
			continue

		var def: Dictionary = crop_defs[crop_name]
		var stages: Array = def["stages"]
		var days: Array = def["days"]

		var stage: int = int(data["stage"])
		var watered := (raining or is_cell_watered(cell))

		# --- Watering requirement logic ---
		var ignore_after := int(def.get("ignore_water_after_stage", -1))
		var needs_water := true
		if ignore_after != -1 and stage >= ignore_after:
			needs_water = false

		# If this stage needs water and we have none, do NOT progress (do not tick days_left)
		if needs_water and not watered:
			continue

		# --- Tick day countdown ---
		var days_left: int = int(data["days_left"]) - 1
		data["days_left"] = days_left

		if days_left > 0:
			crop_state[cell] = data
			continue

		# --- Advance stage ---
		var next_stage := stage + 1

		# Clamp at final stage
		if next_stage >= stages.size():
			data["stage"] = stages.size() - 1
			data["days_left"] = 9999
			crop_state[cell] = data
			continue

		data["stage"] = next_stage
		data["days_left"] = int(days[next_stage])
		crop_state[cell] = data

		objects.set_cell(0, cell, crops_source_id, stages[next_stage])

		print(crop_name, " grew to stage ", next_stage, " at ", cell,
			" (watered=", watered, ", needs_water=", needs_water, ")")
		
		_update_crop_indicator(cell)

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

func _is_crop_harvestable(cell: Vector2i) -> bool:
	if not crop_state.has(cell):
		return false

	var data: Dictionary = crop_state[cell]
	var crop_name := String(data["type"])
	if not crop_defs.has(crop_name):
		return false

	var def: Dictionary = crop_defs[crop_name]
	var stage: int = int(data["stage"])

	# If crop defines custom harvestable stages, use that
	if def.has("harvestable_stages"):
		var hs: Array = def["harvestable_stages"]
		return hs.has(stage)

	# Otherwise: last stage is harvestable
	var stages: Array = def["stages"]
	return stage >= (stages.size() - 1)

func _harvest_crop(cell: Vector2i) -> void:
	var data: Dictionary = crop_state[cell]
	var crop_name := String(data["type"])
	var def: Dictionary = crop_defs[crop_name]
	var stage: int = int(data["stage"])

	# 1) Decide what item + how many we give
	var item_name: String = ""
	var qty: int = 1

	if def.has("harvest_items_by_stage"):
		var hib: Dictionary = def["harvest_items_by_stage"]
		item_name = String(hib.get(stage, ""))
	else:
		item_name = String(def.get("harvest_item", ""))

	# NEW: yield range support (falls back to existing behavior)
	if def.has("harvest_yields_by_stage"):
		var hyb: Dictionary = def["harvest_yields_by_stage"]
		qty = int(hyb.get(stage, 1))
	elif def.has("harvest_yield_min") and def.has("harvest_yield_max"):
		var mn := int(def["harvest_yield_min"])
		var mx := int(def["harvest_yield_max"])
		if mx < mn:
			var tmp := mn
			mn = mx
			mx = tmp
		qty = randi_range(mn, mx)
	else:
		qty = int(def.get("harvest_yield", 1))

	if item_name == "":
		print("Harvest failed: no harvest item defined for crop:", crop_name, " stage:", stage)
		return

	GameState.inventory_add(item_name, qty)
	print("Harvested ", crop_name, " at ", cell, " -> +", qty, " ", item_name)
	_play_sfx(sfx_harvest, _cell_to_world_center(cell))
	player.camera_shake(1.5, 0.08, 28.0, 12.0)

	# 2) Regrow or remove?
	if def.has("regrow_to_stage"):
		var regrow_stage := int(def["regrow_to_stage"])
		var regrow_days := int(def.get("regrow_days", 1))

		data["stage"] = regrow_stage
		data["days_left"] = regrow_days
		crop_state[cell] = data

		# Update visuals to regrow stage
		var stages: Array = def["stages"]
		objects.set_cell(0, cell, crops_source_id, stages[regrow_stage])
		print("Regrow: set ", crop_name, " back to stage ", regrow_stage, " for ", regrow_days, " day(s).")
		_update_crop_indicator(cell)
		return

	# If not regrow, remove crop entirely
	objects.erase_cell(0, cell)
	crop_state.erase(cell)
	
	_update_crop_indicator(cell)
	
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

func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func water_cell(cell: Vector2i) -> void:
	if _is_raining_today():
		print("Already raining — watering not needed.")
		return
	
	var key := _cell_key(cell)
	watered_today[key] = true

	# Visual: switch tilled -> wet tilled
	var src := ground.get_cell_source_id(0, cell)
	var atlas := ground.get_cell_atlas_coords(0, cell)
	var is_tilled := (src == ground_source_id and atlas == tilled_coords)

	if is_tilled:
		ground.set_cell(0, cell, ground_source_id, wet_tilled_coords)
	
	# Optional: visual change (wet soil tile), particles, etc.
	_spawn_water_splash(cell)
	
	# Position sound at the tile
	if sfx_player and sfx_water_splash:
		sfx_player.global_position = _cell_to_world_center(cell)
		sfx_player.stream = sfx_water_splash
		sfx_player.play()

	print("Watered cell:", key)

func is_cell_watered(cell: Vector2i) -> bool:
	return watered_today.has(_cell_key(cell))

func _clear_watered_visuals_and_state() -> void:
	# Revert wet tiles back to normal tilled tiles
	for key_any in watered_today.keys():
		var key := String(key_any)
		var parts := key.split(",")
		var cell := Vector2i(int(parts[0]), int(parts[1]))

		var src := ground.get_cell_source_id(0, cell)
		var atlas := ground.get_cell_atlas_coords(0, cell)

		if src == ground_source_id and atlas == wet_tilled_coords:
			ground.set_cell(0, cell, ground_source_id, tilled_coords)

	watered_today.clear()

func _apply_rain_wet_visuals_today() -> void:
	print("Applying rain wet visuals. crops=", crop_state.size())

	# Wet only planted tiles (recommended)
	for cell in crop_state.keys():
		var src := ground.get_cell_source_id(0, cell)
		var atlas := ground.get_cell_atlas_coords(0, cell)

		if src == ground_source_id and atlas == tilled_coords:
			ground.set_cell(0, cell, ground_source_id, wet_tilled_coords)

func _is_raining_today() -> bool:
	var wc := get_node_or_null("/root/WeatherChange")
	return wc != null and wc.is_raining()

func _was_raining_yesterday() -> bool:
	var wc := get_node_or_null("/root/WeatherChange")
	return wc != null and wc.was_raining_yesterday()

func _on_weather_changed(_new_weather: int) -> void:
	# We only "wet" on rain start. We do NOT dry when rain stops.
	# Drying happens next morning via _on_day_changed.
	print("WEATHER CHANGED: is_raining_today=", _is_raining_today(), " name=", get_node_or_null("/root/WeatherChange").get_weather_name() if get_node_or_null("/root/WeatherChange") else "no weather")
	if _is_raining_today():
		_apply_rain_wet_visuals_today()  # VISUAL ONLY

func _dry_wet_tiles_under_crops() -> void:
	for cell in crop_state.keys():
		var src := ground.get_cell_source_id(0, cell)
		var atlas := ground.get_cell_atlas_coords(0, cell)
		if src == ground_source_id and atlas == wet_tilled_coords:
			ground.set_cell(0, cell, ground_source_id, tilled_coords)

func _spawn_water_splash(cell: Vector2i) -> void:
	if water_splash_scene == null:
		return

	# Place splash at the center of the tile in world space
	var half_tile := Vector2(ground.tile_set.tile_size) * 0.5
	var local_center := ground.map_to_local(cell) + half_tile* 0.5
	var world_pos := ground.to_global(local_center)

	var splash := water_splash_scene.instantiate() as Node2D
	add_child(splash)
	splash.global_position = world_pos
	
func _cell_to_world_center(cell: Vector2i) -> Vector2:
	# map_to_local returns Vector2, tile_size is Vector2i → convert it
	var tile_size: Vector2 = Vector2(ground.tile_set.tile_size)
	return ground.to_global(ground.map_to_local(cell) + tile_size * 0.5)

func _get_crop_readiness(cell: Vector2i) -> String:
	if not crop_state.has(cell):
		return ""

	var data: Dictionary = crop_state[cell]
	var crop_name := String(data.get("type", ""))
	var stage := int(data.get("stage", 0))

	if not crop_defs.has(crop_name):
		return ""

	var def: Dictionary = crop_defs[crop_name]
	var stages: Array = def["stages"]
	var final_stage := stages.size() - 1

	# Default rule: final stage = ripe
	var ripe_stage := int(def.get("ripe_stage", final_stage))
	var overripe_stage := int(def.get("overripe_stage", -1))
	
	if crop_name == "avocado":
		print("AVOCADO stage=", stage, " ripe=", ripe_stage, " overripe=", overripe_stage)

	# If this crop supports overripe, check it
	if overripe_stage >= 0 and stage >= overripe_stage:
		return "overripe"

	if stage >= ripe_stage:
		return "ripe"

	return ""

func _update_crop_indicator(cell: Vector2i) -> void:
	var key := _cell_key(cell)
	var readiness := _get_crop_readiness(cell)  # "", "ripe", "overripe"

	# --- Remove if not ready ---
	if readiness == "":
		if _crop_indicators.has(key):
			var entry := _crop_indicators[key] as Dictionary
			var node := entry.get("node", null) as Node2D
			if node != null:
				node.queue_free()
			_crop_indicators.erase(key)
		return

	# --- Pick which scene to use ---
	var desired_scene: PackedScene = null
	if readiness == "overripe":
		desired_scene = overripe_indicator_scene
	else:
		desired_scene = ripe_indicator_scene

	if desired_scene == null:
		return

	var desired_pos := _cell_to_world_center(cell) + Vector2(0, -10)

	# --- If we already have an indicator, decide whether to keep or swap ---
	if _crop_indicators.has(key):
		var entry := _crop_indicators[key] as Dictionary
		var existing_state := String(entry.get("state", ""))
		var existing_node := entry.get("node", null) as Node2D

		# If the state matches, just move it
		if existing_state == readiness and existing_node != null:
			existing_node.global_position = desired_pos
			return

		# State changed (ripe -> overripe or overripe -> ripe): remove old node
		if existing_node != null:
			existing_node.queue_free()
		_crop_indicators.erase(key)

	# --- Spawn the correct indicator ---
	var fx := desired_scene.instantiate() as Node2D
	add_child(fx)
	fx.global_position = desired_pos
	fx.z_index = 100  # keeps it safely above crops

	_crop_indicators[key] = {
		"state": readiness,
		"node": fx
	}

func _play_sfx(stream: AudioStream, world_pos: Vector2) -> void:
	if stream == null:
		return
	if sfx_player == null:
		return

	sfx_player.pitch_scale = randf_range(0.95, 1.05)
	sfx_player.global_position = world_pos
	sfx_player.stream = stream
	sfx_player.play()

func _schedule_next_life_sound() -> void:
	var t := randf_range(life_interval_min, life_interval_max)
	life_timer.wait_time = t
	life_timer.start()

func _on_life_timer_timeout() -> void:
	if life_player == null:
		return

	# Optional: don’t do life sounds when gameplay is locked (menus/dialogue)
	if GameState.is_gameplay_locked():
		_schedule_next_life_sound()
		return

	var pool: Array[AudioStream] = []

	# You can mix both, or choose based on time of day later
	pool.append_array(bird_chirps)
	pool.append_array(leaf_rustles)

	if pool.is_empty():
		_schedule_next_life_sound()
		return

	var stream: AudioStream = pool[randi() % pool.size()]
	if stream == null:
		_schedule_next_life_sound()
		return

	# Gentle variation makes it feel alive
	life_player.pitch_scale = randf_range(0.95, 1.05)
	life_player.volume_db = randf_range(-18.0, -12.0)

	life_player.stream = stream
	life_player.play()

	_schedule_next_life_sound()
