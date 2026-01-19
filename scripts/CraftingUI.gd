# CraftingUI.gd
extends BaseOverlay

@onready var panel: Panel = $Panel
@onready var recipes_list: ItemList = $Panel/VBox/Content/RecipesList
@onready var selected_title: Label = $Panel/VBox/Content/Right/SelectedTitle
@onready var selected_desc: RichTextLabel = $Panel/VBox/Content/Right/SelectedDesc
@onready var requirements: RichTextLabel = $Panel/VBox/Content/Right/Requirements
@onready var craft_button: Button = $Panel/VBox/Content/Right/CraftButton

@export var recipes: Array[CraftingRecipeData] = []

var _visible_recipe_ids: Array[String] = []
var _selected_recipe_id: String = ""

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	recipes_list.item_selected.connect(_on_recipe_selected)
	craft_button.pressed.connect(_on_craft_pressed)

	# Helps refresh when quests unlock recipes, etc.
	QuestEvents.quest_state_changed.connect(_refresh_list)

	_refresh_list()
	_render_selected(null)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if event.is_action_pressed("open_crafting"):
		toggle_overlay()
		get_viewport().set_input_as_handled()
		return

	if is_open() and event.is_action_pressed("ui_cancel"):
		hide_overlay()
		get_viewport().set_input_as_handled()
		return


func show_overlay() -> void:
	super.show_overlay()
	_refresh_list()
	if recipes_list.item_count > 0:
		recipes_list.grab_focus()


func _refresh_list() -> void:
	recipes_list.clear()
	_visible_recipe_ids.clear()

	var unlocked: Dictionary = GameState.get_unlocked_recipe_ids()
	var inv: Dictionary = GameState.inventory

	var rows: Array = [] # {id:String, name:String, craftable:bool}

	for r in recipes:
		if r == null:
			continue
		if r.id.strip_edges() == "":
			continue
		if not unlocked.has(r.id):
			continue

		var name := r.display_name
		if name.strip_edges() == "":
			name = r.id

		var craftable := r.can_craft(inv)

		rows.append({
			"id": r.id,
			"name": name,
			"craftable": craftable
		})

	# Sort: craftable first, then name
	rows.sort_custom(func(a, b):
		var a_c := bool(a["craftable"])
		var b_c := bool(b["craftable"])
		if a_c != b_c:
			return a_c and not b_c
		return str(a["name"]) < str(b["name"])
	)

	for row in rows:
		var rid: String = row["id"]
		var name2: String = row["name"]
		var craftable2: bool = bool(row["craftable"])

		var label := name2
		if craftable2:
			label = "✅ " + name2
		else:
			label = "   " + name2

		recipes_list.add_item(label)
		_visible_recipe_ids.append(rid)

	# Keep selection if possible
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


func _get_recipe_by_id(rid: String) -> CraftingRecipeData:
	for r in recipes:
		if r != null and r.id == rid:
			return r
	return null


func _on_recipe_selected(index: int) -> void:
	if index < 0 or index >= _visible_recipe_ids.size():
		return
	_selected_recipe_id = _visible_recipe_ids[index]
	_render_selected(_get_recipe_by_id(_selected_recipe_id))


func _render_selected(r: CraftingRecipeData) -> void:
	if r == null:
		selected_title.text = "Crafting"
		selected_desc.text = "Select a recipe on the left."
		requirements.text = ""
		craft_button.disabled = true
		return

	selected_title.text = r.display_name if r.display_name.strip_edges() != "" else r.id
	selected_desc.text = r.description

	var inv: Dictionary = GameState.inventory
	var lines: Array[String] = ["Requirements:"]
	lines.append_array(r.get_requirements_as_lines(inv))
	lines.append("")
	lines.append("Makes: %s x%d" % [r.output_item_id, int(r.output_qty)])

	requirements.text = "\n".join(lines)
	craft_button.disabled = not r.can_craft(inv)

func _on_craft_pressed() -> void:
	var r := _get_recipe_by_id(_selected_recipe_id)
	if r == null:
		return

	var inv: Dictionary = GameState.inventory
	if not r.can_craft(inv):
		GameState.toast_info("Not enough items to craft that.")
		_refresh_list()
		_render_selected(r)
		return

	# Remove requirements safely (works with string keys OR ItemData keys)
	r.consume_requirements(Callable(GameState, "inventory_remove"))

	# Add output
	GameState.inventory_add(r.output_item_id, int(r.output_qty))
	GameState.toast_info("Crafted: %s x%d" % [r.output_item_id, int(r.output_qty)])

	_refresh_list()
	_render_selected(r)
