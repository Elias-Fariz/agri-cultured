extends Node

@export var spawn_points_group: StringName = &"spawn_points"
@export var player_path: NodePath = ^"../Player"


func _ready() -> void:
	call_deferred("_apply_pending_spawn")


func _apply_pending_spawn() -> void:
	var player := get_node_or_null(player_path)
	if player == null:
		return

	var pending_tag := String(GameState.pending_spawn_tag).strip_edges()

	if pending_tag == "":
		if player.has_method("snap_camera_to_player"):
			await player.call("snap_camera_to_player")
		return

	var found := false
	var facing_direction := ""

	for n in get_tree().get_nodes_in_group(String(spawn_points_group)):
		if n == null:
			continue
		if not (n is Marker2D):
			continue

		var t := _get_spawn_tag(n)

		if t == pending_tag:
			player.global_position = (n as Marker2D).global_position
			facing_direction = _get_spawn_facing_direction(n)
			found = true
			break

	if not found:
		print("WorldSpawn: no spawn point found for tag:", pending_tag)

	GameState.pending_spawn_tag = ""

	await get_tree().process_frame

	if player != null and is_instance_valid(player):
		if facing_direction.strip_edges() != "":
			_apply_player_facing(player, facing_direction)

		if player.has_method("snap_camera_to_player"):
			await player.call("snap_camera_to_player")


func _get_spawn_tag(n: Node) -> String:
	if n.has_method("get_tag"):
		return String(n.call("get_tag")).strip_edges()

	if n.has_meta("tag"):
		return String(n.get_meta("tag")).strip_edges()

	if n.has_meta("spawn_tag"):
		return String(n.get_meta("spawn_tag")).strip_edges()

	return ""


func _get_spawn_facing_direction(n: Node) -> String:
	if n.has_method("get_facing_direction"):
		return String(n.call("get_facing_direction")).strip_edges().to_lower()

	if n.has_meta("facing_direction"):
		return String(n.get_meta("facing_direction")).strip_edges().to_lower()

	if n.has_meta("facing"):
		return String(n.get_meta("facing")).strip_edges().to_lower()

	return ""


func _apply_player_facing(player: Node, direction: String) -> void:
	direction = direction.strip_edges().to_lower()
	if direction == "":
		return

	if player.has_method("set_facing_direction"):
		player.call("set_facing_direction", direction)
