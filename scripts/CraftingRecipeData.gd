extends Resource
class_name CraftingRecipeData

@export var id: String = ""
@export var display_name: String = ""
@export var category: String = "Gifts"

# Requirements: key can be String item_id ("Flower") OR ItemData Resource
@export var requires: Dictionary = {}

@export var output_item_id: String = ""
@export var output_qty: int = 1
@export var description: String = ""

func _key_to_item_id(key) -> String:
	# 1) If the key is already a string, perfect.
	if typeof(key) == TYPE_STRING:
		return key

	# 2) If the key is a Resource/Object (e.g., ItemData), try to pull an id field.
	# This supports you dragging ItemData resources into the dictionary in the inspector.
	if typeof(key) == TYPE_OBJECT and key != null:
		# Most ItemData setups have an exported field named "id"
		# Using get("id") is safe even if the field doesn't exist (returns null).
		var v = key.get("id")
		if v != null:
			return str(v)

		# fallback: some people name it item_id
		v = key.get("item_id")
		if v != null:
			return str(v)

	# 3) Could not resolve
	return ""

func can_craft(inventory: Dictionary) -> bool:
	for raw_key in requires.keys():
		var item_id := _key_to_item_id(raw_key)
		if item_id == "":
			# If we can't resolve the key, treat as not craftable.
			return false

		var need := int(requires[raw_key])
		var have := int(inventory.get(item_id, 0))
		if have < need:
			return false
	return true

func get_requirements_as_lines(inventory: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for raw_key in requires.keys():
		var item_id := _key_to_item_id(raw_key)
		var need := int(requires[raw_key])
		var have := int(inventory.get(item_id, 0))

		if item_id == "":
			lines.append("• (Invalid requirement key) x%d" % need)
			continue

		if need <= 1:
			lines.append("• %s (%d/%d)" % [item_id, have, need])
		else:
			lines.append("• %s x%d (%d/%d)" % [item_id, need, have, need])

	return lines

func consume_requirements(inventory_remove_fn: Callable) -> void:
	# Calls GameState.inventory_remove(item_id, qty) via callable
	for raw_key in requires.keys():
		var item_id := _key_to_item_id(raw_key)
		if item_id == "":
			continue
		var need := int(requires[raw_key])
		inventory_remove_fn.call(item_id, need)
