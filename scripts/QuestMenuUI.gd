# QuestMenuUI.gd
extends BaseOverlay

@onready var quest_list: ItemList = $Panel/Margin/Root/BodyRow/LeftCol/QuestList
@onready var close_button: Button = $Panel/Margin/Root/HeaderRow/CloseButton
@onready var track_none_button: Button = $Panel/Margin/Root/BodyRow/LeftCol/TrackNoneButton
@onready var details_title: Label = $Panel/Margin/Root/BodyRow/RightCol/DetailsTitle
@onready var details_text: Label = $Panel/Margin/Root/BodyRow/RightCol/DetailsText
@onready var hint_label: Label = $Panel/Margin/Root/FooterRow/HintLabel

var _ids: Array[String] = []  # row -> quest_id

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	close_button.pressed.connect(hide_overlay)
	track_none_button.pressed.connect(_on_track_none)

	quest_list.item_selected.connect(_on_selected)
	quest_list.item_activated.connect(_on_activated)

	# Refresh whenever quests change
	QuestEvents.quest_state_changed.connect(_refresh)

	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	# Toggle quest menu with V
	if event.is_action_pressed("open_quests"):
		toggle_overlay()
		get_viewport().set_input_as_handled()
		return

	# If open, allow Esc to close
	if is_open() and event.is_action_pressed("ui_cancel"):
		hide_overlay()
		get_viewport().set_input_as_handled()
		return

func show_overlay() -> void:
	super.show_overlay()
	_refresh()
	quest_list.grab_focus()

func hide_overlay() -> void:
	super.hide_overlay()

func _refresh() -> void:
	if not is_inside_tree():
		return
	if Engine.is_editor_hint():
		return

	quest_list.clear()
	_ids.clear()

	var ids: Array[String] = GameState.get_all_trackable_quest_ids()

	if ids.is_empty():
		details_title.text = "Details"
		details_text.text = "No quests yet."
		hint_label.text = "V: Close"
		return

	# Populate list
	for qid in ids:
		var q: Dictionary = {}
		if GameState.active_quests.has(qid):
			q = GameState.active_quests[qid]
		elif GameState.completed_quests.has(qid):
			q = GameState.completed_quests[qid]

		var title := String(q.get("title", qid))

		# Tags
		var suffix := ""
		if bool(q.get("completed", false)) and not bool(q.get("claimed", false)):
			suffix = " (Turn In!)"
		elif GameState.tracked_quest_id == qid:
			suffix = " [TRACKED]"

		_ids.append(qid)
		quest_list.add_item(title + suffix)

		# Select tracked quest if one exists; otherwise select nothing
	var tracked: String = String(GameState.tracked_quest_id)

	if tracked != "":
		var idx := _ids.find(tracked)
		if idx != -1:
			quest_list.select(idx)
			_show_details_for(idx)
		else:
			quest_list.deselect_all()
			_show_no_track_details()
	else:
		quest_list.deselect_all()
		_show_no_track_details()

	hint_label.text = "V: Close   Enter: Track   Esc: Close"

func _on_selected(index: int) -> void:
	_show_details_for(index)

func _on_activated(index: int) -> void:
	_track_index(index)

func _track_index(index: int) -> void:
	if index < 0 or index >= _ids.size():
		return
	GameState.set_tracked_quest(_ids[index])
	_refresh()

func _on_track_none() -> void:
	GameState.clear_tracked_quest()
	QuestEvents.quest_state_changed.emit()
	_refresh()

func _show_details_for(index: int) -> void:
	if index < 0 or index >= _ids.size():
		return

	var qid := _ids[index]
	var q: Dictionary = {}

	if GameState.active_quests.has(qid):
		q = GameState.active_quests[qid]
	elif GameState.completed_quests.has(qid):
		q = GameState.completed_quests[qid]

	var title := String(q.get("title", qid))
	var desc := String(q.get("description", ""))
	var objective := GameState.get_quest_objective_text(q)

	details_title.text = title

	var lines: Array[String] = []
	if desc != "":
		lines.append(desc)

	if objective != "":
		lines.append("")
		lines.append("Current:")
		lines.append(objective)

	# Rewards display (optional but nice)
	var reward: Dictionary = q.get("reward", {})
	if reward.size() > 0:
		lines.append("")
		lines.append("Reward:")
		if reward.has("money"):
			lines.append("• %d money" % int(reward["money"]))
		if reward.has("items"):
			var items: Dictionary = reward["items"]
			for k in items.keys():
				lines.append("• %s x%d" % [String(k), int(items[k])])

	details_text.text = "\n".join(lines)
 
func _show_no_track_details() -> void:
	details_title.text = "No quest tracked"
	details_text.text = "Select a quest on the left, then press Enter to track it.\n\nOr keep tracking none and just explore."
