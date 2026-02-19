extends BaseOverlay

@onready var close_button: Button = $Panel/Margin/Root/HeaderRow/CloseButton
@onready var info_label: Label = $Panel/Margin/Root/FooterRow/InfoLabel

@onready var accept_button: Button = $Panel/Margin/Root/BodyRow/LeftCol/AcceptButton
@onready var claim_button: Button = $Panel/Margin/Root/BodyRow/RightCol/ClaimButton

# New containers (your paths)
@onready var available_wrap: Control = $Panel/Margin/Root/BodyRow/LeftCol/AvailableScroll/AvailableWrap
@onready var active_stack: Control = $Panel/Margin/Root/BodyRow/RightCol/ActiveScroll/ActiveStack
@onready var completed_stack: Control = $Panel/Margin/Root/BodyRow/RightCol/CompletedScroll/CompletedStack

# ✅ Inspector-driven list of QuestData resources
@export var available_quests: Array[QuestData] = []

# ✅ Quest paper scene
@export var quest_paper_scene: PackedScene = preload("res://ui/QuestPaperCard.tscn")

var _available_ids: Array[String] = []
var _completed_ids: Array[String] = []

var _selected_available_index: int = -1
var _selected_completed_index: int = -1

# ButtonGroups make selection behave nicely (one selected at a time per column)
var _available_group := ButtonGroup.new()
var _completed_group := ButtonGroup.new()

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	close_button.pressed.connect(hide_overlay)
	accept_button.pressed.connect(_on_accept_pressed)
	claim_button.pressed.connect(_on_claim_pressed)

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

	# If nothing selected, show a friendly default
	if info_label != null and info_label.text.strip_edges() == "":
		info_label.text = "Select a quest slip to see details."

# -------------------------------------------------------------------
# Build Available (papers)
# -------------------------------------------------------------------
func _refresh_available() -> void:
	_clear_children(available_wrap)
	_available_ids.clear()
	_selected_available_index = -1

	for qres: QuestData in available_quests:
		if qres == null:
			continue

		# Prerequisite gate
		if not qres.is_unlocked():
			continue

		var id: String = String(qres.id).strip_edges()
		if id == "":
			continue

		# Don’t show if already active or completed
		if GameState.active_quests.has(id):
			continue
		if GameState.completed_quests.has(id):
			continue

		_available_ids.append(id)

		var card := _make_paper_card_for_available(qres, _available_ids.size() - 1)
		available_wrap.add_child(card)

	_update_button_states()

func _make_paper_card_for_available(qres: QuestData, index: int) -> Button:
	var b := quest_paper_scene.instantiate() as Button

	# Selection behavior
	b.toggle_mode = true
	b.button_group = _available_group
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE

	# Display
	var title := qres.title if qres.title.strip_edges() != "" else "Quest"
	var subtitle := ""
	if qres.quest_type == "chain":
		subtitle = "Story quest"
	else:
		# Use the tracker text if present, otherwise a short description hint
		subtitle = qres.oneshot_text.strip_edges()
		if subtitle == "":
			subtitle = _shorten(qres.description, 60)

	_set_card_text(b, title, subtitle)

	# Click -> select + show info
	b.pressed.connect(_on_available_card_pressed.bind(index))
	return b

func _on_available_card_pressed(index: int) -> void:
	_selected_available_index = index
	_selected_completed_index = -1
	_update_button_states()

	# Show details in footer
	var qres := _get_questdata_by_available_index(index)
	if qres != null and info_label != null:
		info_label.text = _format_quest_details(qres)

# -------------------------------------------------------------------
# Build Active (pinned list) - display only for now
# -------------------------------------------------------------------
func _refresh_active() -> void:
	_clear_children(active_stack)

	for quest_any in GameState.active_quests.values():
		var quest: Dictionary = quest_any
		var title := String(quest.get("title", "Quest"))

		var line := ""
		if String(quest.get("type", "")) == "chain":
			var obj := GameState.get_quest_objective_text(quest)
			line = "%s — %s" % [title, obj]
		else:
			var progress := int(quest.get("progress", 0))
			var amount := int(quest.get("amount", 0))
			line = "%s (%d/%d)" % [title, progress, amount]

		var row := _make_simple_row_card(line)
		active_stack.add_child(row)

# -------------------------------------------------------------------
# Build Completed (papers)
# -------------------------------------------------------------------
func _refresh_completed() -> void:
	_clear_children(completed_stack)
	_completed_ids.clear()
	_selected_completed_index = -1

	for id_any in GameState.completed_quests.keys():
		var quest_id := String(id_any)
		var quest: Dictionary = GameState.completed_quests[quest_id]
		if quest.is_empty():
			continue

		_completed_ids.append(quest_id)

		var title := String(quest.get("title", "Quest"))
		var claimed := bool(quest.get("claimed", false))
		var subtitle := "READY to claim" if not claimed else "claimed"

		var card := _make_paper_card_for_completed(title, subtitle, _completed_ids.size() - 1)
		completed_stack.add_child(card)

	_update_button_states()

func _make_paper_card_for_completed(title: String, subtitle: String, index: int) -> Button:
	var b := quest_paper_scene.instantiate() as Button
	b.toggle_mode = true
	b.button_group = _completed_group
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE

	_set_card_text(b, title, subtitle)
	b.pressed.connect(_on_completed_card_pressed.bind(index))
	return b

func _on_completed_card_pressed(index: int) -> void:
	_selected_completed_index = index
	_selected_available_index = -1
	_update_button_states()

	# Show details using QuestData if we can find it, else fall back to dict
	if info_label == null:
		return

	var qid := _get_completed_id_by_index(index)
	if qid == "":
		return

	var qdict: Dictionary = GameState.completed_quests.get(qid, {})
	if qdict.is_empty():
		return

	# Prefer QuestData (nicer description + reward formatting)
	var qres := _get_questdata_by_id(qid)
	if qres != null:
		info_label.text = _format_quest_details(qres)
	else:
		# Fallback from dict
		var title := String(qdict.get("title", qid))
		var turn := String(qdict.get("turn_in_text", "")).strip_edges()
		var claimed := bool(qdict.get("claimed", false))
		info_label.text = "%s\n%s\n%s" % [
			title,
			(turn if turn != "" else "Reward ready."),
			("Claimed." if claimed else "Press Claim Reward.")
		]

# -------------------------------------------------------------------
# Buttons
# -------------------------------------------------------------------
func _update_button_states() -> void:
	accept_button.disabled = (_selected_available_index < 0 or _selected_available_index >= _available_ids.size())
	claim_button.disabled = (_selected_completed_index < 0 or _selected_completed_index >= _completed_ids.size())

func _on_accept_pressed() -> void:
	if _selected_available_index < 0 or _selected_available_index >= _available_ids.size():
		if info_label: info_label.text = "Select a quest slip to accept."
		return

	var quest_id := _available_ids[_selected_available_index]
	var qres := _get_questdata_by_id(quest_id)
	if qres == null:
		if info_label: info_label.text = "Could not find quest data."
		return

	GameState.add_quest(qres.to_dict())

	QuestEvents.quest_state_changed.emit()
	if info_label: info_label.text = "Accepted: %s" % (qres.title if qres.title != "" else quest_id)

func _on_claim_pressed() -> void:
	if _selected_completed_index < 0 or _selected_completed_index >= _completed_ids.size():
		return

	var quest_id := _completed_ids[_selected_completed_index]
	var quest: Dictionary = GameState.completed_quests.get(quest_id, {})
	if quest.is_empty():
		return

	if bool(quest.get("claimed", false)):
		if info_label: info_label.text = "Already claimed."
		return

	GameState.claim_quest_reward(quest_id)
	QuestEvents.quest_state_changed.emit()
	if info_label: info_label.text = "Reward claimed!"

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------
func _clear_children(node: Node) -> void:
	if node == null:
		return
	for c in node.get_children():
		c.queue_free()

func _get_questdata_by_id(quest_id: String) -> QuestData:
	for q: QuestData in available_quests:
		if q != null and String(q.id) == quest_id:
			return q
	return null

func _get_questdata_by_available_index(index: int) -> QuestData:
	if index < 0 or index >= _available_ids.size():
		return null
	return _get_questdata_by_id(_available_ids[index])

func _get_completed_id_by_index(index: int) -> String:
	if index < 0 or index >= _completed_ids.size():
		return ""
	return _completed_ids[index]

func _make_simple_row_card(text_line: String) -> Control:
	# Simple, safe display row without needing a new scene.
	var l := Label.new()
	l.text = text_line
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, 24)
	return l

func _set_card_text(card: Node, title: String, subtitle: String) -> void:
	# Assumes your QuestPaperCard.tscn has:
	# VBox/Title (Label) and VBox/Subtitle (Label)
	# If your node names differ, tell me and I’ll adjust to your exact names.
	var title_label := card.get_node_or_null("VBox/Title") as Label
	if title_label != null:
		title_label.text = title

	var sub_label := card.get_node_or_null("VBox/Subtitle") as Label
	if sub_label != null:
		sub_label.text = subtitle

func _format_quest_details(qres: QuestData) -> String:
	var lines: Array[String] = []

	var title := qres.title.strip_edges()
	if title == "":
		title = qres.id
	lines.append(title)

	var desc := qres.description.strip_edges()
	if desc != "":
		lines.append(desc)

	# Reward preview
	var reward_bits: Array[String] = []
	if qres.reward_money > 0:
		reward_bits.append("$%d" % qres.reward_money)
	if qres.reward_items.size() > 0:
		for k in qres.reward_items.keys():
			var item := String(k)
			var qty := int(qres.reward_items[k])
			reward_bits.append("%s x%d" % [item, qty])
	if reward_bits.size() > 0:
		lines.append("Reward: " + ", ".join(reward_bits))

	# Turn-in / giver info
	var turn := qres.turn_in_text.strip_edges()
	if turn != "":
		lines.append(turn)
	elif qres.turn_in_id.strip_edges() != "":
		lines.append("Turn in to: " + qres.turn_in_id)

	if qres.giver_id.strip_edges() != "":
		lines.append("From: " + qres.giver_id)

	return "\n".join(lines)

func _shorten(s: String, max_len: int) -> String:
	s = s.strip_edges()
	if s.length() <= max_len:
		return s
	return s.substr(0, max_len - 1) + "…"
