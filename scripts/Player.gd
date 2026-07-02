# Player.gd (Godot 4.x) — Stardew-like "interact in front of you"
extends CharacterBody2D

@export var speed: float = 150.0

# Last facing direction (cardinal: up/down/left/right)
var facing: Vector2 = Vector2.DOWN

var facing_direction: String = "down"
var facing_vector: Vector2 = Vector2.DOWN

# Future-friendly optional sprite support.
# Later, when you have real player sprites, assign your AnimatedSprite2D here.
@export var animated_sprite_path: NodePath

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

# Developer-only cinematic capture tool.
# Press Z to freeze the camera in the world while the player keeps moving.
@export var dev_camera_tools_enabled: bool = true
@export var dev_camera_lock_key: Key = KEY_Z

# Developer-only cinematic walking tool.
# Press Left Shift to toggle slow walking for prettier recordings.
@export var dev_walk_tools_enabled: bool = true
@export var dev_walk_toggle_key: Key = KEY_SHIFT
@export_range(0.05, 1.0, 0.01)
var dev_walk_speed_multiplier: float = 0.45

var _dev_walk_enabled: bool = false

var _dev_camera_locked: bool = false
var _dev_camera_locked_global_transform: Transform2D

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

@onready var interact_prompt: Node = $InteractPromptController
@onready var gift_ui: Node = get_tree().get_first_node_in_group("gift_ui")

var _camera_zoom_cutscene_override: bool = false
var _camera_zoom_tween: Tween = null

@export var interact_cooldown_seconds: float = 0.15
@export var tool_cooldown_seconds: float = 0.10
@export var inventory_toggle_cooldown_seconds: float = 0.15

# Safety grace after dialogue/cutscene/modal gameplay unlocks.
# This prevents instant T -> click -> Space chains from firing while systems are still cleaning up.
@export var post_gameplay_unlock_input_grace_seconds: float = 0.35

var _interact_cooldown_left: float = 0.0
var _tool_cooldown_left: float = 0.0
var _inventory_toggle_cooldown_left: float = 0.0
var _post_gameplay_unlock_input_grace_left: float = 0.0
var _was_gameplay_locked_last_frame: bool = false

var _overhead_text_timer: SceneTreeTimer = null

@onready var overhead_bubble: Node = $OverheadBubbleController

func _ready() -> void:
	# Ensure the sensor and facing indicator start in the correct direction.
	_set_facing_vector(facing, true)
	call_deferred("_apply_camera_bounds_if_present")
	_target_zoom = cam.zoom.x
	shake_offset.position = Vector2.ZERO
	_was_gameplay_locked_last_frame = _is_gameplay_locked_now()

func _enter_tree() -> void:
	call_deferred("_apply_camera_bounds_if_present")

func _physics_process(delta: float) -> void:
	_interact_cooldown_left = max(0.0, _interact_cooldown_left - delta)
	_tool_cooldown_left = max(0.0, _tool_cooldown_left - delta)
	_inventory_toggle_cooldown_left = max(0.0, _inventory_toggle_cooldown_left - delta)
	_post_gameplay_unlock_input_grace_left = max(0.0, _post_gameplay_unlock_input_grace_left - delta)

	var locked_now := _is_gameplay_locked_now()

	if _was_gameplay_locked_last_frame and not locked_now:
		_post_gameplay_unlock_input_grace_left = max(
			_post_gameplay_unlock_input_grace_left,
			post_gameplay_unlock_input_grace_seconds
		)

	_was_gameplay_locked_last_frame = locked_now
	
	# 1) Camera should ALWAYS update, unless developer camera lock is active.
	if _dev_camera_locked:
		_keep_dev_camera_locked()
		_update_camera_zoom(delta)
	else:
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

	# Food buff: Bright Step / movement speed multiplier.
	# This stacks gently with exhausted slowdown.
	if GameState != null and GameState.has_method("get_movement_speed_multiplier"):
		mult *= GameState.get_movement_speed_multiplier()

	if GameState.exhausted:
		mult *= exhausted_speed_multiplier

	# Dev/cinematic walk mode.
	# This is mainly for recording soft devlog footage.
	if _dev_walk_enabled:
		mult *= dev_walk_speed_multiplier

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
	if _is_dev_camera_toggle_event(event):
		_toggle_dev_camera_lock()
		get_viewport().set_input_as_handled()
		return

	if _is_dev_walk_toggle_event(event):
		_toggle_dev_walk()
		get_viewport().set_input_as_handled()
		return

	# Allow Inventory to close itself even while gameplay is locked.
	# This is important because Inventory is modal, so opening it locks gameplay.
	if event.is_action_pressed("open_inventory") or event.is_action_pressed("ui_cancel"):
		if inventory_ui != null and inventory_ui.has_method("is_open") and bool(inventory_ui.call("is_open")):
			if inventory_ui.has_method("hide_ui"):
				inventory_ui.call("hide_ui")
			else:
				inventory_ui.hide_overlay()

			get_viewport().set_input_as_handled()
			return

	# Do not start new gameplay/UI actions while a cutscene/dialogue/modal system
	# is still locked, or during the tiny grace period right after it unlocks.
	if _should_block_new_gameplay_input():
		if _is_player_gameplay_input_event(event):
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("interact"):
		if _interact_cooldown_left <= 0.0:
			_interact_cooldown_left = interact_cooldown_seconds
			_try_interact()
		return

	if event.is_action_pressed("tool"):
		if _tool_cooldown_left <= 0.0:
			_tool_cooldown_left = tool_cooldown_seconds
			ToolSystem.tool_action_auto(self)
		return
	
	if event.is_action_pressed("open_gift"):
		_try_gift()
		return
		
	if event.is_action_pressed("open_inventory"):
		if _inventory_toggle_cooldown_left <= 0.0:
			_inventory_toggle_cooldown_left = inventory_toggle_cooldown_seconds
			if inventory_ui != null and inventory_ui.has_method("toggle_ui"):
				inventory_ui.toggle_ui()
		get_viewport().set_input_as_handled()
		return
	
	if event.is_action_pressed("tool_next"):
		GameState.cycle_tool_next()
		# print("Selected tool:", GameState.get_tool_name())
		
	if event.is_action_pressed("camera_zoom_in"):
		_target_zoom = clamp(_target_zoom - zoom_step, zoom_min, zoom_max)
	if event.is_action_pressed("camera_zoom_out"):
		_target_zoom = clamp(_target_zoom + zoom_step, zoom_min, zoom_max)
	if event.is_action_pressed("camera_zoom_reset"):
		_target_zoom = 1.0

func _try_interact() -> void:
	# Interact with the first Area2D we overlap that supports interact()
	var areas := sensor.get_overlapping_areas()
	for a in areas:
		if a.has_method("interact"):
			a.interact()
			return

func _update_sensor_position() -> void:
	# Keep sensor one "step" in front of the player
	sensor.position = facing * interact_offset

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
		# print("No CameraBounds found in this scene (optional).")
		return

	var tl := bounds.get_node_or_null("TopLeft") as Marker2D
	var br := bounds.get_node_or_null("BottomRight") as Marker2D
	if tl == null or br == null:
		# print("CameraBounds needs Marker2D children named TopLeft and BottomRight.")
		return

	# Godot Camera2D limits are in pixels (world coordinates)
	cam.limit_left = int(tl.global_position.x)
	cam.limit_top = int(tl.global_position.y)
	cam.limit_right = int(br.global_position.x)
	cam.limit_bottom = int(br.global_position.y)

	# Optional: keep limits updated if you switch scenes
	## print("Camera limits set: L/T/R/B = ",
		#cam.limit_left, cam.limit_top, cam.limit_right, cam.limit_bottom)

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

	if _camera_zoom_cutscene_override:
		return

	var current: float = cam.zoom.x
	var t: float = 1.0 - pow(0.001, delta * zoom_smooth)
	var next_zoom: float = lerp(current, _target_zoom, t)

	cam.zoom = Vector2(next_zoom, next_zoom)
	
func camera_get_target_zoom() -> float:
	return _target_zoom

func camera_set_target_zoom(value: float, instant: bool = false) -> void:
	_target_zoom = clamp(value, zoom_min, zoom_max)

	if instant and cam != null:
		cam.zoom = Vector2(_target_zoom, _target_zoom)

func camera_set_zoom_for_cutscene(value: float, duration: float = 0.0) -> void:
	if cam == null:
		return

	var z :Variant= clamp(value, zoom_min, zoom_max)
	_target_zoom = z

	if _camera_zoom_tween != null:
		_camera_zoom_tween.kill()
		_camera_zoom_tween = null

	if duration <= 0.01:
		cam.zoom = Vector2(z, z)
		_camera_zoom_cutscene_override = false
		return

	_camera_zoom_cutscene_override = true
	_camera_zoom_tween = create_tween()
	_camera_zoom_tween.tween_property(cam, "zoom", Vector2(z, z), duration)
	await _camera_zoom_tween.finished

	_camera_zoom_tween = null
	_camera_zoom_cutscene_override = false

func camera_focus_on_world_point(world_pos: Vector2) -> void:
	_camera_focus_active = true
	_camera_focus_point = world_pos
	_cam_focus_offset = cam.position
	# Optional: stop Camera2D’s own smoothing from fighting us
	if cam:
		cam.position_smoothing_enabled = false
		
	## print("Limits L/T/R/B: ",
	#cam.limit_left, ", ",
	#cam.limit_top, ", ",
	#cam.limit_right, ", ",
	#cam.limit_bottom,
	#"  Zoom:", cam.zoom)

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

func _try_gift() -> void:
	# Gift the closest NPC interact area we overlap
	var areas := sensor.get_overlapping_areas()
	for a in areas:
		# NPCInteract.gd is an Area2D on the NPC, so we can get parent NPC
		var npc := a.get_parent()
		if npc != null and npc.has_method("receive_gift"):
			# Open GiftUI and point it at this npc
			var gift_ui := get_tree().get_first_node_in_group("gift_ui")
			if gift_ui != null and gift_ui.has_method("open_for_npc"):
				gift_ui.call("open_for_npc", npc)
			return

func _is_dev_camera_toggle_event(event: InputEvent) -> bool:
	if not dev_camera_tools_enabled:
		return false

	if event is InputEventKey:
		var key_event := event as InputEventKey
		return key_event.pressed and not key_event.echo and key_event.keycode == dev_camera_lock_key

	return false


func _toggle_dev_camera_lock() -> void:
	if _dev_camera_locked:
		_unlock_dev_camera()
	else:
		_lock_dev_camera()


func _lock_dev_camera() -> void:
	if cam == null:
		return
	if _dev_camera_locked:
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	_dev_camera_locked = true
	_dev_camera_locked_global_transform = cam.global_transform

	_cam_original_parent = cam.get_parent()
	_cam_original_index = cam.get_index()
	_cam_original_transform = cam.transform

	# Stop cutscene/focus camera behavior from fighting the lock.
	_camera_focus_active = false
	_camera_zoom_cutscene_override = false

	if _camera_zoom_tween != null:
		_camera_zoom_tween.kill()
		_camera_zoom_tween = null

	# Detach the camera from the moving player while preserving its world position.
	cam.reparent(scene_root, true)
	cam.global_transform = _dev_camera_locked_global_transform
	cam.position_smoothing_enabled = false
	cam.enabled = true
	cam.make_current()

	# print("[DevCamera] Locked camera at: ", cam.global_position)


func _unlock_dev_camera() -> void:
	if cam == null:
		return
	if not _dev_camera_locked:
		return

	_dev_camera_locked = false

	if _cam_original_parent != null and is_instance_valid(_cam_original_parent):
		# Put the camera back under ShakeOffset, but keep its current world position briefly.
		cam.reparent(_cam_original_parent, true)

		# Start the normal look-ahead system from the camera's current local offset,
		# so it glides back instead of snapping too harshly.
		_cam_offset = cam.position
		_cam_focus_offset = cam.position

		cam.position_smoothing_enabled = true
		cam.enabled = true
		cam.make_current()
	else:
		# Fallback if something strange happened during a scene change.
		cam.enabled = true
		cam.make_current()

	_cam_original_parent = null
	_cam_original_index = -1

	# print("[DevCamera] Unlocked camera; returning to player follow.")


func _keep_dev_camera_locked() -> void:
	if cam == null:
		return

	# Keep the camera frozen in world space.
	# This protects the lock from accidental changes elsewhere.
	cam.global_transform = _dev_camera_locked_global_transform
	cam.enabled = true

func force_unlock_dev_camera() -> void:
	if _dev_camera_locked:
		_unlock_dev_camera()

func _is_gameplay_locked_now() -> bool:
	if GameState == null:
		return false
	if not GameState.has_method("is_gameplay_locked"):
		return false
	return bool(GameState.is_gameplay_locked())


func _should_block_new_gameplay_input() -> bool:
	if _is_gameplay_locked_now():
		return true

	if _post_gameplay_unlock_input_grace_left > 0.0:
		return true

	return false


func _is_player_gameplay_input_event(event: InputEvent) -> bool:
	return (
		event.is_action_pressed("interact")
		or event.is_action_pressed("tool")
		or event.is_action_pressed("open_gift")
		or event.is_action_pressed("open_inventory")
		or event.is_action_pressed("tool_next")
		#or event.is_action_pressed("tool_previous")
	)

func show_overhead_text(text: String, duration: float = 1.0, offset: Vector2 = Vector2.ZERO) -> void:
	text = text.strip_edges()
	if text == "":
		return

	if overhead_bubble != null and overhead_bubble.has_method("show_text"):
		overhead_bubble.call("show_text", text, duration, offset)


func clear_overhead_text() -> void:
	if overhead_bubble != null and overhead_bubble.has_method("hide_bubble"):
		overhead_bubble.call("hide_bubble")

func _schedule_clear_overhead_text(duration: float) -> void:
	duration = max(0.05, duration)

	var timer := get_tree().create_timer(duration)
	_overhead_text_timer = timer
	await timer.timeout

	if _overhead_text_timer == timer:
		clear_overhead_text()
		_overhead_text_timer = null


func _find_first_label_recursive(root: Node) -> Label:
	if root == null:
		return null

	if root is Label:
		return root as Label

	for child in root.get_children():
		var found := _find_first_label_recursive(child)
		if found != null:
			return found

	return null


func _spawn_fallback_overhead_label(text: String, duration: float, offset: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.z_index = 999
	label.position = offset
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "position", offset + Vector2(0, -8), max(duration, 0.05))
	tween.parallel().tween_property(label, "modulate:a", 0.0, max(duration, 0.05))

	await tween.finished

	if label != null and is_instance_valid(label):
		label.queue_free()

func snap_camera_to_player() -> void:
	# Used after scene travel, while the screen is faded out.
	# This prevents the camera from visibly sliding/warping from the
	# editor-placed Player position to the actual spawn point.

	if cam == null:
		return

	# If dev camera lock was active for recording, release it.
	if has_method("force_unlock_dev_camera"):
		force_unlock_dev_camera()

	_camera_focus_active = false
	_camera_focus_point = global_position
	_cam_offset = Vector2.ZERO
	_cam_focus_offset = Vector2.ZERO

	# Reset shake so a previous scene doesn't carry jitter into the new one.
	if shake_offset != null:
		shake_offset.position = Vector2.ZERO

	_shake_time_left = 0.0
	_shake_duration = 0.0
	_shake_intensity = 0.0

	# Put the camera directly back on the player.
	cam.position = Vector2.ZERO
	cam.position_smoothing_enabled = false
	cam.enabled = true
	cam.make_current()

	# Godot 4 Camera2D helpers, if available.
	if cam.has_method("reset_smoothing"):
		cam.call("reset_smoothing")

	if cam.has_method("force_update_scroll"):
		cam.call("force_update_scroll")

	# Re-enable smoothing on the next frame so normal camera behavior resumes.
	await get_tree().process_frame
	if cam != null:
		cam.position_smoothing_enabled = true

func set_facing_direction(direction: String) -> void:
	# Called by WorldSpawn after scene travel.
	# Also future-friendly for cutscenes/NPC scripts if they need
	# to turn the player toward something.

	var v := _direction_to_vector(direction)
	_set_facing_vector(v, true)


func set_facing_vector(new_facing: Vector2) -> void:
	# Optional public helper if another script wants to pass a Vector2 directly.
	_set_facing_vector(new_facing, true)


func _set_facing_vector(new_facing: Vector2, force: bool = false) -> void:
	if new_facing == Vector2.ZERO:
		return

	# Snap to cardinal just in case a diagonal/vector slips through.
	if abs(new_facing.x) > abs(new_facing.y):
		new_facing = Vector2(sign(new_facing.x), 0)
	else:
		new_facing = Vector2(0, sign(new_facing.y))

	if not force and facing == new_facing:
		return

	facing = new_facing
	facing_vector = facing
	facing_direction = _vector_to_direction(facing)

	_update_sensor_position()

	if indicator != null and indicator.has_method("set_direction"):
		indicator.call("set_direction", facing)

	_apply_player_visual_for_facing()


func _direction_to_vector(direction: String) -> Vector2:
	direction = direction.strip_edges().to_lower()

	match direction:
		"up":
			return Vector2.UP
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
		"down":
			return Vector2.DOWN
		_:
			return Vector2.DOWN


func _vector_to_direction(v: Vector2) -> String:
	if abs(v.x) > abs(v.y):
		if v.x > 0.0:
			return "right"
		return "left"

	if v.y < 0.0:
		return "up"

	return "down"


func _apply_player_visual_for_facing() -> void:
	# Future-friendly hook.
	# Right now, your FacingIndicator handles the placeholder arrow.
	# Later, if you assign an AnimatedSprite2D here, the player can
	# automatically switch to idle_up / idle_down / idle_left / idle_right.

	var sprite := get_node_or_null(animated_sprite_path) as AnimatedSprite2D
	if sprite == null:
		return

	var idle_anim := "idle_" + facing_direction
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(idle_anim):
		sprite.play(idle_anim)

func _is_dev_walk_toggle_event(event: InputEvent) -> bool:
	if not dev_walk_tools_enabled:
		return false

	if event is InputEventKey:
		var key_event := event as InputEventKey
		return key_event.pressed and not key_event.echo and key_event.keycode == dev_walk_toggle_key

	return false


func _toggle_dev_walk() -> void:
	_dev_walk_enabled = not _dev_walk_enabled
	print("[DevWalk] Slow walk = ", _dev_walk_enabled)


func set_dev_walk_enabled(value: bool) -> void:
	_dev_walk_enabled = value


func is_dev_walk_enabled() -> bool:
	return _dev_walk_enabled
