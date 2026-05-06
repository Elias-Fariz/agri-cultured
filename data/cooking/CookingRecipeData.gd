extends Resource
class_name CookingRecipeData

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

# First-pass exact ingredients.
# Example:
# {
#   "Milk": 1,
#   "Egg": 1
# }
@export var ingredients: Dictionary[String, int] = {}

@export var output_item_id: String = ""
@export var output_qty: int = 1

# Optional metadata for later filtering / gifting / UI.
# Examples: ["food", "comfort", "gift", "fish", "dairy"]
@export var tags: Array[String] = []

# Optional flavor text shown in the UI.
@export_multiline var cooking_note: String = ""

@export var food_effects: Array[FoodEffectData] = []


func is_valid() -> bool:
	return id.strip_edges() != "" and output_item_id.strip_edges() != "" and output_qty > 0


func can_cook(inventory: Dictionary) -> bool:
	if not is_valid():
		return false

	for item_any in ingredients.keys():
		var item_id := String(item_any)
		var needed := int(ingredients[item_any])

		if item_id.strip_edges() == "" or needed <= 0:
			continue

		var have := int(inventory.get(item_id, 0))
		if have < needed:
			return false

	return true


func consume_ingredients(remove_callable: Callable) -> void:
	for item_any in ingredients.keys():
		var item_id := String(item_any)
		var needed := int(ingredients[item_any])

		if item_id.strip_edges() == "" or needed <= 0:
			continue

		remove_callable.call(item_id, needed)


func get_requirements_as_lines(inventory: Dictionary) -> Array[String]:
	var lines: Array[String] = []

	for item_any in ingredients.keys():
		var item_id := String(item_any)
		var needed := int(ingredients[item_any])
		var have := int(inventory.get(item_id, 0))

		var mark := "✅" if have >= needed else "❌"
		lines.append("%s %s: %d/%d" % [mark, item_id, have, needed])

	return lines


func has_tag(tag: String) -> bool:
	var t := tag.strip_edges().to_lower()
	if t == "":
		return false

	for x in tags:
		if String(x).strip_edges().to_lower() == t:
			return true

	return false

func get_effects_as_lines() -> Array[String]:
	var lines: Array[String] = []

	for effect in food_effects:
		if effect == null:
			continue
		if not effect.is_valid():
			continue

		lines.append("✨ " + effect.get_display_line())

	return lines
