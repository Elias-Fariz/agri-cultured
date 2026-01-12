extends Node

@export var ambience_path: NodePath
@export var life_path: NodePath
@export var life_timer_path: NodePath

@onready var ambience: AudioStreamPlayer2D = get_node(ambience_path) as AudioStreamPlayer2D
@onready var life: AudioStreamPlayer2D = get_node(life_path) as AudioStreamPlayer2D
@onready var life_timer: Timer = get_node(life_timer_path) as Timer

@export var town_birds: Array[AudioStream] = []
@export var town_leaves: Array[AudioStream] = []
@export var town_murmurs: Array[AudioStream] = []   # optional: soft crowd “murmur” clips

@export var life_interval_min: float = 10.0
@export var life_interval_max: float = 30.0

func _ready() -> void:
	# Start ambience (if not autoplay)
	if ambience and not ambience.playing:
		ambience.play()

	life_timer.timeout.connect(_on_life_timer_timeout)
	_schedule_next_life()

func _schedule_next_life() -> void:
	life_timer.wait_time = randf_range(life_interval_min, life_interval_max)
	life_timer.start()

func _on_life_timer_timeout() -> void:
	var pool: Array[AudioStream] = []
	pool.append_array(town_birds)
	pool.append_array(town_leaves)
	pool.append_array(town_murmurs)

	if pool.is_empty():
		_schedule_next_life()
		return

	var s: AudioStream = pool[randi() % pool.size()]
	if s == null:
		_schedule_next_life()
		return

	life.stream = s
	life.pitch_scale = randf_range(0.95, 1.05)
	life.volume_db = randf_range(-18.0, -12.0)
	life.play()

	_schedule_next_life()
