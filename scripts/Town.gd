extends Node2D

@onready var player := $Player

func _ready() -> void:
	_place_player_at_spawn()
	_refresh_festival_decorations()
	_apply_festival_npc_overrides()

func _place_player_at_spawn() -> void:
	if GameState.next_spawn_name != "":
		var marker := get_node_or_null(GameState.next_spawn_name)
		if marker and marker is Marker2D:
			player.global_position = (marker as Marker2D).global_position
		GameState.next_spawn_name = ""

func _refresh_festival_decorations() -> void:
	var decorations := get_tree().get_nodes_in_group("festival_decoration")

	# Hide all decorations in this scene first
	for node in decorations:
		if node == null:
			continue
		if not is_ancestor_of(node):
			continue
		if node is CanvasItem:
			(node as CanvasItem).visible = false

	if FestivalManager == null:
		return

	var active_names := FestivalManager.get_active_decoration_node_names()
	if active_names.is_empty():
		return

	for node in decorations:
		if node == null:
			continue
		if not is_ancestor_of(node):
			continue

		var node_name := String(node.name)
		if active_names.has(node_name):
			if node is CanvasItem:
				(node as CanvasItem).visible = true

func _apply_festival_npc_overrides() -> void:
	if FestivalManager == null:
		return

	if not FestivalManager.is_festival_today():
		return

	var npcs := get_tree().get_nodes_in_group("npc")

	for npc in npcs:
		if npc == null:
			continue
		if not is_ancestor_of(npc):
			continue

		if not npc.has_method("get_npc_id"):
			continue

		var npc_id := String(npc.call("get_npc_id"))
		if npc_id == "":
			continue

		if not FestivalManager.has_npc_override(npc_id):
			continue

		var placement := FestivalManager.get_npc_placement(npc_id)
		if placement == null:
			continue

		_apply_single_festival_npc_override(npc, placement)

func _apply_single_festival_npc_override(npc: Node, placement: FestivalNpcPlacement) -> void:
	# 1) Disable idle wandering if the NPC supports it
	if "enable_idle_wander" in npc:
		npc.enable_idle_wander = false

	# 2) Stop their wander timer if present
	var wander_timer := npc.get_node_or_null("WanderTimer")
	if wander_timer != null and wander_timer is Timer:
		(wander_timer as Timer).stop()

	# 3) Disconnect schedule updates so the normal time-of-day pathing
	#    does not pull them away from the festival spot later in the day.
	var schedule_cb := Callable(npc, "_on_time_changed_for_schedule")
	if TimeManager != null and TimeManager.has_signal("time_changed"):
		if TimeManager.is_connected("time_changed", schedule_cb):
			TimeManager.disconnect("time_changed", schedule_cb)

	# 4) Snap them directly into place
	if npc is Node2D:
		(npc as Node2D).global_position = placement.target_position

	# 5) Optional: also tell the NPC this is their anchor spot if supported
	#    This keeps future wandering centered here if you ever re-enable it.
	if npc.has_method("set_destination"):
		npc.call("set_destination", placement.target_position, true)

	# 6) Stop movement immediately so they stay put
	if "velocity" in npc:
		npc.velocity = Vector2.ZERO

	if npc.has_method("set_physics_process"):
		npc.set_physics_process(false)
