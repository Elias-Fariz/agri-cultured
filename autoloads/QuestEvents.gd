extends Node
class_name QuestEvent

signal talked_to(npc_id: String)
signal went_to(location_id: String)

signal shipped(item_id: String, amount: int)
signal chopped_tree(amount: int)
signal broke_rock(amount: int)

signal harvested(item_id: String, amount: int)
signal pet_animal(animal_id: String)
signal fed_animal(animal_id: String)
signal collected_product(product_id: String, amount: int)

signal quest_state_changed()

func _ready() -> void:
	quest_state_changed.connect(func(): print("QUEST STATE CHANGED"))
