extends Area2D
class_name CookingStation

@export var prompt_text: String = "E: Cook"
@export var prompt_priority: int = 40

# Assign CookingUI node path if the UI is already in the scene.
@export var cooking_ui_path: NodePath

# Optional fallback if you want this station to spawn the UI itself later.
@export var cooking_ui_scene: PackedScene

var _spawned_ui: Node = null


func get_interact_prompt(_context: Node = null) -> String:
	if _has_any_recipes_unlocked():
		return prompt_text

	return "No Recipes Yet"


func get_interact_priority(_context: Node = null) -> int:
	return prompt_priority


func interact() -> void:
	if GameState == null:
		return

	if not _has_any_recipes_unlocked():
		if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
			QuestEvents.toast_requested.emit("You don't know any recipes yet. Maybe someone in town can help.", "info", 2.5)
		return

	var ui := _get_cooking_ui()
	if ui == null:
		push_warning("CookingStation: No CookingUI found or assigned.")
		return

	if ui.has_method("show_overlay"):
		ui.show_overlay()
	elif ui.has_method("show"):
		ui.show()


func _has_any_recipes_unlocked() -> bool:
	if GameState == null:
		return false

	if not GameState.has_method("get_unlocked_cooking_recipe_ids"):
		return false

	var unlocked: Dictionary = GameState.get_unlocked_cooking_recipe_ids()
	return unlocked.size() > 0


func _get_cooking_ui() -> Node:
	if cooking_ui_path != NodePath(""):
		var ui := get_node_or_null(cooking_ui_path)
		if ui != null:
			return ui

	# Search common places.
	var tree := get_tree()
	if tree == null:
		return null

	var current := tree.current_scene
	if current != null:
		var found := current.find_child("CookingUI", true, false)
		if found != null:
			return found

	var root_found := tree.root.find_child("CookingUI", true, false)
	if root_found != null:
		return root_found

	# Optional fallback spawn.
	if cooking_ui_scene != null:
		_spawned_ui = cooking_ui_scene.instantiate()
		tree.root.add_child(_spawned_ui)
		return _spawned_ui

	return null
