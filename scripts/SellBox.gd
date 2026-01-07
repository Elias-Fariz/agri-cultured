extends Node2D
class_name SellBox

signal contents_changed()
signal payout_paid(payout: int)

# item_id -> qty
var contents: Dictionary = {}

func _ready() -> void:
	GameState.sell_box = self

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

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		add_item("Watermelon", 3)
		print("SellBox payout would be: ", calculate_payout())
