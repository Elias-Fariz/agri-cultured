extends Resource
class_name ScrapbookEntryData

@export var entry_id: String = ""
@export var title: String = ""

@export_multiline var body: String = ""

# Leave blank if this entry is available immediately.
@export var unlock_flag: String = ""

# Optional later:
# little drawing, memory picture, quest keepsake, etc.
@export var icon: Texture2D
@export var memory_image: Texture2D


func is_unlocked() -> bool:
	var flag := unlock_flag.strip_edges()

	if flag == "":
		return true

	if GameState == null:
		return false

	if not GameState.has_method("has_flag"):
		return false

	return GameState.has_flag(flag)
