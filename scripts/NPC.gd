extends CharacterBody2D

@export var npc_id: String = "npc_default"
@export var display_name: String = "Alex"
@export var dialogue_lines: Array[String] = [
	"Hi there.",
	"Nice weather, huh?",
	"See you around!"
]

func start_dialogue() -> void:
	var ui_node := get_tree().get_first_node_in_group("dialogue_ui")
	if ui_node == null:
		print("No DialogueUI found in group 'dialogue_ui'. Add DialogueUI.tscn to the scene and put it in that group.")
		return

	# Make sure it's actually our DialogueUI script, not just any CanvasLayer
	if not ui_node.has_method("show_dialogue"):
		print("Node in group 'dialogue_ui' does not have show_dialogue(). Reattach DialogueUI.gd to the DialogueUI CanvasLayer.")
		print("Found node:", ui_node.name, " type:", ui_node.get_class())
		return
	
	var current_day := TimeManager.day  # <-- adjust to your project

	# Gain friendship once per day on talk (recommended)
	if GameState.can_gain_talk_friendship(npc_id, current_day):
		GameState.add_friendship(npc_id, 1)
		GameState.mark_talked_today(npc_id, current_day)
		
	var f := GameState.get_friendship(npc_id)

	ui_node.show_dialogue(display_name, dialogue_lines, f)
