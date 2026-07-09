extends Interactable
class_name ObservationInteractable

enum DisplayMode {
	NARRATION,
	TOAST
}

@export_multiline var observation_text: String = ""

@export_category("Alternate Text")

@export var use_alternate_when_flag_set: bool = false
@export var alternate_required_flag: String = ""
@export_multiline var alternate_observation_text: String = ""

@export_category("Display")

@export var display_mode: DisplayMode = DisplayMode.NARRATION
@export var narration_group: String = "narration_ui"

@export var toast_kind: String = "info"
@export var toast_duration: float = 3.0

@export_category("Memory")

@export var persist_observation_count: bool = true
@export var memory_count_field: String = "observed_count"


func _do_interact() -> void:
	var text := _get_current_text()
	if text == "":
		return

	_record_observation()

	match display_mode:
		DisplayMode.NARRATION:
			if _show_narration(text):
				return

			# Safe fallback if narration UI is missing.
			_show_toast(text)

		DisplayMode.TOAST:
			_show_toast(text)


func _get_current_text() -> String:
	if use_alternate_when_flag_set:
		var flag := alternate_required_flag.strip_edges()

		if flag != "":
			if GameState != null and GameState.has_method("has_flag"):
				if GameState.has_flag(flag):
					var alt := alternate_observation_text.strip_edges()
					if alt != "":
						return alt

	return observation_text.strip_edges()


func _show_narration(text: String) -> bool:
	var ui := get_tree().get_first_node_in_group(narration_group)
	if ui == null:
		push_warning("ObservationInteractable: no narration UI found in group: " + narration_group)
		return false

	if ui.has_method("show_text"):
		ui.call("show_text", text)
		return true

	push_warning("ObservationInteractable: narration UI has no show_text(text) method.")
	return false


func _show_toast(text: String) -> void:
	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(text, toast_kind, toast_duration)


func _record_observation() -> void:
	if not persist_observation_count:
		return

	var memory := get_world_memory()
	if memory == null:
		return

	if not memory.has_method("get_value") or not memory.has_method("set_value"):
		return

	var key := get_memory_key()
	var field := memory_count_field.strip_edges()

	if field == "":
		field = "observed_count"

	var count := int(memory.call("get_value", key, field, 0))
	memory.call("set_value", key, field, count + 1)
