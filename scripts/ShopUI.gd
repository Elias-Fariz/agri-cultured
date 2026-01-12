extends BaseOverlay

@onready var shop_list: ItemList = $Panel/Margin/Root/BodyRow/LeftCol/ShopList
@onready var cart_list: ItemList = $Panel/Margin/Root/BodyRow/RightCol/CartList
@onready var add_button: Button = $Panel/Margin/Root/BodyRow/LeftCol/AddButton
@onready var remove_button: Button = $Panel/Margin/Root/BodyRow/RightCol/RemoveButton
@onready var total_label: Label = $Panel/Margin/Root/FooterRow/TotalLabel
@onready var buy_button: Button = $Panel/Margin/Root/FooterRow/BuyButton
@onready var close_button: Button = $Panel/Margin/Root/HeaderRow/CloseButton

# Simple stock: each item has an id, name, and price
var shop_items: Array = [
	{ "id": "Watermelon Seeds", "name": "Watermelon Seeds", "price": 10 },
	{ "id": "Blueberry Seeds", "name": "Blueberry Seeds", "price": 25 },
	{ "id": "Strawberry Seeds", "name": "Strawberry Seeds", "price": 20 },
	{ "id": "Avocado Seeds", "name": "Avocado Seeds", "price": 40 },
	{ "id": "Watermelon", "name": "Watermelon", "price": 60 },
	{ "id": "Wood", "name": "Bundle of Wood", "price": 10 },
	{ "id": "Animal Feed", "name": "All-Purpose Animal Feed", "price": 5 },
]

# cart[item_id] = count
var cart: Dictionary = {}

var _cart_row_ids: Array[String] = []      # row index -> item_id
var _last_cart_selected_id: String = ""    # currently selected item_id in cart


func _ready() -> void:
	close_button.pressed.connect(hide_overlay)
	add_button.pressed.connect(_on_add_pressed)
	remove_button.pressed.connect(_on_remove_pressed)
	buy_button.pressed.connect(_on_buy_pressed)

	shop_list.item_selected.connect(_on_shop_selected)
	cart_list.item_selected.connect(_on_cart_selected)

	_refresh_shop()
	_refresh_cart()


func show_overlay() -> void:
	super.show_overlay()
	_refresh_shop()
	_refresh_cart()

func _find_item_by_id(item_id: String) -> Dictionary:
	for item_any in shop_items:
		var item: Dictionary = item_any
		if String(item.get("id", "")) == item_id:
			return item
	return {}


func _compute_total() -> int:
	var total := 0
	for id_any in cart.keys():
		var id := String(id_any)
		var count := int(cart[id_any])
		var item := _find_item_by_id(id)
		if item.is_empty():
			continue
		var price := int(item.get("price", 0))
		total += price * count
	return total

func _refresh_shop() -> void:
	shop_list.clear()
	for item_any in shop_items:
		var item: Dictionary = item_any
		var name := String(item.get("name", "Item"))
		var price := int(item.get("price", 0))
		shop_list.add_item("%s - %dg" % [name, price])
	_update_buttons()


func _refresh_cart() -> void:
	# Remember what was selected before refresh
	var previously_selected_id := _last_cart_selected_id

	cart_list.clear()
	_cart_row_ids.clear()

	for id_any in cart.keys():
		var id := String(id_any)
		var count := int(cart[id_any])
		var item := _find_item_by_id(id)
		if item.is_empty():
			continue

		var name := String(item.get("name", "Item"))
		var price := int(item.get("price", 0))
		var line := "%s x%d (%dg)" % [name, count, price * count]

		_cart_row_ids.append(id)
		cart_list.add_item(line)

	# Try to restore selection
	if previously_selected_id != "":
		var row := _cart_row_ids.find(previously_selected_id)
		if row != -1:
			cart_list.select(row)
		else:
			# Item no longer in cart
			_last_cart_selected_id = ""

	var total := _compute_total()
	total_label.text = "Total: %dg" % total

	_update_buttons()

func _update_buttons() -> void:
	var shop_has_selection := not shop_list.get_selected_items().is_empty()
	var cart_has_selection := not cart_list.get_selected_items().is_empty()
	var total := _compute_total()

	add_button.disabled = not shop_has_selection
	remove_button.disabled = not cart_has_selection

	var cart_empty := cart.is_empty()
	var can_afford := MoneySystem.can_afford(total)

	buy_button.disabled = cart_empty or not can_afford

func _on_shop_selected(_index: int) -> void:
	_update_buttons()

func _on_cart_selected(index: int) -> void:
	if index >= 0 and index < _cart_row_ids.size():
		_last_cart_selected_id = _cart_row_ids[index]
	_update_buttons()

func _on_add_pressed() -> void:
	var selected := shop_list.get_selected_items()
	if selected.is_empty():
		return

	var idx := int(selected[0])
	if idx < 0 or idx >= shop_items.size():
		return

	var item: Dictionary = shop_items[idx]
	var id := String(item.get("id", ""))

	if id == "":
		return

	cart[id] = int(cart.get(id, 0)) + 1
	_refresh_cart()


func _on_remove_pressed() -> void:
	if _last_cart_selected_id == "":
		return

	var id := _last_cart_selected_id
	if not cart.has(id):
		_last_cart_selected_id = ""
		_refresh_cart()
		return

	var current := int(cart[id])
	if current <= 1:
		# Removing the last one → erase item entirely
		cart.erase(id)
		_last_cart_selected_id = ""
	else:
		cart[id] = current - 1

	_refresh_cart()

func _on_buy_pressed() -> void:
	var total := _compute_total()
	if cart.is_empty():
		return
	if not MoneySystem.can_afford(total):
		return

	if not MoneySystem.spend(total):
		return

	# Give items to player
	for id_any in cart.keys():
		var id := String(id_any)
		var count := int(cart[id_any])
		# For now, give 1 inventory item per unit name
		# You can map "WatermelonSeed" → "Watermelon Seed" inventory key, etc.
		var inv_name := id  # or map via a dictionary later
		GameState.inventory_add(inv_name, count)

	cart.clear()
	_refresh_cart()
