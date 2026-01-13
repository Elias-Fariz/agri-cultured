extends Area2D

@export var location_id: String = "farm"

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		QuestEvents.went_to.emit(location_id)
