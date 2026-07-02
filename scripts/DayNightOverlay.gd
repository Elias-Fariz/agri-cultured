extends BaseOverlay

@onready var tint: ColorRect = $Tint

# Day phases, in minutes.
const DAWN_START := 5 * 60
const DAY_START := 7 * 60

const SUNSET_TRANSITION_START := 16 * 60       # 4:00 PM
const SUNSET_FULL_START := 17 * 60             # 5:00 PM
const SUNSET_HOLD_END := 18 * 60 + 30          # 6:30 PM
const NIGHT_START := 20 * 60                   # 8:00 PM


@export_category("Canvas Modulate Colors")

@export var day_color: Color = Color("#FFFFFF")
@export var dusk_color: Color = Color("#C98768")
@export var night_color: Color = Color("#596783")

@export_range(0.0, 1.0, 0.01)
var night_strength: float = 0.70


@export_category("Legacy Overlay")

# Keep this false while using CanvasModulate.
# Turn it on only if you need to compare with the old rectangle system.
@export var use_legacy_tint: bool = false

@export var legacy_dusk_color: Color = Color("#B86333")
@export var legacy_night_color: Color = Color("#293861")

@export_range(0.0, 1.0, 0.01)
var legacy_maximum_alpha: float = 0.42


func _ready() -> void:
	super._ready()

	if Engine.is_editor_hint():
		return

	# The old ColorRect remains available, but hidden by default.
	tint.visible = use_legacy_tint

	# Apply the correct lighting immediately when the scene starts.
	_update_lighting(TimeManager.minutes)

	if not TimeManager.time_changed.is_connected(_update_lighting):
		TimeManager.time_changed.connect(_update_lighting)


func _update_lighting(minutes: int) -> void:
	var rain_dim := _get_rain_dim()

	if use_legacy_tint:
		_update_legacy_tint_from_time(minutes, rain_dim)
	else:
		_update_canvas_modulate_from_time(minutes, rain_dim)

	_update_fireflies(minutes)

func _update_canvas_modulate_from_time(
	minutes: int,
	rain_dim: float
) -> void:
	var target_color := _get_lighting_color(minutes)

	target_color = Color(
		target_color.r * rain_dim,
		target_color.g * rain_dim,
		target_color.b * rain_dim,
		1.0
	)

	var modulators := get_tree().get_nodes_in_group(
		"day_night_modulate"
	)

	for node in modulators:
		if node is CanvasModulate:
			(node as CanvasModulate).color = target_color

	# Keep the old BaseOverlay ColorRect hidden.
	tint.visible = false

func _update_legacy_tint_from_time(
	minutes: int,
	rain_dim: float
) -> void:
	var base_color := _get_lighting_color(minutes)
	var tint_strength := _get_legacy_tint_strength(minutes)

	tint.visible = true

	tint.color = Color(
		base_color.r * rain_dim,
		base_color.g * rain_dim,
		base_color.b * rain_dim,
		1.0
	)

	tint.modulate = Color(
		1.0,
		1.0,
		1.0,
		tint_strength * legacy_maximum_alpha
	)

func _get_legacy_tint_strength(minutes: int) -> float:
	# Full night before dawn.
	if minutes < DAWN_START:
		return 1.0

	# Gradually remove the tint during dawn.
	if minutes >= DAWN_START and minutes < DAY_START:
		var dawn_t := inverse_lerp(
			float(DAWN_START),
			float(DAY_START),
			float(minutes)
		)

		return 1.0 - _smooth_transition(dawn_t)

	# No legacy tint during full daylight.
	if minutes >= DAY_START and minutes < SUNSET_TRANSITION_START:
		return 0.0

	# Gradually introduce the tint as sunset begins.
	if minutes >= SUNSET_TRANSITION_START and minutes < SUNSET_FULL_START:
		var sunset_t := inverse_lerp(
			float(SUNSET_TRANSITION_START),
			float(SUNSET_FULL_START),
			float(minutes)
		)

		return _smooth_transition(sunset_t)

	# Full tint during sunset hold, night transition, and night.
	return 1.0

func _update_fireflies(minutes: int) -> void:
	var tree := get_tree()
	if tree == null:
		return

	var is_night := (
		minutes >= NIGHT_START
		or minutes < DAWN_START
	)

	for node in tree.get_nodes_in_group("firefly_layer"):
		if node.has_method("set_night_active"):
			node.set_night_active(is_night)


func _get_rain_dim() -> float:
	var wc := get_node_or_null("/root/WeatherChange")

	if wc != null and wc.is_raining():
		return 0.87

	return 1.0


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return

	if TimeManager.time_changed.is_connected(_update_lighting):
		TimeManager.time_changed.disconnect(_update_lighting)

func _get_lighting_color(minutes: int) -> Color:
	var night_target := day_color.lerp(
		night_color,
		night_strength
	)

	# Dawn: slowly return from night to daylight.
	if minutes >= DAWN_START and minutes < DAY_START:
		var dawn_t := inverse_lerp(
			float(DAWN_START),
			float(DAY_START),
			float(minutes)
		)

		return night_target.lerp(
			day_color,
			_smooth_transition(dawn_t)
		)

	# Full daylight.
	if minutes >= DAY_START and minutes < SUNSET_TRANSITION_START:
		return day_color

	# Daylight gradually warms into sunset.
	if minutes >= SUNSET_TRANSITION_START and minutes < SUNSET_FULL_START:
		var sunset_in_t := inverse_lerp(
			float(SUNSET_TRANSITION_START),
			float(SUNSET_FULL_START),
			float(minutes)
		)

		return day_color.lerp(
			dusk_color,
			_smooth_transition(sunset_in_t)
		)

	# Let sunset remain fully visible for a while.
	if minutes >= SUNSET_FULL_START and minutes < SUNSET_HOLD_END:
		return dusk_color

	# Sunset gradually cools into night.
	if minutes >= SUNSET_HOLD_END and minutes < NIGHT_START:
		var night_in_t := inverse_lerp(
			float(SUNSET_HOLD_END),
			float(NIGHT_START),
			float(minutes)
		)

		return dusk_color.lerp(
			night_target,
			_smooth_transition(night_in_t)
		)

	# Full night, including after midnight.
	return night_target
	
func _smooth_transition(value: float) -> float:
	value = clamp(value, 0.0, 1.0)
	return value * value * (3.0 - 2.0 * value)
