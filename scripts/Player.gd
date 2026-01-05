# Player.gd (Godot 4.x) — Stardew-like "interact in front of you"
extends CharacterBody2D

@export var speed: float = 150.0

# Last facing direction (cardinal: up/down/left/right)
var facing: Vector2 = Vector2.DOWN

# How far in front of the player the interact sensor sits (pixels)
@export var interact_offset: float = 18.0

@export var exhausted_speed_multiplier: float = 0.4

@onready var sensor: Area2D = $InteractSensor
@onready var indicator: Node2D = $FacingIndicator
@onready var inventory_ui = get_tree().current_scene.get_node("InventoryUI")


func _ready() -> void:
	# Ensure the sensor starts in front of the player (down by default)
	_update_sensor_position()
	indicator.set_direction(facing)

func _physics_process(_delta: float) -> void:
	if GameState.is_gameplay_locked():
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
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

	var mult := 1.0
	if GameState.exhausted:
		mult = exhausted_speed_multiplier
	velocity = input.normalized() * speed * mult
	
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()
		
	if event.is_action_pressed("open_inventory"):
		# Refresh UI content then toggle
		inventory_ui.set_items(GameState.inventory)
		inventory_ui.toggle_ui()
		return
	
	if event.is_action_pressed("tool_next"):
		GameState.cycle_tool_next()
		print("Selected tool:", GameState.get_tool_name())


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
