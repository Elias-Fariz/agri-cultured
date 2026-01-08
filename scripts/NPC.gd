extends CharacterBody2D

@export var npc_id: String = ""

@export var display_name: String
@export var dialogue_lines: Array[String] = []

@export var overhead_greeting_lines: Array[String] = []  # e.g. ["Hello there!", "Nice day, huh?"]
@export var overhead_idle_lines: Array[String] = []      # e.g. ["Watermelons...", "I should water the crops..."]

# Optional quest fields — only used if quest_id is non-empty
@export var quest_id: String = ""
@export var quest_title: String = ""
@export var quest_type: String = ""      # e.g. "ship" or "chop_tree"
@export var quest_target: String = ""    # e.g. "Watermelon"
@export var quest_amount: int = 1

@export var quest_reward_money: int = 0
@export var quest_reward_items: Dictionary[String, int] = {}
# e.g. { "Watermelon": 1 }

# Dialogue variants for quest states
@export var quest_request_lines: Array[String] = []       # when offering quest
@export var quest_in_progress_lines: Array[String] = []   # when you haven't finished yet
@export var quest_completed_lines: Array[String] = []     # when you return after finishing (gives reward)
@export var quest_after_thanks_lines: Array[String] = []  # later conversations after it’s all done

@onready var quest_icon: TextureRect = $BubbleAnchor/QuestIcon
@onready var chatter_label: Label = $BubbleAnchor/ChatterLabel
@onready var proximity_area: Area2D = $ProximityArea
@onready var chatter_timer: Timer = $ChatterTimer

@export var opens_shop: bool = false
@export var shop_title: String = "Shop"

func _ready() -> void:
	# ... your existing NPC init ...
	_update_quest_icon()

func start_dialogue() -> void:
	# SHOP CHECK FIRST
	if opens_shop:
		var shop_ui := get_tree().get_first_node_in_group("shop_ui")
		print("He has a shop!")
		if shop_ui:
			# Optional: set title if you want
			if shop_ui.has_method("set_title"):
				shop_ui.set_title(shop_title)
			print("He has a shopssss!")
			shop_ui.show_overlay()
		return

	# ... existing quest + friendship dialogue logic below ...
	
	var ui := get_tree().get_first_node_in_group("dialogue_ui")
	if ui== null:
		print("No DialogueUI found in group 'dialogue_ui'. Add DialogueUI.tscn to the scene and put it in that group.")
		return

	# Make sure it's actually our DialogueUI script, not just any CanvasLayer
	if not ui.has_method("show_dialogue"):
		print("Node in group 'dialogue_ui' does not have show_dialogue(). Reattach DialogueUI.gd to the DialogueUI CanvasLayer.")
		print("Found node:", ui.name, " type:", ui.get_class())
		return
	
	var current_day := TimeManager.day  # <-- adjust to your project

	# Gain friendship once per day on talk (recommended)
	if GameState.can_gain_talk_friendship(npc_id, current_day):
		GameState.add_friendship(npc_id, 1)
		GameState.mark_talked_today(npc_id, current_day)
		
	var f := GameState.get_friendship(npc_id)
	
	# If this NPC doesn’t have a quest attached, use normal dialogue.
	if quest_id == "":
		ui.show_dialogue(display_name, dialogue_lines, f)
		return
		
	# --- Quest-aware behavior below ---

	# 1) Quest already active and not completed → in-progress lines
	if GameState.active_quests.has(quest_id):
		if quest_in_progress_lines.size() > 0:
			ui.show_dialogue(display_name, quest_in_progress_lines, f)
		else:
			ui.show_dialogue(display_name, dialogue_lines, f)
		return

	# 2) Quest completed and not yet claimed → thank + reward
	if GameState.completed_quests.has(quest_id):
		var quest: Dictionary = GameState.completed_quests[quest_id]
		var claimed := bool(quest.get("claimed", false))

		if not claimed:
			# Give reward now
			GameState.claim_quest_reward(quest_id)
			_update_quest_icon()
			GameState.add_friendship(npc_id, 15)
			f = GameState.get_friendship(npc_id)

			if quest_completed_lines.size() > 0:
				ui.show_dialogue(display_name, quest_completed_lines, f)
			else:
				ui.show_dialogue(display_name, ["Thank you so much for your help!"], f)
		else:
			# Already claimed, show “after” lines
			if quest_after_thanks_lines.size() > 0:
				ui.show_dialogue(display_name, quest_after_thanks_lines, f)
			else:
				ui.show_dialogue(display_name, dialogue_lines, f)
		return

	# 3) Quest not started yet → offer + automatically accept
	var new_quest := _build_quest()
	if new_quest.is_empty():
		# Fallback to normal if something went wrong
		ui.show_dialogue(display_name, dialogue_lines, f)
		return

	GameState.add_quest(new_quest)
	_update_quest_icon()

	if quest_request_lines.size() > 0:
		ui.show_dialogue(display_name, quest_request_lines, f)
	else:
		ui.show_dialogue(display_name, dialogue_lines, f)

func _build_quest() -> Dictionary:
	if quest_id == "":
		return {}

	var reward_dict: Dictionary = {}
	if quest_reward_money != 0:
		reward_dict["money"] = quest_reward_money
	if quest_reward_items.size() > 0:
		reward_dict["items"] = quest_reward_items

	var description_text := ""
	if quest_request_lines.size() > 0:
		description_text = quest_request_lines[0]

	return {
		"id": quest_id,
		"title": quest_title if quest_title != "" else (display_name + "'s Request"),
		"description": description_text,
		"type": quest_type,
		"target": quest_target,
		"amount": quest_amount,
		"progress": 0,
		"reward": reward_dict,
		"completed": false,
		"claimed": false,
	}

func _update_quest_icon() -> void:
	if quest_icon == null:
		return

	var show := false

	if quest_id != "":
		# Quest not yet accepted and not completed → available
		if not GameState.active_quests.has(quest_id) and not GameState.completed_quests.has(quest_id):
			show = true
		# Quest completed but reward not claimed → ready to turn in
		elif GameState.completed_quests.has(quest_id):
			var q: Dictionary = GameState.completed_quests[quest_id]
			if not bool(q.get("claimed", false)):
				show = true

	quest_icon.visible = show

func _show_overhead_chatter() -> void:
	# Optionally hide the quest icon while text is shown
	if quest_icon:
		quest_icon.visible = false
	# ... then show chatter_label as before ...
	
	if chatter_label == null:
		return

	# Prefer greetings if available, otherwise idle lines
	var pool: Array[String] = []
	if overhead_greeting_lines.size() > 0:
		pool = overhead_greeting_lines
	elif overhead_idle_lines.size() > 0:
		pool = overhead_idle_lines

	if pool.is_empty():
		return

	var idx := randi() % pool.size()
	var text := pool[idx]

	print("I'm talking to you!")
	chatter_label.text = text
	chatter_label.visible = true
	chatter_timer.start()

func _hide_overhead_chatter() -> void:
	if chatter_label == null:
		return
	chatter_label.visible = false
	_update_quest_icon()

func _on_ProximityArea_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):  # assuming your Player is in group "player"
		return
	print("Proximity ENTER: ", body)
	_show_overhead_chatter()


func _on_ProximityArea_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	print("Proximity EXIT: ", body)
	_hide_overhead_chatter()

func _on_ChatterTimer_timeout() -> void:
	_hide_overhead_chatter()
