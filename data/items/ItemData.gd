extends Resource
class_name ItemData

@export var id: String = ""               # "Egg"
@export var display_name: String = ""     # "Egg"
@export var icon: Texture2D               # optional for now
@export var sell_price: int = 0
@export var shippable: bool = true

# Later (not required now):
@export var description: String = ""
# Tags let you categorize items for UI sorting, quest matching, gifting, etc.
# Examples: ["gift", "forage", "craft_material", "food"]
@export var tags: Array[String] = []      # ["animal_product", "food"]

@export var stack_limit: int = 999

@export var energy_restore: int = 0  # 0 = not food, >0 = restores energy when consumed

# -----------------------------------------------------------------------------
# Tag helpers (safe, no side effects)
# -----------------------------------------------------------------------------
func get_tags() -> Array[String]:
	# Return a copy to prevent accidental external mutation
	return tags.duplicate()

func has_tag(tag: String) -> bool:
	var t := tag.strip_edges().to_lower()
	if t == "":
		return false
	for x in tags:
		if String(x).strip_edges().to_lower() == t:
			return true
	return false
