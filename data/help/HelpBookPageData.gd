extends Resource
class_name HelpBookPageData

@export var page_id: String = ""
@export var title: String = "Help Page"

# Leave blank for pages available from the start.
# Example locked page flag:
# help_page:valley_heart
@export var unlock_flag: String = ""

# If true, hidden until unlock_flag is set.
# If false, the page shows even if unlock_flag is blank.
@export var locked_until_flag: bool = false

@export_multiline var body: String = ""


func is_unlocked() -> bool:
	if not locked_until_flag:
		return true

	var flag := unlock_flag.strip_edges()
	if flag == "":
		return true

	if GameState == null:
		return false

	if not GameState.has_method("has_flag"):
		return false

	return GameState.has_flag(flag)
