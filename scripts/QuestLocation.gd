extends Area2D

@export var location_id: String = "farm"
@export var trigger_once_per_scene_entry: bool = false

var _triggered_this_scene_entry: bool = false


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	if trigger_once_per_scene_entry and _triggered_this_scene_entry:
		return

	_triggered_this_scene_entry = true
	QuestEvents.went_to.emit(location_id)
