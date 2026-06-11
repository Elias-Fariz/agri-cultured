extends Interactable
class_name ToggleVisualInteractable

@export var starts_on: bool = true
@export var persist_state: bool = true

# Optional visuals to show when ON/OFF.
@export var on_visual_path: NodePath
@export var off_visual_path: NodePath

# Optional light node, usually PointLight2D.
@export var light_path: NodePath

# Optional animation player.
@export var animation_player_path: NodePath
@export var on_animation: String = ""
@export var off_animation: String = ""

# Optional text feedback.
@export var on_toast_text: String = ""
@export var off_toast_text: String = ""
@export var toast_kind: String = "info"
@export var toast_duration: float = 1.5

# Optional quest/interact progress.
@export var emit_object_interacted: bool = false
@export var quest_target_id: String = ""
@export var quest_amount: int = 1

var _is_on: bool = true


func _ready() -> void:
	_is_on = starts_on

	if persist_state and interactable_id.strip_edges() != "":
		var flag_id := _state_flag_id()
		if GameState != null and GameState.has_method("has_flag"):
			if GameState.has_flag(flag_id + ":on"):
				_is_on = true
			elif GameState.has_flag(flag_id + ":off"):
				_is_on = false

	_refresh_state(false)


func _do_interact() -> void:
	_is_on = not _is_on

	if persist_state and interactable_id.strip_edges() != "":
		_save_state()

	_refresh_state(true)

	if emit_object_interacted and quest_target_id.strip_edges() != "":
		if QuestEvents != null and QuestEvents.has_signal("object_interacted"):
			QuestEvents.object_interacted.emit(interactable_id, quest_target_id, quest_amount)


func _refresh_state(show_feedback: bool = false) -> void:
	var on_visual := get_node_or_null(on_visual_path)
	var off_visual := get_node_or_null(off_visual_path)
	var light := get_node_or_null(light_path)
	var anim := get_node_or_null(animation_player_path) as AnimationPlayer

	if on_visual != null and on_visual is CanvasItem:
		(on_visual as CanvasItem).visible = _is_on

	if off_visual != null and off_visual is CanvasItem:
		(off_visual as CanvasItem).visible = not _is_on

	if light != null:
		if light is CanvasItem:
			(light as CanvasItem).visible = _is_on
		elif light.has_method("set_enabled"):
			light.call("set_enabled", _is_on)

	if anim != null:
		if _is_on and on_animation.strip_edges() != "":
			anim.play(on_animation)
		elif not _is_on and off_animation.strip_edges() != "":
			anim.play(off_animation)

	if show_feedback:
		_show_toggle_toast()


func _show_toggle_toast() -> void:
	var msg := on_toast_text if _is_on else off_toast_text
	msg = msg.strip_edges()

	if msg == "":
		return

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(msg, toast_kind, toast_duration)


func _save_state() -> void:
	if GameState == null or not GameState.has_method("set_flag"):
		return

	var id := _state_flag_id()

	GameState.set_flag(id + ":on", _is_on)
	GameState.set_flag(id + ":off", not _is_on)


func _state_flag_id() -> String:
	return "interactable_state:" + interactable_id.strip_edges()


func is_on() -> bool:
	return _is_on


func set_on(value: bool, show_feedback: bool = false) -> void:
	_is_on = value

	if persist_state and interactable_id.strip_edges() != "":
		_save_state()

	_refresh_state(show_feedback)
