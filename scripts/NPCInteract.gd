extends Area2D

func interact() -> void:
	var npc := get_parent()
	if npc and npc.has_method("start_dialogue"):
		npc.start_dialogue()
