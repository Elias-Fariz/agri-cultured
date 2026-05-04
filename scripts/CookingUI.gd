extends BaseOverlay
class_name CookingUI

@onready var panel: Panel = $Panel
@onready var recipes_list: ItemList = $Panel/VBox/Content/RecipesList
@onready var selected_title: Label = $Panel/VBox/Content/Right/SelectedTitle
@onready var selected_desc: RichTextLabel = $Panel/VBox/Content/Right/SelectedDesc
@onready var requirements: RichTextLabel = $Panel/VBox/Content/Right/Requirements
@onready var cook_button: Button = $Panel/VBox/Content/Right/CookButton

@export var recipes: Array[CookingRecipeData] = []

var _visible_recipe_ids: Array[String] = []
var _selected_recipe_id: String = ""


func _ready() -> void:
	super._ready()

	if Engine.is_editor_hint():
		return

	if recipes_list != null:
		recipes_list.item_selected.connect(_on_recipe_selected)

	if cook_button != null:
		cook_button.pressed.connect(_on_cook_pressed)

	if QuestEvents != null and QuestEvents.has_signal("quest_state_changed"):
		QuestEvents.quest_state_changed.connect(_refresh_list)

	_refresh_list()
	_render_selected(null)


func show_overlay() -> void:
	super.show_overlay()
	_refresh_list()

	if recipes_list != null and recipes_list.item_count > 0:
		recipes_list.grab_focus()


func hide_overlay() -> void:
	super.hide_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if is_open() and event.is_action_pressed("ui_cancel"):
		hide_overlay()
		get_viewport().set_input_as_handled()
		return


func _refresh_list() -> void:
	if recipes_list == null:
		return

	recipes_list.clear()
	_visible_recipe_ids.clear()

	var unlocked: Dictionary = {}
	if GameState != null and GameState.has_method("get_unlocked_cooking_recipe_ids"):
		unlocked = GameState.get_unlocked_cooking_recipe_ids()

	var inv: Dictionary = GameState.inventory if GameState != null else {}

	var rows: Array = []

	for r in recipes:
		if r == null:
			continue
		if not r.is_valid():
			continue
		if not unlocked.has(r.id):
			continue

		var name := r.display_name
		if name.strip_edges() == "":
			name = r.id

		var cookable := r.can_cook(inv)

		rows.append({
			"id": r.id,
			"name": name,
			"cookable": cookable
		})

	rows.sort_custom(func(a, b):
		var a_c := bool(a["cookable"])
		var b_c := bool(b["cookable"])

		if a_c != b_c:
			return a_c and not b_c

		return String(a["name"]) < String(b["name"])
	)

	for row in rows:
		var rid := String(row["id"])
		var name2 := String(row["name"])
		var cookable2 := bool(row["cookable"])

		var label := name2
		if cookable2:
			label = "✅ " + name2
		else:
			label = "   " + name2

		recipes_list.add_item(label)
		_visible_recipe_ids.append(rid)

	if _selected_recipe_id != "" and _visible_recipe_ids.has(_selected_recipe_id):
		var idx := _visible_recipe_ids.find(_selected_recipe_id)
		recipes_list.select(idx)
		_render_selected(_get_recipe_by_id(_selected_recipe_id))
	elif _visible_recipe_ids.size() > 0:
		_selected_recipe_id = _visible_recipe_ids[0]
		recipes_list.select(0)
		_render_selected(_get_recipe_by_id(_selected_recipe_id))
	else:
		_selected_recipe_id = ""
		_render_selected(null)


func _get_recipe_by_id(recipe_id: String) -> CookingRecipeData:
	for r in recipes:
		if r != null and r.id == recipe_id:
			return r

	return null


func _on_recipe_selected(index: int) -> void:
	if index < 0 or index >= _visible_recipe_ids.size():
		return

	_selected_recipe_id = _visible_recipe_ids[index]
	_render_selected(_get_recipe_by_id(_selected_recipe_id))


func _render_selected(r: CookingRecipeData) -> void:
	if selected_title == null or selected_desc == null or requirements == null or cook_button == null:
		return

	if r == null:
		selected_title.text = "Cooking"
		selected_desc.text = "Select a recipe on the left."
		requirements.text = ""
		cook_button.disabled = true
		return

	selected_title.text = r.display_name if r.display_name.strip_edges() != "" else r.id

	var desc_lines: Array[String] = []
	if r.description.strip_edges() != "":
		desc_lines.append(r.description)
	if r.cooking_note.strip_edges() != "":
		desc_lines.append("")
		desc_lines.append("[i]" + r.cooking_note + "[/i]")

	selected_desc.text = "\n".join(desc_lines)

	var inv: Dictionary = GameState.inventory if GameState != null else {}
	var lines: Array[String] = ["Ingredients:"]
	lines.append_array(r.get_requirements_as_lines(inv))
	lines.append("")
	lines.append("Makes: %s x%d" % [r.output_item_id, int(r.output_qty)])

	requirements.text = "\n".join(lines)
	cook_button.disabled = not r.can_cook(inv)


func _on_cook_pressed() -> void:
	var r := _get_recipe_by_id(_selected_recipe_id)
	if r == null:
		return

	var inv: Dictionary = GameState.inventory if GameState != null else {}

	if not r.can_cook(inv):
		_toast_info("Not enough ingredients.")
		_refresh_list()
		_render_selected(r)
		return

	r.consume_ingredients(Callable(GameState, "inventory_remove"))

	GameState.inventory_add(r.output_item_id, int(r.output_qty))

	# Quest-friendly event hooks.
	if QuestEvents != null:
		if QuestEvents.has_signal("item_crafted"):
			QuestEvents.item_crafted.emit(r.output_item_id, int(r.output_qty))

		if QuestEvents.has_signal("action_done"):
			QuestEvents.action_done.emit("cook", 1)

		if QuestEvents.has_signal("toast_requested"):
			var name := r.display_name if r.display_name.strip_edges() != "" else r.output_item_id
			QuestEvents.toast_requested.emit("Cooked: %s x%d" % [name, int(r.output_qty)], "success", 2.5)

	_refresh_list()
	_render_selected(r)


func _toast_info(msg: String) -> void:
	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(msg, "info", 2.0)
