# res://ui/shop/CartItemRow.gd
extends Button
class_name CartItemRow

@onready var name_label: Label = $Margin/Root/NameLabel
@onready var price_label: Label = $Margin/Root/PriceLabel

var item_id: String = ""
var count: int = 0

signal row_selected(item_id: String)

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	row_selected.emit(item_id)

func set_data(id: String, display_name: String, qty: int, base_line_total: int, final_line_total: int) -> void:
	item_id = id
	count = qty

	name_label.text = "%s  x%d" % [display_name, qty]

	if final_line_total < base_line_total:
		price_label.text = "%dg → %dg" % [base_line_total, final_line_total]
	else:
		price_label.text = "%dg" % base_line_total
