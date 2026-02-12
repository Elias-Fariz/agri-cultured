# res://autoload/CutsceneDirector.gd
extends Node

# Cozy goals:
# - One cutscene at a time
# - Always unlock gameplay, even if something goes wrong
# - Uses DialogueUI + Player camera helpers you already have

var _is_playing: bool = false
var _queued_id: String = ""

# Nodes we spawned for the cutscene (so we can remove them after)
var _temp_spawned_actors: Array[Node] = []

# Cutscene registry: id -> .tres path
var _cutscene_paths := {
	"heart_intro": "res://data/cutscenes/heart_intro.tres",
	"greeting_intro": "res://data/cutscenes/greeting_intro.tres",
}


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
	# Run async without blocking callers
	call_deferred("_run_cutscene_impl", data)


func _run_cutscene_impl(data: CutsceneData) -> void:
	# Always unlock gameplay at the end no matter what.
	GameState.lock_gameplay()

	# Wait a frame so current_scene is stable (especially after scene loads)
	await get_tree().process_frame

	var scene := get_tree().current_scene
	if scene == null:
		_finish_cutscene()
		return

	# Optional: enforce scene
	var desired_scene := String(data.scene_name).strip_edges()
	if desired_scene != "" and scene.name != desired_scene:
		# Not the right place; re-queue gently rather than forcing
		_queued_id = String(data.id)
		call_deferred("_cleanup_temp_actors")
		_finish_cutscene()
		return

	# 1) Resolve player + dialogue UI
	var player := _get_player()
	var dialogue_ui := _get_dialogue_ui()

	if player == null or dialogue_ui == null:
		push_warning("CutsceneDirector: missing player or dialogue_ui.")
		call_deferred("_cleanup_temp_actors")
		_finish_cutscene()
		return

	# 2) Resolve markers (Resource-driven)
	var player_marker: Marker2D = null
	var focus_marker: Marker2D = null
	var npc_spots: Dictionary = {}

	if data.markers != null:
		player_marker = _get_marker(scene, data.markers.player_spot)
		focus_marker  = _get_marker(scene, data.markers.camera_focus)
		npc_spots = data.markers.npc_spots if data.markers.npc_spots != null else {}
	else:
		push_warning("CutsceneDirector: data.markers is null for cutscene: " + String(data.id))

	# 3) Resolve/ensure actors (Resource-driven)
	var actors_by_key: Dictionary = {}

	# Always provide player under its key if present in data; otherwise still store for camera/dialogue
	actors_by_key["player"] = player

	# Spawn/find all configured actors
	for a in data.actors:
		if a == null:
			continue

		var key := String(a.key).strip_edges()
		if key == "":
			continue

		if String(a.actor_type) == "player":
			actors_by_key[key] = player
			continue

		# NPC actor
		var npc_node := _ensure_npc_actor(scene, a)
		actors_by_key[key] = npc_node

	# 4) Stage positions (instant snap)
	if player_marker != null:
		player.global_position = player_marker.global_position

	# Move each npc actor to its spot if provided
	for k in npc_spots.keys():
		var actor_key := String(k)
		var path_variant: Variant = npc_spots[k]
		if not (path_variant is NodePath):
			continue

		var marker := _get_marker(scene, path_variant as NodePath)
		if marker == null:
			continue

		var actor :Variant= actors_by_key.get(actor_key, null)
		if actor != null and is_instance_valid(actor):
			(actor as Node).global_position = marker.global_position

	# 5) Camera focus (smooth) toward focus marker, else speaker, else player
	var focus_point: Vector2 = player.global_position
	if focus_marker != null:
		focus_point = focus_marker.global_position
	elif data.dialogue != null:
		var spk_key := String(data.dialogue.speaker_actor_key).strip_edges()
		var spk :Variant= actors_by_key.get(spk_key, null)
		if spk != null and is_instance_valid(spk):
			focus_point = (spk as Node).global_position

	if player.has_method("camera_focus_on_world_point"):
		player.camera_focus_on_world_point(focus_point)

	await get_tree().create_timer(0.2).timeout

	# 6) Dialogue (Resource-driven)
	# Run step list (dialogue, moves, waits, etc.)
	if data.steps != null and data.steps.size() > 0:
		for step in data.steps:
			await _run_step(data, step, scene, player, dialogue_ui, actors_by_key)
	else:
		# Fallback: if no steps, do nothing (or keep your old dialogue behavior)
		pass

	# 7) Effects / rewards (Resource-driven)
	_apply_effects(data.effects)

	# 8) Cleanup camera + end
	if player != null and player.has_method("camera_clear_focus"):
		player.camera_clear_focus()

	# Defer cleanup so we don't free nodes mid-frame while references are still settling.
	call_deferred("_cleanup_temp_actors")
	_finish_cutscene()


func _finish_cutscene() -> void:
	GameState.unlock_gameplay()
	_is_playing = false


# ------------------------------------------------------------
# Helpers: finding nodes
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


# ------------------------------------------------------------
# Helpers: Dialogue waiting
# ------------------------------------------------------------

var _temp_signal_fired := false
signal _temp_signal

func _await_dialogue_closed(dialogue_ui: Node) -> void:
	if dialogue_ui == null:
		return

	if not dialogue_ui.has_signal("dialogue_closed"):
		# Fallback: don't soft-lock if the signal isn't present
		await get_tree().create_timer(0.5).timeout
		return

	var cb := Callable(self, "_on_dialogue_closed_temp")
	if not dialogue_ui.is_connected("dialogue_closed", cb):
		dialogue_ui.connect("dialogue_closed", cb, CONNECT_ONE_SHOT)

	_temp_signal_fired = false
	await self._temp_signal


func _on_dialogue_closed_temp() -> void:
	_temp_signal_fired = true
	emit_signal("_temp_signal")


# ------------------------------------------------------------
# Helpers: Effects (Resource-driven)
# ------------------------------------------------------------

func _apply_effects(effects: Array) -> void:
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
				# future: more effect types
				pass


# ------------------------------------------------------------
# Helpers: Actors (spawn/find)
# ------------------------------------------------------------

func _ensure_npc_actor(scene: Node, actor: CutsceneActorData) -> Node:
	# 1) Try find an existing NPC in the scene by npc_id (preferred)
	var npc_id := String(actor.npc_id).strip_edges()
	if npc_id != "":
		var found := _find_npc_in_scene(npc_id)
		if found != null:
			return found

	# 2) If a scene_path is provided, spawn it temporarily
	var scene_path := String(actor.scene_path).strip_edges()
	if scene_path != "":
		var packed := load(scene_path)
		if packed is PackedScene:
			var inst := (packed as PackedScene).instantiate()
			scene.add_child(inst)

			# Track this as a temporary cutscene actor so we can remove it after.
			_temp_spawned_actors.append(inst)

			# If the NPC supports npc_id, set it
			if npc_id != "" and inst != null:
				# Safe set (won't crash if property doesn't exist)
				inst.set("npc_id", npc_id)

			return inst

	# 3) Otherwise: no NPC available (fallback)
	return null


func _find_npc_in_scene(npc_id: String) -> Node:
	# We look for nodes in group "npc" and try to match:
	# - exported var npc_id
	# - or get_npc_id() method
	var npcs := get_tree().get_nodes_in_group("npc")
	for n in npcs:
		if n == null:
			continue

		if n.has_method("get_npc_id"):
			if String(n.call("get_npc_id")) == npc_id:
				return n

		# Safe get: returns null if property doesn't exist
		var v: Variant = n.get("npc_id")
		if v != null and String(v) == npc_id:
			return n

	return null


func _cleanup_temp_actors() -> void:
	# Free only what we spawned.
	for n in _temp_spawned_actors:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_temp_spawned_actors.clear()


# ------------------------------------------------------------
# Helpers: speaker display name + npc_id lookup by actor key
# ------------------------------------------------------------

func _get_display_name_for_actor_key(data: CutsceneData, actor_key: String) -> String:
	if actor_key == "player":
		return "You"

	for a in data.actors:
		if a == null:
			continue
		if String(a.key).strip_edges() == actor_key:
			var dn := String(a.display_name).strip_edges()
			if dn != "":
				return dn
			# fallback if not set:
			if String(a.actor_type) == "npc":
				return "…"
	return "…"


func _get_npc_id_for_actor_key(data: CutsceneData, actor_key: String) -> String:
	for a in data.actors:
		if a == null:
			continue
		if String(a.key).strip_edges() == actor_key:
			return String(a.npc_id).strip_edges()
	return ""

func _run_step(data: CutsceneData, step: CutsceneStepData, scene: Node, player: Node, dialogue_ui: Node, actors: Dictionary) -> void:
	if step == null:
		return

	match step.step_type:
		CutsceneStepData.StepType.WAIT:
			await get_tree().create_timer(max(step.duration, 0.01)).timeout

		CutsceneStepData.StepType.FOCUS_CAMERA_MARKER:
			var p := _resolve_marker_path(data, step)
			var m := _get_marker(scene, p)
			if m != null and player != null and player.has_method("camera_focus_on_world_point"):
				player.camera_focus_on_world_point(m.global_position)
			await get_tree().create_timer(0.05).timeout

		CutsceneStepData.StepType.MOVE_ACTOR_TO_MARKER:
			var a: Variant = actors.get(step.actor_key, null)
			if a == null or not is_instance_valid(a):
				return

			var p2 := _resolve_marker_path(data, step)
			var m2 := _get_marker(scene, p2)
			if m2 == null:
				return

			var to_pos := m2.global_position
			var t := scene.create_tween()
			t.tween_property(a, "global_position", to_pos, max(step.duration, 0.01))

			if step.ease_run:
				t.set_trans(Tween.TRANS_QUAD)
				t.set_ease(Tween.EASE_OUT)
			else:
				t.set_trans(Tween.TRANS_SINE)
				t.set_ease(Tween.EASE_IN_OUT)

			await t.finished
	
		CutsceneStepData.StepType.DIALOGUE:
			var speaker_key := step.speaker_actor_key
			var speaker_name := step.speaker_name

			if speaker_name.strip_edges() == "":
				# fallback: if actor exists and has display_name, else key title-case
				speaker_name = speaker_key.capitalize()

			var friendship := -1
			# optional: if your NPCs track npc_id and friendship, you can add:
			# if speaker_key in ["mayor", "lia"]:
			#   ...

			if dialogue_ui != null and dialogue_ui.has_method("show_dialogue"):
				dialogue_ui.show_dialogue(speaker_name, step.lines, friendship)
				await _await_dialogue_closed(dialogue_ui)

func _resolve_marker_path(data: CutsceneData, step: CutsceneStepData) -> NodePath:
	# New preferred: marker_id -> marker_set lookup
	if step.marker_id.strip_edges() != "" and data != null and data.markers != null:
		var p := data.markers.resolve_marker(step.marker_id)
		if p != NodePath(""):
			return p

	# Old fallback: direct marker_path on the step
	return step.marker_path
