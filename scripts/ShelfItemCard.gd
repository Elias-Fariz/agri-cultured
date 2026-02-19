# res://ui/shop/ShelfItemCard.gd
extends Button
class_name ShelfItemCard

@onready var icon_rect: TextureRect = $Margin/Root/Icon
@onready var name_label: Label = $Margin/Root/TextCol/NameLabel
@onready var price_label: Label = $Margin/Root/TextCol/PriceLabel

var item_id: String = ""
var base_price: int = 0
var final_unit_price: int = 0

signal card_selected(item_id: String)

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	card_selected.emit(item_id)

func set_data(id: String, display_name: String, base_p: int, final_p: int, icon: Texture2D) -> void:
	item_id = id
	base_price = base_p
	final_unit_price = final_p

	# Icon vs fallback text
	if icon != null:
		icon_rect.texture = icon
		icon_rect.visible = true
	else:
		icon_rect.texture = null
		icon_rect.visible = false

	name_label.text = display_name

	# Price line
	if final_p > 0 and final_p < base_p:
		price_label.text = "%dg  →  %dg" % [base_p, final_p]
	else:
		price_label.text = "%dg" % base_p
