extends BaseOverlay

@onready var time_label: Label = $TopRightPanel/VBoxContainer/TimeLabel
@onready var day_label: Label = $TopRightPanel/VBoxContainer/DayLabel
@onready var energy_label: Label = $TopRightPanel/VBoxContainer/EnergyLabel

@onready var panel := $TopRightPanel
@onready var warning_label: Label = $TopRightPanel/VBoxContainer/WarningLabel

@export var low_energy_threshold_ratio: float = 0.2

@onready var tool_label: Label = $TopRightPanel/VBoxContainer/ToolLabel
@onready var money_label: Label = $TopRightPanel/VBoxContainer/MoneyLabel


func _ready() -> void:
	super._ready()
	_refresh()
	TimeManager.time_changed.connect(func(_m): _refresh())
	TimeManager.day_changed.connect(func(_d): _refresh())
	_update_money_label(MoneySystem.current_money)
	MoneySystem.money_changed.connect(_update_money_label)


func _process(_delta: float) -> void:
	# Simple approach: update every frame so it always reflects energy changes
	energy_label.text = "Energy: %d/%d" % [GameState.energy, GameState.max_energy]
	tool_label.text = "Tool: %s" % GameState.get_tool_name()
	
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

func _update_money_label(amount: int) -> void:
	money_label.text = "Gold: %d" % amount

func _refresh() -> void:
	time_label.text = TimeManager.get_time_string()
	day_label.text = "Day %d" % TimeManager.day

func _enable_ui_on_play(node: CanvasItem) -> void:
	if Engine.is_editor_hint():
		node.visible = false
	else:
		node.visible = true
