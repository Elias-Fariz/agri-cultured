extends Area2D
class_name DisturbanceCore

signal restoration_hit

@export var vulnerable: bool = false

# Optional visuals
@export var sprite_path: NodePath

@export var closed_texture: Texture2D
@export var open_texture: Texture2D
@export var restored_texture: Texture2D

# If false, textures show exactly as drawn.
# If true, the modulate colors below tint each state.
@export var use_state_modulates: bool = false

@export var closed_modulate: Color = Color(0.45, 0.45, 0.45, 1.0) 
@export var open_modulate: Color = Color(0.45, 1.0, 0.65, 1.0)
@export var restored_modulate: Color = Color(0.85, 1.0, 0.75, 1.0)

# Put restoration cores on layer 6 for the Heartblade slash to detect.
const RESTORATION_CORE_LAYER := 1 << 5

@onready var sprite: Sprite2D = get_node_or_null(sprite_path) as Sprite2D

var restored: bool = false

func _ready() -> void:
	add_to_group("restoration_core")
	monitoring = true
	monitorable = true
	collision_layer = RESTORATION_CORE_LAYER
	collision_mask = 0

	set_vulnerable(vulnerable)

func set_vulnerable(value: bool) -> void:
	if restored:
		vulnerable = false
	else:
		vulnerable = value

	_apply_visual_state()

func receive_restoration_strike() -> bool:
	if restored:
		return false

	if not vulnerable:
		return false

	restoration_hit.emit()
	return true

func mark_restored() -> void:
	restored = true
	vulnerable = false
	_apply_visual_state()

func reset_core() -> void:
	restored = false
	vulnerable = false
	_apply_visual_state()

func _apply_visual_state() -> void:
	if sprite == null:
		return

	if restored:
		if restored_texture != null:
			sprite.texture = restored_texture
		sprite.modulate = restored_modulate if use_state_modulates else Color.WHITE
	elif vulnerable:
		if open_texture != null:
			sprite.texture = open_texture
		sprite.modulate = open_modulate if use_state_modulates else Color.WHITE
	else:
		if closed_texture != null:
			sprite.texture = closed_texture
		sprite.modulate = closed_modulate if use_state_modulates else Color.WHITE
