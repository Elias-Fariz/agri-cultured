extends BaseOverlay
class_name SeedPouchUI

@export var seed_label_path: NodePath = NodePath("Visuals/SeedPanel/SeedRow/SeedLabel")
@export var qty_label_path: NodePath = NodePath("Visuals/SeedPanel/SeedRow/QtyLabel")
@export var prev_button_path: NodePath = NodePath("Visuals/SeedPanel/SeedRow/PrevButton")
@export var next_button_path: NodePath = NodePath("Visuals/SeedPanel/SeedRow/NextButton")

@export var show_only_when_seed_pouch_selected: bool = true

@onready var seed_label: Label = get_node_or_null(seed_label_path) as Label
@onready var qty_label: Label = get_node_or_null(qty_label_path) as Label
@onready var prev_button: Button = get_node_or_null(prev_button_path) as Button
@onready var next_button: Button = get_node_or_null(next_button_path) as Button

func _ready() -> void:
	super._ready()
	add_to_group("seed_pouch_ui")

	if prev_button != null:
		prev_button.pressed.connect(_on_prev_pressed)

	if next_button != null:
		next_button.pressed.connect(_on_next_pressed)

	if GameState.has_signal("seed_selection_changed"):
		GameState.seed_selection_changed.connect(_on_seed_selection_changed)

	if GameState.has_signal("inventory_changed"):
		GameState.inventory_changed.connect(_on_inventory_changed)

	if GameState.has_signal("tool_changed"):
		GameState.tool_changed.connect(_on_tool_changed)

	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if GameState.is_gameplay_locked():
		return

	if event.is_action_pressed("seed_next"):
		# Shift + seed_next cycles backward.
		if event is InputEventKey and (event as InputEventKey).shift_pressed:
			GameState.cycle_seed_previous()
		else:
			GameState.cycle_seed_next()

		get_viewport().set_input_as_handled()
		return


func _on_prev_pressed() -> void:
	if GameState.is_gameplay_locked():
		return
	GameState.cycle_seed_previous()


func _on_next_pressed() -> void:
	if GameState.is_gameplay_locked():
		return
	GameState.cycle_seed_next()


func _on_seed_selection_changed(_seed_id: String, _display_text: String, _quantity: int) -> void:
	_refresh()


func _on_inventory_changed() -> void:
	_refresh()


func _on_tool_changed(_tool_type: int, _tool_name: String) -> void:
	_refresh()


func _refresh() -> void:
	var should_show := true

	if show_only_when_seed_pouch_selected:
		should_show = int(GameState.current_tool) == int(GameState.ToolType.SEED_POUCH)

	if should_show:
		show_overlay()
	else:
		hide_overlay()

	var seed_id := String(GameState.selected_item_id)

	if seed_id.strip_edges() == "" or not GameState.is_seed_item(seed_id):
		if seed_label != null:
			seed_label.text = "Seed Pouch: No seeds"
		if qty_label != null:
			qty_label.text = ""
		return

	var qty := int(GameState.inventory.get(seed_id, 0))

	if seed_label != null:
		seed_label.text = "Seed Pouch: " + seed_id

	if qty_label != null:
		qty_label.text = "x%d" % qty
