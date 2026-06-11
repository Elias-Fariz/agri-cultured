extends BaseOverlay
class_name HelpBookOverlay

@export var help_book_data: HelpBookData

@onready var title_label: Label = $Panel/Margin/VBox/HeaderRow/TitleLabel
@onready var close_button: Button = $Panel/Margin/VBox/HeaderRow/CloseButton
@onready var body_text: RichTextLabel = $Panel/Margin/VBox/PageBodyText
@onready var prev_button: Button = $Panel/Margin/VBox/FooterRow/PrevButton
@onready var page_number_label: Label = $Panel/Margin/VBox/FooterRow/PageNumberLabel
@onready var next_button: Button = $Panel/Margin/VBox/FooterRow/NextButton
@onready var hint_label: Label = $Panel/Margin/VBox/HintLabel

var current_page_index: int = 0
var _visible_pages: Array[HelpBookPageData] = []


func _ready() -> void:
	super._ready()

	if Engine.is_editor_hint():
		return

	close_button.pressed.connect(hide_overlay)
	prev_button.pressed.connect(_go_previous_page)
	next_button.pressed.connect(_go_next_page)

	body_text.bbcode_enabled = true
	body_text.fit_content = false
	body_text.scroll_active = true
	body_text.visible_characters = -1
	body_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	prev_button.text = "←"
	next_button.text = "→"
	close_button.text = "Close"

	_refresh_visible_pages()
	_refresh_page()


func open_to_page(page_index: int = 0) -> void:
	_refresh_visible_pages()

	if _visible_pages.is_empty():
		current_page_index = 0
	else:
		current_page_index = clampi(page_index, 0, _visible_pages.size() - 1)

	# Important:
	# Show first, then refresh after the Control tree has had a frame to size itself.
	show_overlay()

	await get_tree().process_frame

	_refresh_page()

	if close_button != null:
		close_button.grab_focus()


func open_to_page_id(page_id: String) -> void:
	_refresh_visible_pages()

	page_id = page_id.strip_edges()
	if page_id == "":
		open_to_page(0)
		return

	for i in range(_visible_pages.size()):
		if _visible_pages[i] != null and _visible_pages[i].page_id == page_id:
			open_to_page(i)
			return

	open_to_page(0)


func toggle_help_book() -> void:
	if is_open():
		hide_overlay()
	else:
		open_to_page(current_page_index)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	#if event.is_action_pressed("open_help_book"):
		#toggle_help_book()
		#get_viewport().set_input_as_handled()
		#return

	if not is_open():
		return

	if event.is_action_pressed("ui_cancel"):
		hide_overlay()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_left"):
		_go_previous_page()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_right"):
		_go_next_page()
		get_viewport().set_input_as_handled()
		return


func _refresh_visible_pages() -> void:
	_visible_pages.clear()

	if help_book_data == null:
		return

	_visible_pages = help_book_data.get_unlocked_pages()

	if current_page_index >= _visible_pages.size():
		current_page_index = max(0, _visible_pages.size() - 1)


func _go_previous_page() -> void:
	_refresh_visible_pages()

	if _visible_pages.is_empty():
		_refresh_page()
		return

	current_page_index -= 1
	if current_page_index < 0:
		current_page_index = _visible_pages.size() - 1

	_refresh_page()


func _go_next_page() -> void:
	_refresh_visible_pages()

	if _visible_pages.is_empty():
		_refresh_page()
		return

	current_page_index += 1
	if current_page_index >= _visible_pages.size():
		current_page_index = 0

	_refresh_page()


func _refresh_page() -> void:
	if body_text == null:
		return

	if _visible_pages.is_empty():
		title_label.text = "Help Book"

		body_text.clear()
		body_text.text = "No pages are available yet."
		body_text.visible = true
		body_text.scroll_to_line(0)

		page_number_label.text = "0 / 0"
		hint_label.text = ""
		prev_button.disabled = true
		next_button.disabled = true
		return

	current_page_index = clampi(current_page_index, 0, _visible_pages.size() - 1)

	var page := _visible_pages[current_page_index]
	if page == null:
		return

	title_label.text = page.title

	var page_body := String(page.body).strip_edges()
	if page_body == "":
		page_body = "[i]This page is blank for now.[/i]"

	body_text.visible = true
	body_text.bbcode_enabled = true
	body_text.clear()

	# parse_bbcode is more reliable than assigning .text when BBCode is enabled.
	body_text.parse_bbcode(page_body)
	body_text.scroll_to_line(0)

	page_number_label.text = "%d / %d" % [current_page_index + 1, _visible_pages.size()]

	prev_button.disabled = _visible_pages.size() <= 1
	next_button.disabled = _visible_pages.size() <= 1

	hint_label.text = "Use ← / → or the buttons to turn pages."
