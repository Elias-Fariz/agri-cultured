extends Resource
class_name CutsceneStepData

enum StepType {
	MOVE_ACTOR_TO_MARKER,
	FOCUS_CAMERA_MARKER,
	DIALOGUE,
	WAIT
}

@export var step_type: StepType = StepType.WAIT

# Common fields (only some are used depending on step_type)
@export var actor_key: String = ""          # e.g. "lia", "mayor", "player"
@export var marker_id: String = ""          # NEW: e.g. "lia_start", "mayor_greet", "focus_intro"
@export var marker_path: NodePath           # OLD fallback (still works)
@export var duration: float = 0.5           # move time / wait time
@export var ease_run: bool = false          # if true, feels like "run" (snappier)

# Dialogue fields
@export var speaker_actor_key: String = ""  # e.g. "lia" or "mayor"
@export var speaker_name: String = ""       # optional override
@export var lines: Array[String] = []
