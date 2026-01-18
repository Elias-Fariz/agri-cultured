extends Area2D

@export var rest_id: String = "town_bench_1"
@export var energy_gain: int = 1

# Prompt system hooks (only used if your prompt code calls them)
func get_interact_prompt(player: Node) -> String:
	# Show Rest prompt only if available this time block
	if GameState.can_rest_at(_get_rest_id()):
		return "E: Rest"
	return "Rested"

func get_interact_priority() -> int:
	# Put this below NPC talk, above generic objects if you like
	return 40

func interact() -> void:
	var id := _get_rest_id()
	if not GameState.can_rest_at(id):
		# Already used this block; do nothing (prompt will say Rested)
		return

	# Gain energy (clamped)
	var before := GameState.energy
	GameState.energy = min(GameState.max_energy, GameState.energy + max(0, energy_gain))

	# If energy didn't change (already full), don't consume the rest for the block (optional)
	if GameState.energy == before:
		# Optional: toast feedback
		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("Energy is already full.", "info", 2.0)
		return

	GameState.mark_rested_at(id)

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit("+" + str(energy_gain) + " Energy", "success", 2.0)


func _get_rest_id() -> String:
	# Safety: if you forget to set it, auto-generate something stable-ish
	if rest_id.strip_edges() != "":
		return rest_id
	return "bench_" + str(get_instance_id())
