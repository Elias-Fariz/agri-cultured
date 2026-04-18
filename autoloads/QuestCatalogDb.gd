extends Node

@export var quests: Array[QuestData] = []

var _by_id: Dictionary = {}

func _ready() -> void:
	_rebuild_index()

func _rebuild_index() -> void:
	_by_id.clear()

	for q in quests:
		if q == null:
			continue
		if q.id.strip_edges() == "":
			continue

		if _by_id.has(q.id):
			push_warning("QuestCatalogDb: duplicate quest id found: " + q.id)

		_by_id[q.id] = q

func get_quest(qid: String) -> QuestData:
	if qid.strip_edges() == "":
		return null
	return _by_id.get(qid, null)

func has_quest(qid: String) -> bool:
	if qid.strip_edges() == "":
		return false
	return _by_id.has(qid)

func get_all_quests() -> Array[QuestData]:
	return quests
