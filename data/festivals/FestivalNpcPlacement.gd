# res://data/festivals/FestivalNpcPlacement.gd
extends Resource
class_name FestivalNpcPlacement

# -------------------------------------------------------------------
# WHO this placement is for
# -------------------------------------------------------------------

@export var npc_id: String = ""
# Example: "npc_alex", "npc_mayor"
# This should match the npc_id used by your NPC scenes/scripts.

@export var npc_scene_path: String = ""
# Optional for later:
# If this NPC is NOT already in the scene on festival day,
# this can point to the prefab to instantiate.
# Example: "res://tscn/npcs/Alex.tscn"
#
# For first version, this can be left blank if the NPC already exists in scene.

# -------------------------------------------------------------------
# WHERE this NPC should be during the festival
# -------------------------------------------------------------------

@export var target_position: Vector2 = Vector2.ZERO
# World position where the NPC should stand during the festival.
# Since your NPCs do not yet use visible facing art, position is the most important field.

# -------------------------------------------------------------------
# DIALOGUE override
# -------------------------------------------------------------------

@export var use_festival_dialogue: bool = true
# If true, the festival manager can provide these lines instead of normal NPC dialogue.

@export var festival_dialogue_lines: PackedStringArray = PackedStringArray()
# Simple first-pass festival dialogue lines for this NPC.
# Example:
# [
#   "The square feels so bright today.",
#   "I always look forward to this festival."
# ]

# -------------------------------------------------------------------
# FUTURE fields (safe to keep now, even if unused yet)
# -------------------------------------------------------------------

@export var lock_in_place: bool = true
# Future intent:
# If true, this NPC should stay at the target position during the festival
# instead of wandering or following schedule logic.

func is_valid() -> bool:
	return npc_id.strip_edges() != ""
