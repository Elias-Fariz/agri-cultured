extends Area2D

@export var target_scene_path: String = ""
@export var target_spawn_tag: String = ""

# Travel unlock ID.
# If set, this pad can be unlocked by GameState.unlock_travel(travel_id)
@export var travel_id: String = ""

# Locking rules
@export var required_completed_quests: Array[String] = []
@export var require_claimed: bool = true

# Prompt text
@export var prompt_travel: String = "E: Travel"
@export var prompt_locked: String = "E: Check"

# Prompt priority
@export var prompt_priority: int = 30
@export_multiline var locked_text: String = "This path is locked for now."

# Optional visuals controlled by lock state.
# Example:
# locked_visual_path = BlockerVisual
# unlocked_visual_path = OpenPathSparkle / Arrow / RootGlow
@export var locked_visual_path: NodePath
@export var unlocked_visual_path: NodePath

# If true, the travel area remains interactable while locked,
# so the player can press E: Check and get the locked_text.
# Recommended: true.
@export var can_check_while_locked: bool = true

# Transition feel
@export var use_custom_fade_times: bool = false
@export var fade_out_time: float = 0.18
@export var fade_in_time: float = 0.24
@export var frames_to_wait_after_scene_change: int = 4

# Optional travel sound.
@export var travel_sfx: AudioStream
@export var travel_sfx_volume_db: float = 0.0
@export var travel_sfx_delay: float = 0.0

# Optional locked/check sound.
@export var locked_sfx: AudioStream
@export var locked_sfx_volume_db: float = 0.0

var _last_unlocked_state: bool = false


func _ready() -> void:
	_last_unlocked_state = _is_unlocked()
	_refresh_lock_visuals()


func _process(_delta: float) -> void:
	# This lets the visual update automatically if a quest/cutscene unlocks travel
	# while the scene is still loaded.
	var unlocked_now := _is_unlocked()
	if unlocked_now != _last_unlocked_state:
		_last_unlocked_state = unlocked_now
		_refresh_lock_visuals()


func get_interact_priority(_context: Node = null) -> int:
	return prompt_priority


func get_interact_prompt(_context: Node = null) -> String:
	if _is_unlocked():
		return prompt_travel

	if can_check_while_locked:
		return prompt_locked

	return ""


func interact() -> void:
	if GameState != null and "is_scene_traveling" in GameState:
		if GameState.is_scene_traveling:
			return

	if not _is_unlocked():
		_on_locked_interact()
		return

	if target_scene_path.strip_edges() == "":
		return

	if GameState == null or not GameState.has_method("travel_to_scene"):
		push_warning("SceneTravelArea: GameState.travel_to_scene() is missing.")
		return

	if use_custom_fade_times:
		GameState.travel_to_scene(
			target_scene_path,
			target_spawn_tag,
			fade_out_time,
			fade_in_time,
			frames_to_wait_after_scene_change,
			travel_sfx,
			travel_sfx_volume_db,
			travel_sfx_delay
		)
	else:
		GameState.travel_to_scene(
			target_scene_path,
			target_spawn_tag,
			-1.0,
			-1.0,
			-1,
			travel_sfx,
			travel_sfx_volume_db,
			travel_sfx_delay
		)


func _on_locked_interact() -> void:
	if not can_check_while_locked:
		return

	if locked_sfx != null:
		_play_local_sfx(locked_sfx, locked_sfx_volume_db)

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(locked_text, "info", 2.5)


func _is_unlocked() -> bool:
	var tid := travel_id.strip_edges()

	# 1) Travel ID unlock.
	if tid != "":
		if GameState != null and GameState.has_method("is_travel_unlocked"):
			if bool(GameState.call("is_travel_unlocked", tid)):
				return true

	# 2) Quest-based gating.
	if required_completed_quests.is_empty():
		# If there is no travel_id unlock AND no quest requirements, it's open.
		# If travel_id exists but is not unlocked, stay locked.
		return tid == ""

	for qid in required_completed_quests:
		var id := String(qid).strip_edges()
		if id == "":
			continue

		if not GameState.completed_quests.has(id):
			return false

		if require_claimed:
			var q: Dictionary = GameState.completed_quests[id]
			if not bool(q.get("claimed", false)):
				return false

	return true


func _refresh_lock_visuals() -> void:
	var unlocked := _is_unlocked()

	var locked_visual := get_node_or_null(locked_visual_path)
	var unlocked_visual := get_node_or_null(unlocked_visual_path)

	_set_canvas_visible(locked_visual, not unlocked)
	_set_canvas_visible(unlocked_visual, unlocked)


func _set_canvas_visible(node: Node, value: bool) -> void:
	if node == null:
		return

	if node is CanvasItem:
		(node as CanvasItem).visible = value
		return

	# If the assigned path is a parent Node2D/Node with visual children,
	# toggle all CanvasItem descendants too.
	for child in node.get_children():
		_set_canvas_visible(child, value)


func _play_local_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return

	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.volume_db = volume_db
	add_child(p)

	p.play()

	await p.finished

	if p != null and is_instance_valid(p):
		p.queue_free()
