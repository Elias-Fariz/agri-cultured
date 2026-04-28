extends Resource
class_name DialogueBeatData

# -------------------------------------------------------------------
# Core dialogue content
# -------------------------------------------------------------------

@export_multiline var text: String = ""

# Usually an NPC id like "npc_poppy" or "npc_mayor".
# Leave blank for narration / non-speaker context.
@export var speaker_id: String = ""

# Optional override if you want a displayed name different from the NPC's display_name.
# Leave blank to use the NPC's normal display name.
@export var speaker_name_override: String = ""

# -------------------------------------------------------------------
# Presentation / staging
# -------------------------------------------------------------------

# Recommended values:
# - "auto"
# - "left"
# - "center"
# - "right"
# - "none"  # speaker talks, but no staged character art is shown
@export var stage_slot: String = "auto"

# Emotional intent for the line.
# Recommended values for now:
# - "neutral"
# - "happy"
# - "sad"
# - "nervous"
# - "angry"
# - "surprised"
#
# If you don't have a matching emotion visual later, just fall back to neutral.
@export var emotion: String = "neutral"

# If true, the current speaker should visually be the focus
# and other staged characters can be dimmed.
@export var dim_others: bool = true

# -------------------------------------------------------------------
# Special line behavior
# -------------------------------------------------------------------

# If true, this line is narration / descriptive scene text,
# not spoken by a specific visible speaker.
# Example:
# "Poppy kneels among the flowers, brushing soil from her hands."
@export var is_narration: bool = false

# Optional pacing controls for later.
# These do not need to be used immediately.
@export var pause_after: float = 0.0
@export var auto_advance: bool = false

# -------------------------------------------------------------------
# Voice support (future-friendly)
# -------------------------------------------------------------------

# Optional logical voice key, useful if you later want to resolve audio
# through a naming/database system.
@export var voice_key: String = ""

# Optional direct audio clip for this beat.
# If null, just use normal text blips / silent dialogue.
@export var voice_clip: AudioStream

# -------------------------------------------------------------------
# Optional visual overrides (future-friendly)
# -------------------------------------------------------------------

# If you later want a special portrait for this exact beat, you can set it here.
# If null, use the NPC's usual portrait.
@export var portrait_override: Texture2D

# If you later want a special staged half-body/full-body art for this exact beat,
# you can set it here. If null, use the speaker's normal staged art.
@export var stage_texture_override: Texture2D

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------

func has_text() -> bool:
	return text.strip_edges() != ""

func has_speaker() -> bool:
	return speaker_id.strip_edges() != ""

func get_effective_speaker_name(default_name: String = "") -> String:
	if speaker_name_override.strip_edges() != "":
		return speaker_name_override
	return default_name

func get_effective_stage_slot() -> String:
	var s := stage_slot.strip_edges().to_lower()
	if s == "":
		return "auto"

	match s:
		"left", "center", "right", "auto", "none":
			return s
		_:
			return "auto"

func get_effective_emotion() -> String:
	var e := emotion.strip_edges().to_lower()
	if e == "":
		return "neutral"
	return e

func should_use_narration_mode() -> bool:
	# Explicit narration wins, but also treat completely speakerless lines
	# as narration-friendly.
	return is_narration or speaker_id.strip_edges() == ""
