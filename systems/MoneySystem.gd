# res://systems/MoneyManager.gd
extends Node
class_name MoneyManager

signal money_changed(new_amount: int)

var current_money: int = 0

func add(amount: int) -> void:
	if amount <= 0:
		return
	current_money += amount
	money_changed.emit(current_money)

func can_afford(amount: int) -> bool:
	return current_money >= amount

func spend(amount: int) -> bool:
	if amount <= 0:
		return false
	if current_money < amount:
		return false
	current_money -= amount
	return true
