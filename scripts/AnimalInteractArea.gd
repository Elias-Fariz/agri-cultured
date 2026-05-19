extends Area2D

@export var fallback_prompt: String = "E: Interact"
@export var fallback_priority: int = 30

@onready var _animal := get_parent()


func get_interact_prompt(context: Node = null) -> String:
	if _animal != null and _animal.has_method("get_interact_prompt"):
		return String(_animal.get_interact_prompt(context))

	return fallback_prompt


func get_interact_priority(context: Node = null) -> int:
	if _animal != null and _animal.has_method("get_interact_priority"):
		return int(_animal.get_interact_priority(context))

	return fallback_priority


func interact() -> void:
	# print("InteractArea: interact() called on animal:", _animal)

	if _animal != null and _animal.has_method("interact"):
		_animal.interact()
