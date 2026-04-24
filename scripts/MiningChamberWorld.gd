extends Node2D
class_name MiningChamberWorld

@export var world_id: String = ""
@export var ground_path: NodePath
@export var mining_objects_path: NodePath
@export var chamber_data: MiningChamberData

# If true, the chamber refreshes the instant the time block changes.
# If false, the chamber waits until the scene reloads / player re-enters.
@export var refresh_immediately_while_loaded: bool = false

# Optional feel / mood hooks
@export var ambient_light_path: NodePath
@export var ambience_player_path: NodePath
@export var active_modulate: Color = Color(1.15, 1.15, 1.25, 1.0)
@export var dormant_modulate: Color = Color(0.82, 0.82, 0.95, 1.0)
@export var low_harmony_energy: float = 0.75
@export var high_harmony_energy: float = 1.15

# Optional SFX
@export var sfx_player_path: NodePath
@export var sfx_hit_active: AudioStream
@export var sfx_hit_dormant: AudioStream
@export var sfx_break_active: AudioStream
@export var sfx_break_dormant: AudioStream

# Optional special SFX. Safe to leave empty for now.
@export var sfx_special_success: AudioStream
@export var sfx_special_miss: AudioStream

@onready var ground: TileMap = get_node_or_null(ground_path) as TileMap
@onready var objects: TileMap = get_node_or_null(mining_objects_path) as TileMap

@onready var ambient_light: CanvasModulate = get_node_or_null(ambient_light_path) as CanvasModulate
@onready var ambience_player: AudioStreamPlayer = get_node_or_null(ambience_player_path) as AudioStreamPlayer
@onready var sfx_player: AudioStreamPlayer2D = (
	get_node_or_null(sfx_player_path) as AudioStreamPlayer2D
	if sfx_player_path != NodePath("")
	else get_node_or_null("SfxPlayer2D") as AudioStreamPlayer2D
)

var destructible_defs := {
	"mining_node": {
		"tool": GameState.ToolType.PICKAXE
	}
}

# cell_key -> {
#   "node_id": String,
#   "state": "active" | "dormant",
#   "hits": int,
#   "broken": bool,
#   "required_direction": Vector2i,
#   "pulse_offset": float
# }
var _nodes_by_cell: Dictionary = {}

var _active_broken_this_cycle: int = 0
var _dormant_broken_this_cycle: int = 0
var _special_success_this_cycle: int = 0
var _special_miss_this_cycle: int = 0

@export var pulse_visual_scene: PackedScene
var _pulse_visuals_by_cell: Dictionary = {}

func _ready() -> void:
	add_to_group("tool_world")

	if chamber_data == null:
		push_warning("MiningChamberWorld: chamber_data is not assigned.")
		return

	if ground == null:
		push_warning("MiningChamberWorld: ground_path not set or invalid.")

	if objects == null:
		push_warning("MiningChamberWorld: mining_objects_path not set or invalid.")
		return

	_ensure_state_exists()
	_refresh_if_needed()
	_apply_room_visual_state()

	if TimeManager != null and TimeManager.has_signal("time_changed"):
		var cb_time := Callable(self, "_on_time_changed")
		if not TimeManager.is_connected("time_changed", cb_time):
			TimeManager.time_changed.connect(cb_time)

	if TimeManager != null and TimeManager.has_signal("day_changed"):
		var cb_day := Callable(self, "_on_day_changed")
		if not TimeManager.is_connected("day_changed", cb_day):
			TimeManager.day_changed.connect(cb_day)

func _exit_tree() -> void:
	_save_runtime_nodes_to_state()

# -------------------------------------------------------------------
# ToolSystem required API
# -------------------------------------------------------------------

func _get_destructible_key_at(cell: Vector2i) -> String:
	var key := GameState.cell_to_key(cell)
	if not _nodes_by_cell.has(key):
		return ""

	var rec: Dictionary = _nodes_by_cell[key]
	if bool(rec.get("broken", false)):
		return ""

	return "mining_node"

func _hit_destructible(cell: Vector2i, _key: String) -> void:
	var key := GameState.cell_to_key(cell)
	if not _nodes_by_cell.has(key):
		return

	var rec: Dictionary = _nodes_by_cell[key]
	if bool(rec.get("broken", false)):
		return

	var node_data := _get_node_data_by_id(String(rec.get("node_id", "")))
	if node_data == null:
		return

	var current_hits := int(rec.get("hits", 0)) + 1
	rec["hits"] = current_hits
	_nodes_by_cell[key] = rec

	var state := String(rec.get("state", "dormant"))
	_play_hit_feedback(cell, state)

	if current_hits < int(node_data.hits_to_break):
		_save_runtime_nodes_to_state()
		return

	rec["broken"] = true
	_nodes_by_cell[key] = rec

	_resolve_node_break(cell, rec, node_data)
	_set_cell_visual(cell, node_data, "depleted")
	_remove_pulse_visual(cell)
	_save_runtime_nodes_to_state()
	_apply_room_visual_state()

# -------------------------------------------------------------------
# Refresh / generation
# -------------------------------------------------------------------

func _on_time_changed(_minutes: int) -> void:
	if chamber_data == null:
		return
	if not chamber_data.refresh_on_time_block_change:
		return

	var st := _get_mining_state()
	var current_block := String(TimeManager.get_time_block_key(TimeManager.minutes))
	var saved_block := String(st.get("last_refresh_block", ""))

	if current_block == saved_block:
		return

	if not refresh_immediately_while_loaded:
		st["pending_refresh_day"] = int(TimeManager.day)
		st["pending_refresh_block"] = current_block
		return

	_generate_new_cycle(current_block)

func _on_day_changed(_day: int) -> void:
	if refresh_immediately_while_loaded:
		_refresh_if_needed()

func _refresh_if_needed() -> void:
	var st := _get_mining_state()
	var current_day := int(TimeManager.day)
	var current_block := String(TimeManager.get_time_block_key(TimeManager.minutes))

	var saved_day := int(st.get("last_refresh_day", -1))
	var saved_block := String(st.get("last_refresh_block", ""))

	if saved_day != current_day or saved_block != current_block:
		_generate_new_cycle(current_block)
	else:
		_load_runtime_nodes_from_state()
		_rebuild_objects_tilemap_from_runtime()

func _generate_new_cycle(block_key: String) -> void:
	if chamber_data == null or objects == null:
		return

	var st := _get_mining_state()

	_nodes_by_cell.clear()
	objects.clear_layer(0)
	_clear_pulse_visuals()

	_active_broken_this_cycle = 0
	_dormant_broken_this_cycle = 0
	_special_success_this_cycle = 0
	_special_miss_this_cycle = 0

	var harmony := int(st.get("harmony", chamber_data.starting_harmony))
	harmony = clampi(harmony, chamber_data.min_harmony, chamber_data.max_harmony)
	st["harmony"] = harmony

	var valid_cells := chamber_data.spawn_cells.duplicate()
	valid_cells.shuffle()

	var spawn_count :Variant= min(chamber_data.get_spawn_count(), valid_cells.size())
	if spawn_count <= 0:
		st["nodes"] = {}
		st["last_refresh_day"] = int(TimeManager.day)
		st["last_refresh_block"] = block_key
		st.erase("pending_refresh_day")
		st.erase("pending_refresh_block")
		return

	var spawned_cells: Array[Vector2i] = []
	for i in range(spawn_count):
		spawned_cells.append(valid_cells[i])

	var active_count := chamber_data.get_active_count_for_harmony(harmony, spawned_cells.size())
	var active_indices := _pick_random_indices(spawned_cells.size(), active_count)

	for i in range(spawned_cells.size()):
		var cell := spawned_cells[i]
		var node_data := _pick_node_data()
		if node_data == null:
			continue

		var cell_key := GameState.cell_to_key(cell)
		var state := "active" if active_indices.has(i) else "dormant"

		var rec := {
			"node_id": node_data.node_id,
			"state": state,
			"hits": 0,
			"broken": false,
			"required_direction": Vector2i.ZERO,
			"pulse_offset": randf()
		}

		if state == "active" and node_data.mechanic_type == MiningNodeData.MechanicType.DIRECTIONAL:
			rec["required_direction"] = node_data.pick_required_direction()

		_nodes_by_cell[cell_key] = rec
		_set_cell_visual(cell, node_data, state, Vector2i(rec.get("required_direction", Vector2i.ZERO)))
		_maybe_spawn_pulse_visual(cell, node_data, rec)

	st["nodes"] = _nodes_by_cell.duplicate(true)
	st["last_refresh_day"] = int(TimeManager.day)
	st["last_refresh_block"] = block_key
	st.erase("pending_refresh_day")
	st.erase("pending_refresh_block")

	_apply_room_visual_state()

func _pick_node_data() -> MiningNodeData:
	if chamber_data == null:
		return null
	if chamber_data.node_pool.is_empty():
		return null

	var idx := randi_range(0, chamber_data.node_pool.size() - 1)
	return chamber_data.node_pool[idx]

func _pick_random_indices(total_count: int, wanted_count: int) -> Array[int]:
	var indices: Array[int] = []
	for i in range(total_count):
		indices.append(i)

	indices.shuffle()
	wanted_count = clampi(wanted_count, 0, total_count)

	var picked: Array[int] = []
	for i in range(wanted_count):
		picked.append(indices[i])

	return picked

# -------------------------------------------------------------------
# Break / rewards / harmony
# -------------------------------------------------------------------

func _resolve_node_break(cell: Vector2i, rec: Dictionary, node_data: MiningNodeData) -> void:
	var state := String(rec.get("state", "dormant"))
	var harmony_before := get_chamber_harmony()

	if state != "active":
		_dormant_broken_this_cycle += 1
		_give_dormant_rewards(node_data)
		_change_harmony(int(node_data.harmony_on_dormant_break))
		_play_break_feedback(cell, "dormant")
		_maybe_emit_feedback_toast("dormant", node_data)
		return

	var special_success := _is_special_node_success(cell, rec, node_data)

	if special_success:
		_active_broken_this_cycle += 1
		if node_data.mechanic_type != MiningNodeData.MechanicType.BASIC:
			_special_success_this_cycle += 1

		_give_active_rewards(node_data, harmony_before)
		_change_harmony(int(node_data.harmony_on_active_break))
		_maybe_grant_cycle_bonus()
		_play_break_feedback(cell, "active")
		_play_special_feedback(cell, true)
		_maybe_emit_feedback_toast("active", node_data)
	else:
		# This is a gentle miss, not a hard failure.
		# The node still breaks and gives a modest reward.
		_special_miss_this_cycle += 1
		_dormant_broken_this_cycle += 1

		_give_dormant_rewards(node_data)
		_change_harmony(int(node_data.harmony_on_special_miss))
		_play_break_feedback(cell, "dormant")
		_play_special_feedback(cell, false)
		_maybe_emit_feedback_toast("special_miss", node_data)

func _is_special_node_success(cell: Vector2i, rec: Dictionary, node_data: MiningNodeData) -> bool:
	match node_data.mechanic_type:
		MiningNodeData.MechanicType.BASIC:
			return true

		MiningNodeData.MechanicType.DIRECTIONAL:
			return _check_directional_success(rec)

		MiningNodeData.MechanicType.PULSE:
			return _check_pulse_success(rec, node_data)

		_:
			return true

func _check_directional_success(rec: Dictionary) -> bool:
	var required := Vector2i(rec.get("required_direction", Vector2i.ZERO))
	if required == Vector2i.ZERO:
		return true

	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return false

	if not ("facing" in p):
		return false

	var f: Vector2 = p.facing
	var facing_i := Vector2i(int(round(f.x)), int(round(f.y)))

	return facing_i == required

func _check_pulse_success(rec: Dictionary, node_data: MiningNodeData) -> bool:
	var period :Variant= max(0.2, float(node_data.pulse_period_seconds))
	var offset := float(rec.get("pulse_offset", 0.0))

	var now := Time.get_ticks_msec() / 1000.0
	var phase := fmod((now / period) + offset, 1.0)

	# Brightest point is treated as phase 0.5.
	var distance_from_peak :Variant= abs(phase - 0.5)

	return distance_from_peak <= float(node_data.pulse_success_window)

func _give_dormant_rewards(node_data: MiningNodeData) -> void:
	var drop := node_data.roll_dormant_drop()
	var item_id := String(drop.get("item_id", ""))
	var qty := int(drop.get("qty", 0))

	if item_id != "" and qty > 0:
		GameState.inventory_add(item_id, qty)

func _give_active_rewards(node_data: MiningNodeData, harmony: int) -> void:
	var drops := node_data.roll_active_drops(harmony)
	for d_any in drops:
		var d := d_any as Dictionary
		var item_id := String(d.get("item_id", ""))
		var qty := int(d.get("qty", 0))
		if item_id != "" and qty > 0:
			GameState.inventory_add(item_id, qty)

func _maybe_grant_cycle_bonus() -> void:
	if chamber_data == null:
		return
	if chamber_data.bonus_drop_item.strip_edges() == "":
		return

	var total_broken := _active_broken_this_cycle + _dormant_broken_this_cycle
	if total_broken <= 0:
		return

	if _active_broken_this_cycle < 2:
		return
	if _dormant_broken_this_cycle > _active_broken_this_cycle:
		return

	var harmony := get_chamber_harmony()
	var chance := chamber_data.get_bonus_drop_chance_for_harmony(harmony)

	if randf() <= chance:
		var drop := chamber_data.roll_bonus_drop()
		var item_id := String(drop.get("item_id", ""))
		var qty := int(drop.get("qty", 0))
		if item_id != "" and qty > 0:
			GameState.inventory_add(item_id, qty)

func _change_harmony(delta: int) -> void:
	var st := _get_mining_state()
	var harmony := int(st.get("harmony", chamber_data.starting_harmony))
	harmony += delta
	harmony = clampi(harmony, chamber_data.min_harmony, chamber_data.max_harmony)
	st["harmony"] = harmony

func get_chamber_harmony() -> int:
	var st := _get_mining_state()
	return int(st.get("harmony", chamber_data.starting_harmony))

# -------------------------------------------------------------------
# Persistence helpers
# -------------------------------------------------------------------

func _ensure_state_exists() -> void:
	var st := _get_mining_state()
	if not st.has("harmony"):
		st["harmony"] = chamber_data.starting_harmony if chamber_data != null else 50
	if not st.has("last_refresh_day"):
		st["last_refresh_day"] = -1
	if not st.has("last_refresh_block"):
		st["last_refresh_block"] = ""
	if not st.has("nodes"):
		st["nodes"] = {}

func _get_map_state() -> Dictionary:
	return GameState.get_map_state(_state_key())

func _get_mining_state() -> Dictionary:
	var map := _get_map_state()
	if not map.has("mining"):
		map["mining"] = {}
	return map["mining"]

func _load_runtime_nodes_from_state() -> void:
	var st := _get_mining_state()
	_nodes_by_cell = Dictionary(st.get("nodes", {})).duplicate(true)

func _save_runtime_nodes_to_state() -> void:
	var st := _get_mining_state()
	st["nodes"] = _nodes_by_cell.duplicate(true)

func _rebuild_objects_tilemap_from_runtime() -> void:
	if objects == null:
		return

	objects.clear_layer(0)
	_clear_pulse_visuals()

	for cell_key_any in _nodes_by_cell.keys():
		var cell_key := String(cell_key_any)
		var rec: Dictionary = _nodes_by_cell[cell_key]
		if bool(rec.get("broken", false)):
			continue

		var node_data := _get_node_data_by_id(String(rec.get("node_id", "")))
		if node_data == null:
			continue

		var cell := GameState.key_to_cell(cell_key)
		var state := String(rec.get("state", "dormant"))
		var required_direction := Vector2i(rec.get("required_direction", Vector2i.ZERO))

		_set_cell_visual(cell, node_data, state, required_direction)
		_maybe_spawn_pulse_visual(cell, node_data, rec)

func _state_key() -> String:
	if world_id.strip_edges() != "":
		return world_id

	var s := get_tree().current_scene
	return s.name if s != null else "MiningWorld"

# -------------------------------------------------------------------
# Visuals / mood
# -------------------------------------------------------------------

func _set_cell_visual(
	cell: Vector2i,
	node_data: MiningNodeData,
	state: String,
	required_direction: Vector2i = Vector2i.ZERO
) -> void:
	if objects == null or node_data == null:
		return

	var tile_def := node_data.get_tile_for_state(state, required_direction)
	var src := int(tile_def.get("source_id", -1))
	var atlas := Vector2i(tile_def.get("atlas", Vector2i.ZERO))

	if src >= 0:
		objects.set_cell(0, cell, src, atlas)
	else:
		objects.erase_cell(0, cell)

func _apply_room_visual_state() -> void:
	if chamber_data == null:
		return

	var harmony := get_chamber_harmony()
	var t := inverse_lerp(float(chamber_data.min_harmony), float(chamber_data.max_harmony), float(harmony))

	if ambience_player != null:
		ambience_player.volume_db = lerpf(-7.0, -2.0, t)
		ambience_player.pitch_scale = lerpf(low_harmony_energy, high_harmony_energy, t)

	if ambient_light != null:
		ambient_light.color = dormant_modulate.lerp(active_modulate, t)

func _play_hit_feedback(cell: Vector2i, state: String) -> void:
	if sfx_player != null:
		var stream: AudioStream = sfx_hit_active if state == "active" else sfx_hit_dormant
		if stream != null:
			sfx_player.global_position = _cell_to_world_center(cell)
			sfx_player.pitch_scale = randf_range(0.97, 1.03)
			sfx_player.stream = stream
			sfx_player.play()

	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("camera_shake"):
		if state == "active":
			p.camera_shake(320.0, 0.14, 36.0, 9.0)
		else:
			p.camera_shake(220.0, 0.10, 28.0, 9.0)

func _play_break_feedback(cell: Vector2i, state: String) -> void:
	if sfx_player != null:
		var stream: AudioStream = sfx_break_active if state == "active" else sfx_break_dormant
		if stream != null:
			sfx_player.global_position = _cell_to_world_center(cell)
			sfx_player.pitch_scale = 1.0
			sfx_player.stream = stream
			sfx_player.play()

func _play_special_feedback(cell: Vector2i, success: bool) -> void:
	if sfx_player == null:
		return

	var stream: AudioStream = sfx_special_success if success else sfx_special_miss
	if stream == null:
		return

	sfx_player.global_position = _cell_to_world_center(cell)
	sfx_player.pitch_scale = 1.0 if success else 0.92
	sfx_player.stream = stream
	sfx_player.play()

func _maybe_emit_feedback_toast(result: String, node_data: MiningNodeData) -> void:
	if QuestEvents == null or not QuestEvents.has_signal("toast_requested"):
		return

	match result:
		"active":
			if node_data.mechanic_type == MiningNodeData.MechanicType.DIRECTIONAL:
				QuestEvents.toast_requested.emit("The vein opens cleanly.", "success", 1.5)
			elif node_data.mechanic_type == MiningNodeData.MechanicType.PULSE:
				QuestEvents.toast_requested.emit("You met the stone’s breath.", "success", 1.5)
			else:
				QuestEvents.toast_requested.emit("The chamber answers warmly.", "success", 1.5)

		"dormant":
			QuestEvents.toast_requested.emit("Only a faint answer returns.", "info", 1.5)

		"special_miss":
			if node_data.mechanic_type == MiningNodeData.MechanicType.DIRECTIONAL:
				QuestEvents.toast_requested.emit("The vein resists the angle.", "info", 1.5)
			elif node_data.mechanic_type == MiningNodeData.MechanicType.PULSE:
				QuestEvents.toast_requested.emit("The glow slips past your strike.", "info", 1.5)
			else:
				QuestEvents.toast_requested.emit("Only a faint answer returns.", "info", 1.5)

func _cell_to_world_center(cell: Vector2i) -> Vector2:
	if objects != null:
		return objects.to_global(objects.map_to_local(cell))

	if ground != null:
		return ground.to_global(ground.map_to_local(cell))

	return global_position

func _get_node_data_by_id(node_id: String) -> MiningNodeData:
	if chamber_data == null:
		return null

	for nd in chamber_data.node_pool:
		if nd != null and nd.node_id == node_id:
			return nd

	return null

# -------------------------------------------------------------------
# ToolSystem compatibility no-ops
# -------------------------------------------------------------------

func water_cell(_cell: Vector2i) -> void:
	return

func _is_crop_harvestable(_cell: Vector2i) -> bool:
	return false

func _harvest_crop(_cell: Vector2i) -> void:
	return

func _can_till_ground(_cell: Vector2i) -> bool:
	return false

func _try_till_ground(_cell: Vector2i) -> void:
	return

func _clear_pulse_visuals() -> void:
	for key in _pulse_visuals_by_cell.keys():
		var v: Node = _pulse_visuals_by_cell[key]
		if is_instance_valid(v):
			v.queue_free()

	_pulse_visuals_by_cell.clear()

func _remove_pulse_visual(cell: Vector2i) -> void:
	var key := GameState.cell_to_key(cell)

	if not _pulse_visuals_by_cell.has(key):
		return

	var v: Node = _pulse_visuals_by_cell[key]
	if is_instance_valid(v):
		v.queue_free()

	_pulse_visuals_by_cell.erase(key)

func _maybe_spawn_pulse_visual(cell: Vector2i, node_data: MiningNodeData, rec: Dictionary) -> void:
	if pulse_visual_scene == null:
		return

	if node_data == null:
		return

	if node_data.mechanic_type != MiningNodeData.MechanicType.PULSE:
		return

	if String(rec.get("state", "dormant")) != "active":
		return

	if bool(rec.get("broken", false)):
		return

	var key := GameState.cell_to_key(cell)

	# Avoid duplicates if rebuilding the TileMap.
	if _pulse_visuals_by_cell.has(key):
		var existing: Node = _pulse_visuals_by_cell[key]
		if is_instance_valid(existing):
			return

	var v := pulse_visual_scene.instantiate()
	add_child(v)

	if v is Node2D:
		(v as Node2D).global_position = _cell_to_world_center(cell)

	var offset := float(rec.get("pulse_offset", 0.0))

	if v.has_method("setup"):
		v.call("setup", float(node_data.pulse_period_seconds), offset)

	_pulse_visuals_by_cell[key] = v
