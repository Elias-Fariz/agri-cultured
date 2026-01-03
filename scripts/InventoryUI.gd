# InventoryUI.gd
extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var item_list: ItemList = $Panel/VBoxContainer/ItemList

func set_items(items: Array[String]) -> void:
	item_list.clear()

	var counts := {}
	for it in items:
		counts[it] = int(counts.get(it, 0)) + 1

	for key in counts.keys():
		item_list.add_item("%s x%d" % [str(key), counts[key]])


func show_ui() -> void:
	panel.visible = true

func hide_ui() -> void:
	panel.visible = false

func toggle_ui() -> void:
	panel.visible = not panel.visible

func is_open() -> bool:
	return panel.visible
