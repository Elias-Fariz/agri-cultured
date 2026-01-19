extends Area2D

@export var item_id: String = "Shell"
@export var qty: int = 1
@export var prompt_text: String = "E: Pick up"
@export var prompt_priority: int = 20  # lower than NPC talk if you want talk to win

func get_interact_prompt(_context: Node = null) -> String:
	return prompt_text

func get_interact_priority(_context :Node= null) -> int:
	return prompt_priority

func interact() -> void:
	# Add to inventory (your GameState helpers already exist)
	GameState.inventory_add(item_id, qty)

	# Optional: toast feedback if you have this signal
	# (If you don't, you can remove this block safely.)
	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit("+%d %s" % [qty, item_id], "info", 2.0)

	# Optional: emit an event if you want quests to react later
	# (Only keep if your QuestEvents actually has it.)
	if QuestEvents != null and QuestEvents.has_signal("item_picked_up"):
		QuestEvents.item_picked_up.emit(item_id, qty)

	queue_free()
