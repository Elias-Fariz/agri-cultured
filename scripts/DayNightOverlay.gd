extends BaseOverlay

@onready var tint: ColorRect = $Tint

# Day phases (in minutes)
const DAWN_START := 5 * 60
const DAY_START  := 7 * 60
const DUSK_START := 18 * 60
const NIGHT_START:= 20 * 60

func _ready() -> void:
	# Never show in editor (so it doesn't block level editing)
	super._ready()
	if Engine.is_editor_hint():
		return
	_update_tint(TimeManager.minutes)
	TimeManager.time_changed.connect(_update_tint)

	# Enable in gameplay even if it's hidden in the inspector
	tint.visible = true

	# Apply immediately, then update with time
	_update_tint(TimeManager.minutes)
	TimeManager.time_changed.connect(_update_tint)

func _update_tint(minutes: int) -> void:
	var darkness := _compute_darkness(minutes)

	var night_color := Color(0.1, 0.15, 0.25, 1.0)
	tint.color = night_color
	tint.modulate.a = darkness * 0.75

func _compute_darkness(m: int) -> float:
	if m >= DAY_START and m < DUSK_START:
		return 0.0
	if m >= DUSK_START and m < NIGHT_START:
		return float(m - DUSK_START) / float(NIGHT_START - DUSK_START)
	if m >= NIGHT_START or m < DAWN_START:
		return 1.0
	return 1.0 - float(m - DAWN_START) / float(DAY_START - DAWN_START)
