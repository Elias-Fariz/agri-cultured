extends PanelContainer

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var objective_label: Label = $VBoxContainer/ObjectiveLabel
@onready var prev_button: Button = $VBoxContainer/HBoxContainer/PrevButton
@onready var next_button: Button = $VBoxContainer/HBoxContainer/NextButton
@onready var none_button: Button = $VBoxContainer/HBoxContainer/NoneButton

var _active_ids: Array[String] = []
var _index: int = -1

func _ready() -> void:
	prev_button.pressed.connect(_on_prev)
	next_button.pressed.connect(_on_next)
	none_button.pressed.connect(_on_none)

	QuestEvents.quest_state_changed.connect(_refresh)

	_refresh()

func _refresh() -> void:
	_active_ids = GameState.get_all_trackable_quest_ids()

	# No quests at all
	if _active_ids.is_empty():
		GameState.tracked_quest_id = ""
		_index = -1
		_render_none("No active quests")
		return

	# If player chose Track None, respect it
	var tracked: String = String(GameState.tracked_quest_id)
	if tracked == "":
		_index = -1
		_render_none("No quest tracked")
		return

	# If tracked quest is not active anymore, fall back (optional)
	# (This happens when a quest completes or is removed)
	# If the tracked quest isn't trackable anymore (missing or claimed), clear it.
	if not _is_trackable(tracked):
		GameState.tracked_quest_id = ""
		_index = -1
		_render_none("No quest tracked")
		return


	_index = _active_ids.find(tracked)
	if _index == -1:
		# tracked id isn't in our list (shouldn't happen, but safe)
		GameState.tracked_quest_id = ""
		_index = -1
		_render_none("No quest tracked")
		return

	var q: Dictionary = {}
	if GameState.active_quests.has(tracked):
		q = GameState.active_quests[tracked]
	elif GameState.completed_quests.has(tracked):
		q = GameState.completed_quests[tracked]

	var title := String(q.get("title", "Quest"))
	var objective := GameState.get_tracked_objective_text()

	title_label.text = title
	objective_label.text = objective if objective != "" else "…"

	prev_button.disabled = _active_ids.size() <= 1
	next_button.disabled = _active_ids.size() <= 1
	none_button.disabled = false

func _render_none(msg: String) -> void:
	title_label.text = "Quest Tracker"
	objective_label.text = msg
	prev_button.disabled = true
	next_button.disabled = true
	none_button.disabled = false

func _on_prev() -> void:
	if _active_ids.size() <= 1:
		return
	_index = (_index - 1 + _active_ids.size()) % _active_ids.size()
	GameState.set_tracked_quest(_active_ids[_index])

func _on_next() -> void:
	if _active_ids.size() <= 1:
		return
	_index = (_index + 1) % _active_ids.size()
	GameState.set_tracked_quest(_active_ids[_index])

func _on_none() -> void:
	GameState.clear_tracked_quest()

func _is_trackable(qid: String) -> bool:
	if qid == "":
		return false

	# Active quests are always trackable
	if GameState.active_quests.has(qid):
		return true

	# Completed quests are trackable only if not claimed
	if GameState.completed_quests.has(qid):
		var q: Dictionary = GameState.completed_quests[qid]
		return not bool(q.get("claimed", false))

	return false
