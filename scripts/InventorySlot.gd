# res://ui/inventory/InventorySlot.gd
extends Button
class_name InventorySlot

@onready var image: TextureRect = $Icon
@onready var name_label: Label = $Name
@onready var qty_label: Label = $Qty

var slot_index: int = -1
var item_id: String = ""
var qty: int = 0
var has_item: bool = false

@export var style_empty: StyleBox
@export var style_filled: StyleBox
@export var style_hover: StyleBox
@export var style_selected: StyleBox   # optional, but nice for toggle_mode selection

var _hovered: bool = false

func _ready() -> void:
	mouse_entered.connect(_on_mouse_enter)
	mouse_exited.connect(_on_mouse_exit)

	# ✅ refresh visuals whenever Godot changes button_pressed (click OR code)
	toggled.connect(_on_toggled)

	_apply_visual_state()


func _on_toggled(_pressed: bool) -> void:
	_apply_visual_state()


# Optional: lets InventoryUI force a refresh after it changes button_pressed
func refresh_visuals() -> void:
	_apply_visual_state()


# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------
func set_item(id: String, count: int, tex: Texture2D) -> void:
	item_id = id
	qty = count
	has_item = (id.strip_edges() != "" and count > 0)

	# IMPORTANT: don't disable the Button, or "disabled" style will override everything.
	# We'll just ignore presses when empty instead.
	disabled = false
	focus_mode = Control.FOCUS_ALL if has_item else Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if has_item else Control.CURSOR_ARROW

	# Quantity
	qty_label.text = str(count) if has_item else ""

	# Icon vs name fallback
	if has_item and tex != null:
		image.texture = tex
		image.visible = true
		name_label.visible = false
	else:
		image.texture = null
		image.visible = false
		name_label.visible = has_item
		name_label.text = id

	_apply_visual_state()


func clear_item() -> void:
	set_item("", 0, null)


# -------------------------------------------------------------------
# Input behavior
# -------------------------------------------------------------------
func _on_pressed() -> void:
	# If empty, immediately unpress / untoggle and do nothing.
	if not has_item:
		set_pressed_no_signal(false)


# -------------------------------------------------------------------
# Hover visuals
# -------------------------------------------------------------------
func _on_mouse_enter() -> void:
	_hovered = true
	_apply_visual_state()

func _on_mouse_exit() -> void:
	_hovered = false
	_apply_visual_state()


# -------------------------------------------------------------------
# Style application
# -------------------------------------------------------------------
func _apply_visual_state() -> void:
	# Safety: if you forgot to assign styleboxes in the inspector, don’t crash.
	var base_style: StyleBox = style_filled if has_item else style_empty

	# Base states
	if base_style != null:
		add_theme_stylebox_override("normal", base_style)
		add_theme_stylebox_override("disabled", base_style) # just in case you disable later
		add_theme_stylebox_override("focus", base_style)

	# Hover state
	if _hovered and style_hover != null:
		add_theme_stylebox_override("hover", style_hover)

		# This is the trick: some Button states still draw "normal" while hovered,
		# depending on theme, so also override normal during hover.
		add_theme_stylebox_override("normal", style_hover)
	else:
		# Remove hover override; restore base style
		remove_theme_stylebox_override("hover")
		if base_style != null:
			add_theme_stylebox_override("normal", base_style)

	# Selected (toggle_mode) look — apply to normal too so it persists after mouse-up
	if button_pressed and style_selected != null:
		add_theme_stylebox_override("normal", style_selected)
		add_theme_stylebox_override("hover", style_selected)
		add_theme_stylebox_override("pressed", style_selected)
		add_theme_stylebox_override("focus", style_selected)
		add_theme_stylebox_override("disabled", style_selected)
	else:
		# restore base styles
		if base_style != null:
			add_theme_stylebox_override("normal", base_style)
			add_theme_stylebox_override("pressed", base_style)
			add_theme_stylebox_override("focus", base_style)
			add_theme_stylebox_override("disabled", base_style)
		# hover is handled by your hover logic above
