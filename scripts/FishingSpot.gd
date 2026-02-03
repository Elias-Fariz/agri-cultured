extends Area2D
class_name FishingSpot

@export var prompt_text: String = "E: Fish"
@export var prompt_priority: int = 25

@export var possible_fish: Array[FishDefinition] = []
@export var fishing_ui_scene: PackedScene = preload("res://ui/FishingMinigameUI.tscn")

@export var energy_cost_on_success: int = 1
@export var fail_toast: String = "The fish slips away…"

# Prevent multiple minigames spawning
var _active_ui: Node = null


func get_interact_prompt(_context: Node = null) -> String:
	return prompt_text

func get_interact_priority(_context: Node = null) -> int:
	return prompt_priority


func interact() -> void:
	# If a minigame is already open from this spot, ignore.
	if is_instance_valid(_active_ui):
		return

	if GameState == null:
		return

	# Energy check (don’t spend yet)
	if int(GameState.energy) <= 0:
		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("You’re too tired to fish right now.", "info", 2.0)
		return

	var fish := _pick_fish()
	if fish == null:
		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("The water is still… maybe later.", "info", 2.0)
		return

	# Build the input string
	var seq := _generate_sequence(fish.sequence_len)

	# Spawn UI
	var ui := fishing_ui_scene.instantiate()
	_active_ui = ui
	get_tree().root.add_child(ui)

	# Connect result
	ui.fishing_finished.connect(_on_fishing_finished.bind(fish))

	# ✅ IMPORTANT: actually start the minigame
	ui.start_minigame(
		fish.fish_item_id,     # what inventory item you receive on success
		seq,                  # input sequence like ["A","D","A"]
		fish.time_limit,      # seconds to complete
		fish.mistakes_allowed # how many wrong presses allowed
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
