extends BaseOverlay

@onready var box: Panel = $Box
@onready var name_label: Label = $Box/VBox/NameLabel
@onready var text_label: Label = $Box/VBox/TextLabel
@onready var hint_label: Label = $Box/VBox/HintLabel
@onready var friendship_label: Label = $Box/VBox/FriendshipLabel

var _lines: Array[String] = []
var _index: int = 0
var _active: bool = false

func _ready() -> void:
	# Start hidden in play (and stay visible in editor if you want).
	# If you want it hidden in editor too, you can also apply your BaseOverlay pattern later.
	hide_dialogue()

func show_dialogue(speaker_name: String, lines: Array[String], friendship: int = -1) -> void:
	if lines.is_empty():
		return

	_lines = lines
	_index = 0
	_active = true
	
	# Friendship display
	if friendship >= 0:
		friendship_label.visible = true
		friendship_label.text = "Friendship: %s (%d)" % [_hearts(friendship), friendship]
	else:
		friendship_label.visible = false

	name_label.text = speaker_name
	text_label.text = _lines[_index]
	hint_label.text = "E: Next   Esc: Close"

	super.show_overlay()

func hide_dialogue() -> void:
	_active = false
	_lines = []
	_index = 0
	super.hide_overlay()
	
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("camera_clear_focus"):
		player.camera_clear_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	if event.is_action_pressed("ui_cancel"):
		hide_dialogue()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("interact"):
		_index += 1
		if _index >= _lines.size():
			hide_dialogue()
		else:
			text_label.text = _lines[_index]
		get_viewport().set_input_as_handled()

func _hearts(friendship: int) -> String:
	# Example: 0-49 => 0-4 hearts (10 pts per heart)
	var hearts := clampi(friendship / 10, 0, 10)
	return "♥".repeat(hearts) + "♡".repeat(10 - hearts)
