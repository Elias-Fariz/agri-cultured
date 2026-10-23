extends Resource
class_name ScrapbookCharacterData

@export var character_id: String = ""
@export var display_name: String = ""

@export var index_portrait: Texture2D
@export var portrait: Texture2D
@export var silhouette: Texture2D

# Example:
# scrapbook:met:maren
@export var met_flag: String = ""

# Optional future state:
# scrapbook:glimpsed:ash
@export var glimpsed_flag: String = ""

@export_multiline var summary: String = ""

# Some characters, like the Valley Heart,
# may not use ordinary friendship.
@export var show_friendship: bool = true

@export var sections: Array[ScrapbookSectionData] = []


func is_met() -> bool:
	var flag := met_flag.strip_edges()

	# Useful while authoring/testing.
	# No flag means "always known."
	if flag == "":
		return true

	if GameState == null:
		return false

	if not GameState.has_method("has_flag"):
		return false

	return GameState.has_flag(flag)


func is_glimpsed() -> bool:
	if is_met():
		return true

	var flag := glimpsed_flag.strip_edges()

	if flag == "":
		return false

	if GameState == null:
		return false

	if not GameState.has_method("has_flag"):
		return false

	return GameState.has_flag(flag)


func get_section(
	section_type: ScrapbookSectionData.SectionType
) -> ScrapbookSectionData:
	for section in sections:
		if section == null:
			continue

		if section.section_type == section_type:
			return section

	return null
