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



func _ready() -> void:
	_heart_camera = get_node_or_null(heart_camera_path) as Camera2D
	_visual_controller = get_node_or_null(visual_controller_path)
	_top_left = get_node_or_null(bounds_top_left_path) as Marker2D
	_bottom_right = get_node_or_null(bounds_bottom_right_path) as Marker2D

	if debug_enabled:
		print("[HeartRevealDirector] ready heart_cam=", _heart_camera, " vc=", _visual_controller, " bounds=", _top_left, _bottom_right)

	if _heart_camera and _top_left and _bottom_right:
		_apply_camera_bounds(_heart_camera, _top_left.global_position, _bottom_right.global_position)


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

	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("lock_gameplay"):
		gs.call("lock_gameplay")


	_is_running = true
	reveal_started.emit()

	_cached_previous_camera = get_viewport().get_camera_2d()

	if _cached_previous_camera:
		_prev_cam_enabled = _cached_previous_camera.enabled
		_cached_previous_camera.enabled = false


	# Ensure our heart camera starts exactly where the player camera is (no jump)
	_heart_camera.global_position = _cached_previous_pos
	_heart_camera.zoom = _cached_previous_zoom

	# Clamp bounds (in case markers moved)
	if _top_left and _bottom_right:
		_apply_camera_bounds(_heart_camera, _top_left.global_position, _bottom_right.global_position)
	
	_heart_camera.enabled = true
	_heart_camera.make_current()
	await get_tree().process_frame

	if debug_enabled:
		print("[HeartRevealDirector] HeartCam current? ", get_viewport().get_camera_2d() == _heart_camera,
		" active=", get_viewport().get_camera_2d(), " heart=", _heart_camera)

	
	if debug_enabled:
		print("[HeartRevealDirector] HeartCam current? ", get_viewport().get_camera_2d() == _heart_camera,
		" heart_cam_pos=", _heart_camera.global_position,
		" prev_cam_pos=", _cached_previous_pos)
	
	if debug_enabled:
		print("[HeartRevealDirector] Active camera now:", get_viewport().get_camera_2d())

	if debug_enabled:
		print("[HeartRevealDirector] Starting reveals count=", pending.size(), " using=", min(max_reveals_per_entry, pending.size()))

	var count: int = min(max_reveals_per_entry, pending.size())
	for i in range(count):
		await _reveal_one(pending[i])

	# Give control back
	if _cached_previous_camera:
		_cached_previous_camera.make_current()

	var gs2 := get_node_or_null("/root/GameState")
	if gs2 != null and gs2.has_method("unlock_gameplay"):
		gs2.call("unlock_gameplay")

	_is_running = false
	
	# Restore player camera
	if _cached_previous_camera:
		_cached_previous_camera.enabled = _prev_cam_enabled
		_cached_previous_camera.make_current()

	_heart_camera.enabled = false

	
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
		if debug_enabled:
			print("[HeartRevealDirector] Target node invalid; skipping.")
		return
	
	var focus_pos := _get_focus_position(target_node)
	var clamped_pos := _clamp_camera_target(focus_pos, zoom_in)

	if debug_enabled:
		print("[HeartRevealDirector] Reveal key=", reveal_key, " focus=", focus_pos, " clamped=", clamped_pos)

	# Animate camera pan + zoom
	await _tween_camera_to(clamped_pos, zoom_in)

	# Small hold before bloom
	await get_tree().create_timer(camera_hold_time).timeout

	# Animate the sprout itself
	await _tween_canvasitem_reveal(target_node)

	# Mark revealed (this should write to HeartProgress and re-sync visuals)
	if _visual_controller.has_method("mark_reveal_done"):
		_visual_controller.call("mark_reveal_done", reveal_key)


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


func _tween_camera_to(pos: Vector2, target_zoom: Vector2) -> void:
	if not _heart_camera:
		return

	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_IN_OUT)

	t.tween_property(_heart_camera, "global_position", pos, camera_pan_time)
	t.parallel().tween_property(_heart_camera, "zoom", target_zoom, zoom_time)

	await t.finished


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

	# Start hidden-ish
	item.modulate = Color(original_modulate.r, original_modulate.g, original_modulate.b, 0.0)
	if has_scale:
		(n as Node2D).scale = original_scale * sprout_scale_from

	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_OUT)

	t.tween_property(item, "modulate:a", original_modulate.a, sprout_fade_time)
	if has_scale:
		t.parallel().tween_property(n, "scale", original_scale, sprout_scale_time)

	await t.finished

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
