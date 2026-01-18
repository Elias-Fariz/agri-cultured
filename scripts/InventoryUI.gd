# InventoryUI.gd
extends BaseOverlay

@onready var panel: Panel = $Panel
@onready var item_list: ItemList = $Panel/VBoxContainer/ItemList

var _selected_item_id: String = ""
var _selected_index: int = -1

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	# Track selection changes
	item_list.item_selected.connect(_on_item_selected)
	item_list.item_activated.connect(_on_item_activated) # double-click or Enter depending on OS

	_refresh_from_gamestate()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not is_open():
		return

	# Press Enter to "use" the selected item (eat if edible)
	if event.is_action_pressed("ui_accept"):
		_try_use_selected()
		get_viewport().set_input_as_handled()
		return

	# Optional: Press E to use as well (only if you want)
	# Make sure you have an input action named "interact" or "ui_use"
	if event.is_action_pressed("interact"):
		_try_use_selected()
		get_viewport().set_input_as_handled()
		return


func set_items(items: Dictionary) -> void:
	item_list.clear()

	# Keep stable ordering so selection doesn't jump too much
	var keys: Array = items.keys()
	keys.sort()

	for key_any in keys:
		var id := String(key_any)
		var count := int(items[key_any])
		var row_text := "%s x%d" % [id, count]

		# Store the item id in metadata so we can retrieve it safely
		var idx := item_list.add_item(row_text)
		item_list.set_item_metadata(idx, id)

	# Restore selection if possible
	_restore_selection()


func show_ui() -> void:
	super.show_overlay()
	_refresh_from_gamestate()


func hide_ui() -> void:
	super.hide_overlay()


func toggle_ui() -> void:
	if panel.visible:
		hide_ui()
	else:
		show_ui()


func is_open() -> bool:
	return panel.visible


# -------------------------
# Internals
# -------------------------

func _refresh_from_gamestate() -> void:
	# Assumes GameState.inventory is your Dictionary of item_id -> qty
	# If it’s named differently, tell me and I’ll adjust.
	set_items(GameState.inventory)


func _on_item_selected(index: int) -> void:
	_selected_index = index
	_selected_item_id = _get_item_id_at(index)


func _on_item_activated(index: int) -> void:
	# Activated is like double-click / Enter
	_selected_index = index
	_selected_item_id = _get_item_id_at(index)
	_try_use_selected()


func _get_item_id_at(index: int) -> String:
	if index < 0 or index >= item_list.item_count:
		return ""
	var meta = item_list.get_item_metadata(index)
	return String(meta)


func _try_use_selected() -> void:
	if _selected_item_id == "":
		# Nothing selected: pick first item if exists (friendly)
		if item_list.item_count > 0:
			item_list.select(0)
			_on_item_selected(0)
		else:
			return

	# Try to consume (eat)
	var used := GameState.consume_item(_selected_item_id)
	if used:
		_refresh_from_gamestate()

		# If the selected item disappeared (qty hit 0), update selection
		_restore_selection()
	else:
		# Optional: feedback if not edible or energy full
		# (Keep it quiet if you prefer)
		pass


func _restore_selection() -> void:
	if item_list.item_count <= 0:
		_selected_index = -1
		_selected_item_id = ""
		return

	# If we still have same item id somewhere, reselect it
	if _selected_item_id != "":
		for i in range(item_list.item_count):
			if _get_item_id_at(i) == _selected_item_id:
				item_list.select(i)
				_selected_index = i
				return

	# Otherwise select first item
	item_list.select(0)
	_selected_index = 0
	_selected_item_id = _get_item_id_at(0)
