extends BaseOverlay

@onready var time_label: Label = $TopRightPanel/VBoxContainer/TimeLabel
@onready var day_label: Label = $TopRightPanel/VBoxContainer/DayLabel
@onready var energy_label: Label = $TopRightPanel/VBoxContainer/EnergyLabel

@onready var panel := $TopRightPanel
@onready var warning_label: Label = $TopRightPanel/VBoxContainer/WarningLabel

@export var low_energy_threshold_ratio: float = 0.2


func _ready() -> void:
	super._ready()
	_refresh()
	TimeManager.time_changed.connect(func(_m): _refresh())
	TimeManager.day_changed.connect(func(_d): _refresh())


func _process(_delta: float) -> void:
	# Simple approach: update every frame so it always reflects energy changes
	energy_label.text = "Energy: %d/%d" % [GameState.energy, GameState.max_energy]
	
	var ratio := 0.0
	if GameState.max_energy > 0:
		ratio = float(GameState.energy) / float(GameState.max_energy)

	if ratio <= low_energy_threshold_ratio and GameState.energy > 0:
		warning_label.text = "LOW ENERGY"
		warning_label.visible = true
	elif GameState.energy <= 0:
		warning_label.text = "EXHAUSTED"
		warning_label.visible = true
	else:
		warning_label.visible = false


func _refresh() -> void:
	time_label.text = TimeManager.get_time_string()
	day_label.text = "Day %d" % TimeManager.day

func _enable_ui_on_play(node: CanvasItem) -> void:
	if Engine.is_editor_hint():
		node.visible = false
	else:
		node.visible = true
