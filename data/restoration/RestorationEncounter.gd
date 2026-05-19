extends Node2D
class_name RestorationEncounter

enum BoundaryMode {
	RETREAT_ON_EXIT,
	PUSH_BACK_ON_EXIT,
	IGNORE_EXIT
}

@export var boundary_mode: BoundaryMode = BoundaryMode.RETREAT_ON_EXIT

# Used only when boundary_mode = PUSH_BACK_ON_EXIT.
@export var boundary_pushback_distance: float = 56.0
@export var boundary_pushback_toast: String = "The roots hold the clearing shut."
@export var boundary_pushback_cooldown: float = 0.6

var _pushback_locked: bool = false

@export var encounter_data: RestorationEncounterData

@export var core_path: NodePath
@export var trigger_area_path: NodePath
@export var danger_container_path: NodePath
@export var reward_spawn_path: NodePath

# Where to place the player on failure, optional.
@export var fail_exit_marker_path: NodePath

# Begin automatically when player enters trigger.
@export var auto_start_on_trigger: bool = true

# If true, leaving TriggerArea during combat counts as retreat/failure.
@export var trigger_area_is_combat_boundary: bool = true

# Temporary debug feedback. Turn this off later when you build real UI.
@export var show_debug_toasts: bool = true
@export var print_debug: bool = true

@export var boundary_visual_path: NodePath

@export var instability_bar_path: NodePath

@export var hit_sparkle_scene: PackedScene
@export var hit_sparkle_lifetime: float = 0.6
@export var hit_sparkle_scale: float = 2.0

@onready var core: DisturbanceCore = get_node_or_null(core_path) as DisturbanceCore
@onready var trigger_area: Area2D = get_node_or_null(trigger_area_path) as Area2D
@onready var danger_container: Node2D = get_node_or_null(danger_container_path) as Node2D
@onready var reward_spawn: Node2D = get_node_or_null(reward_spawn_path) as Node2D
@onready var fail_exit_marker: Node2D = get_node_or_null(fail_exit_marker_path) as Node2D
@onready var boundary_visual: CanvasItem = get_node_or_null(boundary_visual_path) as CanvasItem
@onready var instability_bar: RestorationInstabilityBar = get_node_or_null(instability_bar_path) as RestorationInstabilityBar

var _active: bool = false
var _resolve: int = 0
var _max_resolve_this_encounter: int = 0
var _instability: int = 0
var _hit_registered_this_opening: bool = false
var _player: Node2D = null
var _ending: bool = false

var _food_first_hit_shield_active: bool = false

func _ready() -> void:
	add_to_group("restoration_encounter")

	if encounter_data == null:
		push_warning("RestorationEncounter: encounter_data is not assigned.")
		return

	if core == null:
		push_warning("RestorationEncounter: core_path is not assigned or invalid.")
		return

	if not core.restoration_hit.is_connected(_on_core_restoration_hit):
		core.restoration_hit.connect(_on_core_restoration_hit)

	if trigger_area != null:
		if auto_start_on_trigger and not trigger_area.body_entered.is_connected(_on_trigger_body_entered):
			trigger_area.body_entered.connect(_on_trigger_body_entered)

		if trigger_area_is_combat_boundary and not trigger_area.body_exited.is_connected(_on_trigger_body_exited):
			trigger_area.body_exited.connect(_on_trigger_body_exited)
	else:
		push_warning("RestorationEncounter: trigger_area_path is not assigned or invalid.")

	_apply_restored_state_if_needed()
	
	_set_boundary_visible(false)

	if print_debug:
		print("[RestorationEncounter] Ready: ", encounter_data.encounter_id, " patterns=", encounter_data.patterns.size())

func is_encounter_active() -> bool:
	return _active

func start_encounter() -> void:
	if encounter_data == null or core == null:
		return

	if _active or _ending:
		return

	if _is_currently_restored():
		_debug_toast("This site is already calm.", "info", 1.5)
		return

	_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		push_warning("RestorationEncounter: No player found in group 'player'.")
		return

	_active = true
	_ending = false
	_set_boundary_visible(true)

	_max_resolve_this_encounter = _get_starting_resolve()
	_resolve = _max_resolve_this_encounter
	_instability = _get_starting_instability()

	_apply_combat_food_buffs_on_start()

	_show_player_resolve_ui()
	_show_instability_bar()

	if encounter_data.pause_time_during_encounter and TimeManager != null and TimeManager.has_method("enter_timeless_zone"):
		TimeManager.enter_timeless_zone()

	_debug_toast("The disturbance stirs. Resolve: %d/%d" % [_resolve, _get_current_max_resolve()], "warning", 1.7)

	if print_debug:
		print("[RestorationEncounter] Started. Resolve=", _resolve, " Instability=", _instability, " Patterns=", encounter_data.patterns.size())

	call_deferred("_run_encounter_loop")

func fail_encounter(reason: String = "overwhelmed") -> void:
	if _ending:
		return

	if not _active:
		return

	_ending = true
	_active = false
	_food_first_hit_shield_active = false
	
	_clear_danger_zones()
	_set_boundary_visible(false)
	_hide_instability_bar()
	_hide_player_resolve_ui()
	#_hide_restoration_ui()

	if core != null:
		core.set_vulnerable(false)

	_record_failure()

	if encounter_data != null and encounter_data.failure_energy_loss > 0:
		GameState.energy = max(0, int(GameState.energy) - int(encounter_data.failure_energy_loss))
		if GameState.energy <= 0:
			GameState.exhausted = true

	var fade := _get_restoration_fade_overlay()

	if fade != null and fade.has_method("fade_out_in"):
		var fade_call = fade.call("fade_out_in", 0.22, 0.12, 0.32)

		await get_tree().create_timer(0.22).timeout

		if fail_exit_marker != null and _player != null:
			_player.global_position = fail_exit_marker.global_position

		await fade_call
	else:
		if fail_exit_marker != null and _player != null:
			_player.global_position = fail_exit_marker.global_position

	if encounter_data.pause_time_during_encounter and TimeManager != null and TimeManager.has_method("exit_timeless_zone"):
		TimeManager.exit_timeless_zone()

	if reason == "retreat":
		_debug_toast("You step away. The disturbance lingers.", "info", 2.5)
	else:
		_debug_toast("The disturbance pushes you back. You can try again.", "info", 2.5)

	if print_debug:
		print("[RestorationEncounter] Failed. reason=", reason, " failures=", _get_failure_count())

	await get_tree().create_timer(0.2).timeout
	_ending = false
	
	if encounter_data.failure_time_loss_minutes > 0 and TimeManager != null:
		TimeManager.advance_time(float(encounter_data.failure_time_loss_minutes))

func complete_encounter() -> void:
	if _ending:
		return

	if not _active:
		return

	_ending = true
	_active = false
	_food_first_hit_shield_active = false
	
	_clear_danger_zones()
	_set_boundary_visible(false)
	_hide_instability_bar()
	_hide_player_resolve_ui()
	#_hide_restoration_ui()

	if core != null:
		core.mark_restored()

	_mark_restored()
	_give_rewards()

	if encounter_data.pause_time_during_encounter and TimeManager != null and TimeManager.has_method("exit_timeless_zone"):
		TimeManager.exit_timeless_zone()

	_debug_toast("The site grows calm again.", "success", 2.5)

	if print_debug:
		print("[RestorationEncounter] Complete: ", encounter_data.encounter_id)

	await get_tree().create_timer(0.2).timeout
	_ending = false

func _run_encounter_loop() -> void:
	# Small moment to let player realize combat started.
	await get_tree().create_timer(0.4).timeout

	while _active and _instability > 0 and _resolve > 0:
		if core == null:
			fail_encounter()
			return

		core.set_vulnerable(false)

		await _run_random_pattern()

		if not _active:
			return

		await get_tree().create_timer(max(0.05, encounter_data.time_between_patterns)).timeout

		if not _active:
			return

		await _open_core_window()

	if not _active:
		return

	if _instability <= 0:
		complete_encounter()
	elif _resolve <= 0:
		fail_encounter()

func _run_random_pattern() -> void:
	if encounter_data == null:
		return

	if encounter_data.patterns.is_empty():
		if print_debug:
			print("[RestorationEncounter] No patterns assigned. Waiting, then opening core.")
		_debug_toast("No danger patterns assigned yet.", "info", 1.0)
		await get_tree().create_timer(0.7).timeout
		return

	var pattern := encounter_data.patterns[randi_range(0, encounter_data.patterns.size() - 1)]
	if pattern == null:
		await get_tree().create_timer(0.5).timeout
		return

	if print_debug:
		print("[RestorationEncounter] Pattern: ", pattern.pattern_id)

	var count :Variant= max(1, pattern.spawn_count)

	for i in range(count):
		if not _active:
			return

		_spawn_pattern_zone(pattern)

		if i < count - 1:
			await get_tree().create_timer(max(0.01, pattern.spacing_seconds)).timeout

	var total_wait :Variant= max(0.05, pattern.warning_seconds + pattern.active_seconds + 0.05)
	await get_tree().create_timer(total_wait).timeout

func _spawn_pattern_zone(pattern: RestorationPatternData) -> void:
	if pattern == null:
		return

	var parent := danger_container
	if parent == null:
		parent = self

	var zone := RestorationDangerZone.new()
	parent.add_child(zone)

	if not zone.player_hit.is_connected(_on_danger_zone_player_hit):
		zone.player_hit.connect(_on_danger_zone_player_hit)

	match pattern.pattern_type:
		RestorationPatternData.PatternType.CIRCLE_AT_PLAYER:
			var pos := _player.global_position if _player != null else global_position
			zone.configure_circle(
				pos,
				pattern.radius,
				pattern.warning_seconds,
				pattern.active_seconds,
				pattern.resolve_damage
			)

		RestorationPatternData.PatternType.CIRCLE_NEAR_CORE:
			var pos2 := core.global_position if core != null else global_position
			pos2 += Vector2(randf_range(-64.0, 64.0), randf_range(-64.0, 64.0))
			zone.configure_circle(
				pos2,
				pattern.radius,
				pattern.warning_seconds,
				pattern.active_seconds,
				pattern.resolve_damage
			)

		RestorationPatternData.PatternType.LINE_FROM_CORE:
			var start := core.global_position if core != null else global_position
			var target := _player.global_position if _player != null else start + Vector2.RIGHT
			var dir := target - start
			if dir.length() < 0.01:
				dir = Vector2.RIGHT
			dir = dir.normalized()

			var center := start + dir * (pattern.line_length * 0.5)
			zone.configure_line(
				center,
				dir.angle(),
				pattern.line_length,
				pattern.line_width,
				pattern.warning_seconds,
				pattern.active_seconds,
				pattern.resolve_damage
			)

	zone.begin()

func _open_core_window() -> void:
	if core == null:
		return

	_hit_registered_this_opening = false
	core.set_vulnerable(true)

	_debug_toast("The core opens — strike now!", "success", 0.9)

	if print_debug:
		print("[RestorationEncounter] Core open. Instability=", _instability)

	var elapsed := 0.0
	var duration :Variant= max(0.15, encounter_data.core_open_duration)

	while elapsed < duration:
		if not _active:
			return
		if _hit_registered_this_opening:
			break

		await get_tree().process_frame
		elapsed += get_process_delta_time()

	core.set_vulnerable(false)

func _on_core_restoration_hit() -> void:
	if not _active or _ending:
		return

	if core == null or not core.vulnerable:
		return

	_hit_registered_this_opening = true
	_instability -= 1
	_instability = max(0, _instability)
	_update_instability_bar()
	_update_player_resolve_ui()
	_spawn_hit_sparkle()

	_debug_toast("The core softens. Instability: %d/%d" % [_instability, encounter_data.max_instability], "success", 1.2)

	if print_debug:
		print("[RestorationEncounter] Hit core. Instability now ", _instability)

func _on_danger_zone_player_hit(resolve_damage: int) -> void:
	if not _active or _ending:
		return

	if _food_first_hit_shield_active:
		_food_first_hit_shield_active = false
		_update_player_resolve_ui()
		#_update_restoration_ui()

		_debug_toast("Heart Guard softens the blow.", "info", 1.5)

		if print_debug:
			print("[RestorationEncounter] Heart Guard blocked a hit.")

		return

	_resolve -= max(1, resolve_damage)
	_resolve = max(0, _resolve)
	_update_player_resolve_ui()
	#_update_restoration_ui()

	_debug_toast("Your resolve wavers. Resolve: %d/%d" % [_resolve, _get_current_max_resolve()], "warning", 1.2)

	if print_debug:
		print("[RestorationEncounter] Player hit. Resolve now ", _resolve)

	if _resolve <= 0:
		fail_encounter()

func _on_trigger_body_entered(body: Node) -> void:
	if not auto_start_on_trigger:
		return

	if body == null:
		return

	if body.is_in_group("player"):
		start_encounter()

func _on_trigger_body_exited(body: Node) -> void:
	if not trigger_area_is_combat_boundary:
		return

	if not _active:
		return

	if body == null:
		return

	if not body.is_in_group("player"):
		return

	match boundary_mode:
		BoundaryMode.RETREAT_ON_EXIT:
			fail_encounter("retreat")

		BoundaryMode.PUSH_BACK_ON_EXIT:
			_push_player_back_into_boundary(body)

		BoundaryMode.IGNORE_EXIT:
			return

func _clear_danger_zones() -> void:
	if danger_container == null:
		return

	for c in danger_container.get_children():
		c.queue_free()

func _give_rewards() -> void:
	if encounter_data == null:
		return

	for item_any in encounter_data.rewards.keys():
		var item_id := String(item_any)
		var qty := int(encounter_data.rewards[item_any])
		if item_id != "" and qty > 0:
			GameState.inventory_add(item_id, qty)

func _get_state() -> Dictionary:
	var map := GameState.get_map_state(_state_key())
	if not map.has("restoration"):
		map["restoration"] = {}
	if not map["restoration"].has(encounter_data.encounter_id):
		map["restoration"][encounter_data.encounter_id] = {}
	return map["restoration"][encounter_data.encounter_id]

func _state_key() -> String:
	var s := get_tree().current_scene
	return s.name if s != null else "RestorationWorld"

func _is_currently_restored() -> bool:
	if encounter_data == null:
		return false

	var st := _get_state()

	if encounter_data.story_one_shot:
		return bool(st.get("restored", false))

	var last_restored_day := int(st.get("last_restored_day", -999999))
	if last_restored_day < 0:
		return false

	var days_since := int(TimeManager.day) - last_restored_day
	return days_since < max(1, encounter_data.respawn_days)

func _mark_restored() -> void:
	var st := _get_state()
	st["restored"] = true
	st["last_restored_day"] = int(TimeManager.day)

func _record_failure() -> void:
	var st := _get_state()
	st["failures"] = int(st.get("failures", 0)) + 1

func _get_failure_count() -> int:
	var st := _get_state()
	return int(st.get("failures", 0))

func _get_starting_resolve() -> int:
	var base := encounter_data.max_resolve
	if encounter_data.adaptive_difficulty_enabled:
		if _get_failure_count() >= encounter_data.easier_after_failures:
			base += 1
	return max(1, base)

func _get_starting_instability() -> int:
	var base := encounter_data.max_instability
	if encounter_data.adaptive_difficulty_enabled:
		if _get_failure_count() >= encounter_data.easier_after_failures:
			base = max(1, base - 1)
	return max(1, base)

func _apply_restored_state_if_needed() -> void:
	if core == null or encounter_data == null:
		return

	if _is_currently_restored():
		core.mark_restored()
	else:
		core.set_vulnerable(false)
	
	_hide_player_resolve_ui()

func _debug_toast(msg: String, kind: String = "info", duration: float = 1.5) -> void:
	if not show_debug_toasts:
		return

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(msg, kind, duration)

func _set_boundary_visible(value: bool) -> void:
	if boundary_visual == null:
		return

	boundary_visual.visible = value

func _get_restoration_ui() -> Node:
	var ui := get_tree().get_first_node_in_group("restoration_combat_ui")
	return ui

func _show_restoration_ui() -> void:
	var ui := _get_restoration_ui()
	if ui == null:
		return

	if ui.has_method("show_encounter"):
		ui.call(
			"show_encounter",
			encounter_data.display_name,
			_resolve,
			_get_current_max_resolve(),
			_instability,
			_get_starting_instability()
		)

func _update_restoration_ui() -> void:
	var ui := _get_restoration_ui()
	if ui == null:
		return

	if ui.has_method("update_values"):
		ui.call(
			"update_values",
			_resolve,
			_get_current_max_resolve(),
			_instability,
			_get_starting_instability()
		)

func _hide_restoration_ui() -> void:
	var ui := _get_restoration_ui()
	if ui == null:
		return

	if ui.has_method("hide_ui"):
		ui.call("hide_ui")

func _show_instability_bar() -> void:
	if instability_bar == null:
		return

	instability_bar.show_bar(_instability, _get_starting_instability())

func _update_instability_bar() -> void:
	if instability_bar == null:
		return

	instability_bar.set_values(_instability, _get_starting_instability())

func _hide_instability_bar() -> void:
	if instability_bar == null:
		return

	instability_bar.hide_bar()

func _get_player_resolve_ui() -> Node:
	return get_tree().get_first_node_in_group("player_resolve_ui")

func _show_player_resolve_ui() -> void:
	var ui := _get_player_resolve_ui()
	if ui == null:
		return

	if ui.has_method("show_resolve"):
		ui.call("show_resolve", _resolve, _get_current_max_resolve())

func _update_player_resolve_ui() -> void:
	var ui := _get_player_resolve_ui()
	if ui == null:
		return

	if ui.has_method("update_resolve"):
		ui.call("update_resolve", _resolve, _get_current_max_resolve())

func _hide_player_resolve_ui() -> void:
	var ui := _get_player_resolve_ui()
	if ui == null:
		return

	if ui.has_method("hide_resolve"):
		ui.call("hide_resolve")

func _get_restoration_fade_overlay() -> Node:
	return get_tree().get_first_node_in_group("restoration_fade_overlay")

func _play_failure_fade() -> void:
	var fade := _get_restoration_fade_overlay()
	if fade == null:
		return

	if fade.has_method("fade_out_in"):
		await fade.call("fade_out_in", 0.22, 0.12, 0.32)

func _spawn_hit_sparkle() -> void:
	if hit_sparkle_scene == null:
		return

	if core == null:
		return

	var sparkle := hit_sparkle_scene.instantiate()
	get_tree().current_scene.add_child(sparkle)

	if sparkle is Node2D:
		var sparkle_2d := sparkle as Node2D
		sparkle_2d.global_position = core.global_position
		sparkle_2d.scale = Vector2.ONE * hit_sparkle_scale
		sparkle_2d.z_index = 250

	await get_tree().create_timer(max(0.05, hit_sparkle_lifetime)).timeout

	if is_instance_valid(sparkle):
		sparkle.queue_free()

func _push_player_back_into_boundary(body: Node) -> void:
	if _pushback_locked:
		return

	if body == null or not (body is Node2D):
		return

	_pushback_locked = true

	var player_2d := body as Node2D

	var center := global_position
	if core != null:
		center = core.global_position
	elif trigger_area != null:
		center = trigger_area.global_position

	var dir_to_center := center - player_2d.global_position

	if dir_to_center.length() < 0.01:
		dir_to_center = Vector2.DOWN
	else:
		dir_to_center = dir_to_center.normalized()

	player_2d.global_position += dir_to_center * boundary_pushback_distance

	_debug_toast(boundary_pushback_toast, "warning", 1.2)

	if print_debug:
		print("[RestorationEncounter] Player pushed back into boundary.")

	await get_tree().create_timer(max(0.05, boundary_pushback_cooldown)).timeout
	_pushback_locked = false

func _get_current_max_resolve() -> int:
	if _max_resolve_this_encounter > 0:
		return _max_resolve_this_encounter
	return _get_starting_resolve()

func _apply_combat_food_buffs_on_start() -> void:
	if GameState == null:
		return
	if not GameState.has_method("get_food_buff_amount"):
		return

	# ------------------------------------------------------------
	# Root Courage: +Resolve for this encounter
	# ------------------------------------------------------------
	var resolve_bonus := GameState.get_food_buff_amount(FoodEffectData.EffectKey.COMBAT_RESOLVE_BONUS)

	if resolve_bonus > 0.0:
		var bonus_int := int(round(resolve_bonus))
		if bonus_int > 0:
			_max_resolve_this_encounter += bonus_int
			_resolve += bonus_int

			if GameState.has_method("consume_food_buff_use"):
				GameState.consume_food_buff_use(FoodEffectData.EffectKey.COMBAT_RESOLVE_BONUS)

			if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
				QuestEvents.toast_requested.emit("Root Courage steadies your heart. +" + str(bonus_int) + " Resolve", "success", 2.5)

			if print_debug:
				print("[RestorationEncounter] Root Courage applied. bonus=", bonus_int, " resolve=", _resolve, "/", _max_resolve_this_encounter)

	# ------------------------------------------------------------
	# Heart Guard: first hit shield for this encounter
	# ------------------------------------------------------------
	var shield_amount := GameState.get_food_buff_amount(FoodEffectData.EffectKey.COMBAT_FIRST_HIT_SHIELD)

	if shield_amount > 0.0:
		_food_first_hit_shield_active = true

		if GameState.has_method("consume_food_buff_use"):
			GameState.consume_food_buff_use(FoodEffectData.EffectKey.COMBAT_FIRST_HIT_SHIELD)

		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("Heart Guard surrounds you.", "success", 2.5)

		if print_debug:
			print("[RestorationEncounter] Heart Guard applied.")
	else:
		_food_first_hit_shield_active = false
