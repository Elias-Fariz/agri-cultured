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
	var p := player.global_position
	var facing: Vector2 = player.facing
	var target_pos := p + facing * float(tile_size)

	var cell: Vector2i = ground.local_to_map(ground.to_local(target_pos))

	var current_source := ground.get_cell_source_id(layer, cell)
	var current_atlas := ground.get_cell_atlas_coords(layer, cell)

	if current_source == source_id and current_atlas == grass_coords:
		ground.set_cell(layer, cell, source_id, tilled_coords)
		print("Tilled tile at cell: ", cell)
	else:
		print("No till: cell=", cell, " source=", current_source, " atlas=", current_atlas)
