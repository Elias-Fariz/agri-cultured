extends Node

signal capture_ui_changed(hidden: bool)

@export var action_name: String = "toggle_capture_ui"
@export var hide_group: String = "devlog_hide_ui"

@export var debug_enabled: bool = true

var ui_hidden: bool = false

# Store original visibility so we restore nodes politely.
var _previous_visibility: Dictionary = {}


func _ready() -> void:
	# Apply once after everything has entered the tree.
	call_deferred("_apply_current_state")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(action_name):
		toggle_capture_ui()
		get_viewport().set_input_as_handled()


func toggle_capture_ui() -> void:
	set_capture_ui_hidden(not ui_hidden)


func set_capture_ui_hidden(hidden: bool) -> void:
	ui_hidden = hidden

	if ui_hidden:
		_hide_group_nodes()
	else:
		_restore_group_nodes()

	capture_ui_changed.emit(ui_hidden)

	if debug_enabled:
		print(
			"[DevlogCaptureMode] UI hidden = ",
			ui_hidden
		)


func _apply_current_state() -> void:
	if ui_hidden:
		_hide_group_nodes()
	else:
		_restore_group_nodes()


func _hide_group_nodes() -> void:
	var nodes := get_tree().get_nodes_in_group(hide_group)

	for node in nodes:
		if not (node is CanvasItem):
			continue

		var canvas_item := node as CanvasItem
		var id := canvas_item.get_instance_id()

		if not _previous_visibility.has(id):
			_previous_visibility[id] = canvas_item.visible

		canvas_item.visible = false


func _restore_group_nodes() -> void:
	var nodes := get_tree().get_nodes_in_group(hide_group)

	for node in nodes:
		if not (node is CanvasItem):
			continue

		var canvas_item := node as CanvasItem
		var id := canvas_item.get_instance_id()

		if _previous_visibility.has(id):
			canvas_item.visible = bool(_previous_visibility[id])
		else:
			canvas_item.visible = true

	_previous_visibility.clear()
