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

@onready var cam: Camera2D = $ShakeOffset/Camera2D
@export var camera_look_ahead_pixels: float = 28.0
@export var camera_look_ahead_smooth: float = 8.0  # higher = snappier

var _cam_offset: Vector2 = Vector2.ZERO

@export var camera_focus_smooth: float = 8.0
@export var camera_max_focus_distance: float = 260.0  # prevents extreme offsets

var _camera_focus_active: bool = false
var _camera_focus_point: Vector2 = Vector2.ZERO
var _cam_focus_offset: Vector2 = Vector2.ZERO

@export var zoom_step: float = 0.1
@export var zoom_min: float = 0.6
@export var zoom_max: float = 1.6
@export var zoom_smooth: float = 12.0

var _target_zoom: float = 1.0

var _cam_original_parent: Node = null
var _cam_original_index: int = -1
var _cam_original_transform: Transform2D

@onready var talk_sfx: AudioStreamPlayer2D = $TalkSfx2D
@export var talk_blips: Array[AudioStream] = []

@export var grass_steps: Array[AudioStream] = []
@export var stone_steps: Array[AudioStream] = []

@export var step_interval: float = 0.4  # seconds between steps
@export var step_pitch_variation: float = 0.1

var _step_timer: float = 0.0

@export var footstep_tile_layer: int = 0

@onready var shake_offset: Node2D = $ShakeOffset

var _shake_time_left: float = 0.0
var _shake_duration: float = 0.0
var _shake_intensity: float = 0.0
var _shake_frequency: float = 30.0
var _shake_damping: float = 10.0

var _shake_seed: float = 0.0


func _ready() -> void:
	# Ensure the sensor starts in front of the player (down by default)
	_update_sensor_position()
	indicator.set_direction(facing)
	call_deferred("_apply_camera_bounds_if_present")
	_target_zoom = cam.zoom.x
	shake_offset.position = Vector2.ZERO

func _enter_tree() -> void:
	call_deferred("_apply_camera_bounds_if_present")

func _physics_process(delta: float) -> void:
	# 1) Camera should ALWAYS update
	if _camera_focus_active:
		_update_camera_focus_offset(delta)
	else:
		_update_camera_lookahead(delta)
		
	_update_camera_zoom(delta)
	_update_camera_shake(delta)

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
	
	var is_moving := velocity.length() > 5.0

	if is_moving:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_play_footstep()
			_step_timer = step_interval
	else:
		_step_timer = 0.0
	
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
		
	if event.is_action_pressed("camera_zoom_in"):
		_target_zoom = clamp(_target_zoom - zoom_step, zoom_min, zoom_max)
	if event.is_action_pressed("camera_zoom_out"):
		_target_zoom = clamp(_target_zoom + zoom_step, zoom_min, zoom_max)
	if event.is_action_pressed("camera_zoom_reset"):
		_target_zoom = 1.0


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

func _apply_camera_bounds_if_present() -> void:
	# Looks for a Node2D called "CameraBounds" in the current scene,
	# with Marker2D children "TopLeft" and "BottomRight".
	# If we're not inside the tree yet (or we're being removed), don't do anything.
	if not is_inside_tree():
		return

	var tree := get_tree()
	if tree == null:
		return

	var scene_root := tree.current_scene
	if scene_root == null:
		return

	var bounds := scene_root.get_node_or_null("CameraBounds")
	if bounds == null:
		print("No CameraBounds found in this scene (optional).")
		return

	var tl := bounds.get_node_or_null("TopLeft") as Marker2D
	var br := bounds.get_node_or_null("BottomRight") as Marker2D
	if tl == null or br == null:
		print("CameraBounds needs Marker2D children named TopLeft and BottomRight.")
		return

	# Godot Camera2D limits are in pixels (world coordinates)
	cam.limit_left = int(tl.global_position.x)
	cam.limit_top = int(tl.global_position.y)
	cam.limit_right = int(br.global_position.x)
	cam.limit_bottom = int(br.global_position.y)

	# Optional: keep limits updated if you switch scenes
	print("Camera limits set: L/T/R/B = ",
		cam.limit_left, cam.limit_top, cam.limit_right, cam.limit_bottom)

func _update_camera_lookahead(delta: float) -> void:
	if cam == null:
		return

	# You said you have player.facing already (Vector2 like (1,0), (0,-1))
	var facing_dir := facing
	if facing_dir == Vector2.ZERO:
		facing_dir = Vector2.DOWN  # safe fallback, optional

	var target_offset := facing_dir.normalized() * camera_look_ahead_pixels

	# Smoothly approach target offset
	_cam_offset = _cam_offset.lerp(target_offset, 1.0 - pow(0.001, delta * camera_look_ahead_smooth))

	# Apply as camera local offset
	cam.position = _cam_offset

func _update_camera_zoom(delta: float) -> void:
	if cam == null:
		return

	var current: float = cam.zoom.x
	var t: float = 1.0 - pow(0.001, delta * zoom_smooth)
	var next_zoom: float = lerp(current, _target_zoom, t)

	cam.zoom = Vector2(next_zoom, next_zoom)

func camera_focus_on_world_point(world_pos: Vector2) -> void:
	_camera_focus_active = true
	_camera_focus_point = world_pos
	_cam_focus_offset = cam.position
	# Optional: stop Camera2D’s own smoothing from fighting us
	if cam:
		cam.position_smoothing_enabled = false
		
	print("Limits L/T/R/B: ",
	cam.limit_left, ", ",
	cam.limit_top, ", ",
	cam.limit_right, ", ",
	cam.limit_bottom,
	"  Zoom:", cam.zoom)

func camera_clear_focus() -> void:
	_camera_focus_active = false
	# Return control to your normal look-ahead system
	if cam:
		cam.position_smoothing_enabled = true

func _update_camera_focus(delta: float) -> void:
	if cam == null:
		return

	if not _camera_focus_active:
		return

	# Smoothly move the camera's global position toward focus point
	# (This overrides the "follow player" feel temporarily)
	var cur: Vector2 = cam.global_position
	var t: float = 1.0 - pow(0.001, delta * camera_focus_smooth)
	cam.global_position = cur.lerp(_camera_focus_point, t)

func _update_camera_focus_offset(delta: float) -> void:
	if cam == null:
		return

	# Desired offset so the camera looks at the NPC relative to the player
	var desired := _camera_focus_point - global_position

	# Keep it reasonable so we don't fling the camera
	if desired.length() > camera_max_focus_distance:
		desired = desired.normalized() * camera_max_focus_distance

	# Smooth it
	var t: float = 1.0 - pow(0.001, delta * camera_focus_smooth)
	_cam_focus_offset = _cam_focus_offset.lerp(desired, t)

	# Apply as local camera offset
	cam.position = _cam_focus_offset

func play_talk_sfx() -> void:
	if talk_blips.is_empty():
		return
	talk_sfx.stream = talk_blips[randi() % talk_blips.size()]
	talk_sfx.pitch_scale = randf_range(0.98, 1.05)
	talk_sfx.play()

func _get_footstep_type() -> String:
	var town: Node = get_tree().get_first_node_in_group("world")
	if town == null:
		return "grass"

	var ground: TileMap = get_tree().get_first_node_in_group("footstep_ground") as TileMap
	if ground == null:
		return "grass"

	var cell: Vector2i = ground.local_to_map(ground.to_local(global_position))
	var data: TileData = ground.get_cell_tile_data(footstep_tile_layer, cell)
	
	if data == null:
		return "grass"

	# TileSet custom data: key = "footstep", value = "grass" or "stone"
	var v: Variant = data.get_custom_data("footstep")
	if v == null:
		return "grass"

	return str(v)

func _play_footstep() -> void:
	var step_type: String = _get_footstep_type()
	var s: AudioStream = _pick_step_stream(step_type)
	if s == null:
		return

	var p: AudioStreamPlayer2D = $FootstepPlayer
	p.stream = s
	p.pitch_scale = 1.0 + randf_range(-step_pitch_variation, step_pitch_variation)
	p.stop()
	p.play()

func _pick_step_stream(step_type: String) -> AudioStream:
	var pool: Array[AudioStream] = grass_steps
	if step_type == "stone":
		pool = stone_steps

	if pool.is_empty():
		return null

	return pool[randi() % pool.size()]

func camera_shake(intensity: float = 6.0, duration: float = 0.12, frequency: float = 30.0, damping: float = 10.0) -> void:
	# If a stronger shake is requested while already shaking, keep the stronger one.
	_shake_intensity = max(_shake_intensity, intensity)

	_shake_duration = max(_shake_duration, duration)
	_shake_time_left = max(_shake_time_left, duration)

	_shake_frequency = frequency
	_shake_damping = damping

	_shake_seed = randf() * 1000.0

func _update_camera_shake(delta: float) -> void:
	if _shake_time_left <= 0.0:
		shake_offset.position = Vector2.ZERO
		return

	_shake_time_left -= delta

	# 0..1 normalized time
	var t: float = 1.0 - (_shake_time_left / max(_shake_duration, 0.001))

	# Smoothly fade out (cozy)
	var falloff: float = exp(-_shake_damping * t)

	# Simple procedural jitter (stable, not too chaotic)
	var phase: float = (_shake_seed + t * _shake_frequency) * TAU
	var x: float = sin(phase) * _shake_intensity * falloff
	var y: float = cos(phase * 1.13) * _shake_intensity * falloff

	shake_offset.position = Vector2(x, y)

	# When it's done, reset cleanly
	if _shake_time_left <= 0.0:
		_shake_intensity = 0.0
		_shake_duration = 0.0
		shake_offset.position = Vector2.ZERO
