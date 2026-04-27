extends Resource
class_name CutsceneStepData

enum StepType {
	MOVE_ACTOR_TO_MARKER,
	FOCUS_CAMERA_MARKER,
	DIALOGUE,
	WAIT,

	# New
	MOVE_PLAYER_TO_MARKER,
	START_RESTORATION_ENCOUNTER
}

@export var step_type: StepType = StepType.WAIT

# Common fields
@export var actor_key: String = ""     # "poppy", "mayor", "player"
@export var marker_id: String = ""     # "poppy_start", "mayor_greet", "focus_intro", "player_end"
@export var duration: float = 0.5
@export var ease_run: bool = false

# Used by steps that need to target a node directly.
# For START_RESTORATION_ENCOUNTER, point this to the RestorationEncounter node.
@export var target_path: NodePath = NodePath("")

# Optional restoration encounter lookup.
# For START_RESTORATION_ENCOUNTER, this can match RestorationEncounterData.encounter_id.
@export var encounter_id: String = ""

# Legacy dialogue fields
@export var speaker_actor_key: String = ""  # "poppy" / "mayor"
@export var speaker_name: String = ""       # optional override
@export var lines: Array[String] = []

# New preferred dialogue field
@export var dialogue_sequence: DialogueSequenceData
