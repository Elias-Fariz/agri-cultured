extends Interactable
class_name SellBox

signal contents_changed()
signal payout_paid(payout: int)

# item_id -> qty
var contents: Dictionary = {}

@export var shipping_ui_group: String = "shipping_ui"
@export var missing_ui_text: String = "The shipping ledger isn't available right now."


func _ready() -> void:
	GameState.sell_box = self


func _do_interact() -> void:
	var ui := get_tree().get_first_node_in_group(shipping_ui_group)

	if ui == null:
		push_warning(
			"SellBox: no UI found in group: "
			+ shipping_ui_group
			+ " for "
			+ str(get_path())
		)
		_show_missing_ui_feedback()
		return

	if ui.has_method("show_overlay"):
		ui.call("show_overlay")
	elif ui.has_method("show"):
		ui.call("show")
	else:
		push_warning(
			"SellBox: shipping UI has no show_overlay() or show() method: "
			+ str(ui.get_path())
		)


func _show_missing_ui_feedback() -> void:
	var msg := missing_ui_text.strip_edges()
	if msg == "":
		return

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(msg, "warning", 2.0)


func add_item(item_id: String, qty: int = 1) -> void:
	item_id = item_id.strip_edges()

	if item_id == "" or qty <= 0:
		return

	contents[item_id] = int(contents.get(item_id, 0)) + qty
	contents_changed.emit()


func remove_item(item_id: String, qty: int = 1) -> void:
	item_id = item_id.strip_edges()

	if item_id == "" or qty <= 0:
		return

	if not contents.has(item_id):
		return

	var new_qty := int(contents[item_id]) - qty

	if new_qty <= 0:
		contents.erase(item_id)
	else:
		contents[item_id] = new_qty

	contents_changed.emit()


func calculate_payout() -> int:
	var total := 0

	for item_id_any in contents.keys():
		var item_id := String(item_id_any)
		var qty := int(contents[item_id_any])
		var price := GameState.get_sell_price(item_id)

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
