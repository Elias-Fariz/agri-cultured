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
	{ "id": "Apple", "name": "Energizing Apple", "price": 15 },
]

# cart[item_id] = count
var cart: Dictionary = {}

var _cart_row_ids: Array[String] = []      # row index -> item_id
var _last_cart_selected_id: String = ""    # currently selected item_id in cart

@onready var shop_sfx: AudioStreamPlayer2D = $ShopSfx2D
@export var buy_sounds: Array[AudioStream] = []

# -------------------------------------------------------------------
# Heart discount helpers
# -------------------------------------------------------------------
func _get_shop_discount_multiplier() -> float:
	# 1.0 = no discount; 0.97 = 3% cheaper
	var mul := 1.0
	var hp := get_node_or_null("/root/HeartProgress")
	if hp != null and hp.has_method("get_shop_discount_multiplier"):
		mul = float(hp.call("get_shop_discount_multiplier"))
	# Safety
	if mul <= 0.0:
		mul = 1.0
	return mul

func _discount_active() -> bool:
	return _get_shop_discount_multiplier() < 0.999

func _calc_discounted_unit_price(base_price: int) -> int:
	if base_price <= 0:
		return 0
	var mul := _get_shop_discount_multiplier()
	# Favor player: floor makes discount feel real and predictable
	var p := int(floor(float(base_price) * mul))
	return max(1, p)

func _compute_subtotal_base() -> int:
	# What the cart would cost with NO blessing.
	var total := 0
	for id_any in cart.keys():
		var id := String(id_any)
		var count := int(cart[id_any])
		var item := _find_item_by_id(id)
		if item.is_empty():
			continue
		var base_price := int(item.get("price", 0))
		total += base_price * count
	return total

func _compute_total_discounted() -> int:
	# What the cart costs with blessing applied.
	var total := 0
	for id_any in cart.keys():
		var id := String(id_any)
		var count := int(cart[id_any])
		var item := _find_item_by_id(id)
		if item.is_empty():
			continue
		var base_price := int(item.get("price", 0))
		var final_unit := _calc_discounted_unit_price(base_price)
		total += final_unit * count
	return total

func _compute_heart_savings() -> int:
	var base_total := _compute_subtotal_base()
	var final_total := _compute_total_discounted()
	return max(0, base_total - final_total)

# -------------------------------------------------------------------

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

func _refresh_shop() -> void:
	shop_list.clear()

	var mul := _get_shop_discount_multiplier()
	var show_discount := mul < 0.999

	for item_any in shop_items:
		var item: Dictionary = item_any
		var name := String(item.get("name", "Item"))
		var base_price := int(item.get("price", 0))

		if show_discount:
			var final_unit := _calc_discounted_unit_price(base_price)
			var savings :Variant= max(0, base_price - final_unit)
			if savings > 0:
				# Example: "Apple - 15g  (Blessing: -1g → 14g)"
				shop_list.add_item("%s - %dg  (Blessing: -%dg → %dg)" % [name, base_price, savings, final_unit])
			else:
				shop_list.add_item("%s - %dg" % [name, base_price])
		else:
			shop_list.add_item("%s - %dg" % [name, base_price])

	_update_buttons()

func _refresh_cart() -> void:
	# Remember what was selected before refresh
	var previously_selected_id := _last_cart_selected_id

	cart_list.clear()
	_cart_row_ids.clear()

	var mul := _get_shop_discount_multiplier()
	var show_discount := mul < 0.999

	for id_any in cart.keys():
		var id := String(id_any)
		var count := int(cart[id_any])
		var item := _find_item_by_id(id)
		if item.is_empty():
			continue

		var name := String(item.get("name", "Item"))
		var base_price := int(item.get("price", 0))

		var base_line_total := base_price * count
		var line := ""

		if show_discount:
			var final_unit := _calc_discounted_unit_price(base_price)
			var final_line_total := final_unit * count
			var savings :Variant= max(0, base_line_total - final_line_total)

			if savings > 0:
				# Example: "Apple x2 (30g → 28g)"
				line = "%s x%d (%dg → %dg)" % [name, count, base_line_total, final_line_total]
			else:
				line = "%s x%d (%dg)" % [name, count, base_line_total]
		else:
			line = "%s x%d (%dg)" % [name, count, base_line_total]

		_cart_row_ids.append(id)
		cart_list.add_item(line)

	# Try to restore selection
	if previously_selected_id != "":
		var row := _cart_row_ids.find(previously_selected_id)
		if row != -1:
			cart_list.select(row)
		else:
			_last_cart_selected_id = ""

	# Total label (multi-line flourish)
	var base_total := _compute_subtotal_base()
	var final_total := _compute_total_discounted()
	var savings_total :Variant= max(0, base_total - final_total)

	if show_discount and savings_total > 0:
		total_label.text = "Total: %dg\nValley Heart Blessing (x%.2f): -%dg\nYou pay: %dg" % [
			base_total,
			mul,
			savings_total,
			final_total
		]
	else:
		total_label.text = "Total: %dg" % final_total

	_update_buttons()

func _update_buttons() -> void:
	var shop_has_selection := not shop_list.get_selected_items().is_empty()
	var cart_has_selection := not cart_list.get_selected_items().is_empty()

	add_button.disabled = not shop_has_selection
	remove_button.disabled = not cart_has_selection

	var cart_empty := cart.is_empty()

	# IMPORTANT: affordability should use the discounted total the player will actually pay
	var final_total := _compute_total_discounted()
	var can_afford := MoneySystem.can_afford(final_total)

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
		cart.erase(id)
		_last_cart_selected_id = ""
	else:
		cart[id] = current - 1

	_refresh_cart()

func _on_buy_pressed() -> void:
	if cart.is_empty():
		return

	# Charge the discounted amount (player pays what UI shows)
	var final_total := _compute_total_discounted()
	if not MoneySystem.can_afford(final_total):
		return
	if not MoneySystem.spend(final_total):
		return

	# Optional cozy toast showing savings (very low risk)
	var savings := _compute_heart_savings()
	
	
	if savings > 0:
		var qe := get_node_or_null("/root/QuestEvents")
		if qe != null and qe.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("Valley Heart Blessing saved you %dg today." % savings, "success", 2.5)

	# Give items to player
	for id_any in cart.keys():
		var id := String(id_any)
		var count := int(cart[id_any])
		var inv_name := id
		GameState.inventory_add(inv_name, count)
		QuestEvents.item_purchased.emit(inv_name, count)

	play_buy_sfx()

	cart.clear()
	_refresh_cart()

func play_buy_sfx() -> void:
	if buy_sounds.is_empty():
		return
	shop_sfx.stream = buy_sounds[randi() % buy_sounds.size()]
	shop_sfx.pitch_scale = randf_range(0.98, 1.03)
	shop_sfx.play()
