extends Resource
class_name CutsceneActorData

@export var key: String = ""           # e.g. "mayor", "player"
@export var actor_type: String = "npc" # "npc" or "player"
@export var npc_id: String = ""        # e.g. "npc_mayor"
@export var display_name: String = ""  # e.g. "Mayor"
@export var scene_path: String = ""    # e.g. "res://tscn/npcs/Mayor.tscn"
