extends Node
class_name ItemDB

# Folder where all ItemData .tres files live
const ITEM_FOLDER := "res://data/items"

# id -> ItemData
var items: Dictionary = {}

func _ready() -> void:
	load_items_from_folder()

func load_items_from_folder() -> void:
	items.clear()

	var dir := DirAccess.open(ITEM_FOLDER)
	if dir == null:
		push_warning("ItemDB: Could not open folder: %s" % ITEM_FOLDER)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		# Skip folders
		if dir.current_is_dir():
			file_name = dir.get_next()
			continue

		# Only load .tres (and optionally .res)
		if file_name.get_extension().to_lower() in ["tres", "res"]:
			var path := ITEM_FOLDER + "/" + file_name
			var res := load(path)

			if res is ItemData:
				var data := res as ItemData
				if data.id.is_empty():
					push_warning("ItemDB: ItemData at %s has empty id." % path)
				elif items.has(data.id):
					push_warning("ItemDB: Duplicate item id '%s' found at %s." % [data.id, path])
				else:
					items[data.id] = data
			else:
				push_warning("ItemDB: Resource at %s is not ItemData." % path)

		file_name = dir.get_next()

	dir.list_dir_end()

	print("ItemDB: Loaded items:", items.keys())

func get_item(id: String) -> ItemData:
	return items.get(id, null)

func get_sell_price(id: String) -> int:
	var d := get_item(id)
	return 0 if d == null else d.sell_price

func is_shippable(id: String) -> bool:
	var d := get_item(id)
	return false if d == null else d.shippable
