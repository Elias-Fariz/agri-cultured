extends Resource
class_name CutsceneEffectData

@export var effect_type: String = ""  # "unlock_travel", "toast"
@export var id: String = ""           # for unlock_travel
@export var msg: String = ""          # for toast
@export var kind: String = "info"
@export var duration: float = 2.5
