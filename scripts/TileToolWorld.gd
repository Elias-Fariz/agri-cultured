# res://world/TileToolWorld.gd
extends Node2D
class_name TileToolWorld

# This node is a reusable "tool provider" for scenes that use TileMaps.
# It plugs into ToolSystem by providing:
# - ground, objects TileMap references
# - destructible_defs + destructible_hits persistence
# - _get_destructible_key_at() and _hit_destructible()
#
# Everything else (watering/tilling/harvesting) is safely disabled for now.

@export var world_id: String = ""  # e.g. "Forest". If empty, we use the scene name.

@export var ground_path: NodePath
@export var objects_path: NodePath

@export var objects_layer: int = 0
@export var ground_layer: int = 0

# Optional SFX + feel (can leave empty)
@export var sfx_player_path: NodePath
@export var sfx_hit_tree: AudioStream
@export var sfx_hit_rock: AudioStream

# --- Ground / watering config (kept for later; safe if unused) ---
@export var ground_source_id: int = 0
@export var tilled_coords: Vector2i = Vector2i(1, 0)
@export var wet_tilled_coords: Vector2i = Vector2i(2, 0)

# --- Regrowth config (beta-friendly) ---
@export var tree_regrow_days: int = 3
@export var rock_regrow_days: int = 2

# Optional placeholder tiles shown while regrowing.
# If source_id is -1, the destructible will simply be absent until it regrows.
@export var tree_regrow_source_id: int = -1
@export var tree_regrow_atlas: Vector2i = Vector2i.ZERO

@export var rock_regrow_source_id: int = -1
@export var rock_regrow_atlas: Vector2i = Vector2i.ZERO

# --- Default destructibles (matches your current setup) ---
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

var destructible_hits: Dictionary = {} # { Vector2i: int }

@onready var ground: TileMap = get_node_or_null(ground_path) as TileMap
@onready var objects: TileMap = get_node_or_null(objects_path) as TileMap
@onready var sfx_player: AudioStreamPlayer2D = (
	get_node_or_null(sfx_player_path) as AudioStreamPlayer2D
	if sfx_player_path != NodePath("")
	else get_node_or_null("SfxPlayer2D") as AudioStreamPlayer2D
)

func _ready() -> void:
	if ground == null:
		push_warning("TileToolWorld: ground_path not set or invalid.")
	if objects == null:
		push_warning("TileToolWorld: objects_path not set or invalid.")
		return

	_load_state()
	_refresh_destructible_regrowth_tiles()

	if TimeManager != null and TimeManager.has_signal("day_changed"):
		var cb := Callable(self, "_on_day_changed")
		if not TimeManager.is_connected("day_changed", cb):
			TimeManager.day_changed.connect(cb)

func _exit_tree() -> void:
	_save_state()

# -------------------------------------------------------------------
# ToolSystem required API (destructibles)
# -------------------------------------------------------------------

func _get_destructible_key_at(cell: Vector2i) -> String:
	if objects == null:
		return ""

	var src := objects.get_cell_source_id(objects_layer, cell)
	if src == -1:
		return ""

	var atlas := objects.get_cell_atlas_coords(objects_layer, cell)

	for key in destructible_defs.keys():
		var def: Dictionary = destructible_defs[key]
		if int(def["source_id"]) == src and Vector2i(def["atlas"]) == atlas:
			return String(key)

	return ""

func _hit_destructible(cell: Vector2i, key: String) -> void:
	if objects == null:
		return
	if not destructible_defs.has(key):
		return

	var def: Dictionary = destructible_defs[key]
	var needed: int = int(def.get("hits", 1))

	var current := int(destructible_hits.get(cell, 0)) + 1
	destructible_hits[cell] = current

	# Optional feedback
	_play_hit_feedback(cell, key)

	if current >= needed:
		destructible_hits.erase(cell)

		var drop := String(def.get("drop", ""))
		if drop != "":
			GameState.inventory_add(drop, 1)

		match key:
			"tree":
				GameState.report_action("chop_tree", 1)
			"rock":
				GameState.report_action("break_rock", 1)
			_:
				GameState.report_action("break_object", 1)

		_begin_destructible_regrowth(cell, key)

# -------------------------------------------------------------------
# Regrowth
# -------------------------------------------------------------------

func _begin_destructible_regrowth(cell: Vector2i, key: String) -> void:
	var today := int(TimeManager.day)
	var respawn_day := today + _get_regrow_days(key)

	var spot_id := _make_regrowth_spot_id(cell)

	GameState.mark_destructible_regrowing(
		spot_id,
		key,
		_state_key(),
		String(objects_path),
		cell,
		respawn_day,
		today # show regrowth placeholder immediately, if configured
	)

	var regrow_tile := _get_regrow_tile_def(key)
	var regrow_src := int(regrow_tile.get("source_id", -1))
	var regrow_atlas := Vector2i(regrow_tile.get("atlas", Vector2i.ZERO))

	if regrow_src >= 0:
		objects.set_cell(objects_layer, cell, regrow_src, regrow_atlas)
	else:
		objects.erase_cell(objects_layer, cell)

func _refresh_destructible_regrowth_tiles() -> void:
	if objects == null:
		return

	var today := int(TimeManager.day)
	var records := GameState.get_destructible_regrowth_records_for_world(_state_key(), String(objects_path))

	for spot_id in records.keys():
		var rec: Dictionary = records[spot_id]

		var cell: Vector2i = rec.get("cell", Vector2i.ZERO)
		var key := String(rec.get("kind", ""))

		if key == "":
			continue

		var stage := GameState.get_regrowth_stage_for_day(spot_id, today)

		match stage:
			"empty":
				objects.erase_cell(objects_layer, cell)

			"regrowing":
				var regrow_tile := _get_regrow_tile_def(key)
				var regrow_src := int(regrow_tile.get("source_id", -1))
				var regrow_atlas := Vector2i(regrow_tile.get("atlas", Vector2i.ZERO))

				if regrow_src >= 0:
					objects.set_cell(objects_layer, cell, regrow_src, regrow_atlas)
				else:
					objects.erase_cell(objects_layer, cell)

			"grown":
				_restore_mature_destructible_tile(cell, key)
				GameState.clear_destructible_regrowth_record(spot_id)

func _restore_mature_destructible_tile(cell: Vector2i, key: String) -> void:
	if not destructible_defs.has(key):
		return

	var def: Dictionary = destructible_defs[key]
	var src := int(def.get("source_id", -1))
	var atlas := Vector2i(def.get("atlas", Vector2i.ZERO))

	if src >= 0:
		objects.set_cell(objects_layer, cell, src, atlas)

func _make_regrowth_spot_id(cell: Vector2i) -> String:
	return GameState.make_destructible_spot_id(_state_key(), String(objects_path), cell)

func _get_regrow_days(key: String) -> int:
	match key:
		"tree":
			return max(1, tree_regrow_days)
		"rock":
			return max(1, rock_regrow_days)
		_:
			return 3

func _get_regrow_tile_def(key: String) -> Dictionary:
	match key:
		"tree":
			return {
				"source_id": tree_regrow_source_id,
				"atlas": tree_regrow_atlas
			}
		"rock":
			return {
				"source_id": rock_regrow_source_id,
				"atlas": rock_regrow_atlas
			}
		_:
			return {
				"source_id": -1,
				"atlas": Vector2i.ZERO
			}

func _on_day_changed(_day: int) -> void:
	_refresh_destructible_regrowth_tiles()

# -------------------------------------------------------------------
# ToolSystem compatibility methods (disabled for Forest for now)
# These exist so ToolSystem can call them without needing farm/crop logic.
# -------------------------------------------------------------------

func water_cell(_cell: Vector2i) -> void:
	# Forest: no watering
	return

func _is_crop_harvestable(_cell: Vector2i) -> bool:
	return false

func _harvest_crop(_cell: Vector2i) -> void:
	return

func _can_till_ground(_cell: Vector2i) -> bool:
	return false

func _try_till_ground(_cell: Vector2i) -> void:
	return

# -------------------------------------------------------------------
# Persistence (objects tiles + partial hits)
# -------------------------------------------------------------------

func _state_key() -> String:
	if world_id != "":
		return world_id
	# fallback: scene name
	var s := get_tree().current_scene
	return s.name if s != null else "World"

func _load_state() -> void:
	if objects == null:
		return

	var map := GameState.get_map_state(_state_key())

	# First run: capture the painted objects as baseline
	if not bool(map.get("has_initialized", false)):
		map["objects"] = {}
		_save_tilemap_non_default(objects, map["objects"])
		map["hits"] = {}
		map["has_initialized"] = true
		destructible_hits.clear()
		return

	# Restore objects from saved state
	objects.clear_layer(objects_layer)
	_load_tilemap_from_dict(objects, map.get("objects", {}))

	# Restore hits
	destructible_hits.clear()
	var hits: Dictionary = map.get("hits", {})
	for key in hits.keys():
		var cell := GameState.key_to_cell(key)
		destructible_hits[cell] = int(hits[key])

func _save_state() -> void:
	if objects == null:
		return

	var map := GameState.get_map_state(_state_key())

	map["objects"] = {}
	_save_tilemap_non_default(objects, map["objects"])

	map["hits"] = {}
	for cell in destructible_hits.keys():
		map["hits"][GameState.cell_to_key(cell)] = int(destructible_hits[cell])

func _save_tilemap_non_default(tilemap: TileMap, out_dict: Dictionary) -> void:
	var used_cells := tilemap.get_used_cells(objects_layer)
	for cell in used_cells:
		var src := tilemap.get_cell_source_id(objects_layer, cell)
		if src == -1:
			continue
		var atlas := tilemap.get_cell_atlas_coords(objects_layer, cell)
		out_dict[GameState.cell_to_key(cell)] = { "src": src, "atlas": atlas }

func _load_tilemap_from_dict(tilemap: TileMap, data: Dictionary) -> void:
	for key in data.keys():
		var cell := GameState.key_to_cell(key)
		var entry: Dictionary = data[key]
		var src := int(entry["src"])
		var atlas := Vector2i(entry["atlas"])
		tilemap.set_cell(objects_layer, cell, src, atlas)

func _play_hit_feedback(cell: Vector2i, key: String) -> void:
	# play SFX if configured
	if sfx_player != null:
		var stream: AudioStream = null
		if key == "tree":
			stream = sfx_hit_tree
		elif key == "rock":
			stream = sfx_hit_rock

		if stream != null:
			sfx_player.pitch_scale = randf_range(0.95, 1.05)
			sfx_player.global_position = _cell_to_world_center(cell)
			sfx_player.stream = stream
			sfx_player.play()

	# camera shake if player exists and supports it
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("camera_shake"):
		if key == "tree":
			p.camera_shake(200.0, 0.12, 32.0, 10.0)
		elif key == "rock":
			p.camera_shake(300.0, 0.16, 35.0, 9.0)

func _cell_to_world_center(cell: Vector2i) -> Vector2:
	if ground != null:
		var tile_size: Vector2 = Vector2(ground.tile_set.tile_size)
		return ground.to_global(ground.map_to_local(cell) + tile_size * 0.5)
	if objects != null:
		var tile_size2: Vector2 = Vector2(objects.tile_set.tile_size)
		return objects.to_global(objects.map_to_local(cell) + tile_size2 * 0.5)
	return global_position
