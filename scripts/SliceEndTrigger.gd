# res://scripts/slice/SliceEndTrigger.gd
extends Node
class_name SliceEndTrigger

@export var completion_flag: String = "slice_01_complete"
@export var slice_end_overlay_path: NodePath
@export var show_only_once_flag: String = "slice_01_end_message_seen"

var _shown_this_session: bool = false


func _ready() -> void:
	if QuestEvents != null and QuestEvents.has_signal("quest_state_changed"):
		QuestEvents.quest_state_changed.connect(_on_quest_state_changed)

	call_deferred("_check_and_show_if_ready")


func _on_quest_state_changed() -> void:
	_check_and_show_if_ready()


func _check_and_show_if_ready() -> void:
	if _shown_this_session:
		return

	if GameState == null:
		return

	if show_only_once_flag.strip_edges() != "":
		if GameState.has_method("has_flag") and GameState.has_flag(show_only_once_flag):
			return

	if completion_flag.strip_edges() != "":
		if GameState.has_method("has_flag") and not GameState.has_flag(completion_flag):
			return

	var overlay := get_node_or_null(slice_end_overlay_path)
	if overlay == null:
		return

	if overlay.has_method("show_slice_end"):
		_shown_this_session = true

		if show_only_once_flag.strip_edges() != "" and GameState.has_method("set_flag"):
			GameState.set_flag(show_only_once_flag, true)

		overlay.call_deferred("show_slice_end")
