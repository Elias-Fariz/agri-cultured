extends BaseOverlay

@onready var available_list: ItemList = $Panel/Margin/Root/BodyRow/LeftCol/AvailableList
@onready var accept_button: Button = $Panel/Margin/Root/BodyRow/LeftCol/AcceptButton
@onready var active_list: ItemList = $Panel/Margin/Root/BodyRow/RightCol/ActiveList
@onready var close_button: Button = $Panel/Margin/Root/HeaderRow/CloseButton
@onready var info_label: Label = $Panel/Margin/Root/FooterRow/InfoLabel  # optional but helpful
@onready var completed_list: ItemList = $Panel/Margin/Root/BodyRow/RightCol/CompletedList
@onready var claim_button: Button = $Panel/Margin/Root/BodyRow/RightCol/ClaimButton

var available_quests: Array[Dictionary] = []
var _available_ids: Array[String] = []  # maps list row -> quest id
var _completed_ids: Array[String] = []

func _ready() -> void:
	close_button.pressed.connect(hide_overlay)
	accept_button.pressed.connect(_on_accept_pressed)
	available_list.item_selected.connect(_on_available_selected)
	claim_button.pressed.connect(_on_claim_pressed)
	completed_list.item_selected.connect(_on_completed_selected)

	# Example board postings (templates). Keep these simple for now.
	available_quests = [
		{
			"id": "ship_watermelon",
			"title": "Fresh Produce Needed",
			"description": "Ship 1 Watermelon",
			"type": "ship",
			"target": "Watermelon",
			"amount": 1,
			"progress": 0,
			"reward": { "money": 100 },
			"completed": false,
			"claimed": false,
		},
		{
			"id": "chop_3_trees",
			"title": "Lumber Request",
			"description": "Chop down 3 trees",
			"type": "chop_tree",
			"amount": 3,
			"progress": 0,
			"reward": { "money": 120 },
			"completed": false,
			"claimed": false,
		},
	]
	_refresh()
 
func show_overlay() -> void:
	super.show_overlay()
	_refresh()

func hide_overlay() -> void:
	super.hide_overlay()

func _refresh() -> void:
	_refresh_available()
	_refresh_active()
	_refresh_completed()
	_update_button_states()

func _refresh_available() -> void:
	available_list.clear()
	_available_ids.clear()

	for q in available_quests:
		var id := String(q.get("id", ""))
		if id == "":
			continue

		# Don’t show if already active or already completed (for now)
		if GameState.active_quests.has(id):
			continue
		if GameState.completed_quests.has(id):
			continue

		_available_ids.append(id)
		available_list.add_item("%s" % String(q.get("title", "Quest")))
		
func _refresh_active() -> void:
	active_list.clear()

	for quest_any in GameState.active_quests.values():
		var quest: Dictionary = quest_any
		var title := String(quest.get("title", "Quest"))
		var progress := int(quest.get("progress", 0))
		var amount := int(quest.get("amount", 0))
		active_list.add_item("%s (%d/%d)" % [title, progress, amount])

func _refresh_completed() -> void:
	completed_list.clear()
	_completed_ids.clear()

	for id_any in GameState.completed_quests.keys():
		var quest_id := String(id_any)
		var quest: Dictionary = GameState.completed_quests[quest_id]

		var title := String(quest.get("title", "Quest"))
		var claimed := bool(quest.get("claimed", false))

		_completed_ids.append(quest_id)

		if claimed:
			completed_list.add_item("%s (claimed)" % title)
		else:
			completed_list.add_item("%s (READY)" % title)

	# Optional: keep stable order
	_completed_ids.sort()

func _update_accept_button_state() -> void:
	accept_button.disabled = available_list.get_selected_items().is_empty()

func _update_button_states() -> void:
	accept_button.disabled = available_list.get_selected_items().is_empty()
	claim_button.disabled = completed_list.get_selected_items().is_empty()

func _on_available_selected(_idx: int) -> void:
	_update_accept_button_state()

func _on_accept_pressed() -> void:
	var selected := available_list.get_selected_items()
	if selected.is_empty():
		if info_label: info_label.text = "Select a quest first."
		return

	var row := int(selected[0])
	if row < 0 or row >= _available_ids.size():
		if info_label: info_label.text = "Selection out of range."
		return

	var quest_id := _available_ids[row]

	# Find the quest template by id
	var template: Dictionary = {}
	for q in available_quests:
		if String(q.get("id", "")) == quest_id:
			template = q
			break

	if template.is_empty():
		if info_label: info_label.text = "Could not find quest data."
		return

	# Add to GameState as an active quest
	GameState.add_quest(template)

	if info_label: info_label.text = "Accepted: %s" % String(template.get("title", "Quest"))
	_refresh()

func _on_completed_selected(_idx: int) -> void:
	_update_button_states()

func _on_claim_pressed() -> void:
	var selected := completed_list.get_selected_items()
	if selected.is_empty():
		return

	var row := int(selected[0])
	if row < 0 or row >= _completed_ids.size():
		return

	var quest_id := _completed_ids[row]

	# Only claim if not already claimed
	var quest: Dictionary = GameState.completed_quests.get(quest_id, {})
	if quest.is_empty():
		return
	if bool(quest.get("claimed", false)):
		if info_label: info_label.text = "Already claimed."
		return

	GameState.claim_quest_reward(quest_id)

	if info_label: info_label.text = "Reward claimed!"
	_refresh()
