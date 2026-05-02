extends BaseOverlay
class_name ToolBeltUI

@export var tool_row_path: NodePath = NodePath("Visuals/BottomPanel/ToolRow")

@export var normal_color: Color = Color(0.12, 0.12, 0.12, 0.75)
@export var selected_color: Color = Color(0.28, 0.45, 0.32, 0.95)
@export var normal_font_color: Color = Color.WHITE
@export var selected_font_color: Color = Color.WHITE

@export var slot_min_size: Vector2 = Vector2(106, 60)
@export var show_number_labels: bool = true

# Future icon support.
# You can leave these empty now.
@export var hand_icon: Texture2D
@export var hoe_icon: Texture2D
@export var seed_pouch_icon: Texture2D
@export var watering_can_icon: Texture2D
@export var axe_icon: Texture2D
@export var pickaxe_icon: Texture2D
@export var bucket_icon: Texture2D
@export var fishing_rod_icon: Texture2D

@onready var tool_row: HBoxContainer = get_node_or_null(tool_row_path) as HBoxContainer

var _slot_nodes: Dictionary = {} # tool_type int -> Button
var _tool_order: Array[int] = []

func _ready() -> void:
	super._ready()

	_rebuild_from_game_state()

	if GameState.has_signal("tool_changed"):
		GameState.tool_changed.connect(_on_tool_changed)

	if GameState.has_signal("tool_list_changed"):
		GameState.tool_list_changed.connect(_on_tool_list_changed)

	if GameState.has_signal("seed_selection_changed"):
		GameState.seed_selection_changed.connect(_on_seed_selection_changed)

	if GameState.has_signal("inventory_changed"):
		GameState.inventory_changed.connect(_on_inventory_changed)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if GameState.is_gameplay_locked():
		return

	# Number keys: direct select based on visible belt order.
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		var number_pressed := -1

		match key_event.keycode:
			KEY_1:
				number_pressed = 1
			KEY_2:
				number_pressed = 2
			KEY_3:
				number_pressed = 3
			KEY_4:
				number_pressed = 4
			KEY_5:
				number_pressed = 5
			KEY_6:
				number_pressed = 6
			KEY_7:
				number_pressed = 7
			KEY_8:
				number_pressed = 8
			KEY_9:
				number_pressed = 9

		if number_pressed > 0:
			_select_tool_by_display_index(number_pressed - 1)
			get_viewport().set_input_as_handled()
			return

	# Mouse wheel cycling.
	if event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton

		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			GameState.cycle_tool_previous()
			get_viewport().set_input_as_handled()
			return

		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			GameState.cycle_tool_next()
			get_viewport().set_input_as_handled()
			return


func _rebuild_from_game_state() -> void:
	if GameState.has_method("get_owned_tool_order"):
		_tool_order = GameState.get_owned_tool_order()
	else:
		_tool_order = [
			GameState.ToolType.HAND,
			GameState.ToolType.HOE,
			GameState.ToolType.WATERING_CAN,
			GameState.ToolType.AXE,
			GameState.ToolType.PICKAXE,
		]

	_build_slots()
	_refresh_all_slot_text()
	_refresh_selected_tool()


func _build_slots() -> void:
	if tool_row == null:
		return

	for child in tool_row.get_children():
		child.queue_free()

	_slot_nodes.clear()

	for i in range(_tool_order.size()):
		var tool_type := int(_tool_order[i])
		var slot := _create_tool_slot(tool_type, i)
		tool_row.add_child(slot)
		_slot_nodes[tool_type] = slot


func _create_tool_slot(tool_type: int, index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = slot_min_size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.text = _get_button_text(tool_type, index)

	var icon := _get_icon_for_tool(tool_type)
	if icon != null:
		button.icon = icon

	button.pressed.connect(func():
		if GameState.is_gameplay_locked():
			return
		GameState.set_current_tool(tool_type)
	)

	return button


func _get_button_text(tool_type: int, index: int) -> String:
	var label := GameState.get_tool_name_for(tool_type)

	if tool_type == GameState.ToolType.SEED_POUCH:
		if GameState.has_method("get_selected_seed_short_text"):
			label = GameState.get_selected_seed_short_text()

	if show_number_labels:
		return "%d\n%s" % [index + 1, label]

	return label


func _get_icon_for_tool(tool_type: int) -> Texture2D:
	match tool_type:
		GameState.ToolType.HAND:
			return hand_icon
		GameState.ToolType.HOE:
			return hoe_icon
		GameState.ToolType.SEED_POUCH:
			return seed_pouch_icon
		GameState.ToolType.WATERING_CAN:
			return watering_can_icon
		GameState.ToolType.AXE:
			return axe_icon
		GameState.ToolType.PICKAXE:
			return pickaxe_icon
		GameState.ToolType.BUCKET:
			return bucket_icon
		GameState.ToolType.FISHING_ROD:
			return fishing_rod_icon

	return null


func _on_tool_changed(_tool_type: int, _tool_name: String) -> void:
	_refresh_selected_tool()


func _on_tool_list_changed() -> void:
	_rebuild_from_game_state()


func _on_seed_selection_changed(_seed_id: String, _display_text: String, _quantity: int) -> void:
	_refresh_all_slot_text()


func _on_inventory_changed() -> void:
	_refresh_all_slot_text()


func _refresh_all_slot_text() -> void:
	for i in range(_tool_order.size()):
		var tool_type := int(_tool_order[i])
		var button := _slot_nodes.get(tool_type, null) as Button
		if button == null:
			continue

		button.text = _get_button_text(tool_type, i)

		var icon := _get_icon_for_tool(tool_type)
		if icon != null:
			button.icon = icon


func _refresh_selected_tool() -> void:
	var selected := int(GameState.current_tool)

	for tool_type_any in _slot_nodes.keys():
		var tool_type := int(tool_type_any)
		var button := _slot_nodes[tool_type] as Button
		if button == null:
			continue

		var is_selected := tool_type == selected
		_apply_slot_style(button, is_selected)


func _apply_slot_style(button: Button, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6

	if selected:
		style.bg_color = selected_color
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.75, 1.0, 0.78, 0.95)
		button.add_theme_color_override("font_color", selected_font_color)
	else:
		style.bg_color = normal_color
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_color = Color(1, 1, 1, 0.18)
		button.add_theme_color_override("font_color", normal_font_color)

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", style)


func _select_tool_by_display_index(index: int) -> void:
	if index < 0 or index >= _tool_order.size():
		return

	var tool_type := int(_tool_order[index])
	GameState.set_current_tool(tool_type)
