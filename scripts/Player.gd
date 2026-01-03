# Player.gd (Godot 4.x) — Stardew-like "interact in front of you"
extends CharacterBody2D

@export var speed: float = 150.0

# Last facing direction (cardinal: up/down/left/right)
var facing: Vector2 = Vector2.DOWN

# How far in front of the player the interact sensor sits (pixels)
@export var interact_offset: float = 18.0

@onready var sensor: Area2D = $InteractSensor
@onready var indicator: Node2D = $FacingIndicator


func _ready() -> void:
	# Ensure the sensor starts in front of the player (down by default)
	_update_sensor_position()
	indicator.set_direction(facing)

func _physics_process(_delta: float) -> void:
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)

	# Update facing only when there's meaningful input, and snap to 4 directions
	if input.length() > 0.1:
		if abs(input.x) > abs(input.y):
			facing = Vector2(sign(input.x), 0)   # left/right
		else:
			facing = Vector2(0, sign(input.y))   # up/down
		_update_sensor_position()
		indicator.set_direction(facing)

	velocity = input.normalized() * speed
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()

func _update_sensor_position() -> void:
	# Keep sensor one "step" in front of the player
	sensor.position = facing * interact_offset

func _try_interact() -> void:
	# Interact with the first Area2D we overlap that supports interact()
	var areas := sensor.get_overlapping_areas()
	for a in areas:
		if a.has_method("interact"):
			a.interact()
			return
