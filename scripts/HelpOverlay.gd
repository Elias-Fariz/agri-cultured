# HelpOverlay.gd
extends BaseOverlay

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/TitleLabel
@onready var body_text: RichTextLabel = $Panel/Margin/VBox/BodyText
@onready var close_button: Button = $Panel/Margin/VBox/ButtonsRow/CloseButton

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	close_button.pressed.connect(hide_overlay)

	title_label.text = "Help"

	# Force RichTextLabel to behave nicely inside VBoxContainer
	body_text.bbcode_enabled = true
	body_text.fit_content = false
	body_text.scroll_active = true
	body_text.visible_characters = -1  # IMPORTANT: show all characters
	body_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Set text in a robust way
	body_text.clear()
	body_text.text = _build_help_text()

	# Debug (temporary): confirm it truly has content
	print("HelpOverlay body length:", body_text.text.length())

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	# Toggle help with H
	if event.is_action_pressed("open_help"):
		toggle_overlay()
		get_viewport().set_input_as_handled()
		return

	# Close with Esc when open
	if is_open() and event.is_action_pressed("ui_cancel"):
		hide_overlay()
		get_viewport().set_input_as_handled()
		return

func show_overlay() -> void:
	super.show_overlay()
	# Optional: focus close button so controller/keyboard feels nice
	close_button.grab_focus()

func _build_help_text() -> String:
	# Keep it simple and friendly for beta testers
	# Update key names here if yours differ.
	return """
Movement
• Move: WASD

Interaction
• Interact: E
• Open Inventory: T
• Open Quests: V

"Inventory"
• Use Tools: Space
• Cycle Tools: Q
• Use Seeds: E (in front of tilled tile)
• Cycle Seeds: R

Quests
• Pick a quest to track in the Quest Menu
• Or choose “Track None” to explore freely

Camera
• Zoom In / Out / Reset (if enabled)
• - / = / `

Menus
• Close menus: Esc
• Help: H
""".strip_edges()
