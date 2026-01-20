extends Node
class_name QuestEvent

signal went_to(location_id: String)

signal chopped_tree(amount: int)
signal broke_rock(amount: int)

signal harvested(item_id: String, amount: int)
signal pet_animal(animal_id: String)
signal fed_animal(animal_id: String)
signal collected_product(product_id: String, amount: int)


signal talked_to(npc_id: String)
signal entered_location(location_id: String)
signal shipped(item_id: String, qty: int)
signal action_done(action: String, amount: int)
signal ui_opened(ui_id: String)
signal item_purchased(item_id: String, qty: int)

signal quest_state_changed
signal toast_requested(text: String, kind: String, duration: float)

signal item_picked_up(item_id: String, qty: int)
signal item_crafted(item_id: String, qty: int)
signal item_gifted(npc_id: String, item_id: String, qty: int)

func _ready() -> void:
	talked_to.connect(func(npc_id: String):
		GameState.apply_quest_event("talk_to", npc_id, 1)
	)

	entered_location.connect(func(loc_id: String):
		GameState.apply_quest_event("go_to", loc_id, 1)
	)

	shipped.connect(func(item_id: String, qty: int):
		GameState.apply_quest_event("ship", item_id, qty)
	)

	action_done.connect(func(action: String, amount: int):
		# For things like "chop_tree"
		GameState.apply_quest_event(action, "", amount)
	)
	
	ui_opened.connect(func(ui_id: String):
		GameState.apply_quest_event("ui_open", ui_id, 1)
	)

	item_purchased.connect(func(item_id: String, qty: int):
		GameState.apply_quest_event("buy", item_id, qty)
	)
#
	#chopped_tree.connect(func(qty: int):
		#GameState.apply_quest_event("chop_tree", "", qty)
	#)
