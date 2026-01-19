extends Node
class_name AreaAudio

# --- NodePaths to scene-local audio nodes ---
@export var ambience_path: NodePath
@export var life_path: NodePath
@export var life_timer_path: NodePath

@onready var ambience: AudioStreamPlayer2D = get_node_or_null(ambience_path) as AudioStreamPlayer2D
@onready var life: AudioStreamPlayer2D = get_node_or_null(life_path) as AudioStreamPlayer2D
@onready var life_timer: Timer = get_node_or_null(life_timer_path) as Timer

# --- Generic "life" pools (use any you want, leave others empty) ---
@export var life_pool_a: Array[AudioStream] = []
@export var life_pool_b: Array[AudioStream] = []
@export var life_pool_c: Array[AudioStream] = []
@export var life_pool_d: Array[AudioStream] = []

# --- Timing ---
@export var life_interval_min: float = 10.0
@export var life_interval_max: float = 30.0

# --- Variation (keep subtle; can tune per area) ---
@export var pitch_min: float = 0.95
@export var pitch_max: float = 1.05
@export var volume_min_db: float = -18.0
@export var volume_max_db: float = -12.0

# Optional: chance to play a life sound at each timer tick
@export_range(0.0, 1.0, 0.01) var life_play_chance: float = 1.0


func _ready() -> void:
	# Start ambience (if present)
	if ambience != null and not ambience.playing:
		ambience.play()

	# Timer hookup
	if life_timer != null:
		if not life_timer.timeout.is_connected(_on_life_timer_timeout):
			life_timer.timeout.connect(_on_life_timer_timeout)
		_schedule_next_life()


func _schedule_next_life() -> void:
	if life_timer == null:
		return
	life_timer.wait_time = randf_range(life_interval_min, life_interval_max)
	life_timer.start()


func _on_life_timer_timeout() -> void:
	# If we only want occasional "life", roll chance
	if randf() > life_play_chance:
		_schedule_next_life()
		return

	var pool: Array[AudioStream] = []
	pool.append_array(life_pool_a)
	pool.append_array(life_pool_b)
	pool.append_array(life_pool_c)
	pool.append_array(life_pool_d)

	if pool.is_empty() or life == null:
		_schedule_next_life()
		return

	var s: AudioStream = pool[randi() % pool.size()]
	if s == null:
		_schedule_next_life()
		return

	life.stream = s
	life.pitch_scale = randf_range(pitch_min, pitch_max)
	life.volume_db = randf_range(volume_min_db, volume_max_db)
	life.play()

	_schedule_next_life()
