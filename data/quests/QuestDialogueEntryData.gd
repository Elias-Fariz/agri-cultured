extends Resource
class_name QuestDialogueEntryData

@export var speaker_id: String = ""
@export_multiline var text: String = ""

# Future-friendly presentation data
@export var emotion: String = "neutral"
@export var stage_slot: String = "auto"   # "left", "right", "center", "auto"
@export var dim_others: bool = true

# Future-friendly voice support
@export var voice_key: String = ""
@export var voice_clip: AudioStream

func is_valid() -> bool:
	return text.strip_edges() != ""
