extends Resource
class_name ScrapbookSectionData

enum SectionType {
	WHO_THEY_ARE,
	THINGS_NOTICED,
	PEOPLE_IN_THEIR_LIFE,
	LIKES_AND_LITTLE_THINGS,
	MEMORIES,
	HEART
}

@export var section_type: SectionType = SectionType.WHO_THEY_ARE

@export var display_name: String = "Section"

# Optional:
# Example: the Heart section could stay locked until
# the Valley Heart sprouts.
@export var unlock_flag: String = ""

@export var entries: Array[ScrapbookEntryData] = []


func is_unlocked() -> bool:
	var flag := unlock_flag.strip_edges()

	if flag == "":
		return true

	if GameState == null:
		return false

	if not GameState.has_method("has_flag"):
		return false

	return GameState.has_flag(flag)


func get_unlocked_entries() -> Array[ScrapbookEntryData]:
	var out: Array[ScrapbookEntryData] = []

	for entry in entries:
		if entry == null:
			continue

		if entry.is_unlocked():
			out.append(entry)

	return out
