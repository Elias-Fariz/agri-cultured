extends BaseOverlay

@onready var panel: PanelContainer = $Panel

@onready var inventory_list: ItemList = $Panel/Margin/Root/BodyRow/LeftCol/InventoryList
@onready var bin_list: ItemList = $Panel/Margin/Root/BodyRow/RightCol/BinList

@onready var payout_label: Label = $Panel/Margin/Root/FooterRow/PayoutLabel
@onready var close_button: Button = $Panel/Margin/Root/TitleRow/CloseButton

@onready var ship_one_button: Button = $Panel/Margin/Root/BodyRow/MidCol/ShipOneButton
@onready var ship_all_button: Button = $Panel/Margin/Root/BodyRow/MidCol/ShipAllButton
@onready var take_one_button: Button = $Panel/Margin/Root/BodyRow/MidCol/TakeOneButton
@onready var take_all_button: Button = $Panel/Margin/Root/BodyRow/MidCol/TakeAllButton

# We store the currently displayed keys so we can map a selected row -> item name.
var _inv_keys: Array[String] = []
var _bin_keys: Array[String] = []

func _ready() -> void:
	# BaseOverlay should handle: hide in editor, lock gameplay, pause time, etc.
	# We’ll just wire up buttons and refresh.

	close_button.pressed.connect(hide_overlay)

	ship_one_button.pressed.connect(_on_ship_one)
	ship_all_button.pressed.connect(_on_ship_all)
	take_one_button.pressed.connect(_on_take_one)
	take_all_button.pressed.connect(_on_take_all)

	inventory_list.item_selected.connect(_on_inventory_selected)
	bin_list.item_selected.connect(_on_bin_selected)

	_refresh_all()

func show_overlay() -> void:
	# If BaseOverlay already has show_overlay(), call super then refresh.
	super.show_overlay()
	_refresh_all()

func hide_overlay() -> void:
	super.hide_overlay()

func _refresh_all() -> void:
	_refresh_inventory_list()
	_refresh_bin_list()
	_refresh_payout_label()
	_update_button_states()

func _refresh_inventory_list() -> void:
	inventory_list.clear()
	_inv_keys.clear()

	# Only show items that exist + are shippable
	for key in GameState.inventory.keys():
		var item_name := str(key)
		var count := int(GameState.inventory[key])
		if count <= 0:
			continue
		if not GameState.is_shippable(item_name):
			continue

		_inv_keys.append(item_name)

	# Keep stable order for sanity
	_inv_keys.sort()

	for item_name in _inv_keys:
		var count := int(GameState.inventory.get(item_name, 0))
		var price := GameState.get_sell_price(item_name)
		# Example: "Watermelon x3 (35g)"
		inventory_list.add_item("%s x%d (%dg)" % [item_name, count, price])

func _refresh_bin_list() -> void:
	bin_list.clear()
	_bin_keys.clear()

	for key in GameState.shipping_bin.keys():
		var item_name := str(key)
		var count := int(GameState.shipping_bin[key])
		if count <= 0:
			continue
		_bin_keys.append(item_name)

	_bin_keys.sort()

	for item_name in _bin_keys:
		var count := int(GameState.shipping_bin.get(item_name, 0))
		var price := GameState.get_sell_price(item_name)
		bin_list.add_item("%s x%d (%dg)" % [item_name, count, price])

func _refresh_payout_label() -> void:
	var payout := GameState.shipping_calculate_payout()
	payout_label.text = "Tomorrow: %dg" % payout

func _update_button_states() -> void:
	var inv_has_selection := inventory_list.get_selected_items().size() > 0
	var bin_has_selection := bin_list.get_selected_items().size() > 0

	ship_one_button.disabled = not inv_has_selection
	ship_all_button.disabled = not inv_has_selection
	take_one_button.disabled = not bin_has_selection
	take_all_button.disabled = not bin_has_selection

func _get_selected_inventory_item() -> String:
	var selected := inventory_list.get_selected_items()
	if selected.size() == 0:
		return ""
	var idx := int(selected[0])
	if idx < 0 or idx >= _inv_keys.size():
		return ""
	return _inv_keys[idx]

func _get_selected_bin_item() -> String:
	var selected := bin_list.get_selected_items()
	if selected.size() == 0:
		return ""
	var idx := int(selected[0])
	if idx < 0 or idx >= _bin_keys.size():
		return ""
	return _bin_keys[idx]

func _on_inventory_selected(_index: int) -> void:
	# Optional: when selecting inventory, clear bin selection
	bin_list.deselect_all()
	_update_button_states()

func _on_bin_selected(_index: int) -> void:
	inventory_list.deselect_all()
	_update_button_states()

func _on_ship_one() -> void:
	var item_name := _get_selected_inventory_item()
	if item_name == "":
		return

	if GameState.ship_from_inventory(item_name, 1):
		_refresh_all()

func _on_ship_all() -> void:
	var item_name := _get_selected_inventory_item()
	if item_name == "":
		return

	var count := int(GameState.inventory.get(item_name, 0))
	if count <= 0:
		return

	if GameState.ship_from_inventory(item_name, count):
		_refresh_all()

func _on_take_one() -> void:
	var item_name := _get_selected_bin_item()
	if item_name == "":
		return

	if GameState.unship_to_inventory(item_name, 1):
		_refresh_all()

func _on_take_all() -> void:
	var item_name := _get_selected_bin_item()
	if item_name == "":
		return

	var count := int(GameState.shipping_bin.get(item_name, 0))
	if count <= 0:
		return

	if GameState.unship_to_inventory(item_name, count):
		_refresh_all()
