# ValleyHeart.gd
extends Node2D

@export var pause_time_in_heart: bool = true
@export var heart_progress_res: Resource

# New preferred route.
@export var cinematic_orchestrator_path: NodePath

# Legacy fallback if you want to keep it assigned for safety.
@export var reveal_director_path: NodePath


func _ready() -> void:
	if pause_time_in_heart:
		var tm := get_node_or_null("/root/TimeManager")
		if tm != null and tm.has_method("enter_timeless_zone"):
			tm.call("enter_timeless_zone")

	var ui := get_node_or_null("HeartProgressUI")
	if ui != null and ui.has_method("set_progress_data") and heart_progress_res != null:
		ui.call("set_progress_data", heart_progress_res)

	_start_heart_sequence_if_needed()


func _exit_tree() -> void:
	if pause_time_in_heart:
		var tm := get_node_or_null("/root/TimeManager")
		if tm != null and tm.has_method("exit_timeless_zone"):
			tm.call("exit_timeless_zone")


func _start_heart_sequence_if_needed() -> void:
	var orchestrator := get_node_or_null(cinematic_orchestrator_path)
	if orchestrator != null and orchestrator.has_method("run_if_needed"):
		orchestrator.call_deferred("run_if_needed")
		return

	# Fallback to old behavior if orchestrator is not assigned yet.
	var director := get_node_or_null(reveal_director_path)
	if director != null and director.has_method("run_reveals_if_any"):
		director.call_deferred("run_reveals_if_any")
