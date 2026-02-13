extends Resource
class_name CutsceneStepData

enum StepType {
	MOVE_ACTOR_TO_MARKER,
	FOCUS_CAMERA_MARKER,
	DIALOGUE,
	WAIT
}

@export var step_type: StepType = StepType.WAIT

# Common fields
@export var actor_key: String = ""     # "lia", "mayor", "player"
@export var marker_id: String = ""     # "lia_start", "mayor_greet", "focus_intro"
@export var duration: float = 0.5
@export var ease_run: bool = false

# Dialogue fields
@export var speaker_actor_key: String = ""  # "lia" / "mayor"
@export var speaker_name: String = ""       # optional override
@export var lines: Array[String] = []
