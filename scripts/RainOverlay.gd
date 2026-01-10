extends CanvasLayer

@onready var particles := $GPUParticles2D

func _ready() -> void:
	var wc := get_node_or_null("/root/WeatherChange")
	if wc == null:
		print("RainOverlay: WeatherChange autoload not found at /root/WeatherChange")
		visible = false
		return

	# Connect to weather changes
	if wc.has_signal("weather_changed"):
		wc.weather_changed.connect(_on_weather_changed)

	# Apply immediately based on today's weather
	_apply()

func _on_weather_changed(_new_weather: int) -> void:
	_apply()

func _apply() -> void:
	var wc := get_node_or_null("/root/WeatherChange")
	var raining: bool= (wc != null and wc.is_raining())

	visible = raining
	if particles:
		particles.emitting = raining

	print("RainOverlay apply: raining=", raining, " visible=", visible, " emitting=", particles.emitting if particles else "no particles")
