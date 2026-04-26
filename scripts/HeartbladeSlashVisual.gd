extends Node2D
class_name HeartbladeSlashVisual

@export var lifetime: float = 0.14
@export var arc_radius: float = 42.0
@export var arc_width: float = 6.0
@export var arc_angle_degrees: float = 105.0

var _age: float = 0.0
var _facing: Vector2 = Vector2.DOWN

func setup(facing: Vector2, p_lifetime: float = 0.14) -> void:
	if facing.length() > 0.01:
		_facing = facing.normalized()
	lifetime = max(0.03, p_lifetime)

	rotation = _facing.angle()
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta

	var t := clampf(_age / lifetime, 0.0, 1.0)
	modulate.a = 1.0 - t

	scale = Vector2.ONE * lerpf(0.85, 1.12, t)

	queue_redraw()

	if _age >= lifetime:
		queue_free()

func _draw() -> void:
	var half_angle := deg_to_rad(arc_angle_degrees * 0.5)

	# Draw arc in front of the facing direction.
	# Because the node itself is rotated to facing, this local arc sits forward.
	var start_angle := -half_angle
	var end_angle := half_angle

	draw_arc(
		Vector2.ZERO,
		arc_radius,
		start_angle,
		end_angle,
		28,
		Color(0.55, 1.0, 0.72, 0.85),
		arc_width,
		true
	)

	draw_arc(
		Vector2.ZERO,
		arc_radius * 0.72,
		start_angle * 0.8,
		end_angle * 0.8,
		20,
		Color(0.9, 1.0, 0.85, 0.55),
		max(2.0, arc_width * 0.45),
		true
	)
