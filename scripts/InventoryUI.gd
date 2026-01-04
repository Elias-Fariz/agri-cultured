# InventoryUI.gd
extends BaseOverlay

@onready var panel: Panel = $Panel
@onready var item_list: ItemList = $Panel/VBoxContainer/ItemList

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	# Any other runtime setup

func set_items(items: Array[String]) -> void:
	item_list.clear()

	var counts := {}
	for it in items:
		counts[it] = int(counts.get(it, 0)) + 1

	for key in counts.keys():
		item_list.add_item("%s x%d" % [str(key), counts[key]])


func show_ui() -> void:
	panel.visible = true
	TimeManager.pause_time()
	GameState.lock_gameplay()

func hide_ui() -> void:
	panel.visible = false
	TimeManager.resume_time()
	GameState.unlock_gameplay()

func toggle_ui() -> void:
	if panel.visible:
		hide_ui()
	else:
		show_ui()

func is_open() -> bool:
	return panel.visible
