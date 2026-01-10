extends Node
class_name WeatherManager

enum WeatherType { CLEAR, RAIN }

@export_range(0.0, 1.0, 0.01) var rain_chance: float = 0.25

var yesterday_weather: int = WeatherType.CLEAR
var today_weather: WeatherType = WeatherType.CLEAR

signal weather_changed(new_weather: int)

func roll_new_day_weather() -> void:
	# Move today -> yesterday BEFORE rolling new
	yesterday_weather = today_weather
	# Now roll today's weather
	today_weather = WeatherType.RAIN if randf() < rain_chance else WeatherType.CLEAR
	emit_signal("weather_changed", int(today_weather))

func is_raining() -> bool:
	return today_weather == WeatherType.RAIN

func get_weather_name() -> String:
	return "RAIN" if is_raining() else "CLEAR"

func was_raining_yesterday() -> bool:
	return yesterday_weather == WeatherType.RAIN
