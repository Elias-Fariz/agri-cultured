extends Area2D
class_name RestorationDangerZone

signal player_hit(resolve_damage: int)

enum ZoneShape {
	CIRCLE,
	LINE
}

@export var zone_shape: ZoneShape = ZoneShape.CIRCLE
@export var warning_seconds: float = 0.8
@export var active_seconds: float = 0.35
@export var resolve_damage: int = 1

@export var radius: float = 48.0
@export var line_length: float = 160.0
@export var line_width: float = 32.0

# Player is on collision layer 2, so this mask detects layer 2.
const PLAYER_LAYER_MASK := 1 << 1

var _collision_shape: CollisionShape2D
var _is_active: bool = false
var _has_hit_player: bool = false

func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = PLAYER_LAYER_MASK

	z_index = 100

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	_ensure_collision_shape()
	_update_shape()
	queue_redraw()

func configure_circle(
	p_position: Vector2,
	p_radius: float,
	p_warning_seconds: float,
	p_active_seconds: float,
	p_resolve_damage: int
) -> void:
	global_position = p_position
	zone_shape = ZoneShape.CIRCLE
	radius = p_radius
	warning_seconds = p_warning_seconds
	active_seconds = p_active_seconds
	resolve_damage = p_resolve_damage

	_ensure_collision_shape()
	_update_shape()
	queue_redraw()

func configure_line(
	p_position: Vector2,
	p_rotation: float,
	p_length: float,
	p_width: float,
	p_warning_seconds: float,
	p_active_seconds: float,
	p_resolve_damage: int
) -> void:
	global_position = p_position
	rotation = p_rotation
	zone_shape = ZoneShape.LINE
	line_length = p_length
	line_width = p_width
	warning_seconds = p_warning_seconds
	active_seconds = p_active_seconds
	resolve_damage = p_resolve_damage

	_ensure_collision_shape()
	_update_shape()
	queue_redraw()

func begin() -> void:
	_is_active = false
	_has_hit_player = false
	queue_redraw()

	await get_tree().create_timer(max(0.05, warning_seconds)).timeout

	_is_active = true
	queue_redraw()

	_check_existing_overlaps()

	await get_tree().create_timer(max(0.05, active_seconds)).timeout

	queue_free()

func _ensure_collision_shape() -> void:
	if _collision_shape != null:
		return

	_collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _collision_shape == null:
		_collision_shape = CollisionShape2D.new()
		_collision_shape.name = "CollisionShape2D"
		add_child(_collision_shape)

func _update_shape() -> void:
	if _collision_shape == null:
		return

	match zone_shape:
		ZoneShape.CIRCLE:
			var circle := CircleShape2D.new()
			circle.radius = max(4.0, radius)
			_collision_shape.shape = circle

		ZoneShape.LINE:
			var rect := RectangleShape2D.new()
			rect.size = Vector2(max(8.0, line_length), max(4.0, line_width))
			_collision_shape.shape = rect

func _on_body_entered(body: Node) -> void:
	if not _is_active:
		return
	_try_hit_body(body)

func _check_existing_overlaps() -> void:
	if not _is_active:
		return

	for body in get_overlapping_bodies():
		_try_hit_body(body)

func _try_hit_body(body: Node) -> void:
	if _has_hit_player:
		return

	if body == null:
		return

	if not body.is_in_group("player"):
		return

	_has_hit_player = true
	player_hit.emit(resolve_damage)

func _draw() -> void:
	if zone_shape == ZoneShape.CIRCLE:
		if _is_active:
			draw_circle(Vector2.ZERO, radius, Color(1.0, 0.12, 0.18, 0.55))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(1.0, 0.85, 0.85, 0.95), 3.0)
		else:
			draw_circle(Vector2.ZERO, radius, Color(0.2, 1.0, 0.65, 0.32))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.75, 1.0, 0.85, 0.9), 2.0)

	elif zone_shape == ZoneShape.LINE:
		var rect := Rect2(
			Vector2(-line_length * 0.5, -line_width * 0.5),
			Vector2(line_length, line_width)
		)

		if _is_active:
			draw_rect(rect, Color(1.0, 0.12, 0.18, 0.50), true)
			draw_rect(rect, Color(1.0, 0.85, 0.85, 0.95), false, 3.0)
		else:
			draw_rect(rect, Color(0.2, 1.0, 0.65, 0.28), true)
			draw_rect(rect, Color(0.75, 1.0, 0.85, 0.85), false, 2.0)
