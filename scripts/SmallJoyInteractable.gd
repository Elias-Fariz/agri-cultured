extends Interactable
class_name SmallJoyInteractable

@export var persist_interaction_count: bool = true
@export var once_per_day: bool = false

@export var animation_player_path: NodePath
@export var animation_name: String = ""

@export var sfx_player_path: NodePath
@export var sfx: AudioStream
@export var sfx_volume_db: float = 0.0
@export var sfx_pitch_min: float = 0.96
@export var sfx_pitch_max: float = 1.04

@export var toast_text: String = ""
@export var toast_kind: String = "info"
@export var toast_duration: float = 1.5

@export var overhead_text: String = ""
@export var overhead_duration: float = 1.0

@export var emit_object_interacted: bool = false
@export var quest_target_id: String = ""
@export var quest_amount: int = 1

var _is_playing: bool = false


func get_interact_prompt(_context: Node = null) -> String:
	if not can_interact():
		return ""

	if once_per_day and _was_used_today():
		return ""

	return prompt_text


func can_interact() -> bool:
	if not super.can_interact():
		return false

	if _is_playing:
		return false

	if once_per_day and _was_used_today():
		return false

	return true


func _do_interact() -> void:
	_is_playing = true

	_record_interaction()

	_play_sfx()
	await _play_animation()

	_show_toast()
	_show_overhead_text()
	_emit_optional_object_interacted()

	_is_playing = false


func _record_interaction() -> void:
	if not persist_interaction_count:
		return

	var memory := get_world_memory()
	if memory == null:
		return

	var key := get_memory_key()
	var count := int(memory.call("get_value", key, "interaction_count", 0))
	memory.call("set_value", key, "interaction_count", count + 1)

	if TimeManager != null:
		memory.call("set_value", key, "last_interacted_day", int(TimeManager.day))


func _was_used_today() -> bool:
	var memory := get_world_memory()
	if memory == null:
		return false

	var key := get_memory_key()
	var last_day := int(memory.call("get_value", key, "last_interacted_day", -999999))

	if TimeManager == null:
		return false

	return last_day == int(TimeManager.day)


func _play_sfx() -> void:
	var stream := sfx
	if stream == null:
		return

	var p := get_node_or_null(sfx_player_path) as AudioStreamPlayer2D

	if p == null:
		p = AudioStreamPlayer2D.new()
		add_child(p)

	p.stream = stream
	p.volume_db = sfx_volume_db
	p.pitch_scale = randf_range(sfx_pitch_min, sfx_pitch_max)
	p.stop()
	p.play()


func _play_animation() -> void:
	var anim := get_node_or_null(animation_player_path) as AnimationPlayer

	if anim == null:
		await get_tree().process_frame
		return

	var anim_name := animation_name.strip_edges()
	if anim_name == "":
		await get_tree().process_frame
		return

	if not anim.has_animation(anim_name):
		await get_tree().process_frame
		return

	anim.play(anim_name)
	await anim.animation_finished


func _show_toast() -> void:
	var msg := toast_text.strip_edges()
	if msg == "":
		return

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(msg, toast_kind, toast_duration)


func _show_overhead_text() -> void:
	var msg := overhead_text.strip_edges()
	if msg == "":
		return

	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("show_overhead_text"):
		player.call("show_overhead_text", msg, overhead_duration)


func _emit_optional_object_interacted() -> void:
	if not emit_object_interacted:
		return

	var target := quest_target_id.strip_edges()
	if target == "":
		target = interactable_id.strip_edges()

	if target == "":
		return

	if QuestEvents != null and QuestEvents.has_signal("object_interacted"):
		QuestEvents.object_interacted.emit(interactable_id, target, quest_amount)
