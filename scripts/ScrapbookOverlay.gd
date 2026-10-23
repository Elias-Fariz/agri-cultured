extends BaseOverlay
class_name ScrapbookOverlay

const CHARACTER_CARD_SCENE := preload("res://tscn/ScrapbookCharacterCard.tscn")
@export var characters: Array[ScrapbookCharacterData] = []

@onready var title_label: Label = (
	$Panel/MarginContainer/Root/HeaderRow/TitleLabel
)

@onready var close_button: Button = (
	$Panel/MarginContainer/Root/HeaderRow/CloseButton
)

@onready var index_view: Control = (
	$Panel/MarginContainer/Root/Content/IndexView
)

@onready var character_grid: GridContainer = (
	$Panel/MarginContainer/Root/Content/IndexView/CharacterGrid
)

@onready var character_view: Control = (
	$Panel/MarginContainer/Root/Content/CharacterView
)

@onready var portrait: TextureRect = (
	$Panel/MarginContainer/Root/Content/
	CharacterView/TwoPageRow/LeftPage/Portrait
)

@onready var name_label: Label = (
	$Panel/MarginContainer/Root/Content/
	CharacterView/TwoPageRow/LeftPage/NameLabel
)

@onready var friendship_label: Label = (
	$Panel/MarginContainer/Root/Content/
	CharacterView/TwoPageRow/LeftPage/FriendshipLabel
)

@onready var summary_label: RichTextLabel = (
	$Panel/MarginContainer/Root/Content/
	CharacterView/TwoPageRow/LeftPage/SummaryLabel
)

@onready var back_to_index_button: Button = (
	$Panel/MarginContainer/Root/Content/
	CharacterView/TwoPageRow/LeftPage/BackToIndexButton
)

@onready var section_button_container: VBoxContainer = (
	$Panel/MarginContainer/Root/Content/
	CharacterView/TwoPageRow/RightPage/SectionButtonContainer
)

@onready var section_view: Control = (
	$Panel/MarginContainer/Root/Content/SectionView
)

@onready var mini_portrait: TextureRect = (
	$Panel/MarginContainer/Root/Content/
	SectionView/TwoPageRow/LeftPage/MiniPortrait
)

@onready var section_title_label: Label = (
	$Panel/MarginContainer/Root/Content/
	SectionView/TwoPageRow/LeftPage/SectionTitleLabel
)

@onready var entry_button_container: VBoxContainer = (
	$Panel/MarginContainer/Root/Content/
	SectionView/TwoPageRow/LeftPage/
	EntryScroll/EntryButtonContainer
)

@onready var back_to_character_button: Button = (
	$Panel/MarginContainer/Root/Content/
	SectionView/TwoPageRow/LeftPage/BackToCharacterButton
)

@onready var entry_title_label: Label = (
	$Panel/MarginContainer/Root/Content/
	SectionView/TwoPageRow/RightPage/EntryTitleLabel
)

@onready var entry_body_text: RichTextLabel = (
	$Panel/MarginContainer/Root/Content/
	SectionView/TwoPageRow/RightPage/EntryBodyText
)

@onready var hint_label: Label = (
	$Panel/MarginContainer/Root/HintLabel
)

var _current_character: ScrapbookCharacterData = null
var _current_section: ScrapbookSectionData = null


func _ready() -> void:
	super._ready()

	if Engine.is_editor_hint():
		return

	close_button.pressed.connect(hide_overlay)
	back_to_index_button.pressed.connect(_show_index)
	back_to_character_button.pressed.connect(_show_character_view)

	title_label.text = "Scrapbook"
	close_button.text = "Close"

	summary_label.bbcode_enabled = true
	entry_body_text.bbcode_enabled = true

	_show_index()


func open_scrapbook() -> void:
	_build_character_index()
	_show_index()
	show_overlay()

	await get_tree().process_frame

	if close_button != null:
		close_button.grab_focus()


func toggle_scrapbook() -> void:
	if is_open():
		hide_overlay()
	else:
		open_scrapbook()


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action("open_scrapbook"):
		if event.is_action_pressed("open_scrapbook"):
			toggle_scrapbook()
			get_viewport().set_input_as_handled()
			return
	
	if not is_open():
		return

	if event.is_action_pressed("ui_cancel"):
		hide_overlay()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------
# Index
# ---------------------------------------------------------

func _show_index() -> void:
	_current_character = null
	_current_section = null

	index_view.visible = true
	character_view.visible = false
	section_view.visible = false

	title_label.text = "Scrapbook"
	hint_label.text = "Choose someone you've met."

	_build_character_index()


func _build_character_index() -> void:
	_clear_children(character_grid)

	for character in characters:
		if character == null:
			continue

		var card := CHARACTER_CARD_SCENE.instantiate() as ScrapbookCharacterCard
		if card == null:
			continue

		var friendship := _get_friendship_value(character.character_id)

		character_grid.add_child(card)

		card.setup(character, friendship)

		if character.is_met():
			card.pressed.connect(
				_open_character.bind(character)
			)

func _make_known_character_button_text(
	character: ScrapbookCharacterData
) -> String:
	var text := character.display_name

	if character.show_friendship:
		var friendship := _get_friendship_value(
			character.character_id
		)

		text += "\nFriendship: %d" % friendship

	return text


# ---------------------------------------------------------
# Character overview
# ---------------------------------------------------------

func _open_character(
	character: ScrapbookCharacterData
) -> void:
	if character == null:
		return

	_current_character = character
	_current_section = null

	index_view.visible = false
	character_view.visible = true
	section_view.visible = false

	title_label.text = character.display_name

	portrait.texture = character.portrait
	name_label.text = character.display_name

	if character.show_friendship:
		var friendship := _get_friendship_value(
			character.character_id
		)

		friendship_label.visible = true
		friendship_label.text = (
			"Friendship: %d" % friendship
		)
	else:
		friendship_label.visible = false

	var summary := character.summary.strip_edges()

	if summary == "":
		summary = (
			"[i]There is still more to learn.[/i]"
		)

	summary_label.clear()
	summary_label.parse_bbcode(summary)

	hint_label.text = (
		"Choose a part of the page to look closer."
	)

	_build_section_buttons(character)


func _show_character_view() -> void:
	if _current_character == null:
		_show_index()
		return

	_open_character(_current_character)


func _build_section_buttons(
	character: ScrapbookCharacterData
) -> void:
	_clear_children(section_button_container)

	for section in character.sections:
		if section == null:
			continue

		var button := Button.new()
		button.custom_minimum_size = Vector2(250, 42)

		if section.is_unlocked():
			button.text = section.display_name
			button.pressed.connect(
				_open_section.bind(section)
			)
		else:
			button.text = section.display_name + "  🔒"
			button.disabled = true

		section_button_container.add_child(button)


# ---------------------------------------------------------
# Section detail
# ---------------------------------------------------------

func _open_section(
	section: ScrapbookSectionData
) -> void:
	if _current_character == null:
		return

	if section == null:
		return

	_current_section = section

	index_view.visible = false
	character_view.visible = false
	section_view.visible = true

	title_label.text = _current_character.display_name

	mini_portrait.texture = _current_character.portrait
	section_title_label.text = section.display_name

	entry_title_label.text = ""
	entry_body_text.clear()
	entry_body_text.text = (
		"Choose something from the left page."
	)

	hint_label.text = (
		"These are things you've learned along the way."
	)

	_build_entry_buttons(section)


func _build_entry_buttons(
	section: ScrapbookSectionData
) -> void:
	_clear_children(entry_button_container)

	var entries := section.get_unlocked_entries()

	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "There's still more to notice."
		entry_button_container.add_child(empty_label)
		return

	for entry in entries:
		var button := Button.new()

		button.text = entry.title
		button.custom_minimum_size = Vector2(0, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		if entry.icon != null:
			button.icon = entry.icon

		button.pressed.connect(
			_show_entry.bind(entry)
		)

		entry_button_container.add_child(button)


func _show_entry(
	entry: ScrapbookEntryData
) -> void:
	if entry == null:
		return

	entry_title_label.text = entry.title

	entry_body_text.clear()

	var body := entry.body.strip_edges()

	if body == "":
		body = "[i]Nothing written here yet.[/i]"

	entry_body_text.parse_bbcode(body)


# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------

func _get_friendship_value(
	character_id: String
) -> int:
	if GameState == null:
		return 0

	if GameState.has_method("get_friendship_level"):
		return int(
			GameState.get_friendship_level(character_id)
		)

	if GameState.has_method("get_friendship"):
		return int(
			GameState.get_friendship(character_id)
		)

	return 0


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
