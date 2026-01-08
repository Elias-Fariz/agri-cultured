extends Node2D

func set_night_active(active: bool) -> void:
	for child in get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = active
