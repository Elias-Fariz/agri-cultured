# res://scripts/heart/ValleyHeartCinematicOrchestrator.gd
extends Node
class_name ValleyHeartCinematicOrchestrator

signal cinematic_started
signal cinematic_finished

# -------------------------------------------------------------------
# Core references
# -------------------------------------------------------------------

@export var player_path: NodePath
@export var heart_camera_path: NodePath
@export var heart_reveal_director_path: NodePath
@export var heart_visual_controller_path: NodePath
@export var heart_overlay_path: NodePath
@export var dialogue_ui_path: NodePath

# Optional parent for spawned actors like Alder.
# Leave blank to spawn under the current scene root.
@export var actor_parent_path: NodePath

# -------------------------------------------------------------------
# First Heart Tree awakening nodes
# -------------------------------------------------------------------

@export var seed_sprite_path: NodePath
@export var sprout_sprite_path: NodePath
@export var seed_focus_marker_path: NodePath
@export var player_approach_marker_path: NodePath

# -------------------------------------------------------------------
# Optional Alder follow-up
# -------------------------------------------------------------------

# Option A: use an Alder already in the scene.
@export var alder_path: NodePath

# Option B: spawn Alder from a PackedScene.
# This is better if Alder should only exist during the cinematic.
@export var alder_scene: PackedScene

@export var alder_start_marker_path: NodePath
@export var alder_end_marker_path: NodePath
@export var alder_dialogue_sequence: DialogueSequenceData

# If true, spawned Alder is deleted after the cinematic.
# If using an existing Alder node, he is hidden and moved back to the start marker.
@export var remove_or_hide_alder_after_dialogue: bool = true

# -------------------------------------------------------------------
# Flags / behavior
# -------------------------------------------------------------------

@export var first_tree_flag: String = "heart_tree_stage_1_awakened"

# Usually false when ValleyHeart.gd calls run_if_needed().
# You can set true only if you want this node to trigger itself.
@export var play_on_scene_ready: bool = false

# For recording/devlog testing.
# If true, the seed awakening can play even if the flag already exists.
@export var force_first_awakening_for_dev: bool = false

# If true, only play the first awakening if HeartVisualController has pending reveals.
@export var require_pending_reveal_for_first_awakening: bool = true

# If true, after the seed becomes sprout, run the normal HeartRevealDirector.
@export var run_normal_reveals_after_tree: bool = true

# If true, Alder walks in and speaks after normal reveals.
@export var play_alder_after_reveals: bool = true

# -------------------------------------------------------------------
# Timing
# -------------------------------------------------------------------

@export var player_walk_time: float = 0.9
@export var camera_pan_time: float = 0.9
@export var camera_zoom: Vector2 = Vector2(0.9, 0.9)

# If true, player and camera begin moving together.
@export var move_player_and_camera_together: bool = true

@export var seed_pulse_count: int = 3
@export var seed_pulse_time: float = 0.28
@export var flash_fade_in_time: float = 0.35
@export var flash_hold_time: float = 0.15
@export var flash_fade_out_time: float = 0.55

@export var sprout_scale_from: float = 0.65
@export var sprout_bloom_time: float = 0.75
@export var post_sprout_hold_time: float = 0.35

# Magical sparkle burst when the seed becomes a sprout.
@export var sprout_sparkle_scene: PackedScene = preload("res://tscn/CropReadySparkle.tscn")
@export var sprout_sparkle_count: int = 7
@export var sprout_sparkle_radius: float = 34.0
@export var sprout_sparkle_lifetime: float = 1.4
@export var sprout_sparkle_scale_min: float = 0.75
@export var sprout_sparkle_scale_max: float = 1.25

# After the normal milestone reveal, pan back to the sprout/seed before Alder enters.
@export var pan_back_to_tree_for_alder: bool = true
@export var pan_back_to_tree_time: float = 0.65

@export var alder_walk_time: float = 1.0
@export var alder_pre_dialogue_pause: float = 0.25

# Final camera return to player after everything is done.
@export var final_camera_return_time: float = 0.3

@export var debug_enabled: bool = true

@export var cinematic_ui_hider_path: NodePath
var _cinematic_ui_hider: Node

# -------------------------------------------------------------------
# Internal state
# -------------------------------------------------------------------

var _running: bool = false
var _skip_requested: bool = false

var _player: Node2D
var _heart_camera: Camera2D
var _reveal_director: Node
var _visual_controller: Node
var _overlay: Node
var _dialogue_ui: Node
var _actor_parent: Node

var _seed: Node2D
var _sprout: Node2D
var _seed_focus_marker: Node2D
var _player_approach_marker: Node2D

var _alder: Node2D
var _alder_start_marker: Node2D
var _alder_end_marker: Node2D
var _spawned_alder: Node = null

var _previous_camera: Camera2D
var _previous_camera_enabled: bool = true
var _previous_camera_pos: Vector2 = Vector2.ZERO
var _previous_camera_zoom: Vector2 = Vector2.ONE

var _camera_tween: Tween
var _player_tween: Tween
var _seed_tween: Tween
var _sprout_tween: Tween
var _alder_tween: Tween


func _ready() -> void:
	_resolve_nodes()

	if play_on_scene_ready:
		call_deferred("run_if_needed")


func _unhandled_input(event: InputEvent) -> void:
	if not _running:
		return

	if event.is_action_pressed("ui_cancel"):
		_skip_requested = true
		get_viewport().set_input_as_handled()


# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------

func run_if_needed() -> void:
	if _running:
		return

	_resolve_nodes()

	var has_pending := _has_pending_reveals()
	var should_play_tree := _should_play_first_tree_awakening(has_pending)
	var should_play_reveals := run_normal_reveals_after_tree and has_pending

	if not should_play_tree and not should_play_reveals:
		if debug_enabled:
			print("[ValleyHeartCinematic] Nothing to run. pending=", has_pending)
		return

	await _run_sequence(should_play_tree, should_play_reveals)


# -------------------------------------------------------------------
# Main sequence
# -------------------------------------------------------------------

func _run_sequence(should_play_tree: bool, should_play_reveals: bool) -> void:
	_running = true
	_skip_requested = false
	cinematic_started.emit()

	if debug_enabled:
		print("[ValleyHeartCinematic] Started. tree=", should_play_tree, " reveals=", should_play_reveals)

	_lock_gameplay()
	
	_hide_cinematic_ui()

	await _take_over_heart_camera()

	if should_play_tree:
		await _run_first_tree_awakening()

		if not force_first_awakening_for_dev:
			_set_flag(first_tree_flag, true)

	if should_play_reveals:
		await _run_existing_heart_reveals()

		# HeartRevealDirector is self-contained and may restore/disable cameras.
		# Reclaim HeartCamera2D immediately so the rest of this special sequence
		# still feels continuous.
		await _reclaim_heart_camera_after_reveal()

	if play_alder_after_reveals:
		if pan_back_to_tree_for_alder and _seed_focus_marker != null:
			await _tween_heart_camera_to(_seed_focus_marker.global_position, camera_zoom, pan_back_to_tree_time)

		await _run_alder_followup()

	await _return_to_previous_camera(final_camera_return_time)

	_cleanup_alder_if_needed()
	
	_show_cinematic_ui()
	
	_unlock_gameplay()

	_running = false
	_skip_requested = false
	cinematic_finished.emit()

	if debug_enabled:
		print("[ValleyHeartCinematic] Finished.")


# -------------------------------------------------------------------
# First tree awakening
# -------------------------------------------------------------------

func _run_first_tree_awakening() -> void:
	if _seed == null or _sprout == null:
		push_warning("[ValleyHeartCinematic] Missing seed or sprout sprite.")
		return

	_prepare_seed_and_sprout()

	if move_player_and_camera_together:
		await _move_player_and_camera_to_tree()
	else:
		if _player != null and _player_approach_marker != null:
			await _move_node_to(_player, _player_approach_marker.global_position, player_walk_time)

		if _seed_focus_marker != null:
			await _tween_heart_camera_to(_seed_focus_marker.global_position, camera_zoom, camera_pan_time)

	if _skip_requested:
		_instant_seed_to_sprout()
		return

	await _pulse_seed()

	if _skip_requested:
		_instant_seed_to_sprout()
		return

	await _flash_to_sprout()

	if _skip_requested:
		_instant_seed_to_sprout()
		return

	await get_tree().create_timer(post_sprout_hold_time).timeout


func _move_player_and_camera_to_tree() -> void:
	var tweens: Array[Tween] = []

	if _player != null and _player_approach_marker != null:
		_kill_tween(_player_tween)

		_player_tween = create_tween()
		_player_tween.set_trans(Tween.TRANS_SINE)
		_player_tween.set_ease(Tween.EASE_IN_OUT)
		_player_tween.tween_property(
			_player,
			"global_position",
			_player_approach_marker.global_position,
			max(0.01, player_walk_time)
		)

		tweens.append(_player_tween)

	if _heart_camera != null and _seed_focus_marker != null:
		_kill_tween(_camera_tween)

		_camera_tween = create_tween()
		_camera_tween.set_trans(Tween.TRANS_SINE)
		_camera_tween.set_ease(Tween.EASE_IN_OUT)
		_camera_tween.tween_property(
			_heart_camera,
			"global_position",
			_seed_focus_marker.global_position,
			max(0.01, camera_pan_time)
		)
		_camera_tween.parallel().tween_property(
			_heart_camera,
			"zoom",
			camera_zoom,
			max(0.01, camera_pan_time)
		)

		tweens.append(_camera_tween)

	await _await_tweens_or_skip(tweens)

	if not _skip_requested:
		if _player != null and _player_approach_marker != null:
			_player.global_position = _player_approach_marker.global_position
		if _heart_camera != null and _seed_focus_marker != null:
			_heart_camera.global_position = _seed_focus_marker.global_position
			_heart_camera.zoom = camera_zoom


func _prepare_seed_and_sprout() -> void:
	if _seed != null:
		_seed.visible = true
		_seed.modulate = Color(1, 1, 1, 1)

	if _sprout != null:
		_sprout.visible = false
		_sprout.modulate = Color(1, 1, 1, 1)


func _pulse_seed() -> void:
	if _seed == null:
		return

	var original_scale := _seed.scale

	for i in range(max(1, seed_pulse_count)):
		if _skip_requested:
			break

		_kill_tween(_seed_tween)
		_seed_tween = create_tween()
		_seed_tween.set_trans(Tween.TRANS_SINE)
		_seed_tween.set_ease(Tween.EASE_IN_OUT)
		_seed_tween.tween_property(_seed, "scale", original_scale * 1.18, seed_pulse_time)
		_seed_tween.tween_property(_seed, "scale", original_scale, seed_pulse_time)

		await _await_tween_or_skip(_seed_tween)

	_seed.scale = original_scale


func _flash_to_sprout() -> void:
	# Make this a bright/holy/soft white flash instead of a black fade.
	if _overlay != null and _overlay.has_method("set_fade_color"):
		_overlay.call("set_fade_color", Color.WHITE)

	if _overlay != null and _overlay.has_method("vignette_to"):
		_overlay.call("vignette_to", 0.45, flash_fade_in_time)

	if _overlay != null and _overlay.has_method("fade_to"):
		_overlay.call("fade_to", 0.9, flash_fade_in_time)
		await get_tree().create_timer(flash_fade_in_time).timeout

	if _skip_requested:
		_instant_seed_to_sprout()
		return

	await get_tree().create_timer(flash_hold_time).timeout

	# Swap seed into sprout while the screen is bright.
	_seed.visible = false
	_sprout.visible = true

	var original_sprout_scale := _sprout.scale
	_sprout.scale = original_sprout_scale * sprout_scale_from
	_sprout.modulate = Color(1, 1, 1, 0)

	# Sparkles begin right as the sprout is revealed.
	_spawn_sprout_sparkles()

	_kill_tween(_sprout_tween)
	_sprout_tween = create_tween()
	_sprout_tween.set_trans(Tween.TRANS_SINE)
	_sprout_tween.set_ease(Tween.EASE_OUT)
	_sprout_tween.tween_property(_sprout, "modulate:a", 1.0, sprout_bloom_time)
	_sprout_tween.parallel().tween_property(_sprout, "scale", original_sprout_scale, sprout_bloom_time)

	if _overlay != null and _overlay.has_method("fade_to"):
		_overlay.call("fade_to", 0.0, flash_fade_out_time)

	if _overlay != null and _overlay.has_method("vignette_to"):
		_overlay.call("vignette_to", 0.0, flash_fade_out_time)

	await _await_tween_or_skip(_sprout_tween)

	_sprout.modulate = Color(1, 1, 1, 1)
	_sprout.scale = original_sprout_scale

func _instant_seed_to_sprout() -> void:
	_stop_all_local_tweens()

	if _seed != null:
		_seed.visible = false

	if _sprout != null:
		_sprout.visible = true
		_sprout.modulate = Color(1, 1, 1, 1)

	if _overlay != null and _overlay.has_method("fade_to"):
		_overlay.call("fade_to", 0.0, 0.05)

	if _overlay != null and _overlay.has_method("vignette_to"):
		_overlay.call("vignette_to", 0.0, 0.05)


# -------------------------------------------------------------------
# Existing Heart reveal director
# -------------------------------------------------------------------

func _run_existing_heart_reveals() -> void:
	if _reveal_director == null:
		return
	if not _reveal_director.has_method("run_reveals_if_any"):
		return

	if debug_enabled:
		print("[ValleyHeartCinematic] Running HeartRevealDirector.")

	_reveal_director.call("run_reveals_if_any")

	if _reveal_director.has_signal("reveal_finished"):
		await _reveal_director.reveal_finished
	else:
		await get_tree().process_frame


func _reclaim_heart_camera_after_reveal() -> void:
	if _heart_camera == null:
		return

	# If HeartRevealDirector disabled the HeartCamera2D at the end,
	# immediately make it current again for the Alder follow-up.
	_heart_camera.enabled = true
	_heart_camera.make_current()

	await get_tree().process_frame


# -------------------------------------------------------------------
# Alder follow-up
# -------------------------------------------------------------------

func _run_alder_followup() -> void:
	_alder = _get_or_spawn_alder()

	if _alder == null:
		return

	if _alder_start_marker != null:
		_alder.global_position = _alder_start_marker.global_position

	_alder.visible = true

	if _alder_end_marker != null:
		await _move_node_to(_alder, _alder_end_marker.global_position, alder_walk_time)

	await get_tree().create_timer(alder_pre_dialogue_pause).timeout

	if alder_dialogue_sequence == null:
		return

	if _dialogue_ui == null:
		return

	if _dialogue_ui.has_method("show_dialogue_sequence"):
		_dialogue_ui.call("show_dialogue_sequence", alder_dialogue_sequence)

		if _dialogue_ui.has_signal("dialogue_closed"):
			await _dialogue_ui.dialogue_closed
		else:
			await get_tree().process_frame

		# NEW:
		# DialogueSequenceData can now grant rewards after the whole sequence finishes.
		# This is where the Valley Heart Help Book page can unlock.
		if GameState != null and GameState.has_method("apply_dialogue_sequence_rewards"):
			GameState.apply_dialogue_sequence_rewards(
				alder_dialogue_sequence,
				"valley_heart:alder_followup"
			)

func _get_or_spawn_alder() -> Node2D:
	# Prefer an existing assigned node if provided.
	if _alder != null and is_instance_valid(_alder):
		return _alder

	if alder_path != NodePath(""):
		var existing := get_node_or_null(alder_path) as Node2D
		if existing != null:
			_alder = existing
			return _alder

	# Otherwise spawn from PackedScene.
	if alder_scene == null:
		return null

	var inst := alder_scene.instantiate()
	if inst == null:
		return null

	var parent := _actor_parent
	if parent == null:
		parent = get_tree().current_scene
	if parent == null:
		parent = self

	parent.add_child(inst)
	_spawned_alder = inst

	if inst is Node2D:
		_alder = inst as Node2D
	else:
		push_warning("[ValleyHeartCinematic] Spawned Alder scene is not Node2D.")
		return null

	return _alder


func _cleanup_alder_if_needed() -> void:
	if not remove_or_hide_alder_after_dialogue:
		return

	if _spawned_alder != null and is_instance_valid(_spawned_alder):
		_spawned_alder.queue_free()
		_spawned_alder = null
		_alder = null
		return

	# If Alder was an existing node, hide him and optionally return him to start.
	if _alder != null and is_instance_valid(_alder):
		if _alder_start_marker != null:
			_alder.global_position = _alder_start_marker.global_position
		_alder.visible = false


# -------------------------------------------------------------------
# Camera helpers
# -------------------------------------------------------------------

func _take_over_heart_camera() -> void:
	if _heart_camera == null:
		return

	if _previous_camera == null or not is_instance_valid(_previous_camera):
		_previous_camera = get_viewport().get_camera_2d()

		if _previous_camera != null:
			_previous_camera_enabled = _previous_camera.enabled
			_previous_camera_pos = _previous_camera.global_position
			_previous_camera_zoom = _previous_camera.zoom
			_previous_camera.enabled = false

	_heart_camera.enabled = true

	if _previous_camera != null:
		_heart_camera.global_position = _previous_camera_pos
		_heart_camera.zoom = _previous_camera_zoom

	_heart_camera.make_current()

	await get_tree().process_frame


func _return_to_previous_camera(duration: float = 0.25) -> void:
	if _heart_camera == null:
		return

	if _previous_camera != null and is_instance_valid(_previous_camera):
		await _tween_heart_camera_to(_previous_camera_pos, _previous_camera_zoom, duration)

		_previous_camera.enabled = _previous_camera_enabled
		_previous_camera.make_current()

	_heart_camera.enabled = false


func _restore_camera_if_needed() -> void:
	if _heart_camera != null:
		_heart_camera.enabled = false

	if _previous_camera != null and is_instance_valid(_previous_camera):
		_previous_camera.enabled = _previous_camera_enabled
		_previous_camera.make_current()


func _tween_heart_camera_to(pos: Vector2, zoom: Vector2, duration: float) -> void:
	if _heart_camera == null:
		return

	_kill_tween(_camera_tween)
	_camera_tween = create_tween()
	_camera_tween.set_trans(Tween.TRANS_SINE)
	_camera_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(_heart_camera, "global_position", pos, max(0.01, duration))
	_camera_tween.parallel().tween_property(_heart_camera, "zoom", zoom, max(0.01, duration))

	await _await_tween_or_skip(_camera_tween)


# -------------------------------------------------------------------
# Generic movement/tween helpers
# -------------------------------------------------------------------

func _move_node_to(node: Node2D, pos: Vector2, duration: float) -> void:
	if node == null:
		return

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "global_position", pos, max(0.01, duration))

	if node == _player:
		_kill_tween(_player_tween)
		_player_tween = tween
	elif node == _alder:
		_kill_tween(_alder_tween)
		_alder_tween = tween

	await _await_tween_or_skip(tween)

	if not _skip_requested:
		node.global_position = pos


func _await_tween_or_skip(tween: Tween) -> void:
	if tween == null:
		return

	while tween.is_running():
		if _skip_requested:
			tween.kill()
			return
		await get_tree().process_frame


func _await_tweens_or_skip(tweens: Array[Tween]) -> void:
	while true:
		if _skip_requested:
			for t in tweens:
				_kill_tween(t)
			return

		var any_running := false
		for t in tweens:
			if t != null and t.is_running():
				any_running = true
				break

		if not any_running:
			return

		await get_tree().process_frame


func _kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_running():
		tween.kill()


func _stop_all_local_tweens() -> void:
	_kill_tween(_camera_tween)
	_kill_tween(_player_tween)
	_kill_tween(_seed_tween)
	_kill_tween(_sprout_tween)
	_kill_tween(_alder_tween)


# -------------------------------------------------------------------
# Checks / state
# -------------------------------------------------------------------

func _should_play_first_tree_awakening(has_pending: bool) -> bool:
	if force_first_awakening_for_dev:
		return true

	if first_tree_flag.strip_edges() == "":
		return false

	if _has_flag(first_tree_flag):
		return false

	if require_pending_reveal_for_first_awakening and not has_pending:
		return false

	return true


func _has_pending_reveals() -> bool:
	if _visual_controller == null:
		return false
	if not _visual_controller.has_method("get_pending_reveals"):
		return false

	var pending: Array = _visual_controller.call("get_pending_reveals")
	return not pending.is_empty()


func _has_flag(flag: String) -> bool:
	if GameState == null:
		return false
	if GameState.has_method("has_flag"):
		return bool(GameState.call("has_flag", flag))
	return false


func _set_flag(flag: String, value: bool) -> void:
	if GameState == null:
		return
	if GameState.has_method("set_flag"):
		GameState.call("set_flag", flag, value)


func _lock_gameplay() -> void:
	if GameState != null and GameState.has_method("lock_gameplay"):
		GameState.lock_gameplay()

	if TimeManager != null and TimeManager.has_method("pause_time"):
		TimeManager.pause_time()


func _unlock_gameplay() -> void:
	if GameState != null and GameState.has_method("unlock_gameplay"):
		GameState.unlock_gameplay()

	if TimeManager != null and TimeManager.has_method("resume_time"):
		TimeManager.resume_time()


func _resolve_nodes() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_heart_camera = get_node_or_null(heart_camera_path) as Camera2D
	_reveal_director = get_node_or_null(heart_reveal_director_path)
	_visual_controller = get_node_or_null(heart_visual_controller_path)
	_overlay = get_node_or_null(heart_overlay_path)
	_dialogue_ui = get_node_or_null(dialogue_ui_path)
	_actor_parent = get_node_or_null(actor_parent_path)

	_seed = get_node_or_null(seed_sprite_path) as Node2D
	_sprout = get_node_or_null(sprout_sprite_path) as Node2D
	_seed_focus_marker = get_node_or_null(seed_focus_marker_path) as Node2D
	_player_approach_marker = get_node_or_null(player_approach_marker_path) as Node2D

	_alder = get_node_or_null(alder_path) as Node2D
	_alder_start_marker = get_node_or_null(alder_start_marker_path) as Node2D
	_alder_end_marker = get_node_or_null(alder_end_marker_path) as Node2D
	
	_cinematic_ui_hider = get_node_or_null(cinematic_ui_hider_path)

func _spawn_sprout_sparkles() -> void:
	if sprout_sparkle_scene == null:
		return

	if _sprout == null:
		return

	var parent := _sprout.get_parent()
	if parent == null:
		parent = get_tree().current_scene
	if parent == null:
		parent = self

	var spawned: Array[Node] = []

	for i in range(max(0, sprout_sparkle_count)):
		var sparkle := sprout_sparkle_scene.instantiate()
		if sparkle == null:
			continue

		parent.add_child(sparkle)

		if sparkle is Node2D:
			var sparkle_2d := sparkle as Node2D

			var angle := randf_range(0.0, TAU)
			var dist := randf_range(4.0, sprout_sparkle_radius)
			var offset := Vector2(cos(angle), sin(angle)) * dist

			# Slight upward bias so sparkles feel like they rise around the sprout.
			offset.y -= randf_range(4.0, 18.0)

			sparkle_2d.global_position = _sprout.global_position + offset
			sparkle_2d.scale = Vector2.ONE * randf_range(sprout_sparkle_scale_min, sprout_sparkle_scale_max)
			sparkle_2d.z_index = max(sparkle_2d.z_index, _sprout.z_index + 5)

		spawned.append(sparkle)

	await get_tree().create_timer(max(0.05, sprout_sparkle_lifetime)).timeout

	for sparkle in spawned:
		if sparkle != null and is_instance_valid(sparkle):
			sparkle.queue_free()

func _hide_cinematic_ui() -> void:
	if _cinematic_ui_hider != null and _cinematic_ui_hider.has_method("hide_cinematic_ui"):
		_cinematic_ui_hider.call("hide_cinematic_ui")


func _show_cinematic_ui() -> void:
	if _cinematic_ui_hider != null and _cinematic_ui_hider.has_method("show_cinematic_ui"):
		_cinematic_ui_hider.call("show_cinematic_ui")
