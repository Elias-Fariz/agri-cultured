extends Area2D
class_name Interactable

signal interacted(interactable_id: String)

@export var interactable_id: String = ""
@export var prompt_text: String = "E: Interact"
@export var prompt_priority: int = 10
@export var interaction_enabled: bool = true
@export var one_time_only: bool = false

var _has_been_used: bool = false

func get_interact_prompt(_context: Node = null) -> String:
	if not can_interact():
		return ""
	return prompt_text

func get_interact_priority(_context: Node = null) -> int:
	return prompt_priority

func can_interact() -> bool:
	if not interaction_enabled:
		return false
	if one_time_only and _has_been_used:
		return false
	return true

func interact() -> void:
	if not can_interact():
		return

	# Mark used first if this is a one-time interactable
	if one_time_only:
		_has_been_used = true

	# Let child scripts define what "doing the interaction" means
	_do_interact()

	# Emit a local signal for anything that wants to listen
	interacted.emit(interactable_id)

func _do_interact() -> void:
	# Child classes override this.
	# Example uses later:
	# - show text
	# - toggle decoration state
	# - emit quest progress
	# - give item
	pass

func set_interaction_enabled(value: bool) -> void:
	interaction_enabled = value

func reset_interaction_state() -> void:
	_has_been_used = false
