extends Area2D
class_name ItemPickup

@export var item_id: String = "Shell"
@export var qty: int = 1

# IMPORTANT: unique per placed pickup instance
# Example: "beach_shell_01", "beach_shell_02", etc.
@export var pickup_id: String = ""

@export var prompt_text: String = "E: Pick Up"
@export var prompt_priority: int = 20

@export var toast_enabled: bool = true
@export var toast_duration: float = 2.0

func _ready() -> void:
	# If player already collected this pickup today, remove it immediately on scene load.
	if pickup_id.strip_edges() != "" and GameState.was_pickup_collected_today(pickup_id):
		queue_free()

func get_interact_prompt(_context :Node= null) -> String:
	return prompt_text

func get_interact_priority(_context :Node= null) -> int:
	return prompt_priority

func interact() -> void:
	# Prevent double-collect in same day even if interact spam happens
	if pickup_id.strip_edges() != "" and GameState.was_pickup_collected_today(pickup_id):
		queue_free()
		return

	# Give item
	GameState.inventory_add(item_id, qty)
	QuestEvents.item_picked_up.emit(item_id, qty)

	# Mark collected today (so it won't respawn on scene reload)
	if pickup_id.strip_edges() != "":
		GameState.mark_pickup_collected(pickup_id)

	# Toast
	if toast_enabled and QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit("+%d %s" % [qty, item_id], "info", toast_duration)

	queue_free()
