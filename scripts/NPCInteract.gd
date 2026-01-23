extends Area2D

@export var prompt_text: String = "E: Talk"
@export var npc_id_property_name: StringName = &"npc_id"  # the variable name on NPC.gd

func _get_parent_npc_id() -> String:
	var npc := get_parent()
	if npc == null:
		return ""

	# 1) Best case: NPC.gd exposes a method
	if npc.has_method("get_npc_id"):
		return str(npc.call("get_npc_id"))

	# 2) Otherwise: read property directly (works for script variables)
	# Godot lets you access script variables as properties if they exist.
	# We guard by checking if the property exists to avoid errors.
	if npc_id_property_name != &"" and npc.has_method("get"):
		# 'get' exists on Object; we still need to ensure the property is real.
		# If property doesn't exist, get() returns null.
		var v = npc.get(npc_id_property_name)
		if v != null:
			return str(v)

	# 3) Fallback: use node name (only if you want)
	# return npc.name
	return ""

func can_player_interact(player: Node) -> bool:
	var id := _get_parent_npc_id()
	if id == "":
		# If we can't identify, be conservative: allow once (or return true)
		return true

	return GameState.can_talk_to_npc(id)

func get_interact_prompt(player: Node) -> String:
	if not can_player_interact(player):
		return ""
	return prompt_text

func interact() -> void:
	# Block interaction if the talk cooldown says no
	if not can_player_interact(null):
		return

	var npc := get_parent()
	if npc and npc.has_method("start_dialogue"):
		npc.start_dialogue()

func get_interact_priority() -> int:
	return 10

# GiftUI / prompt helper: who receives the gift?
func get_gift_receiver() -> Node:
	return get_parent()
