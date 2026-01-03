# GameState.gd
extends Node

var inventory: Array[String] = []

func add_item(item: String) -> void:
	inventory.append(item)
	print("Added to inventory:", item, " Inventory now:", inventory)
