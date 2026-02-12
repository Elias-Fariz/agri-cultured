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
	},

	"blueberry": {
		"stages": [Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(3,1)],
		"days":   [1, 1, 1, 9999],
		"harvest_item": "Blueberry",
		"harvest_yield_min": 2,
		"harvest_yield_max": 4,
		"regrow_to_stage": 2,
		"regrow_days": 1,
	},

	"strawberry": {
		"stages": [Vector2i(0,2), Vector2i(1,2), Vector2i(2,2), Vector2i(3,2)],
		"days":   [1, 1, 1, 9999],
		"harvest_item": "Strawberry",
		"harvest_yield": 1,
		"regrow_to_stage": 1,
		"regrow_days": 1,
	},

	"avocado": {
		"stages": [Vector2i(0,3), Vector2i(1,3), Vector2i(2,3)],
		"days":   [2, 2, 9999],
		"harvest_items_by_stage": {
			1: "Avocado",
			2: "Overripe Avocado",
		},
		"harvest_yields_by_stage": {
			1: 1,
			2: 1,
		},
		"harvestable_stages": [1, 2],
		"ignore_water_after_stage": 1,
		"ripe_stage": 1,
		"overripe_stage": 2,
	},
}

# crop_state[cell] = { "type": String, "stage": int, "days_left": int }
var crop_state: Dictionary = {}
# --- Crop system ---

# --- Destructibles (Objects TileMap) ---
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

	if _is_raining_today():
		_apply_rain_wet_visuals_today()
	
	# Wait 2 frames so Player + DialogueUI are definitely in groups,
	# and CutsceneDirector can see current_scene reliably.
	await get_tree().process_frame
	await get_tree().process_frame

	# If a greeting cutscene is pending, play it now.
	if GameState != null and GameState.has_method("try_play_pending_cutscene"):
		GameState.try_play_pending_cutscene()

func _on_day_changed(_day: int) -> void:
	var grew_from_rain := rained_today  # rain that happened during the previous day

	print("DAY CHANGED: grew_from_rain=", grew_from_rain, " is_raining_today=", _is_raining_today())

	_advance_all_crops_one_day(grew_from_rain)

	watered_today.clear()
	_clear_watered_visuals_and_state()
	_dry_wet_tiles_under_crops()

	rained_today = false

	if _is_raining_today():
		rained_today = true
		_apply_rain_wet_visuals_today()

func _load_farm_state() -> void:
	var map := GameState.get_map_state("Farm")

	if not bool(map.get("has_initialized", false)):
		print("Farm state not initialized yet. Capturing baseline from painted scene...")

		map["ground"] = {}
		_save_tilemap_non_default(ground, map["ground"])

		map["objects"] = {}
		_save_tilemap_non_default(objects, map["objects"])

		map["crops"] = {}
		map["hits"] = {}

		map["has_initialized"] = true

		crop_state.clear()
		destructible_hits.clear()

		print("Baseline captured. Ground:", map["ground"].size(), " Objects:", map["objects"].size())
		return

	ground.clear_layer(0)
	objects.clear_layer(0)

	_load_tilemap_from_dict(ground, map["ground"])
	_load_tilemap_from_dict(objects, map["objects"])

	crop_state.clear()
	for key in map["crops"].keys():
		var cell := GameState.key_to_cell(key)
		crop_state[cell] = map["crops"][key]

	destructible_hits.clear()
	for key in map["hits"].keys():
		var cell := GameState.key_to_cell(key)
		destructible_hits[cell] = int(map["hits"][key])

	print("Loaded Farm state. Ground:", map["ground"].size(), " Objects:", map["objects"].size(), " Crops:", map["crops"].size(), " Hits:", map["hits"].size())

func _unhandled_input(event: InputEvent) -> void:
	# ✅ Tool action moved OUT of Farm and into ToolSystem
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

	var planted := _try_plant_crop_return_success(crop_name)
	if planted:
		GameState.inventory_remove(seed_id, 1)
		print("Planted", crop_name, "using", seed_id)

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

	var src := ground.get_cell_source_id(0, cell)
	var atlas := ground.get_cell_atlas_coords(0, cell)

	var is_dry_tilled := (src == ground_source_id and atlas == tilled_coords)
	var is_wet_tilled := (src == ground_source_id and atlas == wet_tilled_coords)

	if not (is_dry_tilled or is_wet_tilled):
		print("Not tilled soil; can't plant.")
		return false

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

		var ignore_after := int(def.get("ignore_water_after_stage", -1))
		var needs_water := true
		if ignore_after != -1 and stage >= ignore_after:
			needs_water = false

		if needs_water and not watered:
			continue

		var days_left: int = int(data["days_left"]) - 1
		data["days_left"] = days_left

		if days_left > 0:
			crop_state[cell] = data
			continue

		var next_stage := stage + 1

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

	if def.has("harvestable_stages"):
		var hs: Array = def["harvestable_stages"]
		return hs.has(stage)

	var stages: Array = def["stages"]
	return stage >= (stages.size() - 1)

func _harvest_crop(cell: Vector2i) -> void:
	var data: Dictionary = crop_state[cell]
	var crop_name := String(data["type"])
	var def: Dictionary = crop_defs[crop_name]
	var stage: int = int(data["stage"])

	var item_name: String = ""
	var qty: int = 1

	if def.has("harvest_items_by_stage"):
		var hib: Dictionary = def["harvest_items_by_stage"]
		item_name = String(hib.get(stage, ""))
	else:
		item_name = String(def.get("harvest_item", ""))

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

	QuestEvents.crop_harvested.emit(item_name, qty)

	_play_sfx(sfx_harvest, _cell_to_world_center(cell))
	player.camera_shake(1.5, 0.08, 28.0, 12.0)

	if def.has("regrow_to_stage"):
		var regrow_stage := int(def["regrow_to_stage"])
		var regrow_days := int(def.get("regrow_days", 1))

		data["stage"] = regrow_stage
		data["days_left"] = regrow_days
		crop_state[cell] = data

		var stages: Array = def["stages"]
		objects.set_cell(0, cell, crops_source_id, stages[regrow_stage])
		print("Regrow: set ", crop_name, " back to stage ", regrow_stage, " for ", regrow_days, " day(s).")
		_update_crop_indicator(cell)
		return

	objects.erase_cell(0, cell)
	crop_state.erase(cell)
	_update_crop_indicator(cell)

func _exit_tree() -> void:
	_save_farm_state()

func _save_farm_state() -> void:
	var map := GameState.get_map_state("Farm")

	map["ground"] = {}
	_save_tilemap_non_default(ground, map["ground"])

	map["objects"] = {}
	_save_tilemap_non_default(objects, map["objects"])

	map["crops"] = {}
	for cell in crop_state.keys():
		var key := GameState.cell_to_key(cell)
		map["crops"][key] = crop_state[cell]

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

	var src := ground.get_cell_source_id(0, cell)
	var atlas := ground.get_cell_atlas_coords(0, cell)
	var is_tilled := (src == ground_source_id and atlas == tilled_coords)

	if is_tilled:
		ground.set_cell(0, cell, ground_source_id, wet_tilled_coords)

	_spawn_water_splash(cell)

	if sfx_player and sfx_water_splash:
		sfx_player.global_position = _cell_to_world_center(cell)
		sfx_player.stream = sfx_water_splash
		sfx_player.play()

	print("Watered cell:", key)

func is_cell_watered(cell: Vector2i) -> bool:
	return watered_today.has(_cell_key(cell))

func _clear_watered_visuals_and_state() -> void:
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
	print("WEATHER CHANGED: is_raining_today=", _is_raining_today(),
		" name=", get_node_or_null("/root/WeatherChange").get_weather_name() if get_node_or_null("/root/WeatherChange") else "no weather")
	if _is_raining_today():
		_apply_rain_wet_visuals_today()

func _dry_wet_tiles_under_crops() -> void:
	for cell in crop_state.keys():
		var src := ground.get_cell_source_id(0, cell)
		var atlas := ground.get_cell_atlas_coords(0, cell)
		if src == ground_source_id and atlas == wet_tilled_coords:
			ground.set_cell(0, cell, ground_source_id, tilled_coords)

func _spawn_water_splash(cell: Vector2i) -> void:
	if water_splash_scene == null:
		return

	var half_tile := Vector2(ground.tile_set.tile_size) * 0.5
	var local_center := ground.map_to_local(cell) + half_tile * 0.5
	var world_pos := ground.to_global(local_center)

	var splash := water_splash_scene.instantiate() as Node2D
	add_child(splash)
	splash.global_position = world_pos

func _cell_to_world_center(cell: Vector2i) -> Vector2:
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

	var ripe_stage := int(def.get("ripe_stage", final_stage))
	var overripe_stage := int(def.get("overripe_stage", -1))

	if overripe_stage >= 0 and stage >= overripe_stage:
		return "overripe"

	if stage >= ripe_stage:
		return "ripe"

	return ""

func _update_crop_indicator(cell: Vector2i) -> void:
	var key := _cell_key(cell)
	var readiness := _get_crop_readiness(cell)

	if readiness == "":
		if _crop_indicators.has(key):
			var entry := _crop_indicators[key] as Dictionary
			var node := entry.get("node", null) as Node2D
			if node != null:
				node.queue_free()
			_crop_indicators.erase(key)
		return

	var desired_scene: PackedScene = null
	if readiness == "overripe":
		desired_scene = overripe_indicator_scene
	else:
		desired_scene = ripe_indicator_scene

	if desired_scene == null:
		return

	var desired_pos := _cell_to_world_center(cell) + Vector2(0, -10)

	if _crop_indicators.has(key):
		var entry := _crop_indicators[key] as Dictionary
		var existing_state := String(entry.get("state", ""))
		var existing_node := entry.get("node", null) as Node2D

		if existing_state == readiness and existing_node != null:
			existing_node.global_position = desired_pos
			return

		if existing_node != null:
			existing_node.queue_free()
		_crop_indicators.erase(key)

	var fx := desired_scene.instantiate() as Node2D
	add_child(fx)
	fx.global_position = desired_pos
	fx.z_index = 100

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

	if GameState.is_gameplay_locked():
		_schedule_next_life_sound()
		return

	var pool: Array[AudioStream] = []
	pool.append_array(bird_chirps)
	pool.append_array(leaf_rustles)

	if pool.is_empty():
		_schedule_next_life_sound()
		return

	var stream: AudioStream = pool[randi() % pool.size()]
	if stream == null:
		_schedule_next_life_sound()
		return

	life_player.pitch_scale = randf_range(0.95, 1.05)
	life_player.volume_db = randf_range(-18.0, -12.0)

	life_player.stream = stream
	life_player.play()

	_schedule_next_life_sound()
