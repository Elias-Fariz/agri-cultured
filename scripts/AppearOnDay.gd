extends Node
class_name AppearOnDay

@export var target_path: NodePath = NodePath("..")

@export var appear_day: int = 2
@export var disappear_day: int = -1

@export var hide_before_appear_day: bool = true
@export var hide_on_or_after_disappear_day: bool = false

@export_category("What To Control")

@export var control_visibility: bool = true
@export var control_interaction_enabled: bool = true
@export var control_area_monitoring: bool = true
@export var control_collision_shapes: bool = true
@export var control_processing: bool = false

@export_category("Optional Hint")

@export var hint_node_path: NodePath
@export var hide_hint_after_first_interaction: bool = true
@export var refresh_hint_after_interaction: bool = true

@export_category("Debug")

@export var debug_enabled: bool = false


var _target: Node = null
var _hint_node: Node = null

var _original_area_monitoring: Dictionary = {}
var _original_area_monitorable: Dictionary = {}
var _original_collision_disabled: Dictionary = {}


func _ready() -> void:
	_target = get_node_or_null(target_path)
	_hint_node = get_node_or_null(hint_node_path)

	if refresh_hint_after_interaction and _target != null:
		if _target.has_signal("interacted"):
			var cb := Callable(self, "_on_target_interacted")
			if not _target.is_connected("interacted", cb):
				_target.connect("interacted", cb)

	_cache_original_collision_state()

	if TimeManager != null:
		if not TimeManager.day_changed.is_connected(_on_day_changed):
			TimeManager.day_changed.connect(_on_day_changed)

	_apply_for_current_day()


func _exit_tree() -> void:
	if TimeManager != null:
		if TimeManager.day_changed.is_connected(_on_day_changed):
			TimeManager.day_changed.disconnect(_on_day_changed)


func _on_day_changed(_day: int) -> void:
	_apply_for_current_day()


func _apply_for_current_day() -> void:
	var current_day := 1

	if TimeManager != null:
		current_day = int(TimeManager.day)

	var should_be_available := _should_be_available(current_day)

	if debug_enabled:
		print(
			"[AppearOnDay] ",
			name,
			" target=",
			_target,
			" day=",
			current_day,
			" available=",
			should_be_available
		)

	_set_available(should_be_available)


func _should_be_available(current_day: int) -> bool:
	if hide_before_appear_day and current_day < appear_day:
		return false

	if disappear_day >= 0:
		if hide_on_or_after_disappear_day:
			if current_day >= disappear_day:
				return false
		else:
			if current_day > disappear_day:
				return false

	return true


func _set_available(value: bool) -> void:
	if _target == null or not is_instance_valid(_target):
		return

	if control_visibility and _target is CanvasItem:
		(_target as CanvasItem).visible = value

	if control_interaction_enabled:
		_set_interaction_enabled_safe(_target, value)

	if control_area_monitoring:
		_set_area_monitoring_recursive(_target, value)

	if control_collision_shapes:
		_set_collision_shapes_recursive(_target, value)

	if control_processing:
		_target.set_process(value)
		_target.set_physics_process(value)
		_target.set_process_input(value)
		_target.set_process_unhandled_input(value)

	_update_hint(value)


func _set_interaction_enabled_safe(node: Node, value: bool) -> void:
	if node == null:
		return

	if "interaction_enabled" in node:
		node.set("interaction_enabled", value)

	if node.has_method("set_interaction_enabled"):
		node.call("set_interaction_enabled", value)


func _set_area_monitoring_recursive(node: Node, available: bool) -> void:
	if node is Area2D:
		var area := node as Area2D
		var id := area.get_instance_id()

		if available:
			if _original_area_monitoring.has(id):
				area.monitoring = bool(_original_area_monitoring[id])
			else:
				area.monitoring = true

			if _original_area_monitorable.has(id):
				area.monitorable = bool(_original_area_monitorable[id])
			else:
				area.monitorable = true
		else:
			area.monitoring = false
			area.monitorable = false

	for child in node.get_children():
		_set_area_monitoring_recursive(child, available)


func _set_collision_shapes_recursive(node: Node, available: bool) -> void:
	if node is CollisionShape2D:
		var shape := node as CollisionShape2D
		var id := shape.get_instance_id()

		if available:
			if _original_collision_disabled.has(id):
				shape.disabled = bool(_original_collision_disabled[id])
			else:
				shape.disabled = false
		else:
			shape.disabled = true

	for child in node.get_children():
		_set_collision_shapes_recursive(child, available)


func _cache_original_collision_state() -> void:
	var target := get_node_or_null(target_path)
	if target == null:
		return

	_cache_original_collision_state_recursive(target)


func _cache_original_collision_state_recursive(node: Node) -> void:
	if node is Area2D:
		var area := node as Area2D
		var id := area.get_instance_id()
		_original_area_monitoring[id] = area.monitoring
		_original_area_monitorable[id] = area.monitorable

	if node is CollisionShape2D:
		var shape := node as CollisionShape2D
		var id := shape.get_instance_id()
		_original_collision_disabled[id] = shape.disabled

	for child in node.get_children():
		_cache_original_collision_state_recursive(child)


func _update_hint(available: bool) -> void:
	if _hint_node == null or not is_instance_valid(_hint_node):
		return

	var show_hint := available

	if hide_hint_after_first_interaction:
		show_hint = show_hint and not _has_target_been_used_or_observed()

	if _hint_node is CanvasItem:
		(_hint_node as CanvasItem).visible = show_hint
	else:
		_hint_node.set("visible", show_hint)


func _has_target_been_used_or_observed() -> bool:
	if _target == null:
		return false

	# ObservationInteractable uses WorldMemory observed_count.
	if _target.has_method("get_world_memory") and _target.has_method("get_memory_key"):
		var memory = _target.call("get_world_memory")
		if memory != null and memory.has_method("get_value"):
			var key := String(_target.call("get_memory_key"))
			var observed_count := int(memory.call("get_value", key, "observed_count", 0))
			if observed_count > 0:
				return true

			var interaction_count := int(memory.call("get_value", key, "interaction_count", 0))
			if interaction_count > 0:
				return true

	# Generic interactable object tracking.
	if "interactable_id" in _target:
		var id := String(_target.get("interactable_id")).strip_edges()
		if id != "" and GameState != null and GameState.has_method("has_object_been_interacted"):
			if GameState.has_object_been_interacted(id):
				return true

	return false

func _on_target_interacted(_interactable_id: String = "") -> void:
	# Wait a frame so ObservationInteractable / SmallJoyInteractable
	# have time to write their WorldMemory counts.
	await get_tree().process_frame

	var current_day := 1
	if TimeManager != null:
		current_day = int(TimeManager.day)

	var available := _should_be_available(current_day)
	_update_hint(available)
