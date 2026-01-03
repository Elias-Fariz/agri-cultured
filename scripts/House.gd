# House.gd
extends Node2D

@onready var spawn: Marker2D = $Spawn

func _ready() -> void:
	var player = get_node_or_null("Player")
	if player:
		player.global_position = spawn.global_position
