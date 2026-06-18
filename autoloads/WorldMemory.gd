extends Node

signal state_changed(key: String, state: Dictionary)

var _states: Dictionary = {}


func has_state(key: String) -> bool:
	key = key.strip_edges()
	if key == "":
		return false

	return _states.has(key)


func get_state(key: String, default_state: Dictionary = {}) -> Dictionary:
	key = key.strip_edges()
	if key == "":
		return default_state.duplicate(true)

	if not _states.has(key):
		return default_state.duplicate(true)

	var state = _states.get(key, {})
	if state is Dictionary:
		return (state as Dictionary).duplicate(true)

	return default_state.duplicate(true)


func set_state(key: String, state: Dictionary) -> void:
	key = key.strip_edges()
	if key == "":
		return

	_states[key] = state.duplicate(true)
	state_changed.emit(key, get_state(key))


func merge_state(key: String, patch: Dictionary) -> void:
	key = key.strip_edges()
	if key == "":
		return

	var state := get_state(key)

	for k in patch.keys():
		state[k] = patch[k]

	set_state(key, state)


func get_value(key: String, field: String, default_value: Variant = null) -> Variant:
	key = key.strip_edges()
	field = field.strip_edges()

	if key == "" or field == "":
		return default_value

	var state := get_state(key)
	return state.get(field, default_value)


func set_value(key: String, field: String, value: Variant) -> void:
	key = key.strip_edges()
	field = field.strip_edges()

	if key == "" or field == "":
		return

	var state := get_state(key)
	state[field] = value
	set_state(key, state)


func erase_state(key: String) -> void:
	key = key.strip_edges()
	if key == "":
		return

	if _states.has(key):
		_states.erase(key)
		state_changed.emit(key, {})


func clear_all() -> void:
	_states.clear()


func get_save_data() -> Dictionary:
	return _states.duplicate(true)


func load_save_data(data: Dictionary) -> void:
	_states = data.duplicate(true)


func debug_print_all() -> void:
	print("\n=== WorldMemory ===")
	for key in _states.keys():
		print(key, " -> ", _states[key])
	print("===================\n")
