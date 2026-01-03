extends Area2D

var opened := false

func interact() -> void:
	opened = !opened
	print("Chest opened? ", opened)
	# Optional: visually reflect state
	# $Sprite2D.modulate = opened ? Color(1,1,1) : Color(0.8,0.8,0.8)
