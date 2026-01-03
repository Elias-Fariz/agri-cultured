extends Node2D

@onready var ground: TileMap = $Ground
@onready var player := $Player as CharacterBody2D
@onready var spawn: Marker2D = $Spawn

@export var layer := 0
@export var source_id := 0
@export var grass_coords := Vector2i(0, 0)
@export var tilled_coords := Vector2i(1, 0)
@export var tile_size := 32

func _ready() -> void:
	# Place player at spawn if present
	if player:
		player.global_position = spawn.global_position

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("tool"):
		_try_till()

func _try_till() -> void:
	# Convert player world position to the tile cell they are standing on
	var player_cell: Vector2i = ground.local_to_map(ground.to_local(player.global_position))

	# Convert facing (Vector2) to a grid step (Vector2i)
	var step := Vector2i(int(player.facing.x), int(player.facing.y))

	# Target is exactly 1 tile in front
	var target_cell := player_cell + step

	# Read what's currently on that cell
	var current_source: int = ground.get_cell_source_id(layer, target_cell)
	var current_atlas: Vector2i = ground.get_cell_atlas_coords(layer, target_cell)

	if current_source == source_id and current_atlas == grass_coords:
		ground.set_cell(layer, target_cell, source_id, tilled_coords)
		print("Tilled tile at cell: ", target_cell)
	else:
		print("No till: cell=", target_cell, " source=", current_source, " atlas=", current_atlas)
