# SpawnPoint.gd
extends Marker2D
class_name SpawnPoint

@export var tag: String = ""

func get_tag() -> String:
	return tag
