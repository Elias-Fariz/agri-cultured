# res://autoloads/FestivalManager.gd
extends Node

signal festival_changed(current_festival_id: String)
signal festival_day_started(festival_id: String)
signal festival_day_tomorrow(festival_id: String)

@export var festivals: Array[FestivalData] = []

var _current_festival: FestivalData = null

func _ready() -> void:
	print("[FestivalManager] Ready. festivals loaded = ", festivals.size())

	if TimeManager != null and TimeManager.has_signal("day_changed"):
		TimeManager.day_changed.connect(_on_day_changed)
		print("[FestivalManager] Connected to TimeManager.day_changed")
	else:
		print("[FestivalManager] WARNING: TimeManager.day_changed not found")

	_recompute_for_today(true)

# -------------------------------------------------------------------
# Day change handling
# -------------------------------------------------------------------

func _on_day_changed(_day: int) -> void:
	print("[FestivalManager] Day changed -> recomputing festival state")
	_recompute_for_today(false)

func _recompute_for_today(is_bootstrap: bool) -> void:
	var old_id := ""
	if _current_festival != null:
		old_id = _current_festival.festival_id

	_current_festival = get_today_festival()

	var new_id := ""
	if _current_festival != null:
		new_id = _current_festival.festival_id

	print("[FestivalManager] Today = season ", _get_current_season(), ", day_in_season ", _get_current_day_in_season())
	print("[FestivalManager] Current festival today = ", new_id if new_id != "" else "<none>")

	if old_id != new_id:
		festival_changed.emit(new_id)

	# Festival today
	if not is_bootstrap and _current_festival != null:
		if _current_festival.day_of_toast.strip_edges() != "":
			print("[FestivalManager] Queueing day-of festival toast: ", _current_festival.day_of_toast)
			if GameState != null and GameState.has_method("queue_day_start_toast"):
				GameState.queue_day_start_toast(_current_festival.day_of_toast, "info", 3.0)
			else:
				print("[FestivalManager] WARNING: GameState.queue_day_start_toast not found")
			festival_day_started.emit(_current_festival.festival_id)

	# Festival tomorrow
	if not is_bootstrap:
		var tomorrow_festival := get_tomorrow_festival()
		if tomorrow_festival != null:
			print("[FestivalManager] Festival tomorrow = ", tomorrow_festival.festival_id)
			if tomorrow_festival.day_before_toast.strip_edges() != "":
				print("[FestivalManager] Queueing day-before festival toast: ", tomorrow_festival.day_before_toast)
				if GameState != null and GameState.has_method("queue_day_start_toast"):
					GameState.queue_day_start_toast(tomorrow_festival.day_before_toast, "info", 3.0)
				else:
					print("[FestivalManager] WARNING: GameState.queue_day_start_toast not found")
				festival_day_tomorrow.emit(tomorrow_festival.festival_id)
		else:
			print("[FestivalManager] No festival tomorrow")

# -------------------------------------------------------------------
# Festival lookup
# -------------------------------------------------------------------

func get_today_festival() -> FestivalData:
	var season := _get_current_season()
	var day_in_season := _get_current_day_in_season()

	for f in festivals:
		if f == null:
			continue
		if not f.is_valid():
			continue
		if int(f.season) != season:
			continue
		if int(f.day_in_season) != day_in_season:
			continue
		return f

	return null

func get_tomorrow_festival() -> FestivalData:
	var today_total_day := _get_total_day()
	var tomorrow_total_day := today_total_day + 1

	var tomorrow_season := _get_season_for_total_day(tomorrow_total_day)
	var tomorrow_day_in_season := _get_day_in_season_for_total_day(tomorrow_total_day)

	for f in festivals:
		if f == null:
			continue
		if not f.is_valid():
			continue
		if int(f.season) != tomorrow_season:
			continue
		if int(f.day_in_season) != tomorrow_day_in_season:
			continue
		return f

	return null

func is_festival_today() -> bool:
	return _current_festival != null

func get_current_festival_id() -> String:
	if _current_festival == null:
		return ""
	return _current_festival.festival_id

# -------------------------------------------------------------------
# NPC helper queries
# -------------------------------------------------------------------

func has_npc_override(npc_id: String) -> bool:
	if _current_festival == null:
		return false

	for placement in _current_festival.npc_placements:
		if placement == null:
			continue
		if placement.npc_id == npc_id:
			return true

	return false

func get_npc_placement(npc_id: String) -> FestivalNpcPlacement:
	if _current_festival == null:
		return null

	for placement in _current_festival.npc_placements:
		if placement == null:
			continue
		if placement.npc_id == npc_id:
			return placement

	return null

func get_npc_festival_position(npc_id: String) -> Vector2:
	var placement := get_npc_placement(npc_id)
	if placement == null:
		return Vector2.ZERO
	return placement.target_position

func get_npc_festival_dialogue(npc_id: String) -> Array[String]:
	var placement := get_npc_placement(npc_id)
	if placement == null:
		return []

	if not placement.use_festival_dialogue:
		return []

	var out: Array[String] = []
	for line in placement.festival_dialogue_lines:
		out.append(String(line))
	return out

# -------------------------------------------------------------------
# Decoration helper queries
# -------------------------------------------------------------------

func should_show_decoration_node(node_name: String) -> bool:
	if _current_festival == null:
		return false

	for n in _current_festival.decoration_node_names:
		if String(n) == node_name:
			return true

	return false

func get_active_decoration_node_names() -> PackedStringArray:
	if _current_festival == null:
		return PackedStringArray()
	return _current_festival.decoration_node_names

# -------------------------------------------------------------------
# Calendar helper math
# -------------------------------------------------------------------

func _get_current_season() -> int:
	if CalendarSystem != null and CalendarSystem.has_method("get_season"):
		return int(CalendarSystem.get_season())
	return 0

func _get_current_day_in_season() -> int:
	if CalendarSystem != null and CalendarSystem.has_method("get_day_in_season"):
		return int(CalendarSystem.get_day_in_season())
	return 1

func _get_total_day() -> int:
	if TimeManager == null:
		return 1
	return int(TimeManager.day)

func _get_season_for_total_day(total_day: int) -> int:
	if CalendarSystem == null:
		return 0

	var day_index :Variant= max(0, total_day - 1)
	var cycle_len := int(CalendarSystem.days_per_season) * 2
	var in_cycle :Variant= day_index % cycle_len

	return 0 if in_cycle < int(CalendarSystem.days_per_season) else 1

func _get_day_in_season_for_total_day(total_day: int) -> int:
	if CalendarSystem == null:
		return 1

	var day_index :Variant= max(0, total_day - 1)
	var cycle_len := int(CalendarSystem.days_per_season) * 2
	var in_cycle :Variant= day_index % cycle_len

	if in_cycle >= int(CalendarSystem.days_per_season):
		in_cycle -= int(CalendarSystem.days_per_season)

	return in_cycle + 1
