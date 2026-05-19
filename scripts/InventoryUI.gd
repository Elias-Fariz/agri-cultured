# res://ui/InventoryUI.gd
extends BaseOverlay

@onready var panel: Panel = $Panel
@onready var grid: GridContainer = $Panel/VBoxContainer/Scroll/Grid

@export var slot_count: int = 30            # ✅ change this later anytime
@export var columns: int = 6                # Grid width
@export var slot_scene: PackedScene = preload("res://ui/InventorySlot.tscn")

var _slots: Array[InventorySlot] = []

var _selected_slot_index: int = -1
var _selected_item_id: String = ""

# Stability guards.
var _using_item: bool = false
@export var use_item_cooldown: float = 0.12
@export var use_item_delay_after_open: float = 0.10
var _use_item_cooldown_left: float = 0.0
var _use_item_delay_after_open_left: float = 0.0

var _slot_group := ButtonGroup.new()

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	
	_slot_group.allow_unpress = true
	_build_slots()
	_refresh_from_gamestate()

func _process(delta: float) -> void:
	_use_item_cooldown_left = max(0.0, _use_item_cooldown_left - delta)
	_use_item_delay_after_open_left = max(0.0, _use_item_delay_after_open_left - delta)

func show_ui() -> void:
	super.show_overlay()
	_use_item_delay_after_open_left = use_item_delay_after_open
	_refresh_from_gamestate()
	_clear_selection()

func hide_ui() -> void:
	_clear_selection()
	super.hide_overlay()

func toggle_ui() -> void:
	if panel.visible:
		hide_ui()
	else:
		show_ui()

func is_open() -> bool:
	return panel.visible

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not is_open():
		return

	# Inventory should close with T or Esc.
	if event.is_action_pressed("open_inventory") or event.is_action_pressed("ui_cancel"):
		hide_ui()
		get_viewport().set_input_as_handled()
		return

	# Space / Interact consumes selected item.
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_try_use_selected()
		get_viewport().set_input_as_handled()
		return

func _build_slots() -> void:
	# Configure columns
	grid.columns = max(1, columns)

	# Clear existing children (if any)
	for c in grid.get_children():
		c.queue_free()
	_slots.clear()

	# Build slot instances
	for i in range(slot_count):
		var s := slot_scene.instantiate() as InventorySlot
		grid.add_child(s)
		s.slot_index = i
		s.toggle_mode = true
		s.focus_mode = Control.FOCUS_ALL
		s.toggled.connect(_on_slot_toggled.bind(i))
		s.button_group = _slot_group
		s.toggle_mode = true
		s.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE  # important in Godot 4
		_slots.append(s)

	# Default select first slot
	_selected_slot_index = -1
	_selected_item_id = ""

func _refresh_from_gamestate() -> void:
	# Convert GameState.inventory (Dictionary item_id -> qty) into a stable list
	var inv: Dictionary = GameState.inventory

	var ids: Array[String] = []
	for k in inv.keys():
		var id := String(k)
		var qty := int(inv[k])
		if id != "" and qty > 0:
			ids.append(id)
	ids.sort() # stable ordering

	# Fill slots
	for i in range(_slots.size()):
		var slot := _slots[i]
		if i < ids.size():
			var id := ids[i]
			var qty := int(inv.get(id, 0))
			var tex := _get_item_icon(id)
			slot.set_item(id, qty, tex)
		else:
			slot.clear_item()

	# Restore selection
	_restore_selection()

func _on_slot_pressed(i: int) -> void:
	if i < 0 or i >= _slots.size():
		return
	if _slots[i].item_id == "" or _slots[i].qty <= 0:
		# ✅ don’t select empties
		return

	_select_slot(i)

func _select_slot(i: int) -> void:
	if i < 0 or i >= _slots.size():
		return

	for j in range(_slots.size()):
		if j != i:
			_slots[j].button_pressed = false
			_slots[j].refresh_visuals() # ✅ immediate unhighlight

	_slots[i].button_pressed = true
	_slots[i].refresh_visuals()      # ✅ immediate highlight

	_selected_slot_index = i
	_selected_item_id = _slots[i].item_id

func _restore_selection() -> void:
	# If we had an item selected, try to re-select it
	if _selected_item_id != "":
		for i in range(_slots.size()):
			if _slots[i].item_id == _selected_item_id:
				_select_slot(i)
				return

	# Otherwise select first non-empty slot, else none
	for i in range(_slots.size()):
		if _slots[i].item_id != "":
			_select_slot(i)
			return

	_selected_slot_index = -1
	_selected_item_id = ""

func _try_use_selected() -> void:
	if GameState != null and GameState.has_method("can_use_items_now"):
		if not GameState.can_use_items_now():
			return
	
	if _using_item:
		return
		
	if _use_item_delay_after_open_left > 0.0:
		return

	if _use_item_cooldown_left > 0.0:
		return

	_using_item = true
	_use_item_cooldown_left = use_item_cooldown

	# If nothing selected, pick the first item.
	if _selected_item_id == "":
		_restore_selection()
		if _selected_item_id == "":
			_using_item = false
			return

	var item_to_use := _selected_item_id

	# Attempt to consume/eat through existing GameState logic.
	var used := false
	if GameState != null and GameState.has_method("consume_item"):
		used = GameState.consume_item(item_to_use)

	if used:
		_refresh_from_gamestate()

	# Release on next frame so UI refresh and button state can settle.
	await get_tree().process_frame
	_using_item = false

func _get_item_icon(item_id: String) -> Texture2D:
	if ItemDb != null and ItemDb.has_method("get_item"):
		var data = ItemDb.get_item(item_id)
		if data != null:
			# ItemData.icon is exactly what we want
			var tex: Variant = data.icon
			if tex is Texture2D:
				return tex
	return null

func _on_slot_toggled(pressed: bool, index: int) -> void:
	if not pressed:
		return

	if index < 0 or index >= _slots.size():
		return

	var slot := _slots[index]

	# ✅ Block empty slots from being selected — and keep NOTHING selected
	if slot.item_id == "" or slot.qty <= 0:
		# Untoggle the clicked empty slot immediately
		slot.button_pressed = false
		if slot.has_method("refresh_visuals"):
			slot.refresh_visuals()

		# Clear selection state
		_selected_slot_index = -1
		_selected_item_id = ""

		# Also clear any other toggles (just to be extra safe)
		for s in _slots:
			if s.button_pressed:
				s.button_pressed = false
				if s.has_method("refresh_visuals"):
					s.refresh_visuals()

		return

	# ✅ Valid selection
	_selected_slot_index = index
	_selected_item_id = slot.item_id

func _clear_selection() -> void:
	_selected_slot_index = -1
	_selected_item_id = ""

	for s in _slots:
		s.button_pressed = false
		if s.has_method("refresh_visuals"):
			s.refresh_visuals()
