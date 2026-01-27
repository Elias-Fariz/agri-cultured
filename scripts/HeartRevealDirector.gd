# res://scripts/heart/HeartRevealDirector.gd
extends Node
class_name HeartRevealDirector

signal reveal_started
signal reveal_finished

@export var heart_camera_path: NodePath
@export var visual_controller_path: NodePath
@export var bounds_top_left_path: NodePath
@export var bounds_bottom_right_path: NodePath

# Tuning (cozy defaults)
@export var camera_pan_time := 0.9
@export var camera_hold_time := 0.2
@export var sprout_fade_time := 0.8
@export var sprout_scale_from := 0.85
@export var sprout_scale_time := 0.8
@export var zoom_in := Vector2(0.90, 0.90) # slightly closer
@export var zoom_time := 0.9

# Limit how many reveals per visit (keeps it special)
@export var max_reveals_per_entry := 2

@export var debug_enabled := true

var _heart_camera: Camera2D
var _visual_controller: Node
var _top_left: Marker2D
var _bottom_right: Marker2D

var _cached_previous_camera: Camera2D
var _cached_previous_zoom := Vector2.ONE
var _cached_previous_pos := Vector2.ZERO

var _is_running := false

var _prev_cam_enabled: bool = true

@export var camera_return_time := 0.25
@export var swap_fade_time := 0.12  # optional if you add overlay

@export var cutscene_overlay_path: NodePath
var _overlay: Node = null
var _skip_requested := false

var _camera_tween: Tween = null
var _reveal_tween: Tween = null

var _current_entry: Dictionary = {}
var _current_entry_active := false

var _sfx_player: AudioStreamPlayer
var _swell_player: AudioStreamPlayer

# --- Tier tuning (NEW) -------------------------------------------------------
@export var sprout_zoom_in := Vector2(0.90, 0.90)
@export var root_zoom_in := Vector2(0.82, 0.82) # closer for roots

@export var sprout_hold_time := 0.20
@export var root_hold_time := 0.45

@export var sprout_pan_time := 0.90
@export var root_pan_time := 1.15

@export var sprout_fade_time_override := 0.80
@export var root_fade_time_override := 1.10

@export var sprout_scale_from_override := 0.85
@export var root_scale_from_override := 0.75

@export var sprout_scale_time_override := 0.80
@export var root_scale_time_override := 1.10

# --- Audio (NEW) -------------------------------------------------------------
@export var sprout_reveal_sfx: AudioStream
@export var root_reveal_sfx: AudioStream

# Optional: a soft swell for roots (if you want later)
@export var root_swell_sfx: AudioStream

@export var sfx_bus_name: StringName = &"SFX"

@export var root_post_reveal_linger := 0.35  # cozy pause after the root ping finishes
@export var sfx_poll_interval := 0.03        # how often we check if sound finished

func _ready() -> void:
	_heart_camera = get_node_or_null(heart_camera_path) as Camera2D
	_visual_controller = get_node_or_null(visual_controller_path)
	_top_left = get_node_or_null(bounds_top_left_path) as Marker2D
	_bottom_right = get_node_or_null(bounds_bottom_right_path) as Marker2D

	if debug_enabled:
		print("[HeartRevealDirector] ready heart_cam=", _heart_camera, " vc=", _visual_controller, " bounds=", _top_left, _bottom_right)

	if _heart_camera and _top_left and _bottom_right:
		_apply_camera_bounds(_heart_camera, _top_left.global_position, _bottom_right.global_position)
	
	_overlay = get_node_or_null(cutscene_overlay_path)
	set_process_unhandled_input(true)
	
	set_process(true) # allow _process() to run 
	
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = sfx_bus_name
	add_child(_sfx_player)

	_swell_player = AudioStreamPlayer.new()
	_swell_player.bus = sfx_bus_name
	add_child(_swell_player)

func _process(_delta: float) -> void:
	if not _is_running:
		return
	if Input.is_action_just_pressed("ui_cancel"):
		print("Pressed Escape!")
		_skip_requested = true
		if _overlay and _overlay.has_method("fade_to"):
			print("[HeartRevealDirector] Skip -> calling overlay fade_to(1.0)")
			_overlay.call("fade_to", 1.0, 0.10)
		else:
			print("[HeartRevealDirector] Skip -> NO overlay or fade_to() missing")


func _unhandled_input(event: InputEvent) -> void:
	if not _is_running:
		return
	if event.is_action_pressed("ui_cancel"): # Escape by default
		_skip_requested = true

func run_reveals_if_any() -> void:
	if _is_running:
		return
	if not _heart_camera or not _visual_controller:
		if debug_enabled:
			print("[HeartRevealDirector] No heart camera or visual controller; cannot run.")
		return

	if not _visual_controller.has_method("get_pending_reveals"):
		if debug_enabled:
			print("[HeartRevealDirector] Visual controller missing get_pending_reveals().")
		return

	var pending: Array = _visual_controller.call("get_pending_reveals")
	if pending.is_empty():
		if debug_enabled:
			print("[HeartRevealDirector] No pending reveals.")
		return

	# Lock gameplay (player cannot move)
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("lock_gameplay"):
		gs.call("lock_gameplay")

	_is_running = true
	_skip_requested = false
	reveal_started.emit()
	
	if debug_enabled:
		print("[HeartRevealDirector] Overlay node=", _overlay, " path=", cutscene_overlay_path)
	
	# Optional soft blink during camera handoff
	if _overlay and _overlay.has_method("fade_to"):
		_overlay.call("fade_to", 0.15, swap_fade_time)

	# Cache current camera (player camera) + its pose BEFORE disabling it
	_cached_previous_camera = get_viewport().get_camera_2d()
	if _cached_previous_camera:
		_cached_previous_pos = _cached_previous_camera.global_position
		_cached_previous_zoom = _cached_previous_camera.zoom

		_prev_cam_enabled = _cached_previous_camera.enabled
		_cached_previous_camera.enabled = false

	# Prepare heart camera to start exactly where the player camera was
	_heart_camera.enabled = true
	_heart_camera.global_position = _cached_previous_pos
	_heart_camera.zoom = _cached_previous_zoom

	# Clamp bounds (in case markers moved)
	if _top_left and _bottom_right:
		_apply_camera_bounds(_heart_camera, _top_left.global_position, _bottom_right.global_position)

	# Activate heart camera
	_heart_camera.make_current()
	await get_tree().process_frame

	# Fade back from soft blink
	if _overlay and _overlay.has_method("fade_to"):
		_overlay.call("fade_to", 0.0, swap_fade_time)

	if debug_enabled:
		print("[HeartRevealDirector] HeartCam current? ", get_viewport().get_camera_2d() == _heart_camera,
			" active=", get_viewport().get_camera_2d(), " heart=", _heart_camera)
		print("[HeartRevealDirector] Starting reveals count=", pending.size(), " using=", min(max_reveals_per_entry, pending.size()))

	# Reveal only up to max per entry
	var count: int = min(max_reveals_per_entry, pending.size())

	# IMPORTANT: keep i in outer scope so skip can reveal the rest
	var i: int = 0
	while i < count and not _skip_requested:
		await _reveal_one(pending[i])
		i += 1

	# If skipped: fade to black, apply remaining instantly, fade back
	if _skip_requested:
		_stop_reveal_audio()
		if _overlay and _overlay.has_method("fade_to"):
			_overlay.call("fade_to", 1.0, 0.10)
			await get_tree().create_timer(0.10).timeout

		while i < count:
			_instant_reveal(pending[i])
			i += 1

		# Ensure the currently-in-progress reveal becomes real (no missing sprout)
		if _current_entry_active:
			_instant_reveal(_current_entry)
		
		if _overlay and _overlay.has_method("fade_to"):
			_overlay.call("fade_to", 0.0, 0.18)

	# Smoothly return heart camera back to the player's cached pose (prevents snap)
	await _tween_camera_to(_cached_previous_pos, _cached_previous_zoom, camera_return_time)

	# Restore player camera exactly as it was
	if _cached_previous_camera:
		_cached_previous_camera.enabled = _prev_cam_enabled
		_cached_previous_camera.make_current()

	# Turn off heart camera so it can't compete later
	_heart_camera.enabled = false

	# Unlock gameplay
	var gs2 := get_node_or_null("/root/GameState")
	if gs2 != null and gs2.has_method("unlock_gameplay"):
		gs2.call("unlock_gameplay")

	_is_running = false
	_stop_reveal_audio()
	reveal_finished.emit()

	if debug_enabled:
		print("[HeartRevealDirector] Finished reveals; returned to previous camera.")

func _apply_camera_bounds(cam: Camera2D, tl: Vector2, br: Vector2) -> void:
	# Godot camera limits are in global pixels.
	cam.limit_left = int(min(tl.x, br.x))
	cam.limit_right = int(max(tl.x, br.x))
	cam.limit_top = int(min(tl.y, br.y))
	cam.limit_bottom = int(max(tl.y, br.y))


func _reveal_one(entry: Dictionary) -> void:
	if not entry.has("node") or not entry.has("key"):
		if debug_enabled:
			print("[HeartRevealDirector] Bad pending entry:", entry)
		return

	var target_node: Node = entry["node"]
	var reveal_key: String = entry["key"]

	if not is_instance_valid(target_node):
		_force_complete_entry(entry)
		return

	var tier := _get_entry_tier(entry)

	# Pick tier settings
	var target_zoom := sprout_zoom_in if tier == 0 else root_zoom_in
	var pan_time := sprout_pan_time if tier == 0 else root_pan_time
	var hold_time := sprout_hold_time if tier == 0 else root_hold_time

	var fade_time := sprout_fade_time_override if tier == 0 else root_fade_time_override
	var scale_from := sprout_scale_from_override if tier == 0 else root_scale_from_override
	var scale_time := sprout_scale_time_override if tier == 0 else root_scale_time_override

	# Camera focus
	var focus_pos := _get_focus_position(target_node)
	var clamped_pos := _clamp_camera_target(focus_pos, target_zoom)

	if debug_enabled:
		print("[HeartRevealDirector] Reveal key=", reveal_key, " tier=", tier, " focus=", focus_pos, " clamped=", clamped_pos)

	# Pan + zoom (use override duration)
	await _tween_camera_to(clamped_pos, target_zoom, pan_time)

	if _skip_requested:
		_force_complete_entry(entry)
		return

	# Optional: stronger vignette moment for roots
	# (Requires your overlay to support set_vignette_strength(strength, time))
	if tier != 0 and _overlay and _overlay.has_method("set_vignette_strength"):
		_overlay.call("set_vignette_strength", 0.65, 0.10) # pulse in

	# Hold
	await get_tree().create_timer(hold_time).timeout
	if _skip_requested:
		_force_complete_entry(entry)
		return

	# Audio
	_stop_reveal_audio()

	if tier == 0:
		# Sprout: ping at start of bloom feels fine
		if sprout_reveal_sfx and _sfx_player:
			_sfx_player.stream = sprout_reveal_sfx
			_sfx_player.play()
	else:
		# Root: swell first
		if root_swell_sfx and _swell_player:
			_swell_player.stream = root_swell_sfx
			_swell_player.play()

	# Animate the visual (pass overrides so roots feel weightier)
	await _tween_canvasitem_reveal_tier(target_node, fade_time, scale_from, scale_time)
	
	# After bloom finishes, do the root "reveal ping"
	if tier != 0 and not _skip_requested:
		if root_reveal_sfx and _sfx_player:
			_sfx_player.stream = root_reveal_sfx
			_sfx_player.play()

			# NEW: wait for the ping to finish (skip-safe)
			await _await_sfx_finish_or_skip(_sfx_player)

			# NEW: a tiny linger so accomplishment lands
			if not _skip_requested and root_post_reveal_linger > 0.0:
				await get_tree().create_timer(root_post_reveal_linger).timeout

	# Vignette back to normal
	if tier != 0 and _overlay and _overlay.has_method("set_vignette_strength"):
		_overlay.call("set_vignette_strength", 0.30, 0.18) # pulse out

	if _skip_requested:
		_force_complete_entry(entry)
		return

	# Mark revealed
	if _visual_controller.has_method("mark_reveal_done"):
		_visual_controller.call("mark_reveal_done", reveal_key)
	
func _tween_canvasitem_reveal_tier(n: Node, fade_time: float, scale_from: float, scale_time: float) -> void:
	var item := n as CanvasItem
	if item == null:
		return

	item.visible = true

	var original_modulate := item.modulate
	var original_scale := Vector2.ONE
	var has_scale := false

	if n is Node2D:
		original_scale = (n as Node2D).scale
		has_scale = true

	# Start hidden-ish
	item.modulate = Color(original_modulate.r, original_modulate.g, original_modulate.b, 0.0)
	if has_scale:
		(n as Node2D).scale = original_scale * scale_from

	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_OUT)

	t.tween_property(item, "modulate:a", original_modulate.a, fade_time)
	if has_scale:
		t.parallel().tween_property(n, "scale", original_scale, scale_time)

	await t.finished

func _get_global_pos(n: Node) -> Vector2:
	if n is Node2D:
		return (n as Node2D).global_position
	if n is CanvasItem:
		return (n as CanvasItem).get_global_transform().origin
	return _heart_camera.global_position

func _get_global_pos_precise(n: Node) -> Vector2:
	# Prefer Node2D global_position (most reliable for sprites/markers)
	if n is Node2D:
		return (n as Node2D).global_position

	# Fallback: CanvasItem transform origin
	if n is CanvasItem:
		return (n as CanvasItem).get_global_transform().origin

	return _heart_camera.global_position


func _viewport_half_size_at_zoom(z: Vector2) -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var size := vp.get_visible_rect().size
	# Camera2D zoom: smaller zoom => closer => visible rect in world units shrinks.
	# Half extents in world units = (viewport_px * zoom) / 2
	return (size * z) * 0.5


func _clamp_camera_target(pos: Vector2, target_zoom: Vector2) -> Vector2:
	# Clamp the camera center so the view never goes beyond limits,
	# accounting for viewport half size at the given zoom.
	if _heart_camera == null:
		return pos

	var half := _viewport_half_size_at_zoom(target_zoom)

	var left := float(_heart_camera.limit_left) + half.x
	var right := float(_heart_camera.limit_right) - half.x
	var top := float(_heart_camera.limit_top) + half.y
	var bottom := float(_heart_camera.limit_bottom) - half.y

	# If bounds are too tight for this zoom, fall back to midpoint
	if left > right:
		pos.x = (float(_heart_camera.limit_left) + float(_heart_camera.limit_right)) * 0.5
	else:
		pos.x = clamp(pos.x, left, right)

	if top > bottom:
		pos.y = (float(_heart_camera.limit_top) + float(_heart_camera.limit_bottom)) * 0.5
	else:
		pos.y = clamp(pos.y, top, bottom)

	return pos


func _tween_camera_to(pos: Vector2, target_zoom: Vector2, duration_override: float = -1.0) -> void:
	if not _heart_camera:
		return

	var d := camera_pan_time if duration_override < 0.0 else duration_override

	# Kill any previous camera tween (safe because we won't await its finished)
	if _camera_tween != null and _camera_tween.is_running():
		_camera_tween.kill()
	_camera_tween = null

	_camera_tween = create_tween()
	_camera_tween.set_trans(Tween.TRANS_SINE)
	_camera_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(_heart_camera, "global_position", pos, d)
	_camera_tween.parallel().tween_property(_heart_camera, "zoom", target_zoom, min(d, zoom_time))

	# Instead of: await _camera_tween.finished
	# We poll so skip can break us out cleanly.
	while _camera_tween != null and _camera_tween.is_running():
		if _skip_requested:
			_stop_reveal_audio()
			_camera_tween.kill()
			break
		await get_tree().process_frame

	_camera_tween = null


func _tween_canvasitem_reveal(n: Node) -> void:
	var item := n as CanvasItem
	if item == null:
		return

	item.visible = true

	var original_modulate := item.modulate
	var original_scale := Vector2.ONE
	var has_scale := false

	if n is Node2D:
		original_scale = (n as Node2D).scale
		has_scale = true

	item.modulate = Color(original_modulate.r, original_modulate.g, original_modulate.b, 0.0)
	if has_scale:
		(n as Node2D).scale = original_scale * sprout_scale_from

	# Kill any previous reveal tween (safe because we won't await its finished)
	if _reveal_tween != null and _reveal_tween.is_running():
		_reveal_tween.kill()
	_reveal_tween = null

	_reveal_tween = create_tween()
	_reveal_tween.set_trans(Tween.TRANS_SINE)
	_reveal_tween.set_ease(Tween.EASE_OUT)

	_reveal_tween.tween_property(item, "modulate:a", original_modulate.a, sprout_fade_time)
	if has_scale:
		_reveal_tween.parallel().tween_property(n, "scale", original_scale, sprout_scale_time)

	while _reveal_tween != null and _reveal_tween.is_running():
		if _skip_requested:
			_stop_reveal_audio()
			_reveal_tween.kill()
			break
		await get_tree().process_frame

	_reveal_tween = null

	# If we skipped mid-reveal, snap to fully shown so we don't leave half-alpha
	if _skip_requested:
		_stop_reveal_audio()
		item.modulate = Color(original_modulate.r, original_modulate.g, original_modulate.b, 1.0)
		if has_scale:
			(n as Node2D).scale = original_scale

func _get_focus_position(target_node: Node) -> Vector2:
	# If there's a sibling Marker2D named "<SproutName>Focus", use that.
	# Example: Sprout1 -> Sprout1Focus
	var parent := target_node.get_parent()
	if parent != null:
		var focus_name := "%sFocus" % target_node.name
		var focus := parent.get_node_or_null(focus_name)
		if focus != null and focus is Node2D:
			return (focus as Node2D).global_position

	# Fall back to the node's own position if it's Node2D
	if target_node is Node2D:
		return (target_node as Node2D).global_position

	# Last resort
	return _heart_camera.global_position

func _instant_reveal(entry: Dictionary) -> void:
	if not entry.has("node") or not entry.has("key"):
		return
	var n: Node = entry["node"]
	var k: String = entry["key"]
	if not is_instance_valid(n):
		return

	var item := n as CanvasItem
	if item:
		item.visible = true
		# restore fully visible (no partial alpha)
		var m := item.modulate
		item.modulate = Color(m.r, m.g, m.b, 1.0)

	if _visual_controller and _visual_controller.has_method("mark_reveal_done"):
		_visual_controller.call("mark_reveal_done", k)

func _get_entry_tier(entry: Dictionary) -> int:
	# Default to SPROUT if not provided
	if entry.has("binding") and entry["binding"] != null:
		var b = entry["binding"]
		# Binding is a Resource, so use get() safely
		if b.has_method("get"):
			return int(b.get("reveal_tier"))
	return 0 # HeartVisualBinding.RevealTier.SPROUT

func _stop_reveal_audio() -> void:
	if _sfx_player:
		_sfx_player.stop()
	if _swell_player:
		_swell_player.stop()

func _force_complete_entry(entry: Dictionary) -> void:
	# Ensures the visual exists + is marked revealed, even if we skip mid-cutscene.
	_instant_reveal(entry)
	_stop_reveal_audio()

func _await_sfx_finish_or_skip(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	# Wait until the stream finishes OR skip is requested.
	while is_instance_valid(player) and player.playing and not _skip_requested:
		await get_tree().create_timer(sfx_poll_interval).timeout
