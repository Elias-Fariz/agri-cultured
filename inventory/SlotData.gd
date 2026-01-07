# res://inventory/SlotData.gd
extends Resource
class_name SlotData

@export var item: ItemData
@export var quantity: int = 0

func is_empty() -> bool:
	return item == null or quantity <= 0
