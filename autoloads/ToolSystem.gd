# res://autoloads/ToolSystem.gd
extends Node

# This autoload contains the *decision logic* for Space-bar tool use.
# It expects the current "world" node (Farm, Mine, Forest, etc.) to provide
# the same helper methods/fields that Farm.gd already has.
#
# ✅ Safe design: if something is missing, we fail softly and do nothing.

func tool_action(world: Node, player: Node) -> void:
	if world == null or player == null:
		return

	# If gameplay is locked, do nothing (menus/dialogue/cutscenes)
	if GameState.is_gameplay_locked():
		return

	# If exhausted, block tool use
	if GameState.exhausted and GameState.energy <= 0:
		# print("Too exhausted to use tools!")
		return

	# We rely on these being present (Farm already has them)
	if not world.has_method("_get_destructible_key_at"):
		push_warning("ToolSystem: world missing _get_destructible_key_at().")
		return
	if not world.has_method("_hit_destructible"):
		push_warning("ToolSystem: world missing _hit_destructible().")
		return
	if not world.has_method("water_cell"):
		push_warning("ToolSystem: world missing water_cell().")
		return
	if not world.has_method("_is_crop_harvestable"):
		push_warning("ToolSystem: world missing _is_crop_harvestable().")
		return
	if not world.has_method("_harvest_crop"):
		push_warning("ToolSystem: world missing _harvest_crop().")
		return
	if not world.has_method("_can_till_ground"):
		push_warning("ToolSystem: world missing _can_till_ground().")
		return
	if not world.has_method("_try_till_ground"):
		push_warning("ToolSystem: world missing _try_till_ground().")
		return

	# We also need access to the TileMaps from the world
	var ground :TileMap= world.get("ground")
	var objects :TileMap= world.get("objects")

	if ground == null or objects == null:
		# No tilemaps connected -> do nothing safely
		return

	# Optional: type safety
	if not (ground is TileMap) or not (objects is TileMap):
		return

	# --- Determine the target cell (in front of player facing) ---
	# You already store facing as a cardinal Vector2 on Player.gd
	if not ("facing" in player):
		push_warning("ToolSystem: player missing 'facing'.")
		return

	var player_cell: Vector2i = ground.local_to_map(ground.to_local(player.global_position))
	var step := Vector2i(int(player.facing.x), int(player.facing.y))
	var target_cell := player_cell + step

	# 1) Destructibles (trees/rocks)
	var dkey: String = world.call("_get_destructible_key_at", target_cell)
	if dkey != "":
		if not ("destructible_defs" in world):
			push_warning("ToolSystem: world missing destructible_defs.")
			return

		var def: Dictionary = world.destructible_defs[dkey]
		var required_tool := int(def.get("tool", -1))

		if int(GameState.current_tool) != required_tool:
			# print("Wrong tool! Need ", dkey, " tool.")
			return

		if not GameState.spend_tool_energy(GameState.tool_action_cost, int(GameState.current_tool)):
			# print("No energy to use tools!")
			return

		world.call("_hit_destructible", target_cell, dkey)
		return

	# 2) Watering (Watering Can)
	if GameState.current_tool == GameState.ToolType.WATERING_CAN:
		# We need these values from the world (Farm already has them)
		if not ("ground_source_id" in world and "tilled_coords" in world and "wet_tilled_coords" in world):
			push_warning("ToolSystem: world missing tilled/wet coords config.")
			return

		var src := ground.get_cell_source_id(0, target_cell)
		var atlas := ground.get_cell_atlas_coords(0, target_cell)

		var is_tilled_or_wet :Variant= (src == int(world.ground_source_id)
			and (atlas == world.tilled_coords or atlas == world.wet_tilled_coords))

		if not is_tilled_or_wet:
			# print("Can't water here (not tilled soil).")
			return

		if atlas == world.wet_tilled_coords:
			# print("This tile is already wet.")
			return

		if not GameState.spend_tool_energy(GameState.tool_action_cost, int(GameState.current_tool)):
			# print("No energy to water!")
			return

		world.call("water_cell", target_cell)
		return

	# 3) Harvest ripe crops (Hoe)
	var harvestable: bool = bool(world.call("_is_crop_harvestable", target_cell))
	if harvestable:
		if GameState.current_tool != GameState.ToolType.HOE:
			# print("Need Hoe to harvest.")
			return
		if not GameState.spend_tool_energy(GameState.tool_action_cost, int(GameState.current_tool)):
			# print("No energy to harvest!")
			return
		world.call("_harvest_crop", target_cell)
		return

	# 4) Otherwise till (Hoe)
	var can_till: bool = bool(world.call("_can_till_ground", target_cell))
	if can_till:
		if GameState.current_tool != GameState.ToolType.HOE:
			# print("Need Hoe to till.")
			return
		if not GameState.spend_tool_energy(GameState.tool_action_cost, int(GameState.current_tool)):
			# print("No energy to till!")
			return
		world.call("_try_till_ground", target_cell)
		return

	# print("Nothing to do here.")

func tool_action_auto(player: Node) -> void:
	if player == null:
		return

	var tree := get_tree()
	if tree == null:
		return

	var scene := tree.current_scene
	if scene == null:
		return

	var world: Node = null
	for n in tree.get_nodes_in_group("tool_world"):
		# Only accept providers that are in the current scene tree
		if not scene.is_ancestor_of(n) and n != scene:
			continue

		# Only accept nodes that actually implement the required API
		if n.has_method("_get_destructible_key_at") and n.has_method("_hit_destructible"):
			world = n
			break

	if world == null:
		return

	tool_action(world, player)
