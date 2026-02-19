# res://autoload/CutsceneDirector.gd
extends Node

var _is_playing: bool = false
var _queued_id: String = ""

# Nodes we spawned for the cutscene (so we can remove them after)
var _temp_spawned_actors: Array[Node] = []

# Camera lock (prevents snap-back)
var _camera_lock_active: bool = false
var _camera_lock_point: Vector2 = Vector2.ZERO
var _camera_lock_player: Node = null

# Cutscene registry: id -> .tres path
var _cutscene_paths := {
	"heart_intro": "res://data/cutscenes/heart_intro.tres",
	"greeting_intro": "res://data/cutscenes/greeting_intro.tres",
}

func _process(_delta: float) -> void:
	# Keep camera steady while a cutscene is playing.
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

func try_play_queued() -> void:
	if _is_playing:
		return
	if _queued_id.strip_edges() == "":
		return

	var id := _queued_id
	_queued_id = ""
	play_cutscene(id)

func play_cutscene(id: String) -> void:
	if _is_playing:
		return

	id = id.strip_edges()
	var path := String(_cutscene_paths.get(id, ""))
	if path == "":
		push_warning("CutsceneDirector: no resource path for cutscene id: " + id)
		return

	var data := load(path) as CutsceneData
	if data == null:
		push_warning("CutsceneDirector: failed to load cutscene resource: " + path)
		return

	_is_playing = true
	_run_cutscene_async(data)

# ------------------------------------------------------------
# Internals
# ------------------------------------------------------------

func _run_cutscene_async(data: CutsceneData) -> void:
	call_deferred("_run_cutscene_impl", data)

func _run_cutscene_impl(data: CutsceneData) -> void:
	GameState.lock_gameplay()
	_set_time_paused(true)

	# Make sure current_scene is stable
	await get_tree().process_frame

	var scene := get_tree().current_scene
	if scene == null:
		_finish_cutscene()
		return

	# Optional: enforce scene name
	var desired_scene := String(data.scene_name).strip_edges()
	if desired_scene != "" and scene.name != desired_scene:
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

	# 1) Fade OUT immediately (hide spawning/teleporting)
	if has_node("/root/FadeOverlay"):
		await FadeOverlay.fade_out(0.15)

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

	# 5) Fade IN to reveal the staged scene
	if has_node("/root/FadeOverlay"):
		await FadeOverlay.fade_in(0.25)

	await get_tree().create_timer(0.1).timeout

	# 6) Run steps
	if data.steps != null and data.steps.size() > 0:
		for step in data.steps:
			await _run_step(step, scene, player, dialogue_ui, data, actors_by_key)

	# 7) Apply effects
	_apply_effects(data.effects)

	# 8) Fade OUT, cleanup temp actors, fade IN, unlock
	if has_node("/root/FadeOverlay"):
		await FadeOverlay.fade_out(0.20)

	# Stop enforcing camera before clearing focus
	_clear_camera_lock()

	if player != null and player.has_method("camera_clear_focus"):
		player.camera_clear_focus()

	call_deferred("_cleanup_temp_actors")
	await get_tree().process_frame

	if has_node("/root/FadeOverlay"):
		await FadeOverlay.fade_in(0.20)

	_finish_cutscene()

func _finish_cutscene() -> void:
	GameState.unlock_gameplay()
	_set_time_paused(false)
	_is_playing = false

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

# ------------------------------------------------------------
# Steps
# ------------------------------------------------------------

func _run_step(step: CutsceneStepData, scene: Node, player: Node, dialogue_ui: Node, data: CutsceneData, actors_by_key: Dictionary) -> void:
	if step == null:
		return

	match step.step_type:
		CutsceneStepData.StepType.WAIT:
			await get_tree().create_timer(max(step.duration, 0.01)).timeout

		CutsceneStepData.StepType.FOCUS_CAMERA_MARKER:
			var marker := _resolve_marker(scene, data, step)
			if marker != null:
				# IMPORTANT: update the camera lock point so it stays there.
				_set_camera_lock(player, marker.global_position)
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
			var speaker_key := String(step.speaker_actor_key).strip_edges()
			if speaker_key == "":
				# If empty, don’t crash—just do nothing.
				return

			# 1) Decide speaker display name
			var speaker_name := String(step.speaker_name).strip_edges()
			if speaker_name == "":
				# Prefer actor display name from resource (so it matches NPC dialogue naming)
				speaker_name = _get_display_name_for_actor_key(data, speaker_key)
				if speaker_name.strip_edges() == "":
					speaker_name = speaker_key.capitalize()

			# 2) Friendship (only if this speaker maps to an npc_id)
			var friendship := -1
			var npc_id := _get_npc_id_for_actor_key(data, speaker_key)
			if npc_id != "":
				friendship = int(GameState.get_friendship(npc_id))

			# 3) Ensure lines are an Array[String]
			var lines: Array[String] = []
			for l in step.lines:
				lines.append(String(l))

			if lines.is_empty():
				return

			# 4) Use YOUR DialogueUI exactly as normal
			if dialogue_ui != null and dialogue_ui.has_method("show_dialogue"):
				dialogue_ui.show_dialogue(speaker_name, lines, friendship, npc_id)
				await _await_dialogue_closed(dialogue_ui)

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
