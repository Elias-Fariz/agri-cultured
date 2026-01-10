extends Resource
class_name ItemData

@export var id: String = ""               # "Egg"
@export var display_name: String = ""     # "Egg"
@export var icon: Texture2D               # optional for now
@export var sell_price: int = 0
@export var shippable: bool = true

# Later (not required now):
@export var description: String = ""
@export var tags: Array[String] = []      # ["animal_product", "food"]

@export var stack_limit: int = 999
