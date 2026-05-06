extends Area2D
class_name FishingSpot

@export var prompt_text: String = "E: Fish"
@export var prompt_priority: int = 25

@export var possible_fish: Array[FishDefinition] = []
@export var fishing_ui_scene: PackedScene = preload("res://ui/FishingMinigameUI.tscn")

@export var energy_cost_on_success: int = 1
@export var fail_toast: String = "The fish slips away…"

@export var require_fishing_unlocked: bool = true
@export var require_fishing_rod_selected: bool = true

@export var locked_prompt_text: String = ""
@export var wrong_tool_prompt_text: String = "Select Fishing Rod"

# Prevent multiple minigames spawning
var _active_ui: Node = null


func get_interact_prompt(_context: Node = null) -> String:
	if _can_fish_here(false):
		return prompt_text

	if _has_fishing_rod() and not _is_fishing_rod_selected():
		return wrong_tool_prompt_text

	return locked_prompt_text

func get_interact_priority(_context: Node = null) -> int:
	return prompt_priority


func interact() -> void:
	if is_instance_valid(_active_ui):
		return

	if GameState == null:
		return

	if not _can_fish_here(true):
		return

	# Energy check
	if int(GameState.energy) <= 0:
		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("You’re too tired to fish right now.", "info", 2.0)
		return

	var fish := _pick_fish()
	if fish == null:
		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("The water is still… maybe later.", "info", 2.0)
		return

	# rest of your existing function continues...

	# Apply food buff modifiers before starting the minigame.
	var final_time_limit := float(fish.time_limit)
	var final_sequence_len := int(fish.sequence_len)
	var final_mistakes_allowed := int(fish.mistakes_allowed)

	# ------------------------------------------------------------
	# Fishing Focus: +seconds to fishing timer
	# ------------------------------------------------------------
	var fishing_time_bonus := 0.0
	if GameState != null and GameState.has_method("get_food_buff_amount"):
		fishing_time_bonus = GameState.get_food_buff_amount(FoodEffectData.EffectKey.FISHING_TIME_BONUS)

	if fishing_time_bonus > 0.0:
		final_time_limit += fishing_time_bonus

		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("Fishing Focus: +" + str(fishing_time_bonus) + "s", "info", 1.5)

		if GameState.has_method("consume_food_buff_use"):
			GameState.consume_food_buff_use(FoodEffectData.EffectKey.FISHING_TIME_BONUS)


	# ------------------------------------------------------------
	# Fishing Grace: +mistakes allowed
	# ------------------------------------------------------------
	var fishing_mistake_bonus := 0.0
	if GameState != null and GameState.has_method("get_food_buff_amount"):
		fishing_mistake_bonus = GameState.get_food_buff_amount(FoodEffectData.EffectKey.FISHING_MISTAKE_BONUS)

	if fishing_mistake_bonus > 0.0:
		final_mistakes_allowed += int(round(fishing_mistake_bonus))

		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("Fishing Grace: +" + str(int(round(fishing_mistake_bonus))) + " mistake", "info", 1.5)

		if GameState.has_method("consume_food_buff_use"):
			GameState.consume_food_buff_use(FoodEffectData.EffectKey.FISHING_MISTAKE_BONUS)


	# ------------------------------------------------------------
	# Clear Rhythm: fewer letters in the sequence
	# ------------------------------------------------------------
	var fishing_sequence_reduction := 0.0
	if GameState != null and GameState.has_method("get_food_buff_amount"):
		fishing_sequence_reduction = GameState.get_food_buff_amount(FoodEffectData.EffectKey.FISHING_SEQUENCE_REDUCTION)

	if fishing_sequence_reduction > 0.0:
		final_sequence_len -= int(round(fishing_sequence_reduction))
		final_sequence_len = max(1, final_sequence_len)

		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("Clear Rhythm: easier pattern", "info", 1.5)

		if GameState.has_method("consume_food_buff_use"):
			GameState.consume_food_buff_use(FoodEffectData.EffectKey.FISHING_SEQUENCE_REDUCTION)


	# Build the input string after buffs modify the sequence length.
	var seq := _generate_sequence(final_sequence_len)

	# Spawn UI
	var ui := fishing_ui_scene.instantiate()
	_active_ui = ui
	get_tree().root.add_child(ui)

	# Connect result
	ui.fishing_finished.connect(_on_fishing_finished.bind(fish))

	# ✅ IMPORTANT: actually start the minigame
	ui.start_minigame(
		fish.fish_item_id,
		seq,
		final_time_limit,
		final_mistakes_allowed
	)


func _on_fishing_finished(success: bool, caught_fish_id: String, fish: FishDefinition) -> void:
	# Clear active marker (UI will self-free)
	_active_ui = null

	if not success:
		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit(fail_toast, "info", 2.0)
		return

	# Spend energy only on success
	GameState.energy = max(int(GameState.energy) - energy_cost_on_success, 0)
	GameState.exhausted = false

	# Give fish
	GameState.inventory_add(caught_fish_id, 1)
	
	if QuestEvents != null and QuestEvents.has_signal("fish_caught"):
		QuestEvents.fish_caught.emit(caught_fish_id, 1)

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		var name := fish.display_name if fish.display_name != "" else caught_fish_id
		QuestEvents.toast_requested.emit("You caught: %s!" % name, "success", 2.5)


func _pick_fish() -> FishDefinition:
	if possible_fish.is_empty():
		return null

	var total_weight := 0
	for f_any in possible_fish:
		var f := f_any as FishDefinition
		if f == null:
			continue
		total_weight += max(1, f.weight)

	var roll := randi() % total_weight
	var running := 0
	for f_any2 in possible_fish:
		var f2 := f_any2 as FishDefinition
		if f2 == null:
			continue
		running += max(1, f2.weight)
		if roll < running:
			return f2

	return possible_fish[0] as FishDefinition


func _generate_sequence(len: int) -> Array[String]:
	var keys := ["A", "D", "W", "S"]
	var out: Array[String] = []
	len = clamp(len, 1, 10)
	for i in range(len):
		out.append(keys[randi() % keys.size()])
	return out

func _is_fishing_unlocked() -> bool:
	# Fallback to GameState flag if needed.
	if GameState != null and GameState.has_method("has_flag"):
		return bool(GameState.has_flag("fishing_unlocked"))
	
	# Prefer HeartProgress, because the Valley Heart owns this unlock.
	var hp := get_node_or_null("/root/HeartProgress")
	if hp != null and hp.has_method("is_fishing_unlocked"):
		return bool(hp.call("is_fishing_unlocked"))

	

	return false


func _has_fishing_rod() -> bool:
	if GameState == null:
		return false
	if not GameState.has_method("has_tool"):
		return false
	return bool(GameState.has_tool(GameState.ToolType.FISHING_ROD))


func _is_fishing_rod_selected() -> bool:
	if GameState == null:
		return false
	return int(GameState.current_tool) == int(GameState.ToolType.FISHING_ROD)


func _can_fish_here(show_toast: bool = false) -> bool:
	if require_fishing_unlocked and not _is_fishing_unlocked():
		if show_toast and QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("The tide feels quiet… The Sea Wing hasn’t awakened yet.", "info", 2.5)
		return false

	if not _has_fishing_rod():
		if show_toast and QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("You may need someone to teach you how to listen to this water.", "info", 2.5)
		return false

	if require_fishing_rod_selected and not _is_fishing_rod_selected():
		if show_toast and QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("Select the Fishing Rod first.", "info", 2.0)
		return false

	return true
