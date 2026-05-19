extends Resource
class_name DialogueArtEntry

# A flexible lookup key such as:
# "default", "happy", "sad", "nervous", "holding_bread", "weapon_ready"
@export var key: String = "default"

# For now, this is the still image used by DialogueUI.
@export var texture: Texture2D

# Future-friendly fields.
# We are not using these yet, but they leave the door open for animated poses later.
@export var animation_frames: SpriteFrames
@export var animation_name: StringName = &"default"
@export var animation_loops: bool = true
@export var animation_revert_to_key: String = "default"

# Small per-pose tuning hooks for later.
# Not wired yet, but useful if one character needs a tiny visual adjustment.
@export var stage_offset: Vector2 = Vector2.ZERO
@export var stage_scale: float = 1.0


func get_clean_key() -> String:
	var k := key.strip_edges().to_lower()
	if k == "":
		return "default"
	return k
