extends Node2D

@onready var player := $Player

func _ready() -> void:
	if GameState.next_spawn_name != "":
		var marker := get_node_or_null(GameState.next_spawn_name)
		if marker and marker is Marker2D:
			player.global_position = (marker as Marker2D).global_position
		GameState.next_spawn_name = ""
