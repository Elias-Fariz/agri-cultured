extends Area2D
class_name GateInteractArea

@export var prompt_priority: int = 30


func interact() -> void:
	var gate := get_parent()
	if gate != null and gate.has_method("interact"):
		gate.interact()


func get_interact_prompt(_context: Node = null) -> String:
	var gate := get_parent()

	if gate != null and "is_open" in gate:
		if bool(gate.is_open):
			return "E: Close Gate"
		else:
			return "E: Open Gate"

	return "E: Gate"


func get_interact_priority() -> int:
	return prompt_priority
