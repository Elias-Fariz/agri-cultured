# res://data/festivals/FestivalData.gd
extends Resource
class_name FestivalData

# -------------------------------------------------------------------
# IDENTITY
# -------------------------------------------------------------------

@export var festival_id: String = ""
# Internal id, example: "bloom_festival"

@export var display_name: String = ""
# Player-facing name, example: "Bloom Festival"

# -------------------------------------------------------------------
# WHEN the festival happens
# -------------------------------------------------------------------

@export var season: int = 0
# Match CalendarSystem seasons:
# 0 = Sunwake
# 1 = Duskhaven

@export var day_in_season: int = 1
# 1..28
# Example: 14 means the festival happens on day 14 of that season.

@export var active_all_day: bool = true
# Your current design choice:
# the festival exists for the whole day, and the player may come and go freely.

# -------------------------------------------------------------------
# WHERE / WORLD CONTEXT
# -------------------------------------------------------------------

@export var location_id: String = ""
# Example: "town_square"
# This is a simple logical key for the festival area.
# We can use it later for scene checks, decoration groups, etc.

# -------------------------------------------------------------------
# TOASTS / PLAYER NOTIFICATION
# -------------------------------------------------------------------

@export var day_before_toast: String = ""
# Example:
# "The Bloom Festival will be held tomorrow in the town square. 🌸"

@export var day_of_toast: String = ""
# Example:
# "Today is the Bloom Festival! Stop by the town square anytime. 🌸"

# -------------------------------------------------------------------
# NPCS
# -------------------------------------------------------------------

@export var npc_placements: Array[FestivalNpcPlacement] = []
# All festival participants for this event.

# -------------------------------------------------------------------
# DECORATIONS
# -------------------------------------------------------------------

@export var decoration_node_names: PackedStringArray = PackedStringArray()
# These are names of pre-placed decoration nodes in the scene that should be shown
# when this festival is active.
#
# Example:
# [
#   "BloomBanner",
#   "FlowerLanterns",
#   "FestivalStall"
# ]
#
# This matches your current comfort level well:
# pre-place decorations in the scene, hide them by default, then show them on festival day.

func is_valid() -> bool:
	return festival_id.strip_edges() != "" \
		and display_name.strip_edges() != "" \
		and day_in_season >= 1
