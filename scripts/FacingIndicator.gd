# FacingIndicator.gd (Godot 4.x)
extends Node2D

@export var length: float = 18.0   # how far the arrow sits from the player
@export var size: float = 8.0      # arrowhead size

var dir: Vector2 = Vector2.DOWN

func set_direction(d: Vector2) -> void:
	if d == Vector2.ZERO:
		return
	dir = d.normalized()
	queue_redraw()

func _draw() -> void:
	# Draw an arrow from origin (0,0) toward dir
	var start := Vector2.ZERO
	var end := dir * length

	# Shaft
	draw_line(start, end, Color(1, 1, 1), 2.0)

	# Arrowhead (two small lines)
	var left := (dir.rotated(deg_to_rad(150.0)) * size)
	var right := (dir.rotated(deg_to_rad(-150.0)) * size)
	draw_line(end, end + left, Color(1, 1, 1), 2.0)
	draw_line(end, end + right, Color(1, 1, 1), 2.0)
