# InventoryUI.gd
extends BaseOverlay

@onready var panel: Panel = $Panel
@onready var item_list: ItemList = $Panel/VBoxContainer/ItemList

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	# Any other runtime setup

func set_items(items: Dictionary) -> void:
	item_list.clear()

	for key in items.keys():
		var count := int(items[key])
		item_list.add_item("%s x%d" % [str(key), count])

func show_ui() -> void:
	super.show_overlay()

func hide_ui() -> void:
	super.hide_overlay()

func toggle_ui() -> void:
	if panel.visible:
		hide_ui()
	else:
		show_ui()

func is_open() -> bool:
	return panel.visible
