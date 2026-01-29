# ValleyHeart.gd
extends Node2D

@export var pause_time_in_heart: bool = true
@export var heart_progress_res: Resource  # optional, if your UI wants it

@export var reveal_director_path: NodePath


func _ready() -> void:
	if pause_time_in_heart:
		var tm := get_node_or_null("/root/TimeManager")
		if tm != null and tm.has_method("enter_timeless_zone"):
			tm.call("enter_timeless_zone")

	# Optional: pass resource to UI (correct path: UI/HeartProgressUI)
	var ui := get_node_or_null("HeartProgressUI")
	if ui != null and ui.has_method("set_progress_data") and heart_progress_res != null:
		ui.call("set_progress_data", heart_progress_res)

	# Kick the reveal sequence (if anything is pending).
	_start_heart_reveal_if_needed()


func _exit_tree() -> void:
	if pause_time_in_heart:
		var tm := get_node_or_null("/root/TimeManager")
		if tm != null and tm.has_method("exit_timeless_zone"):
			tm.call("exit_timeless_zone")


func _start_heart_reveal_if_needed() -> void:
	var director := get_node_or_null(reveal_director_path)
	if director and director.has_method("run_reveals_if_any"):
		director.call_deferred("run_reveals_if_any")
