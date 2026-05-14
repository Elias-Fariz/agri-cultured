extends Node2D
class_name Gate

@export var closed_texture: Texture2D
@export var open_texture: Texture2D

@export var starts_open: bool = false
@export var open_rotation_degrees: float = 0.0

@export var open_toast: String = "You open the gate."
@export var close_toast: String = "You close the gate."

@onready var sprite: Sprite2D = $Sprite2D
@onready var blocker: StaticBody2D = $StaticBody2D
@onready var blocker_collision: CollisionShape2D = $StaticBody2D/CollisionShape2D
@onready var interact_area: Area2D = $InteractArea

var is_open: bool = false


func _ready() -> void:
	add_to_group("interactables")

	if interact_area != null:
		interact_area.add_to_group("interactables")

	is_open = starts_open
	_apply_state()


func interact() -> void:
	toggle_gate()


func toggle_gate() -> void:
	is_open = not is_open
	_apply_state()

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		if is_open:
			QuestEvents.toast_requested.emit(open_toast, "info", 1.2)
		else:
			QuestEvents.toast_requested.emit(close_toast, "info", 1.2)


func _apply_state() -> void:
	if sprite != null:
		if is_open and open_texture != null:
			sprite.texture = open_texture
		elif not is_open and closed_texture != null:
			sprite.texture = closed_texture

	if blocker_collision != null:
		blocker_collision.disabled = is_open
