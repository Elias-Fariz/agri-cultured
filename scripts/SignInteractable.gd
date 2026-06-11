extends Interactable
class_name SignInteractable

@export var sign_title: String = ""
@export_multiline var sign_text: String = ""

# Optional: use dialogue UI instead of toast.
@export var use_dialogue_ui: bool = true

# Optional: for signs that should count toward quests.
@export var emit_object_interacted: bool = false
@export var quest_target_id: String = ""
@export var quest_amount: int = 1


func _do_interact() -> void:
	if emit_object_interacted and quest_target_id.strip_edges() != "":
		if QuestEvents != null and QuestEvents.has_signal("object_interacted"):
			QuestEvents.object_interacted.emit(interactable_id, quest_target_id, quest_amount)

	if use_dialogue_ui:
		_show_as_dialogue()
	else:
		_show_as_toast()


func _show_as_dialogue() -> void:
	var ui := get_tree().get_first_node_in_group("dialogue_ui")
	if ui == null or not ui.has_method("show_dialogue"):
		_show_as_toast()
		return

	var title := sign_title.strip_edges()
	if title == "":
		title = "Sign"

	var text := sign_text.strip_edges()
	if text == "":
		text = "Nothing is written here."

	ui.show_dialogue(title, [text], -1, "")


func _show_as_toast() -> void:
	var text := sign_text.strip_edges()
	if text == "":
		return

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(text, "info", 2.5)
