extends Resource
class_name DialogueSequenceData

# -------------------------------------------------------------------
# Optional metadata
# -------------------------------------------------------------------

@export var sequence_id: String = ""
@export var display_name: String = ""

# Optional default speaker for older/simple dialogue.
# If a beat does not specify its own speaker_id, this can be used.
@export var default_speaker_id: String = ""

# Optional default stage slot for simple converted lines.
# Recommended values:
# - "auto"
# - "left"
# - "center"
# - "right"
@export var default_stage_slot: String = "auto"

# Optional default emotion for simple converted lines.
@export var default_emotion: String = "neutral"

# -------------------------------------------------------------------
# Main content
# -------------------------------------------------------------------

@export var beats: Array[DialogueBeatData] = []

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------

func has_beats() -> bool:
	return not beats.is_empty()

func get_valid_beats() -> Array[DialogueBeatData]:
	var out: Array[DialogueBeatData] = []
	for beat in beats:
		if beat == null:
			continue
		if not beat.has_text():
			continue
		out.append(beat)
	return out

func add_beat(beat: DialogueBeatData) -> void:
	if beat == null:
		return
	beats.append(beat)

func clear_beats() -> void:
	beats.clear()

func get_beat_count() -> int:
	return beats.size()

func get_beat(index: int) -> DialogueBeatData:
	if index < 0 or index >= beats.size():
		return null
	return beats[index]

# -------------------------------------------------------------------
# Legacy conversion support
# -------------------------------------------------------------------

func build_from_lines(lines: Array[String], speaker_id: String = "", stage_slot: String = "", emotion: String = "") -> void:
	beats.clear()

	var use_speaker_id := speaker_id.strip_edges()
	if use_speaker_id == "":
		use_speaker_id = default_speaker_id

	var use_stage_slot := stage_slot.strip_edges().to_lower()
	if use_stage_slot == "":
		use_stage_slot = default_stage_slot

	var use_emotion := emotion.strip_edges().to_lower()
	if use_emotion == "":
		use_emotion = default_emotion

	for line in lines:
		var text := String(line).strip_edges()
		if text == "":
			continue

		var beat := DialogueBeatData.new()
		beat.text = text
		beat.speaker_id = use_speaker_id
		beat.stage_slot = use_stage_slot
		beat.emotion = use_emotion
		beat.dim_others = true
		beat.is_narration = (use_speaker_id == "")

		beats.append(beat)

func to_plain_lines() -> Array[String]:
	var lines: Array[String] = []

	for beat in beats:
		if beat == null:
			continue
		if not beat.has_text():
			continue
		lines.append(beat.text)

	return lines

func is_narration_only() -> bool:
	if beats.is_empty():
		return false

	for beat in beats:
		if beat == null:
			continue
		if not beat.should_use_narration_mode():
			return false

	return true
