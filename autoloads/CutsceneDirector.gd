# res://autoload/CutsceneDirector.gd
extends Node

var _is_playing: bool = false
var _queued_id: String = ""

# Nodes we spawned for the cutscene (so we can remove them after)
var _temp_spawned_actors: Array[Node] = []
var _original_actor_positions: Array[Dictionary] = []

# Camera lock (prevents snap-back)
var _camera_lock_active: bool = false
var _camera_lock_point: Vector2 = Vector2.ZERO
var _camera_lock_player: Node = null

signal cutscene_finished(cutscene_id: String)

var _current_cutscene_id: String = ""

var _skip_initial_fade_out_once: bool = false

@export var hide_ui_during_cutscenes: bool = true

@export var cutscene_camera_process_priority: int = 1000

var _cutscene_hid_ui: bool = false

# Cutscene registry: id -> .tres path
var _cutscene_paths := {
	"heart_intro": "res://data/cutscenes/heart_intro.tres",
	"greeting_intro": "res://data/cutscenes/greeting_intro.tres",
	"shop_intro": "res://data/cutscenes/shop_intro.tres",
	"fearroot_intro": "res://data/cutscenes/fearroot_intro.tres",
	"connector_valley_discovery": "res://data/cutscenes/connector_valley_discovery.tres",
	"ash_first_passout_rescue": "res://data/cutscenes/ash_first_passout_rescue.tres",
	"whisper_test": "res://data/cutscenes/whisper_test.tres",
	"day1_wakeup_whisper": "res://data/cutscenes/day1_wakeup_whisper.tres",
}

var _pending_restoration_encounter_path: NodePath = NodePath("")
var _pending_restoration_encounter_id: String = ""

var _pending_player_end_marker_id: String = ""

var _cutscene_original_zoom: float = 1.0
var _has_cutscene_original_zoom: bool = false

var _keep_screen_black_after_cutscene_once: bool = false
var _suppress_time_resume_once: bool = false

func _ready() -> void:
	process_priority = cutscene_camera_process_priority
#	physics_process_priority = cutscene_camera_process_priority

func _process(_delta: float) -> void:
	_enforce_camera_lock()


func _physics_process(_delta: float) -> void:
	_enforce_camera_lock()


func _enforce_camera_lock() -> void:
	if not _camera_lock_active:
		return

	if _camera_lock_player == null or not is_instance_valid(_camera_lock_player):
		return

	if _camera_lock_player.has_method("camera_focus_on_world_point"):
		_camera_lock_player.camera_focus_on_world_point(_camera_lock_point)

# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------

func queue_cutscene(id: String) -> void:
	id = id.strip_edges()
	if id == "":
		return
	_queued_id = id

func is_playing_cutscene() -> bool:
	return _is_playing

func try_play_queued() -> void:
	if _is_playing:
		return
	if _queued_id.strip_edges() == "":
		return

	var id := _queued_id
	_queued_id = ""
	play_cutscene(id)

func _get_cutscene_path(id: String) -> String:
	id = id.strip_edges()
	if id == "":
		return ""

	# 1) Manual registry wins.
	var manual_path := String(_cutscene_paths.get(id, "")).strip_edges()
	if manual_path != "":
		return manual_path

	# 2) Automatic fallback by file name.
	var fallback_path := "res://data/cutscenes/%s.tres" % id
	if ResourceLoader.exists(fallback_path):
		return fallback_path

	return ""

func play_cutscene(id: String) -> void:
	# print("CutsceneDirector: play_cutscene called with:", id)
	# print("Is already playing?", _is_playing)
	
	if _is_playing:
		return

	id = id.strip_edges()
	var path := _get_cutscene_path(id)
	if path == "":
		push_warning("CutsceneDirector: no resource path for cutscene id: " + id)
		return

	var data := load(path) as CutsceneData
	if data == null:
		push_warning("CutsceneDirector: failed to load cutscene resource: " + path)
		return

	_is_playing = true
	_current_cutscene_id = id
	_run_cutscene_async(data)

# ------------------------------------------------------------
# Internals
# ------------------------------------------------------------

func _run_cutscene_async(data: CutsceneData) -> void:
	call_deferred("_run_cutscene_impl", data)

func _run_cutscene_impl(data: CutsceneData) -> void:
	GameState.lock_gameplay()
	_set_time_paused(true)
	
	_set_cutscene_ui_hidden(true)

	# Make sure current_scene is stable
	await get_tree().process_frame

	var scene := get_tree().current_scene
	if scene == null:
		# print("CutsceneDirector: current_scene is null")
		_finish_cutscene()
		return

	var desired_scene := String(data.scene_name).strip_edges()
	# print("CutsceneDirector: current scene name =", scene.name)
	# print("CutsceneDirector: desired scene name =", desired_scene)

	if desired_scene != "" and scene.name != desired_scene:
		# print("CutsceneDirector: scene mismatch, re-queuing cutscene:", data.id)
		_queued_id = String(data.id)
		call_deferred("_cleanup_temp_actors")
		_finish_cutscene()
		return

	var player := _get_player()
	var dialogue_ui := _get_dialogue_ui()

	if player == null or dialogue_ui == null:
		push_warning("CutsceneDirector: missing player or dialogue_ui.")
		call_deferred("_cleanup_temp_actors")
		_finish_cutscene()
		return

	# 1) Fade OUT immediately unless travel already left us on a black screen.
	var skip_initial_fade := _skip_initial_fade_out_once
	_skip_initial_fade_out_once = false

	if has_node("/root/FadeOverlay") and not skip_initial_fade:
		await FadeOverlay.fade_out(0.15)
		
	_store_cutscene_original_zoom(player)
	await _set_player_cutscene_zoom(player, 1.0, 0.0)

	# 2) Spawn / resolve actors
	var actors_by_key: Dictionary = {}
	actors_by_key["player"] = player

	for a in data.actors:
		if a == null:
			continue

		var key := String(a.key).strip_edges()
		if key == "":
			continue

		if String(a.actor_type) == "player":
			actors_by_key[key] = player
			continue

		var npc_node := _ensure_npc_actor(scene, a)
		actors_by_key[key] = npc_node
	
	# NEW: remember where reused scene actors were before the cutscene moves them
	_record_original_actor_positions(actors_by_key)

	# 3) Place START positions for everyone
	_place_start_positions(scene, data, actors_by_key)

	# 4) Set initial camera focus BEFORE fade-in + lock it
	# We accept any of these marker ids (so "focus" still works):
	# - focus_start (preferred)
	# - focus
	# - focus_intro
	var initial_focus_marker := _get_first_marker_by_ids(scene, data, ["focus_start", "focus", "focus_intro"])
	var focus_point :Variant= player.global_position
	if initial_focus_marker != null:
		focus_point = initial_focus_marker.global_position

	_set_camera_lock(player, focus_point)

	# 5) Fade IN to reveal the staged scene,
	# unless this cutscene wants to control its own reveal.
	if has_node("/root/FadeOverlay"):
		if not data.defer_initial_fade_in:
			await FadeOverlay.fade_in(0.25)

	await get_tree().create_timer(0.1).timeout

	# 6) Run steps
	if data.steps != null and data.steps.size() > 0:
		for step in data.steps:
			await _run_step(step, scene, player, dialogue_ui, data, actors_by_key)

	# 7) Apply effects
	_apply_effects(data.effects)

	# 7.5) Apply completion rewards
	# These happen after all cutscene steps/effects are complete,
	# before cleanup and unlock.
	_apply_cutscene_completion_rewards(data)

	# ------------------------------------------------------------
	# 8) Final presentation + cleanup
	# ------------------------------------------------------------

	# Special flows such as passout may explicitly require the screen
	# to remain black after the cutscene. That behavior takes priority
	# over skip_final_fade_cycle.
	var keep_black_requested := _keep_screen_black_after_cutscene_once

	var skip_final_fade_cycle := (
		data.skip_final_fade_cycle
		and not keep_black_requested
	)

	# Normal behavior:
	# hide cleanup behind a short fade to black.
	#
	# If skip_final_fade_cycle is enabled, cleanup happens visibly,
	# so the cutscene author is responsible for making sure nothing
	# visibly jumps or disappears in an awkward way.
	if has_node("/root/FadeOverlay") and not skip_final_fade_cycle:
		await FadeOverlay.fade_out(0.20)


	# Stop enforcing the cinematic camera before clearing focus.
	_clear_camera_lock()

	if player != null and player.has_method("camera_clear_focus"):
		player.camera_clear_focus()


	# Reused scene NPCs return to where they were before the cutscene.
	_restore_original_actor_positions()


	# Optional final player placement.
	# NOTE:
	# With skip_final_fade_cycle enabled, this placement can be visible.
	# Only use player_end / stored end markers when that visual jump
	# is intentional or imperceptible.
	_apply_final_player_placement(
		scene,
		data,
		actors_by_key
	)


	# Restore whatever zoom the player had before the cutscene.
	await _restore_player_cutscene_zoom(
		player,
		0.0
	)


	# Temporary actors still disappear exactly as before.
	# With no ending fade, make sure they are already off-screen
	# or otherwise safe to remove.
	call_deferred("_cleanup_temp_actors")
	await get_tree().process_frame


	# Consume the one-shot keep-black request.
	var keep_black := _keep_screen_black_after_cutscene_once
	_keep_screen_black_after_cutscene_once = false


	# Reveal the world again only when appropriate.
	if has_node("/root/FadeOverlay"):
		if keep_black:
			FadeOverlay.set_black()

		elif not skip_final_fade_cycle:
			await FadeOverlay.fade_in(0.20)

	var finished_id := String(data.id).strip_edges()
	if finished_id != "":
		if GameState != null and GameState.has_method("mark_cutscene_played"):
			GameState.mark_cutscene_played(finished_id)

		cutscene_finished.emit(finished_id)

	_finish_cutscene()

	await get_tree().process_frame

	if _pending_restoration_encounter_path != NodePath("") or _pending_restoration_encounter_id.strip_edges() != "":
		var current_scene := get_tree().current_scene
		if current_scene != null and is_instance_valid(current_scene):
			_start_pending_restoration_encounter(current_scene)

func _finish_cutscene() -> void:
	_set_cutscene_ui_hidden(false)
	
	GameState.unlock_gameplay()
	if not _suppress_time_resume_once:
		_set_time_paused(false)

	_suppress_time_resume_once = false
	_is_playing = false
	_current_cutscene_id = ""

	if GameState != null and GameState.has_method("block_modal_overlays_for"):
		GameState.block_modal_overlays_for(0.45)

	if GameState != null and GameState.has_method("block_item_use_for"):
		GameState.block_item_use_for(0.90)

func _start_pending_restoration_encounter(scene: Node) -> void:
	if scene == null or not is_instance_valid(scene):
		_pending_restoration_encounter_path = NodePath("")
		_pending_restoration_encounter_id = ""
		return

	var path := _pending_restoration_encounter_path
	var encounter_id := _pending_restoration_encounter_id.strip_edges()

	_pending_restoration_encounter_path = NodePath("")
	_pending_restoration_encounter_id = ""

	# rest of function...

	if scene == null:
		return

	var encounter: Node = null

	# 1) Try exact node path first, if provided.
	if path != NodePath(""):
		var direct := scene.get_node_or_null(path)
		if direct != null:
			if direct.has_method("start_encounter"):
				encounter = direct
			else:
				encounter = _find_restoration_encounter_under(direct)

	# 2) If no path worked, search by encounter_id.
	if encounter == null and encounter_id != "":
		encounter = _find_restoration_encounter_by_id(encounter_id)

	# 3) If still nothing, use first restoration encounter in the current scene as fallback.
	# This is useful for simple test scenes with only one encounter.
	if encounter == null:
		encounter = _find_first_restoration_encounter_in_scene(scene)

	if encounter == null:
		push_warning(
			"CutsceneDirector: no restoration encounter found. path="
			+ str(path)
			+ " encounter_id="
			+ encounter_id
		)
		return

	if encounter.has_method("start_encounter"):
		encounter.call("start_encounter")
	else:
		push_warning("CutsceneDirector: found target but it does not have start_encounter(): " + str(encounter.name))

# ------------------------------------------------------------
# Camera lock helpers
# ------------------------------------------------------------

func _set_camera_lock(player: Node, point: Vector2) -> void:
	_camera_lock_player = player
	_camera_lock_point = point
	_camera_lock_active = true

	# Apply immediately too (so it’s correct during fade-in)
	if player != null and player.has_method("camera_focus_on_world_point"):
		player.camera_focus_on_world_point(point)

func _clear_camera_lock() -> void:
	_camera_lock_active = false
	_camera_lock_player = null

# ------------------------------------------------------------
# Helpers: node lookups
# ------------------------------------------------------------

func _get_player() -> Node:
	return get_tree().get_first_node_in_group("player")

func _get_dialogue_ui() -> Node:
	return get_tree().get_first_node_in_group("dialogue_ui")

func _get_marker(scene: Node, path: NodePath) -> Marker2D:
	if path == NodePath(""):
		return null
	var n := scene.get_node_or_null(path)
	return n as Marker2D

func _get_marker_by_id(scene: Node, data: CutsceneData, marker_id: String) -> Marker2D:
	if data == null or data.markers == null:
		return null
	var p := data.markers.get_marker_path(marker_id)
	if p == NodePath(""):
		return null
	return _get_marker(scene, p)

func _get_first_marker_by_ids(scene: Node, data: CutsceneData, ids: Array[String]) -> Marker2D:
	for id in ids:
		var m := _get_marker_by_id(scene, data, id)
		if m != null:
			return m
	return null

func _record_original_actor_positions(actors_by_key: Dictionary) -> void:
	_original_actor_positions.clear()

	for k_any in actors_by_key.keys():
		var k := String(k_any)
		if k == "player":
			continue

		var actor: Variant = actors_by_key.get(k, null)
		if actor == null or not is_instance_valid(actor):
			continue

		# Only record actors that already existed in the scene.
		# Temp-spawned actors will just be cleaned up.
		if _temp_spawned_actors.has(actor):
			continue

		_original_actor_positions.append({
			"node": actor,
			"global_position": actor.global_position
		})

func _place_start_positions(scene: Node, data: CutsceneData, actors_by_key: Dictionary) -> void:
	# Player convention: "player_start"
	var player :Variant= actors_by_key.get("player", null)
	if player != null and is_instance_valid(player):
		var pm := _get_marker_by_id(scene, data, "player_start")
		if pm != null:
			(player as Node).global_position = pm.global_position

	# Everyone else: "<key>_start"
	for k_any in actors_by_key.keys():
		var k := String(k_any)
		if k == "player":
			continue
		var actor: Variant = actors_by_key.get(k, null)
		if actor == null or not is_instance_valid(actor):
			continue

		var m := _get_marker_by_id(scene, data, k + "_start")
		if m != null:
			(actor as Node).global_position = m.global_position

func _place_end_positions(scene: Node, data: CutsceneData, actors_by_key: Dictionary) -> void:
	# Optional convention: if a cutscene has "player_end", place player there
	# during the final fade-out before revealing normal gameplay again.
	var player: Variant = actors_by_key.get("player", null)
	if player != null and is_instance_valid(player):
		var pm := _get_marker_by_id(scene, data, "player_end")
		if pm != null:
			(player as Node).global_position = pm.global_position

# ------------------------------------------------------------
# Helpers: dialogue waiting
# ------------------------------------------------------------

signal _temp_signal

func _await_dialogue_closed(dialogue_ui: Node) -> void:
	if dialogue_ui == null:
		return

	if not dialogue_ui.has_signal("dialogue_closed"):
		await get_tree().create_timer(0.5).timeout
		return

	var cb := Callable(self, "_on_dialogue_closed_temp")
	if not dialogue_ui.is_connected("dialogue_closed", cb):
		dialogue_ui.connect("dialogue_closed", cb, CONNECT_ONE_SHOT)

	await self._temp_signal

func _on_dialogue_closed_temp() -> void:
	emit_signal("_temp_signal")

# ------------------------------------------------------------
# Helpers: effects
# ------------------------------------------------------------

func _apply_effects(effects: Array) -> void:
	if effects == null:
		return

	for e in effects:
		var fx := e as CutsceneEffectData
		if fx == null:
			continue

		match String(fx.effect_type):
			"unlock_travel":
				var tid := String(fx.id).strip_edges()
				if tid != "":
					GameState.unlock_travel(tid)

			"toast":
				var msg := String(fx.msg).strip_edges()
				if msg != "" and QuestEvents != null and QuestEvents.has_signal("toast_requested"):
					QuestEvents.toast_requested.emit(msg, String(fx.kind), float(fx.duration))

			_:
				pass

# ------------------------------------------------------------
# Helpers: actors (spawn/find)
# ------------------------------------------------------------

func _ensure_npc_actor(scene: Node, actor: CutsceneActorData) -> Node:
	var npc_id := String(actor.npc_id).strip_edges()
	if npc_id != "":
		var found := _find_npc_in_scene(npc_id)
		if found != null:
			return found

	var scene_path := String(actor.scene_path).strip_edges()
	if scene_path != "":
		var packed := load(scene_path)
		if packed is PackedScene:
			var inst := (packed as PackedScene).instantiate()
			scene.add_child(inst)

			_temp_spawned_actors.append(inst)

			if npc_id != "" and inst != null:
				inst.set("npc_id", npc_id)

			return inst

	return null

func _find_npc_in_scene(npc_id: String) -> Node:
	var npcs := get_tree().get_nodes_in_group("npc")
	for n in npcs:
		if n == null:
			continue

		if n.has_method("get_npc_id"):
			if String(n.call("get_npc_id")) == npc_id:
				return n

		var v: Variant = n.get("npc_id")
		if v != null and String(v) == npc_id:
			return n

	return null

func _cleanup_temp_actors() -> void:
	for n in _temp_spawned_actors:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_temp_spawned_actors.clear()

func _restore_original_actor_positions() -> void:
	for rec_any in _original_actor_positions:
		var rec: Dictionary = rec_any
		var node: Variant = rec.get("node", null)
		var pos: Variant = rec.get("global_position", null)

		if node != null and is_instance_valid(node) and pos is Vector2:
			node.global_position = pos

	_original_actor_positions.clear()

# ------------------------------------------------------------
# Steps
# ------------------------------------------------------------

func _run_step(step: CutsceneStepData, scene: Node, player: Node, _dialogue_ui: Node, data: CutsceneData, actors_by_key: Dictionary) -> void:
	if step == null:
		return

	match step.step_type:
		CutsceneStepData.StepType.WAIT:
			await get_tree().create_timer(max(step.duration, 0.01)).timeout

		CutsceneStepData.StepType.FOCUS_CAMERA_MARKER:
			var marker := _resolve_marker(
				scene,
				data,
				step
			)

			if marker != null:
				if player.has_method(
					"camera_set_cutscene_ignore_limits"
				):
					player.camera_set_cutscene_ignore_limits(
						step.camera_ignore_limits
					)

				_set_camera_lock(
					player,
					marker.global_position
				)

			await get_tree().create_timer(0.05).timeout

		CutsceneStepData.StepType.MOVE_ACTOR_TO_MARKER:
			var actor: Variant = actors_by_key.get(String(step.actor_key).strip_edges(), null)
			if actor == null or not is_instance_valid(actor):
				return

			var marker2 := _resolve_marker(scene, data, step)
			if marker2 == null:
				return

			var to_pos := marker2.global_position
			var t := scene.create_tween()
			t.tween_property(actor, "global_position", to_pos, max(step.duration, 0.01))

			if step.ease_run:
				t.set_trans(Tween.TRANS_QUAD)
				t.set_ease(Tween.EASE_OUT)
			else:
				t.set_trans(Tween.TRANS_SINE)
				t.set_ease(Tween.EASE_IN_OUT)

			await t.finished

		CutsceneStepData.StepType.DIALOGUE:
			if _dialogue_ui == null:
				await get_tree().process_frame
				return

			# New preferred path: use a full dialogue sequence if present
			if step.dialogue_sequence != null and step.dialogue_sequence.has_beats():
				if _dialogue_ui.has_method("show_dialogue_sequence"):
					_dialogue_ui.show_dialogue_sequence(step.dialogue_sequence)
					await _dialogue_ui.dialogue_closed

					if GameState != null and GameState.has_method("apply_dialogue_sequence_rewards"):
						GameState.apply_dialogue_sequence_rewards(
							step.dialogue_sequence,
							"cutscene_step:%s" % String(data.id)
						)

					await get_tree().process_frame
					return

			# Legacy fallback path
			var speaker_name := step.speaker_name
			var friendship := -1
			var npc_id := ""

			if step.speaker_actor_key.strip_edges() != "":
				if speaker_name.strip_edges() == "":
					speaker_name = _get_display_name_for_actor_key(data, step.speaker_actor_key)

				npc_id = _get_npc_id_for_actor_key(data, step.speaker_actor_key)
				if npc_id != "":
					friendship = int(GameState.get_friendship(npc_id))

			if speaker_name.strip_edges() == "":
				speaker_name = "..."

			var lines: Array[String] = []
			for l in step.lines:
				lines.append(String(l))

			if lines.is_empty():
				lines = ["..."]

			_dialogue_ui.show_dialogue(speaker_name, lines, friendship, npc_id)
			await _dialogue_ui.dialogue_closed
			await get_tree().process_frame
			
		CutsceneStepData.StepType.MOVE_PLAYER_TO_MARKER:
			var marker_player := _resolve_marker(scene, data, step)
			if marker_player == null:
				return

			var to_player_pos := marker_player.global_position

			# If duration is tiny, teleport instantly.
			if step.duration <= 0.01:
				player.global_position = to_player_pos
				_enforce_camera_lock()
				await get_tree().process_frame
				_enforce_camera_lock()
				return

			var tp := scene.create_tween()
			tp.tween_property(
				player,
				"global_position",
				to_player_pos,
				max(step.duration, 0.01)
			)

			if step.ease_run:
				tp.set_trans(Tween.TRANS_QUAD)
				tp.set_ease(Tween.EASE_OUT)
			else:
				tp.set_trans(Tween.TRANS_SINE)
				tp.set_ease(Tween.EASE_IN_OUT)

			while tp != null and tp.is_running():
				_enforce_camera_lock()
				await get_tree().process_frame

			_enforce_camera_lock()

		CutsceneStepData.StepType.START_RESTORATION_ENCOUNTER:
			# Do not start it immediately while the cutscene is still locked/fading.
			# Store it and start after _finish_cutscene().
			_pending_restoration_encounter_path = step.target_path
			_pending_restoration_encounter_id = String(step.encounter_id).strip_edges()
			await get_tree().process_frame
			
		CutsceneStepData.StepType.SHOW_NODE:
			var target_show := _resolve_cutscene_target(scene, step)
			if target_show != null:
				_set_node_visible_safe(target_show, true)
			await get_tree().process_frame

		CutsceneStepData.StepType.HIDE_NODE:
			var target_hide := _resolve_cutscene_target(scene, step)
			if target_hide != null:
				_set_node_visible_safe(target_hide, false)
			await get_tree().process_frame

		CutsceneStepData.StepType.MOVE_NODE_TO_MARKER:
			var target_move := _resolve_cutscene_target(scene, step)
			var marker_move := _resolve_marker(scene, data, step)

			if target_move == null or marker_move == null:
				await get_tree().process_frame
				return

			if not (target_move is Node2D):
				push_warning("CutsceneDirector: MOVE_NODE_TO_MARKER target is not Node2D: " + str(target_move.name))
				await get_tree().process_frame
				return

			var target_2d := target_move as Node2D
			var to_pos := marker_move.global_position

			if step.duration <= 0.01:
				target_2d.global_position = to_pos
				await get_tree().process_frame
				return

			var move_tween := scene.create_tween()
			move_tween.tween_property(target_2d, "global_position", to_pos, max(step.duration, 0.01))

			if step.ease_run:
				move_tween.set_trans(Tween.TRANS_QUAD)
				move_tween.set_ease(Tween.EASE_OUT)
			else:
				move_tween.set_trans(Tween.TRANS_SINE)
				move_tween.set_ease(Tween.EASE_IN_OUT)

			await move_tween.finished

		CutsceneStepData.StepType.SET_NODE_TEXTURE:
			var target_texture := _resolve_cutscene_target(scene, step)
			if target_texture != null:
				_set_node_texture_safe(target_texture, step.texture)
			await get_tree().process_frame

		CutsceneStepData.StepType.SPAWN_SCENE_AT_MARKER:
			var marker_spawn := _resolve_marker(scene, data, step)
			if marker_spawn != null:
				_spawn_scene_at_marker(scene, step, marker_spawn)
			await get_tree().process_frame

		CutsceneStepData.StepType.PLAY_NODE_ANIMATION:
			var target_anim := _resolve_cutscene_target(scene, step)
			if target_anim != null:
				_play_animation_safe(target_anim, step.animation_name)

			if step.duration > 0.01:
				await get_tree().create_timer(step.duration).timeout
			else:
				await get_tree().process_frame
				
		CutsceneStepData.StepType.STORE_PLAYER_END_MARKER:
			_pending_player_end_marker_id = String(step.marker_id).strip_edges()
			await get_tree().process_frame

		CutsceneStepData.StepType.CLEAR_STORED_PLAYER_END_MARKER:
			_pending_player_end_marker_id = ""
			await get_tree().process_frame
		
		CutsceneStepData.StepType.SET_CAMERA_ZOOM:
			await _set_player_cutscene_zoom(player, step.zoom_value, step.duration)

		CutsceneStepData.StepType.RESTORE_CAMERA_ZOOM:
			await _restore_player_cutscene_zoom(player, step.duration) 
			
		CutsceneStepData.StepType.SHOW_ILLUSTRATION:
			await _show_cutscene_illustration(step.texture, step.duration)

		CutsceneStepData.StepType.HIDE_ILLUSTRATION:
			await _hide_cutscene_illustration(step.duration)
		
		CutsceneStepData.StepType.SHOW_OVERHEAD_TEXT:
			var actor_overhead: Variant = actors_by_key.get(String(step.actor_key).strip_edges(), null)

			if actor_overhead == null or not is_instance_valid(actor_overhead):
				await get_tree().process_frame
				return

			var text := String(step.overhead_text).strip_edges()
			var hold_time := float(step.overhead_duration)
			if hold_time <= 0.0:
				hold_time = max(step.duration, 0.5)

			var offset := step.overhead_offset

			if actor_overhead.has_method("show_overhead_text"):
				actor_overhead.call("show_overhead_text", text, hold_time, offset)
			else:
				_show_fallback_overhead_text(actor_overhead, text, hold_time, offset)

			await get_tree().create_timer(hold_time).timeout
		
		CutsceneStepData.StepType.NARRATION:
			await _run_narration_step(step)

		CutsceneStepData.StepType.PAN_CAMERA_TO_MARKER:
			await _pan_camera_to_marker(scene, data, step)

		CutsceneStepData.StepType.WHISPER:
			await _run_whisper_step(step)

		CutsceneStepData.StepType.FADE_TO_BLACK:
			await _run_fade_to_black_step(step)

		CutsceneStepData.StepType.FADE_FROM_BLACK:
			await _run_fade_from_black_step(step)

func _resolve_marker(scene: Node, data: CutsceneData, step: CutsceneStepData) -> Marker2D:
	# New way: marker_id -> markers_by_id
	var mid := String(step.marker_id).strip_edges()
	if mid != "" and data != null and data.markers != null:
		var p := data.markers.get_marker_path(mid)
		if p != NodePath(""):
			return _get_marker(scene, p)

	# Legacy fallback (if you still have old steps with marker_path)
	if step.has_method("get") and step.get("marker_path") != null:
		var legacy: Variant = step.get("marker_path")
		if legacy is NodePath and legacy != NodePath(""):
			return _get_marker(scene, legacy)

	return null

func _set_time_paused(paused: bool) -> void:
	var tm := get_node_or_null("/root/TimeManager")
	if tm == null:
		return
	
	tm.call("set_paused", paused)

func _get_display_name_for_actor_key(data: CutsceneData, actor_key: String) -> String:
	if data == null:
		return ""

	actor_key = actor_key.strip_edges()
	if actor_key == "":
		return ""

	# Special case: player
	if actor_key == "player":
		return "You"

	for a in data.actors:
		if a == null:
			continue

		if String(a.key).strip_edges() == actor_key:
			var dn := String(a.display_name).strip_edges()
			if dn != "":
				return dn

			# Fallback: if no display_name set
			return actor_key.capitalize()

	return actor_key.capitalize()

func _get_npc_id_for_actor_key(data: CutsceneData, actor_key: String) -> String:
	if data == null:
		return ""

	actor_key = actor_key.strip_edges()
	if actor_key == "":
		return ""

	for a in data.actors:
		if a == null:
			continue

		if String(a.key).strip_edges() == actor_key:
			return String(a.npc_id).strip_edges()

	return ""

func _find_restoration_encounter_under(root: Node) -> Node:
	if root == null:
		return null

	if root.has_method("start_encounter"):
		return root

	for child in root.get_children():
		var found := _find_restoration_encounter_under(child)
		if found != null:
			return found

	return null

func _find_restoration_encounter_by_id(encounter_id: String) -> Node:
	encounter_id = encounter_id.strip_edges()
	if encounter_id == "":
		return null

	for n in get_tree().get_nodes_in_group("restoration_encounter"):
		if n == null:
			continue

		var data = n.get("encounter_data")
		if data == null:
			continue

		var id := String(data.get("encounter_id")).strip_edges()
		if id == encounter_id:
			return n

	return null

func _find_first_restoration_encounter_in_scene(scene: Node) -> Node:
	if scene == null:
		return null

	for n in get_tree().get_nodes_in_group("restoration_encounter"):
		if n == null:
			continue

		if scene.is_ancestor_of(n) or n == scene:
			if n.has_method("start_encounter"):
				return n

	return null

func _resolve_cutscene_target(scene: Node, step: CutsceneStepData) -> Node:
	if scene == null or step == null:
		return null

	# 1) Direct path first.
	if step.target_path != NodePath(""):
		var direct := scene.get_node_or_null(step.target_path)
		if direct != null:
			return direct

	# 2) ID fallback.
	var tid := String(step.target_id).strip_edges()
	if tid == "":
		return null

	# Prefer nodes explicitly registered as cutscene targets.
	for n in get_tree().get_nodes_in_group("cutscene_target"):
		if n == null:
			continue
		if not scene.is_ancestor_of(n) and n != scene:
			continue

		var id_from_property := String(n.get("cutscene_id")).strip_edges()
		if id_from_property == tid:
			return n

		if n.has_meta("cutscene_id"):
			var id_from_meta := String(n.get_meta("cutscene_id")).strip_edges()
			if id_from_meta == tid:
				return n

	# 3) Gentle fallback by node name.
	return _find_node_by_name_recursive(scene, tid)

func _find_node_by_name_recursive(root: Node, wanted_name: String) -> Node:
	if root == null:
		return null

	if root.name == wanted_name:
		return root

	for child in root.get_children():
		var found := _find_node_by_name_recursive(child, wanted_name)
		if found != null:
			return found

	return null

func _set_node_visible_safe(target: Node, value: bool) -> void:
	if target == null:
		return

	if target is CanvasItem:
		(target as CanvasItem).visible = value
		return

	# Fallback for nodes/scripts that expose a visible property.
	target.set("visible", value)

func _set_node_texture_safe(target: Node, texture: Texture2D) -> void:
	if target == null or texture == null:
		return

	if target is Sprite2D:
		(target as Sprite2D).texture = texture
		return

	if target is TextureRect:
		(target as TextureRect).texture = texture
		return

	# Fallback for custom nodes with a texture property.
	target.set("texture", texture)

func _spawn_scene_at_marker(scene: Node, step: CutsceneStepData, marker: Marker2D) -> Node:
	if scene == null or step == null or marker == null:
		return null

	var path := String(step.scene_path).strip_edges()
	if path == "":
		return null

	var packed := load(path)
	if not (packed is PackedScene):
		push_warning("CutsceneDirector: failed to load PackedScene: " + path)
		return null

	var inst := (packed as PackedScene).instantiate()
	scene.add_child(inst)

	if String(step.spawned_name).strip_edges() != "":
		inst.name = String(step.spawned_name).strip_edges()

	if inst is Node2D:
		(inst as Node2D).global_position = marker.global_position

	if not step.keep_spawned_after_cutscene:
		_temp_spawned_actors.append(inst)

	return inst

func _play_animation_safe(target: Node, animation_name: String) -> void:
	if target == null:
		return

	animation_name = animation_name.strip_edges()
	if animation_name == "":
		return

	if target is AnimationPlayer:
		(target as AnimationPlayer).play(animation_name)
		return

	var anim := target.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim != null:
		anim.play(animation_name)
		return

	if target.has_method("play"):
		target.call("play", animation_name)

func _apply_final_player_placement(scene: Node, data: CutsceneData, actors_by_key: Dictionary) -> void:
	var player: Variant = actors_by_key.get("player", null)
	if player == null or not is_instance_valid(player):
		return

	# First priority: explicit stored end marker from a cutscene step.
	var marker_id := _pending_player_end_marker_id.strip_edges()

	# Second priority: your existing optional convention.
	# If a cutscene has a marker called player_end, use it.
	if marker_id == "":
		marker_id = "player_end"

	var pm := _get_marker_by_id(scene, data, marker_id)
	if pm != null:
		(player as Node2D).global_position = pm.global_position

	_pending_player_end_marker_id = ""

func _store_cutscene_original_zoom(player: Node) -> void:
	if player == null:
		return

	if _has_cutscene_original_zoom:
		return

	if player.has_method("camera_get_target_zoom"):
		_cutscene_original_zoom = float(player.call("camera_get_target_zoom"))
	else:
		_cutscene_original_zoom = 1.0

	_has_cutscene_original_zoom = true

func _set_player_cutscene_zoom(player: Node, zoom_value: float, duration: float = 0.0) -> void:
	if player == null:
		return

	_store_cutscene_original_zoom(player)

	if player.has_method("camera_set_zoom_for_cutscene"):
		await player.call("camera_set_zoom_for_cutscene", zoom_value, duration)

func _restore_player_cutscene_zoom(player: Node, duration: float = 0.0) -> void:
	if player == null:
		return

	if not _has_cutscene_original_zoom:
		return

	if player.has_method("camera_set_zoom_for_cutscene"):
		await player.call("camera_set_zoom_for_cutscene", _cutscene_original_zoom, duration)

	_has_cutscene_original_zoom = false

func _get_cutscene_illustration_overlay() -> Node:
	return get_tree().get_first_node_in_group("cutscene_illustration_overlay")

func _show_cutscene_illustration(texture: Texture2D, fade_seconds: float = 0.25) -> void:
	var overlay := _get_cutscene_illustration_overlay()
	if overlay == null:
		push_warning("CutsceneDirector: no CutsceneIllustrationOverlay found in scene.")
		return

	if overlay.has_method("show_illustration"):
		await overlay.call("show_illustration", texture, fade_seconds)

func _hide_cutscene_illustration(fade_seconds: float = 0.25) -> void:
	var overlay := _get_cutscene_illustration_overlay()
	if overlay == null:
		return

	if overlay.has_method("hide_illustration"):
		await overlay.call("hide_illustration", fade_seconds)

func _apply_cutscene_completion_rewards(data: CutsceneData) -> void:
	if data == null:
		return

	if not data.has_completion_rewards():
		return

	var cutscene_id := String(data.id).strip_edges()
	var reward_flag := ""
	if cutscene_id != "":
		reward_flag = "cutscene_reward_claimed:" + cutscene_id

	# Safety: prevent repeated rewards if the same cutscene is replayed.
	if data.rewards_once and reward_flag != "":
		if GameState != null and GameState.has_method("has_flag"):
			if bool(GameState.has_flag(reward_flag)):
				# print("[CutsceneReward] Already claimed for cutscene:", cutscene_id)
				return

	# Apply normal reward dictionary: money, items, flags, tools, spawns.
	var reward := data.get_completion_reward_dict()
	if not reward.is_empty():
		if GameState != null and GameState.has_method("apply_reward_dict"):
			GameState.apply_reward_dict(reward, "cutscene:%s" % cutscene_id)
		else:
			push_warning("CutsceneDirector: GameState.apply_reward_dict missing; cannot apply cutscene reward.")

	# Add quest rewards, if any.
	for qd in data.reward_quests:
		if qd == null:
			continue

		var quest_id := String(qd.id).strip_edges()
		if quest_id == "":
			continue

		if GameState.active_quests.has(quest_id):
			continue
		if GameState.completed_quests.has(quest_id):
			continue

		if GameState.has_method("add_quest"):
			GameState.add_quest(qd.to_dict())
		else:
			push_warning("CutsceneDirector: GameState.add_quest missing; cannot add quest: " + quest_id)

	# Mark cutscene rewards as claimed only after everything has been attempted.
	if data.rewards_once and reward_flag != "":
		if GameState != null and GameState.has_method("set_flag"):
			GameState.set_flag(reward_flag, true)

	if QuestEvents != null and QuestEvents.has_signal("quest_state_changed"):
		QuestEvents.quest_state_changed.emit()

func _show_fallback_overhead_text(actor: Node, text: String, duration: float, offset: Vector2 = Vector2(0, -34)) -> void:
	if actor == null:
		return

	text = text.strip_edges()
	if text == "":
		return

	if not (actor is Node2D):
		return

	var label := Label.new()
	label.text = text
	label.z_index = 999
	label.position = offset
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	(actor as Node2D).add_child(label)

	var tween := (actor as Node).create_tween()
	tween.tween_property(label, "position", offset + Vector2(0, -8), max(duration, 0.05))
	tween.parallel().tween_property(label, "modulate:a", 0.0, max(duration, 0.05))

	await tween.finished

	if label != null and is_instance_valid(label):
		label.queue_free()

func can_play_cutscene_in_current_scene(id: String) -> bool:
	id = id.strip_edges()
	if id == "":
		return false

	var path := _get_cutscene_path(id)
	if path == "":
		return false

	var data := load(path) as CutsceneData
	if data == null:
		return false

	var desired_scene := String(data.scene_name).strip_edges()
	if desired_scene == "":
		return true

	var scene := get_tree().current_scene
	if scene == null:
		return false

	return scene.name == desired_scene


func play_cutscene_from_black(id: String) -> void:
	# Used when travel already faded to black.
	# This avoids the extra visible fade cycle:
	# travel fade-in -> cutscene fade-out -> cutscene fade-in.
	_skip_initial_fade_out_once = true
	play_cutscene(id)

func _get_narration_ui() -> Node:
	return get_tree().get_first_node_in_group("narration_ui")

func _get_whisper_ui() -> Node:
	return get_tree().get_first_node_in_group("whisper_ui")

func _run_narration_step(step: CutsceneStepData) -> void:
	
	if step == null:
		return

	var text := String(step.narration_text).strip_edges()

	if text == "" and step.lines.size() > 0:
		text = String(step.lines[0]).strip_edges()

	if text == "":
		text = "..."

	var narration_ui := _get_narration_ui()

	if narration_ui == null:
		push_warning("CutsceneDirector: no narration_ui found for narration step.")
		await get_tree().create_timer(max(step.duration, 0.25)).timeout
		return
	
	_enforce_camera_lock()
	await get_tree().process_frame
	_enforce_camera_lock()

	# IMPORTANT: use the cutscene-safe method first.
	if narration_ui.has_method("show_text_for_cutscene_and_wait"):
		await narration_ui.call("show_text_for_cutscene_and_wait", text)
	
		await get_tree().process_frame
		_enforce_camera_lock()
		return

	if narration_ui.has_method("show_text_and_wait"):
		await narration_ui.call("show_text_and_wait", text)
		return

	if narration_ui.has_method("show_text"):
		narration_ui.call("show_text", text)

		if narration_ui.has_signal("narration_closed"):
			await narration_ui.narration_closed
		else:
			await get_tree().create_timer(max(step.duration, 1.0)).timeout

		return

	push_warning("CutsceneDirector: narration_ui has no show_text method.")
	await get_tree().create_timer(max(step.duration, 0.25)).timeout

func _set_cutscene_ui_hidden(hidden: bool) -> void:
	if not hide_ui_during_cutscenes:
		return

	if DevlogCaptureMode == null:
		return

	if not DevlogCaptureMode.has_method("set_capture_ui_hidden"):
		return

	if hidden:
		# Only restore later if the cutscene was the thing that hid it.
		# If you had manually hidden UI already with F10, don't undo that.
		if not bool(DevlogCaptureMode.ui_hidden):
			_cutscene_hid_ui = true
			DevlogCaptureMode.set_capture_ui_hidden(true)
		return

	if _cutscene_hid_ui:
		DevlogCaptureMode.set_capture_ui_hidden(false)

	_cutscene_hid_ui = false

func _pan_camera_to_marker(
	scene: Node,
	data: CutsceneData,
	step: CutsceneStepData
) -> void:
	var marker := _resolve_marker(scene, data, step)

	if marker == null:
		push_warning(
			"CutsceneDirector: PAN_CAMERA_TO_MARKER missing marker: "
			+ step.marker_id
		)
		return

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
		
	if player.has_method(
		"camera_set_cutscene_ignore_limits"
	):
		player.camera_set_cutscene_ignore_limits(
			step.camera_ignore_limits
		)

	var start_point := _get_current_cutscene_camera_point(player)
	var end_point := marker.global_position

	_camera_lock_active = true
	_camera_lock_player = player
	_camera_lock_point = start_point

	if player.has_method("camera_focus_on_world_point"):
		player.camera_focus_on_world_point(start_point)

	var pan_duration :Variant= max(step.duration, 0.01)

	var tween := create_tween()
	tween.tween_method(
		_set_cutscene_camera_point,
		start_point,
		end_point,
		pan_duration
	)

	if step.ease_run:
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
	else:
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_IN_OUT)

	while tween != null and tween.is_running():
		_enforce_camera_lock()
		await get_tree().process_frame

	_camera_lock_point = end_point
	_enforce_camera_lock()
	
func _set_cutscene_camera_point(point: Vector2) -> void:
	_camera_lock_point = point
	_enforce_camera_lock()


func _get_current_cutscene_camera_point(player: Node) -> Vector2:
	# If the cutscene camera is already locked, continue from there.
	if _camera_lock_active:
		return _camera_lock_point

	# Try the actual active Camera2D first.
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		return camera.global_position

	# Fallback to player position.
	if player is Node2D:
		return (player as Node2D).global_position

	return Vector2.ZERO

func play_cutscene_from_black_keep_black(id: String, suppress_time_resume: bool = true) -> void:
	# Used by passout / sleep-like flows.
	# The screen is already black, so skip the initial fade-out.
	# When the cutscene ends, do NOT reveal the current scene.
	# Let the caller decide what scene/summary appears next.
	_skip_initial_fade_out_once = true
	_keep_screen_black_after_cutscene_once = true
	_suppress_time_resume_once = suppress_time_resume

	play_cutscene(id)

func _run_whisper_step(step: CutsceneStepData) -> void:
	if step == null:
		return

	var phrases: Array[String] = []

	for phrase in step.whisper_phrases:
		var cleaned := String(phrase).strip_edges()

		if cleaned != "":
			phrases.append(cleaned)

	if phrases.is_empty():
		push_warning(
			"CutsceneDirector: WHISPER step has no phrases."
		)
		return

	var whisper_ui := _get_whisper_ui()

	if whisper_ui == null:
		push_warning(
			"CutsceneDirector: no whisper_ui found for WHISPER step."
		)

		# Do not completely destroy the cutscene timing if the UI
		# was accidentally forgotten from a scene.
		var phrase_duration :Variant= (
			max(step.whisper_fade_in_duration, 0.0)
			+ max(step.whisper_hold_duration, 0.0)
			+ max(step.whisper_fade_out_duration, 0.0)
			+ max(step.whisper_gap_duration, 0.0)
		)

		var fallback_duration :Variant= (
			phrase_duration * phrases.size()
		)

		await get_tree().create_timer(
			max(fallback_duration, 0.25)
		).timeout

		return

	# Keep your existing cinematic camera locked firmly
	# while UI is appearing.
	_enforce_camera_lock()
	await get_tree().process_frame
	_enforce_camera_lock()
	
	# Optional: allow the world to reveal itself while
	# the whisper continues independently above it.
	if step.whisper_fade_from_black_during:
		_start_whisper_world_fade_async(
			step.whisper_world_fade_delay,
			step.whisper_world_fade_duration
		)

	if whisper_ui.has_method(
		"show_sequence_for_cutscene_and_wait"
	):
		await whisper_ui.call(
			"show_sequence_for_cutscene_and_wait",
			phrases,
			step.whisper_fade_in_duration,
			step.whisper_hold_duration,
			step.whisper_fade_out_duration,
			step.whisper_gap_duration
		)

		await get_tree().process_frame

		_enforce_camera_lock()

		return

	push_warning(
		"CutsceneDirector: WhisperOverlay is missing "
		+ "show_sequence_for_cutscene_and_wait()."
	)

func _run_fade_to_black_step(step: CutsceneStepData) -> void:
	if step == null:
		return

	if not has_node("/root/FadeOverlay"):
		push_warning(
			"CutsceneDirector: FadeOverlay missing for FADE_TO_BLACK step."
		)
		return

	var fade_duration :Variant= max(step.duration, 0.01)

	await FadeOverlay.fade_out(fade_duration)


func _run_fade_from_black_step(step: CutsceneStepData) -> void:
	if step == null:
		return

	if not has_node("/root/FadeOverlay"):
		push_warning(
			"CutsceneDirector: FadeOverlay missing for FADE_FROM_BLACK step."
		)
		return

	var fade_duration :Variant= max(step.duration, 0.01)

	await FadeOverlay.fade_in(fade_duration)

func _start_whisper_world_fade_async(
	delay: float,
	duration: float
) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	if not has_node("/root/FadeOverlay"):
		push_warning(
			"CutsceneDirector: FadeOverlay missing for whisper world fade."
		)
		return

	await FadeOverlay.fade_in(
		max(duration, 0.01)
	)

func is_playing_cutscene_id(cutscene_id: String) -> bool:
	cutscene_id = cutscene_id.strip_edges()

	if cutscene_id == "":
		return false

	return (
		_is_playing
		and _current_cutscene_id == cutscene_id
	)
