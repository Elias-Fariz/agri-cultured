# res://systems/MoneyManager.gd
extends Node
class_name MoneyManager

signal money_changed(new_amount: int)

var money: int = 0 : set = _set_money

func _set_money(value: int) -> void:
	money = max(0, value)
	money_changed.emit(money)

func add(amount: int) -> void:
	if amount <= 0:
		return
	_set_money(money + amount)

func spend(amount: int) -> bool:
	if amount <= 0:
		return true
	if money < amount:
		return false
	_set_money(money - amount)
	return true
