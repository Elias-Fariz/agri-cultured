extends Node

@export var scene_id: String = "farm"
@export var spawn_points_group: String = "reward_spawn_points"

func _ready() -> void:
	print("[RewardSpawner] ready. pending_spawns:", GameState.pending_spawns)
	call_deferred("_spawn_pending_rewards")

func _spawn_pending_rewards() -> void:
	if GameState.pending_spawns.is_empty():
		return

	# Build a map of marker_tag -> Marker2D
	var markers: Dictionary = {}
	for m in get_tree().get_nodes_in_group(spawn_points_group):
		if m is Marker2D and m.has_method("get_tag"):
			markers[str(m.call("get_tag"))] = m
		elif m is Marker2D and m.has_meta("tag"):
			markers[str(m.get_meta("tag"))] = m
		elif m is Marker2D and m.name != "":
			# Optional fallback: marker name acts as tag
			markers[m.name] = m

	var remaining: Array[Dictionary] = []
	for reward in GameState.pending_spawns:
		if str(reward.get("scene_id","")) != scene_id:
			remaining.append(reward)
			continue

		var prefab_path := str(reward.get("prefab",""))
		var marker_tag := str(reward.get("marker_tag",""))
		var marker: Marker2D = markers.get(marker_tag, null)
		if marker == null:
			# Can't place yet, keep it for later
			remaining.append(reward)
			continue

		print("[RewardSpawner] loading prefab:", prefab_path)
		var packed := load(prefab_path)
		if packed == null:
			continue
		
		print("[RewardSpawner] markers found:", markers.keys())
		print("[RewardSpawner] looking for marker_tag:", marker_tag)

		var inst = packed.instantiate()
		if inst is Node2D:
			(inst as Node2D).global_position = (marker as Marker2D).global_position
		
		print("[RewardSpawner] scene_id=", scene_id)
		print("[RewardSpawner] reward.scene_id=", str(reward.get("scene_id","")))
		
		# Add to farm scene root (or a dedicated Animals node if you have one)
		var scene_root := get_tree().current_scene
		scene_root.call_deferred("add_child", inst)

		if inst is Node2D:
			var spawn_pos := (marker as Marker2D).global_position
			inst.call_deferred("set_global_position", spawn_pos)
		print("[RewardSpawner] spawned cow:", inst.name, " at ", (inst as Node2D).global_position)
		

	# Keep only rewards that weren't spawned yet
	GameState.pending_spawns = remaining
