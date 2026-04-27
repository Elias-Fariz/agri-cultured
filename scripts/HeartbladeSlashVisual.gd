extends Node2D
class_name HeartbladeSlashVisual

@export var lifetime: float = 0.12

# Shape
@export var arc_radius: float = 42.0
@export var arc_width: float = 6.0
@export var visible_arc_degrees: float = 52.0
@export var sweep_angle_degrees: float = 100.0
@export var forward_offset: float = 16.0

# Trail
@export var trail_count: int = 3
@export var trail_spacing: float = 0.13

var _age: float = 0.0
var _facing: Vector2 = Vector2.DOWN

func setup(facing: Vector2, p_lifetime: float = 0.12) -> void:
	if facing.length() > 0.01:
		_facing = facing.normalized()

	lifetime = max(0.03, p_lifetime)
	rotation = _facing.angle()
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta
	queue_redraw()

	if _age >= lifetime:
		queue_free()

func _draw() -> void:
	var t := clampf(_age / lifetime, 0.0, 1.0)

	# The node itself is rotated to the facing direction.
	# So local +X is "forward".
	var center := Vector2(forward_offset, 0.0)

	var half_sweep := deg_to_rad(sweep_angle_degrees * 0.5)
	var visible_arc := deg_to_rad(visible_arc_degrees)

	# Sweep from left side to right side over lifetime.
	var main_angle := lerpf(-half_sweep, half_sweep, t)

	for i in range(trail_count):
		var trail_t := clampf(t - float(i) * trail_spacing, 0.0, 1.0)
		var alpha := (1.0 - t) * (1.0 - float(i) * 0.25)

		if alpha <= 0.01:
			continue

		var angle := lerpf(-half_sweep, half_sweep, trail_t)
		var start_angle := angle - visible_arc * 0.5
		var end_angle := angle + visible_arc * 0.5

		var radius := arc_radius + float(i) * 2.0
		var width :Variant= max(2.0, arc_width - float(i) * 1.3)

		var color := Color(0.58, 1.0, 0.76, 0.85 * alpha)
		if i > 0:
			color = Color(0.82, 1.0, 0.88, 0.45 * alpha)

		draw_arc(
			center,
			radius,
			start_angle,
			end_angle,
			22,
			color,
			width,
			true
		)

	# Tiny brighter leading accent so the front of the sweep reads a bit better
	var accent_start := main_angle - visible_arc * 0.20
	var accent_end := main_angle + visible_arc * 0.12
	draw_arc(
		center,
		arc_radius - 2.0,
		accent_start,
		accent_end,
		16,
		Color(0.95, 1.0, 0.92, 0.95 * (1.0 - t)),
		max(2.0, arc_width * 0.45),
		true
	)
