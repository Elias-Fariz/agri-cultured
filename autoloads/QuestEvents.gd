extends Node
class_name QuestEvent

signal went_to(location_id: String)

signal chopped_tree(amount: int)
signal broke_rock(amount: int)

signal crop_harvested(item_id: String, amount: int)
signal pet_animal(animal_id: String)
signal fed_animal(animal_id: String)
signal collected_product(product_id: String, amount: int)

signal soil_tilled(target_id: String, qty: int)
signal seed_planted(crop_id: String, qty: int)
signal crop_watered(target_id: String, qty: int)

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

signal fish_caught(fish_id: String, qty: int)

signal object_interacted(interactable_id: String, quest_target_id: String, qty: int)


func _ready() -> void:
	talked_to.connect(func(npc_id: String):
		GameState.apply_quest_event("talk_to", npc_id, 1)
	)

	went_to.connect(func(location_id: String):
		GameState.apply_quest_event("go_to", location_id, 1)
	)

	entered_location.connect(func(location_id: String):
		GameState.apply_quest_event("go_to", location_id, 1)
	)

	shipped.connect(func(item_id: String, qty: int):
		GameState.apply_quest_event("ship", item_id, qty)
	)

	ui_opened.connect(func(ui_id: String):
		GameState.apply_quest_event("ui_open", ui_id, 1)
	)

	item_purchased.connect(func(item_id: String, qty: int):
		GameState.apply_quest_event("buy", item_id, qty)
	)

	fish_caught.connect(func(fish_id: String, qty: int):
		GameState.apply_quest_event("fish", fish_id, qty)
	)

	crop_harvested.connect(func(item_id: String, qty: int):
		GameState.apply_quest_event("harvest", item_id, qty)
	)

	item_picked_up.connect(func(item_id: String, qty: int):
		GameState.apply_quest_event("pickup", item_id, qty)
	)

	item_crafted.connect(func(item_id: String, qty: int):
		GameState.apply_quest_event("craft", item_id, qty)
	)

	item_gifted.connect(func(npc_id: String, item_id: String, qty: int):
		GameState.apply_quest_event("gift", item_id, qty, npc_id)
	)

	object_interacted.connect(func(_interactable_id: String, quest_target_id: String, qty: int):
		GameState.apply_quest_event("interact", quest_target_id, qty)
	)

	chopped_tree.connect(func(amount: int):
		GameState.apply_quest_event("chop_tree", "", amount)
	)

	broke_rock.connect(func(amount: int):
		GameState.apply_quest_event("break_rock", "", amount)
	)

	action_done.connect(func(action: String, amount: int):
		GameState.apply_quest_event(action, "", amount)
	)

	soil_tilled.connect(func(target_id: String, qty: int):
		GameState.apply_quest_event("till", target_id, qty)
	)

	seed_planted.connect(func(crop_id: String, qty: int):
		GameState.apply_quest_event("plant", crop_id, qty)
	)

	crop_watered.connect(func(target_id: String, qty: int):
		GameState.apply_quest_event("water", target_id, qty)
	)
