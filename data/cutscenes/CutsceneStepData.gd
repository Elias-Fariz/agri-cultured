extends Resource
class_name CutsceneStepData

enum StepType {
	MOVE_ACTOR_TO_MARKER,
	FOCUS_CAMERA_MARKER,
	DIALOGUE,
	WAIT,

	# Player / gameplay bridge
	MOVE_PLAYER_TO_MARKER,
	START_RESTORATION_ENCOUNTER,

	# World-changing cutscene steps
	SHOW_NODE,
	HIDE_NODE,
	MOVE_NODE_TO_MARKER,
	SET_NODE_TEXTURE,
	SPAWN_SCENE_AT_MARKER,
	PLAY_NODE_ANIMATION,
	
	STORE_PLAYER_END_MARKER,
	CLEAR_STORED_PLAYER_END_MARKER,
	
	SET_CAMERA_ZOOM,
	RESTORE_CAMERA_ZOOM,
	
	SHOW_ILLUSTRATION,
	HIDE_ILLUSTRATION,

	# Cute overhead emotes / thought bubbles
	SHOW_OVERHEAD_TEXT,
	
	# World / speakerless narration box
	NARRATION,
	
	# Smooth camera movement
	PAN_CAMERA_TO_MARKER,
}

@export var step_type: StepType = StepType.WAIT

# Common fields
@export var actor_key: String = ""     # "poppy", "mayor", "player"
@export var marker_id: String = ""     # "poppy_start", "focus_intro", "root_flare"
@export var duration: float = 0.5
@export var ease_run: bool = false

# Targeting world objects.
# Prefer target_path when the object is easy to reach.
# Use target_id when the object has CutsceneTarget.gd attached.
@export var target_path: NodePath = NodePath("")
@export var target_id: String = ""

# Used by START_RESTORATION_ENCOUNTER.
@export var encounter_id: String = ""

# Used by SET_NODE_TEXTURE.
@export var texture: Texture2D

# Used by SPAWN_SCENE_AT_MARKER.
@export var scene_path: String = ""
@export var spawned_name: String = ""
@export var keep_spawned_after_cutscene: bool = false

# Used by PLAY_NODE_ANIMATION.
@export var animation_name: String = ""

# Legacy dialogue fields
@export var speaker_actor_key: String = ""  # "poppy" / "mayor"
@export var speaker_name: String = ""       # optional override
@export var lines: Array[String] = []

# New preferred dialogue field
@export var dialogue_sequence: DialogueSequenceData

@export var zoom_value: float = 1.0

# Used by SHOW_OVERHEAD_TEXT.
# actor_key chooses who shows the bubble: "player", "mayor", "maren", etc.
@export_multiline var overhead_text: String = "?"
@export var overhead_duration: float = 1.0
@export var overhead_offset: Vector2 = Vector2(0, -34)

@export_group("Narration")

@export_multiline var narration_text: String = ""
