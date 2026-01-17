extends Control

@export var max_toasts: int = 4
@export var default_duration: float = 2.5

@onready var toast_vbox: VBoxContainer = $ToastVBox

func _ready() -> void:
	QuestEvents.toast_requested.connect(_on_toast_requested)

func _on_toast_requested(text: String, kind: String = "info", duration: float = -1.0) -> void:
	if duration <= 0.0:
		duration = default_duration

	_add_toast(text, kind, duration)

func _add_toast(text: String, kind: String, duration: float) -> void:
	# Trim old toasts
	while toast_vbox.get_child_count() >= max_toasts:
		var old := toast_vbox.get_child(0)
		old.queue_free()

	# Build a toast panel
	var panel := PanelContainer.new()
	panel.name = "Toast"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Simple padding container
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)

	margin.add_child(label)
	panel.add_child(margin)

	# Optional: tiny visual hint by kind (no fancy colors required yet)
	# You can style later with Theme overrides.

	toast_vbox.add_child(panel)

	# Auto-remove after duration
	_remove_later(panel, duration)

func _remove_later(node: Control, duration: float) -> void:
	var t := get_tree().create_timer(duration)
	t.timeout.connect(func():
		if is_instance_valid(node):
			node.queue_free()
	)
