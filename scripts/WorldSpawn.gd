extends Node

@export var spawn_points_group: StringName = &"spawn_points"
@export var player_path: NodePath = ^"../Player"  # adjust if your Player lives elsewhere

func _ready() -> void:
	var player := get_node_or_null(player_path)
	if player == null:
		print("WorldSpawn: couldn't find Player at path:", player_path)
		return

	var pending_tag := GameState.pending_spawn_tag
	if pending_tag == "":
		return  # no special spawn requested

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

	print("WorldSpawn pending tag:", GameState.pending_spawn_tag)

	# Always clear it after attempting
	GameState.pending_spawn_tag = ""
	
