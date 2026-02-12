extends Resource
class_name CutsceneMarkerSet

@export var player_spot: NodePath
@export var npc_spots: Dictionary = {}     # npc_key -> NodePath (optional for multi-NPC later)
@export var camera_focus: NodePath
