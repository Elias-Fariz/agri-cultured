extends BaseOverlay
class_name ConfirmOverlay

signal answered(confirmed: bool)

@onready var title_label: Label = $Panel/Margin/VBox/TitleLabel
@onready var message_label: Label = $Panel/Margin/VBox/MessageLabel
@onready var yes_button: Button = $Panel/Margin/VBox/ButtonRow/YesButton
@onready var no_button: Button = $Panel/Margin/VBox/ButtonRow/NoButton

var _is_waiting_for_answer: bool = false


func _ready() -> void:
	super._ready()

	if Engine.is_editor_hint():
		return

	yes_button.pressed.connect(_choose_yes)
	no_button.pressed.connect(_choose_no)

	yes_button.text = "Yes"
	no_button.text = "No"


func ask(
	title: String,
	message: String,
	yes_text: String = "Yes",
	no_text: String = "No"
) -> bool:
	title_label.text = title
	message_label.text = message
	yes_button.text = yes_text
	no_button.text = no_text

	_is_waiting_for_answer = true
	show_overlay()

	await get_tree().process_frame
	if yes_button != null:
		yes_button.grab_focus()

	var result: bool = await answered

	_is_waiting_for_answer = false
	hide_overlay()

	return result


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if not is_open():
		return

	if event.is_action_pressed("ui_cancel"):
		_choose_no()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_accept"):
		_choose_yes()
		get_viewport().set_input_as_handled()
		return


func _choose_yes() -> void:
	if not _is_waiting_for_answer:
		return

	answered.emit(true)


func _choose_no() -> void:
	if not _is_waiting_for_answer:
		return

	answered.emit(false)
