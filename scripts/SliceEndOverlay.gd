# res://scripts/ui/SliceEndOverlay.gd
extends BaseOverlay
class_name SliceEndOverlay

@export_multiline var title_text: String = "The Valley Heart Has Begun to Wake"
@export_multiline var message_text: String = "This is the end of the current Heart Root slice, but you can keep exploring, farming, and talking with townsfolk.\n\nThank you for playing."
@export var feedback_url: String = ""
@export var show_feedback_button: bool = true

@onready var title_label: Label = $Panel/CenterContainer/Card/VBox/TitleLabel
@onready var message_label: Label = $Panel/CenterContainer/Card/VBox/MessageLabel
@onready var continue_button: Button = $Panel/CenterContainer/Card/VBox/ButtonRow/ContinueButton
@onready var feedback_button: Button = $Panel/CenterContainer/Card/VBox/ButtonRow/FeedbackButton
@onready var hint_label: Label = $Panel/CenterContainer/Card/VBox/HintLabel


func _ready() -> void:
	super._ready()

	title_label.text = title_text
	message_label.text = message_text

	continue_button.pressed.connect(_on_continue_pressed)
	feedback_button.pressed.connect(_on_feedback_pressed)

	_refresh_feedback_button()


func show_slice_end() -> void:
	title_label.text = title_text
	message_label.text = message_text
	_refresh_feedback_button()
	show_overlay()

	if continue_button != null:
		continue_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return

	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		hide_overlay()
		get_viewport().set_input_as_handled()


func _on_continue_pressed() -> void:
	hide_overlay()


func _on_feedback_pressed() -> void:
	if feedback_url.strip_edges() == "":
		return

	OS.shell_open(feedback_url)


func _refresh_feedback_button() -> void:
	var has_url := feedback_url.strip_edges() != ""
	feedback_button.visible = show_feedback_button and has_url

	if hint_label != null:
		if has_url:
			hint_label.text = "You can continue playing after this."
		else:
			hint_label.text = "You can continue playing after this."
