# res://ui/ShopUI.gd
extends BaseOverlay

# --- NEW: visual containers ---
@onready var shop_wrap: FlowContainer = $Panel/Margin/Root/BodyRow/LeftCol/ShopScroll/ShopWrap
@onready var cart_stack: VBoxContainer = $Panel/Margin/Root/BodyRow/RightCol/CartScroll/CartStack

# --- Buttons / labels stay the same ---
@onready var add_button: Button = $Panel/Margin/Root/BodyRow/LeftCol/AddButton
@onready var remove_button: Button = $Panel/Margin/Root/BodyRow/RightCol/RemoveButton
@onready var total_label: Label = $Panel/Margin/Root/FooterRow/TotalLabel
@onready var buy_button: Button = $Panel/Margin/Root/FooterRow/BuyButton
@onready var close_button: Button = $Panel/Margin/Root/HeaderRow/CloseButton

@onready var shop_sfx: AudioStreamPlayer2D = $ShopSfx2D
@export var buy_sounds: Array[AudioStream] = []

# --- Card scenes ---
@export var shelf_card_scene: PackedScene = preload("res://tscn/ShelfItemCard.tscn")
@export var cart_row_scene: PackedScene = preload("res://tscn/CartItemRow.tscn")

# Which shop is this UI representing?
@export var shop_id: String = "GeneralStore"

# Loaded from ShopCatalogDb; same shape as before:
# [{ "id": "...", "name": "...", "price": 10 }, ...]
var shop_items: Array = []

# cart[item_id] = count
var cart: Dictionary = {}

# --- Selection state (replaces ItemList selection) ---
var _selected_shop_id: String = ""
var _last_cart_selected_id: String = ""

# ButtonGroups so only one stays “pressed” visually
var _shop_group := ButtonGroup.new()
var _cart_group := ButtonGroup.new()

# -------------------------------------------------------------------
# Heart discount helpers
# -------------------------------------------------------------------
func _get_shop_discount_multiplier() -> float:
	var mul := 1.0
	var hp := get_node_or_null("/root/HeartProgress")
	if hp != null and hp.has_method("get_shop_discount_multiplier"):
		mul = float(hp.call("get_shop_discount_multiplier"))
	if mul <= 0.0:
		mul = 1.0
	return mul

func _calc_discounted_unit_price(base_price: int) -> int:
	if base_price <= 0:
		return 0
	var mul := _get_shop_discount_multiplier()
	var p := int(floor(float(base_price) * mul))
	return max(1, p)

func _compute_subtotal_base() -> int:
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
	super._ready()
	if Engine.is_editor_hint():
		return

	close_button.pressed.connect(hide_overlay)
	add_button.pressed.connect(_on_add_pressed)
	remove_button.pressed.connect(_on_remove_pressed)
	buy_button.pressed.connect(_on_buy_pressed)

	_reload_catalog()
	_refresh_shop()
	_refresh_cart()

func show_overlay() -> void:
	super.show_overlay()
	_reload_catalog()
	_refresh_shop()
	_refresh_cart()

func _reload_catalog() -> void:
	# Pull items from ShopCatalogDb (preferred).
	if ShopCatalogDb != null and ShopCatalogDb.has_method("get_shop_items"):
		shop_items = ShopCatalogDb.get_shop_items(shop_id)
	else:
		shop_items = []

	# If the current selection is no longer in the catalog, clear it
	if _selected_shop_id != "" and _find_item_by_id(_selected_shop_id).is_empty():
		_selected_shop_id = ""

func _find_item_by_id(item_id: String) -> Dictionary:
	for item_any in shop_items:
		var item: Dictionary = item_any
		if String(item.get("id", "")) == item_id:
			return item
	return {}

func _get_item_icon(item_id: String) -> Texture2D:
	# Optional icons from ItemDb -> ItemData.icon
	if ItemDb != null and ItemDb.has_method("get_item"):
		var data = ItemDb.get_item(item_id)
		if data != null:
			var tex: Variant = data.icon
			if tex is Texture2D:
				return tex
	return null

# -------------------------------------------------------------------
# VISUAL REFRESH (Shelf cards + Cart rows)
# -------------------------------------------------------------------
func _clear_children(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()

func _refresh_shop() -> void:
	_clear_children(shop_wrap)

	for item_any in shop_items:
		var item: Dictionary = item_any
		var id := String(item.get("id", ""))
		if id == "":
			continue

		var display_name := String(item.get("name", "Item"))
		var base_price := int(item.get("price", 0))
		var final_unit := _calc_discounted_unit_price(base_price)

		var icon := _get_item_icon(id)

		var card = shelf_card_scene.instantiate()
		shop_wrap.add_child(card)

		card.button_group = _shop_group
		card.toggle_mode = true
		card.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE

		if card.has_method("set_data"):
			card.call("set_data", id, display_name, base_price, final_unit, icon)

		if card.has_signal("card_selected"):
			card.connect("card_selected", Callable(self, "_on_shelf_card_selected"))
		else:
			card.pressed.connect(_on_shelf_pressed_fallback.bind(id))

		if id == _selected_shop_id:
			card.button_pressed = true

	_update_buttons()

func _refresh_cart() -> void:
	_clear_children(cart_stack)

	var mul := _get_shop_discount_multiplier()
	var show_discount := mul < 0.999

	var ids: Array[String] = []
	for id_any in cart.keys():
		var id := String(id_any)
		if int(cart[id_any]) > 0:
			ids.append(id)
	ids.sort()

	for id in ids:
		var count := int(cart.get(id, 0))
		var item := _find_item_by_id(id)
		if item.is_empty():
			continue

		var display_name := String(item.get("name", "Item"))
		var base_price := int(item.get("price", 0))

		var base_line_total := base_price * count
		var final_unit := _calc_discounted_unit_price(base_price)
		var final_line_total := final_unit * count

		var row = cart_row_scene.instantiate()
		cart_stack.add_child(row)

		row.button_group = _cart_group
		row.toggle_mode = true
		row.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE

		if row.has_method("set_data"):
			row.call("set_data", id, display_name, count, base_line_total, final_line_total)

		if row.has_signal("row_selected"):
			row.connect("row_selected", Callable(self, "_on_cart_row_selected"))
		else:
			row.pressed.connect(_on_cart_pressed_fallback.bind(id))

		if id == _last_cart_selected_id:
			row.button_pressed = true

	var base_total := _compute_subtotal_base()
	var final_total := _compute_total_discounted()
	var savings_total: Variant = max(0, base_total - final_total)

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

# -------------------------------------------------------------------
# Selection handlers
# -------------------------------------------------------------------
func _on_shelf_card_selected(item_id: String) -> void:
	_selected_shop_id = item_id
	_update_buttons()

func _on_shelf_pressed_fallback(item_id: String) -> void:
	_selected_shop_id = item_id
	_update_buttons()

func _on_cart_row_selected(item_id: String) -> void:
	_last_cart_selected_id = item_id
	_update_buttons()

func _on_cart_pressed_fallback(item_id: String) -> void:
	_last_cart_selected_id = item_id
	_update_buttons()

# -------------------------------------------------------------------
# Buttons
# -------------------------------------------------------------------
func _update_buttons() -> void:
	var shop_has_selection := (_selected_shop_id != "")
	var cart_has_selection := (_last_cart_selected_id != "")

	add_button.disabled = not shop_has_selection
	remove_button.disabled = not cart_has_selection

	var cart_empty := cart.is_empty()

	var final_total := _compute_total_discounted()
	var can_afford := MoneySystem.can_afford(final_total)

	buy_button.disabled = cart_empty or not can_afford

func _on_add_pressed() -> void:
	if _selected_shop_id == "":
		return

	var item := _find_item_by_id(_selected_shop_id)
	if item.is_empty():
		_selected_shop_id = ""
		_refresh_shop()
		return

	cart[_selected_shop_id] = int(cart.get(_selected_shop_id, 0)) + 1
	_last_cart_selected_id = _selected_shop_id
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

	var final_total := _compute_total_discounted()
	if not MoneySystem.can_afford(final_total):
		return
	if not MoneySystem.spend(final_total):
		return

	var savings := _compute_heart_savings()
	if savings > 0:
		var qe := get_node_or_null("/root/QuestEvents")
		if qe != null and qe.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("Valley Heart Blessing saved you %dg today." % savings, "success", 2.5)

	for id_any in cart.keys():
		var id := String(id_any)
		var count := int(cart[id_any])
		GameState.inventory_add(id, count)
		QuestEvents.item_purchased.emit(id, count)

	play_buy_sfx()

	cart.clear()
	_last_cart_selected_id = ""
	_refresh_cart()

func play_buy_sfx() -> void:
	if buy_sounds.is_empty():
		return
	shop_sfx.stream = buy_sounds[randi() % buy_sounds.size()]
	shop_sfx.pitch_scale = randf_range(0.98, 1.03)
	shop_sfx.play()
