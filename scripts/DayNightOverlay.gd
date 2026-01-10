extends BaseOverlay

@onready var tint: ColorRect = $Tint

# Day phases (in minutes)
const DAWN_START := 5 * 60
const DAY_START  := 7 * 60
const DUSK_START := 18 * 60
const NIGHT_START:= 20 * 60

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	tint.visible = true

	# Apply immediately, then update with time
	_update_tint(TimeManager.minutes)
	TimeManager.time_changed.connect(_update_tint)

func _update_tint(minutes: int) -> void:
	var darkness := _compute_darkness(minutes)

	# --- Base colors you can tune later ---
	var day_color := Color(1.0, 1.0, 1.0, 1.0)          # not really used except blending
	var dusk_color := Color(0.95, 0.55, 0.25, 1.0)      # warm orange
	var night_color := Color(0.10, 0.15, 0.25, 1.0)     # cool blue

	# How "dusk-ish" are we? (0..1)
	var dusk_strength := _compute_dusk_strength(minutes)

	# Blend color: at dusk we tint orange, otherwise night blue.
	var base_color := night_color.lerp(dusk_color, dusk_strength)

	# Rain makes everything feel slightly dimmer/overcast
	var rain_dim := _get_rain_dim()
	tint.color = base_color * Color(rain_dim, rain_dim, rain_dim, 1.0)

	# Alpha is still driven by darkness like before
	tint.modulate.a = darkness * 0.75

	_update_fireflies(minutes)

func _compute_darkness(m: int) -> float:
	if m >= DAY_START and m < DUSK_START:
		return 0.0
	if m >= DUSK_START and m < NIGHT_START:
		return float(m - DUSK_START) / float(NIGHT_START - DUSK_START)
	if m >= NIGHT_START or m < DAWN_START:
		return 1.0
	return 1.0 - float(m - DAWN_START) / float(DAY_START - DAWN_START)
	
func _update_fireflies(minutes: int) -> void:
	# If this node is not in a tree (e.g. during scene change), bail out
	var tree := get_tree()
	if tree == null:
		return

	var is_night := (minutes >= NIGHT_START) or (minutes < DAWN_START)

	for node in tree.get_nodes_in_group("firefly_layer"):
		if node.has_method("set_night_active"):
			node.set_night_active(is_night)

func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		if TimeManager.time_changed.is_connected(_update_tint):
			TimeManager.time_changed.disconnect(_update_tint)

func _compute_dusk_strength(m: int) -> float:
	# 0..1 during dusk window, otherwise 0
	# strongest around the middle of dusk.
	if m < DUSK_START or m >= NIGHT_START:
		return 0.0

	var t := float(m - DUSK_START) / float(NIGHT_START - DUSK_START)  # 0..1
	# Make it peak in the middle (soft bell shape)
	# 0 at edges, 1 at mid
	var peak: float = 1.0 - abs(2.0 * t - 1.0)
	return clamp(peak, 0.0, 1.0)

func _get_rain_dim() -> float:
	var wc := get_node_or_null("/root/WeatherChange")
	if wc != null and wc.is_raining():
		return 0.55 # DEBUG intense, change later to 0.85-ish
	return 1.0
