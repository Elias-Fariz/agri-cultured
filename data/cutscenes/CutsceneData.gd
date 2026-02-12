extends Resource
class_name CutsceneData

@export var id: String = ""
@export var scene_name: String = ""

@export var actors: Array[CutsceneActorData] = []
@export var markers: CutsceneMarkerSet
@export var dialogue: CutsceneDialogueData
@export var effects: Array[CutsceneEffectData] = []

# Gate for future cinematic steps (we’ll add StepData later)
@export var steps: Array[Resource] = []
