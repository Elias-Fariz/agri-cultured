extends AnimatedSprite2D
class_name NPCWalkAnimator

@export var enabled_for_this_npc: bool = false
@export var static_sprite_path: NodePath
@export var move_threshold: float = 0.5
@export var settle_to_idle_delay: float = 0.12

# If your side art is drawn facing LEFT, leave this false.
# If it is drawn facing RIGHT, make this true.
@export var side_art_faces_right: bool = false

var _host: Node2D
var _static_sprite: Sprite2D
var _last_global_position: Vector2
var _last_move_dir: Vector2 = Vector2.DOWN
var _idle_timer: float = 0.0

func _ready() -> void:
	_host = get_parent() as Node2D
	_static_sprite = get_node_or_null(static_sprite_path) as Sprite2D

	if _host != null:
		_last_global_position = _host.global_position

	_refresh_visibility()

func _process(delta: float) -> void:
	if _host == null:
		return

	_refresh_visibility()

	if not enabled_for_this_npc:
		return

	var current_pos := _host.global_position
	var delta_pos := current_pos - _last_global_position
	_last_global_position = current_pos

	if delta_pos.length() > move_threshold:
		_idle_timer = 0.0
		_last_move_dir = _get_dominant_direction(delta_pos)
		_play_walk_for_direction(_last_move_dir)
	else:
		_idle_timer += delta
		if _idle_timer >= settle_to_idle_delay:
			_show_idle()

func _refresh_visibility() -> void:
	if _static_sprite != null:
		_static_sprite.visible = not enabled_for_this_npc

	visible = enabled_for_this_npc

func _get_dominant_direction(v: Vector2) -> Vector2:
	if abs(v.x) > abs(v.y):
		return Vector2.RIGHT if v.x > 0.0 else Vector2.LEFT
	else:
		return Vector2.DOWN if v.y > 0.0 else Vector2.UP

func _play_walk_for_direction(dir: Vector2) -> void:
	if sprite_frames == null:
		return

	if dir == Vector2.LEFT:
		_set_side_flip(false)
		_play_if_needed("walk_side")
	elif dir == Vector2.RIGHT:
		_set_side_flip(true)
		_play_if_needed("walk_side")
	elif dir == Vector2.UP:
		# Temporary fallback until you have real "walk_up" frames
		flip_h = false
		_play_if_needed("walk_down")
	else:
		flip_h = false
		_play_if_needed("walk_down")

func _show_idle() -> void:
	if sprite_frames == null:
		return

	flip_h = false
	if sprite_frames.has_animation("idle_down"):
		if animation != "idle_down":
			play("idle_down")
		frame = 0
		stop()

func _set_side_flip(want_right: bool) -> void:
	if side_art_faces_right:
		flip_h = not want_right
	else:
		flip_h = want_right

func _play_if_needed(anim_name: String) -> void:
	if sprite_frames == null:
		return
	if not sprite_frames.has_animation(anim_name):
		return

	if animation != anim_name or not is_playing():
		play(anim_name)
