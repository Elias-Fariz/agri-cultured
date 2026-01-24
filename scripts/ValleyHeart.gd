# ValleyHeart.gd
extends Node2D

@export var pause_time_in_heart: bool = true
@export var heart_progress_res: Resource  # optional, if your UI wants it

func _ready() -> void:
	if pause_time_in_heart:
		var tm := get_node_or_null("/root/TimeManager")
		if tm != null and tm.has_method("enter_timeless_zone"):
			tm.call("enter_timeless_zone")

	# Optional: pass resource to UI
	var ui := $HeartProgressUI
	if ui != null and ui.has_method("set_progress_data") and heart_progress_res != null:
		ui.call("set_progress_data", heart_progress_res)

func _exit_tree() -> void:
	if pause_time_in_heart:
		var tm := get_node_or_null("/root/TimeManager")
		if tm != null and tm.has_method("exit_timeless_zone"):
			tm.call("exit_timeless_zone")
