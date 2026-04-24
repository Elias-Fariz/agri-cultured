extends Node2D
class_name PulseVisual

@export var glow_path: NodePath = NodePath("Glow")

@export var pulse_period_seconds: float = 1.6
@export var pulse_offset: float = 0.0

@export var min_scale: float = 0.55
@export var max_scale: float = 1.25

@export var min_alpha: float = 0.35
@export var max_alpha: float = 1.0

@export var draw_above_node: bool = true

@onready var glow: Sprite2D = get_node_or_null(glow_path) as Sprite2D

func _ready() -> void:
	if draw_above_node:
		z_index = 10

func setup(period_seconds: float, offset: float) -> void:
	pulse_period_seconds = max(0.2, period_seconds)
	pulse_offset = offset

func _process(_delta: float) -> void:
	if glow == null:
		return

	var period :Variant= max(0.2, pulse_period_seconds)
	var now := Time.get_ticks_msec() / 1000.0

	# Phase goes 0.0 -> 1.0 repeatedly.
	var phase := fmod((now / period) + pulse_offset, 1.0)

	# Brightness peaks at phase 0.5.
	# This matches the mining success check.
	var brightness := 0.5 - 0.5 * cos(phase * TAU)

	var s := lerpf(min_scale, max_scale, brightness)
	glow.scale = Vector2(s, s)

	var c := glow.modulate
	c.a = lerpf(min_alpha, max_alpha, brightness)
	glow.modulate = c
