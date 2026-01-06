extends CharacterBody2D

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

	ui_node.show_dialogue(display_name, dialogue_lines)
