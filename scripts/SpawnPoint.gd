extends Marker2D
class_name SpawnPoint

@export var tag: String = ""

@export_enum("down", "up", "left", "right") var facing_direction: String = "down"


func get_tag() -> String:
	return tag.strip_edges()


func get_facing_direction() -> String:
	return facing_direction.strip_edges().to_lower()
