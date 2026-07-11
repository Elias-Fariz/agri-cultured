extends Interactable
class_name OldFarmSpigot

@export_category("Required Items")

@export var required_items: Dictionary = {
	"Wood": 3,
	"Stone": 2,
}

@export_category("Visuals")

@export var broken_visual_path: NodePath = ^"BrokenVisual"
@export var repaired_visual_path: NodePath = ^"RepairedVisual"

@export_category("UI")

@export var narration_group: String = "narration_ui"
@export var confirm_group: String = "confirm_ui"

@export_category("Behavior")

@export var water_field_on_repair: bool = true
@export var once_per_day: bool = true

@export_category("Text")

@export_multiline var discovery_text: String = """An old farm spigot peeks out from beside the house.

The handle is loose, but the pipe beneath it still seems sturdy.

It looks connected to the watering lines beneath the field."""

@export_multiline var missing_items_text: String = """It might work again with {items}."""

@export var repair_confirm_title: String = "Repair Spigot"
@export var repair_confirm_message: String = "Repair the Old Farm Spigot with {items}?"
@export var repair_yes_text: String = "Repair"
@export var repair_no_text: String = "Not now"

@export_multiline var repair_success_text: String = """The old spigot gives a stubborn little cough.

Then water rushes through the line."""

@export var use_confirm_title: String = "Use Spigot"
@export var use_confirm_message: String = "Use the Old Farm Spigot to water the field?"
@export var use_yes_text: String = "Use"
@export var use_no_text: String = "Not now"

@export_multiline var already_used_text: String = """The spigot is quiet for now.

There should be fresh water again tomorrow."""

@export var watered_toast_text: String = "The farm field was watered."
@export var no_dry_soil_toast_text: String = "The field is already watered."

@export_category("Memory")

@export var repaired_field: String = "repaired"
@export var last_used_day_field: String = "last_used_day"

var _busy: bool = false


func _ready() -> void:
	_refresh_visual_state()


func get_interact_prompt(_context: Node = null) -> String:
	if not can_interact():
		return ""

	if not _is_repaired():
		return "E: Check"

	if once_per_day and _was_used_today():
		return "E: Check"

	return "E: Use"


func can_interact() -> bool:
	if not super.can_interact():
		return false

	if _busy:
		return false

	return true


func _do_interact() -> void:
	if _busy:
		return

	_busy = true

	if _is_repaired():
		await _handle_repaired_interaction()
	else:
		await _handle_broken_interaction()

	_busy = false


func _handle_broken_interaction() -> void:
	await _show_narration_and_wait(discovery_text)

	if not _has_required_items():
		var msg := missing_items_text.replace("{items}", _format_required_items())
		await _show_narration_and_wait(msg)
		return

	var confirmed := await _ask_confirm(
		repair_confirm_title,
		repair_confirm_message.replace("{items}", _format_required_items()),
		repair_yes_text,
		repair_no_text
	)

	if not confirmed:
		return

	if not _has_required_items():
		var msg := missing_items_text.replace("{items}", _format_required_items())
		await _show_narration_and_wait(msg)
		return

	if not _consume_required_items():
		await _show_narration_and_wait("Something went wrong. The spigot remains loose.")
		return

	_set_repaired(true)
	_refresh_visual_state()

	await _show_narration_and_wait(repair_success_text)

	if water_field_on_repair:
		_use_spigot_today()


func _handle_repaired_interaction() -> void:
	if once_per_day and _was_used_today():
		await _show_narration_and_wait(already_used_text)
		return

	var confirmed := await _ask_confirm(
		use_confirm_title,
		use_confirm_message,
		use_yes_text,
		use_no_text
	)

	if not confirmed:
		return

	_use_spigot_today()


func _use_spigot_today() -> void:
	var watered_count := _water_farm_field()

	_mark_used_today()

	if watered_count > 0:
		_show_toast(watered_toast_text, "success", 2.0)
	else:
		_show_toast(no_dry_soil_toast_text, "info", 2.0)


func _water_farm_field() -> int:
	var scene := get_tree().current_scene
	if scene == null:
		return 0

	if scene.has_method("water_all_tilled_soil_from_spigot"):
		return int(scene.call("water_all_tilled_soil_from_spigot"))

	# Fallback: search current scene for a farm/tool world that has the method.
	for node in get_tree().get_nodes_in_group("tool_world"):
		if node == null:
			continue

		if not (scene.is_ancestor_of(node) or node == scene):
			continue

		if node.has_method("water_all_tilled_soil_from_spigot"):
			return int(node.call("water_all_tilled_soil_from_spigot"))

	push_warning("OldFarmSpigot: no water_all_tilled_soil_from_spigot() found in current scene.")
	return 0


func _has_required_items() -> bool:
	for item_id_any in required_items.keys():
		var item_id := String(item_id_any)
		var qty := int(required_items[item_id_any])

		if qty <= 0:
			continue

		if GameState == null or not GameState.has_method("inventory_has"):
			return false

		if not GameState.inventory_has(item_id, qty):
			return false

	return true


func _consume_required_items() -> bool:
	if not _has_required_items():
		return false

	for item_id_any in required_items.keys():
		var item_id := String(item_id_any)
		var qty := int(required_items[item_id_any])

		if qty <= 0:
			continue

		if GameState == null or not GameState.has_method("inventory_remove"):
			return false

		var removed := GameState.inventory_remove(item_id, qty)
		if not removed:
			return false

	return true


func _format_required_items() -> String:
	var parts: Array[String] = []

	for item_id_any in required_items.keys():
		var item_id := String(item_id_any)
		var qty := int(required_items[item_id_any])

		if qty <= 0:
			continue

		parts.append("%d %s" % [qty, item_id])

	if parts.is_empty():
		return "the needed parts"

	if parts.size() == 1:
		return parts[0]

	if parts.size() == 2:
		return "%s and %s" % [parts[0], parts[1]]

	var last :Variant= parts.pop_back()
	return "%s, and %s" % [", ".join(parts), last]


func _show_narration_and_wait(text: String) -> void:
	text = text.strip_edges()

	if text == "":
		return

	var ui := get_tree().get_first_node_in_group(narration_group)

	if ui == null:
		_show_toast(text, "info", 3.0)
		await get_tree().create_timer(0.5).timeout
		return

	if ui.has_method("show_text_and_wait"):
		await ui.call("show_text_and_wait", text)
		return

	if ui.has_method("show_text"):
		ui.call("show_text", text)

		if ui.has_signal("narration_closed"):
			await ui.narration_closed
		else:
			await get_tree().create_timer(1.0).timeout

		return

	_show_toast(text, "info", 3.0)


func _ask_confirm(
	title: String,
	message: String,
	yes_text: String = "Yes",
	no_text: String = "No"
) -> bool:
	var ui := get_tree().get_first_node_in_group(confirm_group)

	if ui == null:
		push_warning("OldFarmSpigot: no confirm UI found in group: " + confirm_group)
		return false

	if not ui.has_method("ask"):
		push_warning("OldFarmSpigot: confirm UI has no ask() method.")
		return false

	var result: bool = await ui.call("ask", title, message, yes_text, no_text)
	return result


func _show_toast(text: String, kind: String = "info", duration: float = 2.0) -> void:
	text = text.strip_edges()

	if text == "":
		return

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(text, kind, duration)


func _refresh_visual_state() -> void:
	var repaired := _is_repaired()

	var broken_visual := get_node_or_null(broken_visual_path)
	if broken_visual is CanvasItem:
		(broken_visual as CanvasItem).visible = not repaired

	var repaired_visual := get_node_or_null(repaired_visual_path)
	if repaired_visual is CanvasItem:
		(repaired_visual as CanvasItem).visible = repaired


func _is_repaired() -> bool:
	var memory := get_world_memory()
	if memory == null:
		return false

	var key := get_memory_key()
	return bool(memory.call("get_value", key, repaired_field, false))


func _set_repaired(value: bool) -> void:
	var memory := get_world_memory()
	if memory == null:
		return

	var key := get_memory_key()
	memory.call("set_value", key, repaired_field, value)


func _was_used_today() -> bool:
	if TimeManager == null:
		return false

	var memory := get_world_memory()
	if memory == null:
		return false

	var key := get_memory_key()
	var last_day := int(memory.call("get_value", key, last_used_day_field, -999999))

	return last_day == int(TimeManager.day)


func _mark_used_today() -> void:
	if TimeManager == null:
		return

	var memory := get_world_memory()
	if memory == null:
		return

	var key := get_memory_key()
	memory.call("set_value", key, last_used_day_field, int(TimeManager.day))
