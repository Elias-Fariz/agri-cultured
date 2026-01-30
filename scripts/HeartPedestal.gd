# res://world/HeartPedestal.gd
extends Area2D
class_name HeartPedestal

@export var prompt_priority: int = 35

@export var prompt_text: String = "E: Rest your hands on the Heart"
@export var prompt_subtext: String = "A quiet blessing awaits…"

@export var ui_scene: PackedScene = preload("res://ui/HeartDomainHubUI.tscn")

var _ui_instance: HeartDomainHubUI = null

func get_interact_priority(_context: Node = null) -> int:
	return prompt_priority

func get_interact_prompt(_context: Node = null) -> String:
	# Keep it short enough for your prompt UI
	# (You can include a newline if your prompt label supports it)
	return prompt_text

func interact() -> void:
	_open_ui()

func _open_ui() -> void:
	if _ui_instance == null or not is_instance_valid(_ui_instance):
		_ui_instance = ui_scene.instantiate()
		get_tree().root.add_child(_ui_instance)

	# Optional: if you have a toast system and want a tiny cozy line on open
	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(prompt_subtext, "info", 1.8)

	_ui_instance.show_overlay()
