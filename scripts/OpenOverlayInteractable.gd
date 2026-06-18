extends Interactable
class_name OpenOverlayInteractable

@export var overlay_group: String = ""
@export var open_method: String = "show_overlay"

# Optional: for overlays that have a nicer method than show_overlay.
# Example:
# HelpBookOverlay might use "open_to_first_unlocked_page" later.
@export var fallback_open_method: String = "show"

@export var close_inventory_first: bool = false

# Optional quest/object event support.
@export var emit_object_interacted: bool = false
@export var quest_target_id: String = ""
@export var quest_amount: int = 1

# Optional toast if the overlay cannot be found.
@export var missing_overlay_toast: String = ""


func _do_interact() -> void:
	var group_name := overlay_group.strip_edges()
	if group_name == "":
		push_warning("OpenOverlayInteractable: overlay_group is empty on " + str(name))
		return

	if close_inventory_first:
		_try_close_inventory()

	var ui := get_tree().get_first_node_in_group(group_name)
	if ui == null:
		push_warning("OpenOverlayInteractable: no UI found in group: " + group_name)
		_show_missing_overlay_toast()
		return

	if _try_open_ui(ui):
		_emit_optional_object_interacted()
	else:
		push_warning(
			"OpenOverlayInteractable: UI found, but no valid open method. Group: "
			+ group_name
			+ " Node: "
			+ str(ui.name)
		)


func _try_open_ui(ui: Node) -> bool:
	var method_name := open_method.strip_edges()

	if method_name != "" and ui.has_method(method_name):
		ui.call(method_name)
		return true

	var fallback := fallback_open_method.strip_edges()
	if fallback != "" and ui.has_method(fallback):
		ui.call(fallback)
		return true

	# Last fallback: if it is a CanvasItem, just make it visible.
	if ui is CanvasItem:
		(ui as CanvasItem).visible = true
		return true

	return false


func _try_close_inventory() -> void:
	var inventory_ui := get_tree().get_first_node_in_group("inventory_ui")
	if inventory_ui == null:
		return

	if inventory_ui.has_method("is_open") and not bool(inventory_ui.call("is_open")):
		return

	if inventory_ui.has_method("hide_ui"):
		inventory_ui.call("hide_ui")
	elif inventory_ui.has_method("hide_overlay"):
		inventory_ui.call("hide_overlay")
	elif inventory_ui is CanvasItem:
		(inventory_ui as CanvasItem).visible = false


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


func _show_missing_overlay_toast() -> void:
	var msg := missing_overlay_toast.strip_edges()
	if msg == "":
		return

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(msg, "warning", 2.0)
