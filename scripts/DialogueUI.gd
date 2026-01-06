extends CanvasLayer

@onready var box: Panel = $Box
@onready var name_label: Label = $Box/VBox/NameLabel
@onready var text_label: Label = $Box/VBox/TextLabel
@onready var hint_label: Label = $Box/VBox/HintLabel

var _lines: Array[String] = []
var _index: int = 0
var _active: bool = false

func _ready() -> void:
	# Start hidden in play (and stay visible in editor if you want).
	# If you want it hidden in editor too, you can also apply your BaseOverlay pattern later.
	hide_dialogue()

func show_dialogue(speaker_name: String, lines: Array[String]) -> void:
	if lines.is_empty():
		return

	_lines = lines
	_index = 0
	_active = true

	name_label.text = speaker_name
	text_label.text = _lines[_index]
	hint_label.text = "E: Next   Esc: Close"

	box.visible = true

	# Optional: lock gameplay while dialogue is open
	# If you already have a lock system, use it here.
	# If not, we can add it next.
	if GameState.has_method("lock_gameplay"):
		TimeManager.pause_time()
		GameState.lock_gameplay()

func hide_dialogue() -> void:
	_active = false
	_lines = []
	_index = 0
	box.visible = false

	# Optional: unlock gameplay
	if GameState.has_method("unlock_gameplay"):
		TimeManager.resume_time()
		GameState.unlock_gameplay()

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
