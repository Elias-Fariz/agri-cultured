extends BaseOverlay

@onready var available_list: ItemList = $Panel/Margin/Root/BodyRow/LeftCol/AvailableList
@onready var accept_button: Button = $Panel/Margin/Root/BodyRow/LeftCol/AcceptButton
@onready var active_list: ItemList = $Panel/Margin/Root/BodyRow/RightCol/ActiveList
@onready var close_button: Button = $Panel/Margin/Root/HeaderRow/CloseButton
@onready var info_label: Label = $Panel/Margin/Root/FooterRow/InfoLabel
@onready var completed_list: ItemList = $Panel/Margin/Root/BodyRow/RightCol/CompletedList
@onready var claim_button: Button = $Panel/Margin/Root/BodyRow/RightCol/ClaimButton

# ✅ Inspector-driven list of QuestData resources
@export var available_quests: Array[QuestData] = []

var _available_ids: Array[String] = []
var _completed_ids: Array[String] = []

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	close_button.pressed.connect(hide_overlay)
	accept_button.pressed.connect(_on_accept_pressed)
	available_list.item_selected.connect(_on_available_selected)
	claim_button.pressed.connect(_on_claim_pressed)
	completed_list.item_selected.connect(_on_completed_selected)

	# ✅ Refresh whenever anything quest-related changes
	if QuestEvents and QuestEvents.has_signal("quest_state_changed"):
		QuestEvents.quest_state_changed.connect(_refresh)

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

	# Helpful debug (remove later)
	print("QuestBoardUI: available_quests size =", available_quests.size())

	for qres: QuestData in available_quests:
		if qres == null:
			continue
		
		# NEW: prerequisite gate
		if not qres.is_unlocked():
			continue

		var id: String = qres.id
		if id == "":
			continue

		# Don’t show if already active or completed
		if GameState.active_quests.has(id):
			continue
		if GameState.completed_quests.has(id):
			continue

		_available_ids.append(id)
		var title := qres.title if qres.title != "" else "Quest"
		available_list.add_item(title)

func _refresh_active() -> void:
	active_list.clear()

	for quest_any in GameState.active_quests.values():
		var quest: Dictionary = quest_any
		var title := String(quest.get("title", "Quest"))

		# If chain, show the current objective text (nicer)
		if String(quest.get("type", "")) == "chain":
			var obj := GameState.get_quest_objective_text(quest)
			active_list.add_item("%s - %s" % [title, obj])
		else:
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

func _update_button_states() -> void:
	accept_button.disabled = available_list.get_selected_items().is_empty()
	claim_button.disabled = completed_list.get_selected_items().is_empty()

func _on_available_selected(_idx: int) -> void:
	_update_button_states()

func _on_accept_pressed() -> void:
	var selected := available_list.get_selected_items()
	if selected.is_empty():
		if info_label: info_label.text = "Select a quest to accept."
		return

	var row := int(selected[0])
	if row < 0 or row >= _available_ids.size():
		if info_label: info_label.text = "Selection out of range."
		return

	var quest_id := _available_ids[row]

	# Find QuestData by id
	var qres: QuestData = null
	for q: QuestData in available_quests:
		if q != null and q.id == quest_id:
			qres = q
			break

	if qres == null:
		if info_label: info_label.text = "Could not find quest data."
		return

	GameState.add_quest(qres.to_dict())

	# Notify + refresh immediately
	QuestEvents.quest_state_changed.emit()
	if info_label: info_label.text = "Accepted: %s" % (qres.title if qres.title != "" else quest_id)
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
	var quest: Dictionary = GameState.completed_quests.get(quest_id, {})
	if quest.is_empty():
		return

	if bool(quest.get("claimed", false)):
		if info_label: info_label.text = "Already claimed."
		return

	GameState.claim_quest_reward(quest_id)
	QuestEvents.quest_state_changed.emit()

	if info_label: info_label.text = "Reward claimed!"
	_refresh()

func debug_print_available_quests() -> void:
	print("QuestBoardUI DEBUG path:", get_path())
	print("available_quests size:", available_quests.size())
	for i in range(available_quests.size()):
		var q := available_quests[i]
		if q == null:
			print("  [", i, "] null")
		else:
			print("  [", i, "] id=", q.id, " title=", q.title)
