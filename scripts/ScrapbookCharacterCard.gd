extends Button
class_name ScrapbookCharacterCard

@onready var portrait_rect: TextureRect = $MarginContainer/VBoxContainer/PortraitRect
@onready var name_label: Label = $MarginContainer/VBoxContainer/NameLabel
@onready var friendship_label: Label = $MarginContainer/VBoxContainer/FriendshipLabel
@onready var summary_label: Label = $MarginContainer/VBoxContainer/SummaryLabel
@onready var locked_label: Label = $MarginContainer/VBoxContainer/LockedLabel

var _character: ScrapbookCharacterData = null

func _ready() -> void:
	if portrait_rect == null:
		push_error("[ScrapbookCharacterCard] PortraitRect node was not found.")
	
	if name_label == null:
		push_error("[ScrapbookCharacterCard] NameLabel node was not found.")
	
	if friendship_label == null:
		push_error("[ScrapbookCharacterCard] FriendshipLabel node was not found.")
	
	if summary_label == null:
		push_error("[ScrapbookCharacterCard] SummaryLabel node was not found.")
	
	if locked_label == null:
		push_error("[ScrapbookCharacterCard] LockedLabel node was not found.")


func setup(character: ScrapbookCharacterData, friendship_value: int) -> void:
	_character = character
	
	if character == null:
		push_error("[ScrapbookCharacterCard] setup() received null character data.")
		return
	
	if portrait_rect == null:
		push_error("[ScrapbookCharacterCard] PortraitRect is null. Check the scene node path.")
		return
	
	if character.is_met():
		_setup_known(character, friendship_value)
	elif character.is_glimpsed():
		_setup_glimpsed(character)
	else:
		_setup_unknown(character)


func _setup_known(character: ScrapbookCharacterData, friendship_value: int) -> void:
	disabled = false
	
	portrait_rect.modulate = Color(1, 1, 1, 1)
	
	if character.index_portrait != null:
		portrait_rect.texture = character.index_portrait
	else:
		portrait_rect.texture = character.portrait
	
	name_label.text = character.display_name
	
	if character.show_friendship:
		friendship_label.visible = true
		friendship_label.text = "Friendship: %d" % friendship_value
	else:
		friendship_label.visible = false
	
	summary_label.visible = true
	summary_label.text = _make_preview_text(character.summary)
	
	locked_label.visible = false


func _setup_unknown(character: ScrapbookCharacterData) -> void:
	disabled = true

	portrait_rect.modulate = Color.WHITE

	if character.silhouette != null:
		portrait_rect.texture = character.silhouette
	elif character.index_portrait != null:
		portrait_rect.texture = character.index_portrait
		portrait_rect.modulate = Color(0.15, 0.15, 0.15, 1.0)
	elif character.portrait != null:
		portrait_rect.texture = character.portrait
		portrait_rect.modulate = Color(0.15, 0.15, 0.15, 1.0)
	else:
		portrait_rect.texture = null

	name_label.text = "???"
	friendship_label.visible = false
	summary_label.visible = false

	locked_label.visible = true
	locked_label.text = "You haven’t met them yet."

func _setup_glimpsed(character: ScrapbookCharacterData) -> void:
	disabled = true
	
	portrait_rect.modulate = Color(0.4, 0.4, 0.4, 1.0)
	
	if character.silhouette != null:
		portrait_rect.texture = character.silhouette
	elif character.index_portrait != null:
		portrait_rect.texture = character.index_portrait
	else:
		portrait_rect.texture = character.portrait
	
	name_label.text = "???"
	friendship_label.visible = false
	
	summary_label.visible = true
	summary_label.text = "I've heard something about them."
	
	locked_label.visible = true
	locked_label.text = "Not properly met yet."


func _make_preview_text(full_text: String) -> String:
	var t := full_text.strip_edges()
	if t == "":
		return ""
	
	if t.length() > 70:
		return t.substr(0, 70) + "..."
	
	return t


func reset_visual_modulate() -> void:
	portrait_rect.modulate = Color(1, 1, 1, 1)
