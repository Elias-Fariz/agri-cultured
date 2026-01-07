extends Node2D
class_name SellBox

signal contents_changed()
signal payout_paid(payout: int)

# item_id -> qty
var contents: Dictionary = {}

func _ready() -> void:
	GameState.sell_box = self
	
func interact() -> void:
	# Find the UI and open it
	var ui := get_tree().get_first_node_in_group("shipping_ui")
	if ui:
		ui.show_overlay()

func add_item(item_id: String, qty: int = 1) -> void:
	if item_id.is_empty() or qty <= 0:
		return

	contents[item_id] = int(contents.get(item_id, 0)) + qty
	contents_changed.emit()

func remove_item(item_id: String, qty: int = 1) -> void:
	# This is your “future path” for taking stuff back out.
	if not contents.has(item_id) or qty <= 0:
		return

	var new_qty := int(contents[item_id]) - qty
	if new_qty <= 0:
		contents.erase(item_id)
	else:
		contents[item_id] = new_qty

	contents_changed.emit()

func calculate_payout() -> int:
	var total := 0
	for item_id in contents.keys():
		var qty := int(contents[item_id])
		var price := GameState.get_sell_price(String(item_id))
		total += price * qty
	return total

func payout_and_clear() -> int:
	var payout := calculate_payout()
	if payout > 0:
		MoneySystem.add(payout)
		payout_paid.emit(payout)

	contents.clear()
	contents_changed.emit()
	return payout
