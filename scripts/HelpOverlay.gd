# HelpOverlay.gd
extends BaseOverlay

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/TitleLabel
@onready var body_text: RichTextLabel = $Panel/Margin/VBox/BodyText
@onready var buttons_row: HBoxContainer = $Panel/Margin/VBox/ButtonsRow
@onready var open_book_button: Button = $Panel/Margin/VBox/ButtonsRow/OpenBookButton
@onready var close_button: Button = $Panel/Margin/VBox/ButtonsRow/CloseButton


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	close_button.pressed.connect(hide_overlay)
	open_book_button.pressed.connect(_on_open_book_pressed)

	title_label.text = "Help"

	open_book_button.text = "Open Help Book"
	close_button.text = "Close (Esc)"

	body_text.bbcode_enabled = true
	body_text.fit_content = false
	body_text.scroll_active = true
	body_text.visible_characters = -1
	body_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	body_text.clear()
	body_text.text = _build_help_text()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	# Toggle controls/help overlay with H.
	if event.is_action_pressed("open_help"):
		toggle_overlay()
		get_viewport().set_input_as_handled()
		return

	if is_open() and event.is_action_pressed("ui_cancel"):
		hide_overlay()
		get_viewport().set_input_as_handled()
		return


func show_overlay() -> void:
	super.show_overlay()

	if open_book_button != null:
		open_book_button.grab_focus()
	elif close_button != null:
		close_button.grab_focus()


func _on_open_book_pressed() -> void:
	hide_overlay()

	var book := get_tree().get_first_node_in_group("help_book_ui")
	if book != null and book.has_method("open_to_page"):
		book.call("open_to_page", 0)


func _build_help_text() -> String:
	return """
[b]Controls[/b]

Movement
• Move: WASD

Interaction
• Interact: E
• Open Inventory: T
• Open Quests: V

Tools
• Use Tools: Space
• Cycle Tools: Q
• Use Seeds: E, when facing tilled soil
• Cycle Seeds: R

Quests
• Pick a quest to track in the Quest Menu
• Or choose “Track None” to explore freely

Camera
• Zoom In / Out / Reset, if enabled
• - / = / `

Menus
• Close menus: Esc
• Help: H

For gentler guidance, open the Help Book.
""".strip_edges()
