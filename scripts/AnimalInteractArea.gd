extends Area2D

@onready var _animal := get_parent()  # parent is the CharacterBody2D with AnimalBase.gd

func interact() -> void:
	print("InteractArea: interact() called on animal:", _animal)
	if _animal and _animal.has_method("interact"):
		_animal.interact()
