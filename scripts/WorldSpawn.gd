extends Node

@export var spawn_points_group: StringName = &"spawn_points"
@export var player_path: NodePath = ^"../Player"


func _ready() -> void:
	# Defer so Player, Camera2D, and spawn markers are fully ready.
	call_deferred("_apply_pending_spawn")


func _apply_pending_spawn() -> void:
	var player := get_node_or_null(player_path)
	if player == null:
		# print("WorldSpawn: couldn't find Player at path:", player_path)
		return

	var pending_tag := String(GameState.pending_spawn_tag).strip_edges()
	if pending_tag == "":
		# Still snap the camera once on scene start, just in case.
		if player.has_method("snap_camera_to_player"):
			player.call("snap_camera_to_player")
		return

	var found := false

	for n in get_tree().get_nodes_in_group(String(spawn_points_group)):
		if n == null:
			continue
		if not (n is Marker2D):
			continue

		var t := ""
		if n.has_method("get_tag"):
			t = String(n.call("get_tag"))
		elif n.has_meta("tag"):
			t = String(n.get_meta("tag"))

		if t == pending_tag:
			player.global_position = (n as Marker2D).global_position
			found = true
			break

	if not found:
		print("WorldSpawn: no spawn point found for tag:", pending_tag)

	# Clear after attempting, even if not found.
	GameState.pending_spawn_tag = ""

	# Let physics/camera nodes register the new player position.
	await get_tree().process_frame

	if player != null and is_instance_valid(player):
		if player.has_method("snap_camera_to_player"):
			await player.call("snap_camera_to_player")
