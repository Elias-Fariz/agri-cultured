extends Resource
class_name QuestSpawnRewardData

@export var scene_key: String = "farm"
@export_file("*.tscn") var scene_path: String = ""
@export var marker_id: String = ""

func is_valid() -> bool:
	return scene_key.strip_edges() != "" and scene_path.strip_edges() != "" and marker_id.strip_edges() != ""

func to_dict() -> Dictionary:
	return {
		"scene_key": scene_key,
		"scene_path": scene_path,
		"marker_id": marker_id,
	}
