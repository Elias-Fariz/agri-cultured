extends Node
class_name RestorationCombatController

@export var input_action: String = "restore_attack"

# Slash placement
@export var slash_distance: float = 32.0
@export var slash_length: float = 72.0
@export var slash_width: float = 52.0
@export var slash_lifetime: float = 0.12

# Debug / temporary visual
@export var show_slash_visual: bool = true
@export var show_debug_toasts: bool = true
@export var print_debug: bool = true

# DisturbanceCore is placed on layer 6 in DisturbanceCore.gd.
const RESTORATION_CORE_LAYER_MASK := 1 << 5

var _player: Node2D
var _can_attack: bool = true

@export var slash_visual_scene: PackedScene

func _ready() -> void:
	_player = get_parent() as Node2D
	if _player == null:
		push_warning("RestorationCombatController should be attached under the Player node.")

func _process(_delta: float) -> void:
	if _player == null:
		return

	if not Input.is_action_just_pressed(input_action):
		return

	_try_restore_attack()

func _try_restore_attack() -> void:
	if not _can_attack:
		return

	if not _is_restoration_combat_active():
		if print_debug:
			print("[Heartblade] restore_attack pressed, but no restoration encounter is active.")
		return

	_can_attack = false

	var hit_success := _perform_restore_query()

	await get_tree().create_timer(0.22).timeout
	_can_attack = true

	if print_debug:
		print("[Heartblade] attack complete. success=", hit_success)

func _perform_restore_query() -> bool:
	var facing := _get_player_facing()
	if facing == Vector2.ZERO:
		facing = Vector2.DOWN

	facing = facing.normalized()

	var slash_center := _player.global_position + facing * slash_distance
	var slash_rotation := 0.0

	var shape := RectangleShape2D.new()

	if abs(facing.x) > abs(facing.y):
		shape.size = Vector2(slash_length, slash_width)
		slash_rotation = 0.0
	else:
		shape.size = Vector2(slash_width, slash_length)
		slash_rotation = 0.0

	# Visual is separate from query, so you can see where the slash happened.
	if show_slash_visual:
		_spawn_slash_visual(slash_center, shape.size, slash_lifetime)

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(slash_rotation, slash_center)
	query.collision_mask = RESTORATION_CORE_LAYER_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var space_state := _player.get_world_2d().direct_space_state
	var results := space_state.intersect_shape(query, 16)

	if print_debug:
		print("[Heartblade] query results=", results.size(), " center=", slash_center, " size=", shape.size)

	var found_core := false

	for result in results:
		var collider = result.get("collider")
		if collider == null:
			continue

		if print_debug:
			print("[Heartblade] hit collider=", collider.name)

		if collider.has_method("receive_restoration_strike"):
			found_core = true
			var success := bool(collider.call("receive_restoration_strike"))

			if success:
				_debug_toast("The Heartblade reaches the core.", "success", 0.8)
				return true
			else:
				_debug_toast("The core is not open yet.", "info", 0.8)

	if not found_core:
		_debug_toast("The Heartblade finds no opening.", "info", 0.8)

	return false

func _spawn_slash_visual(center: Vector2, size: Vector2, lifetime: float) -> void:
	var facing := _get_player_facing()

	if slash_visual_scene != null:
		var v := slash_visual_scene.instantiate()
		var scene := get_tree().current_scene
		if scene != null:
			scene.add_child(v)
		else:
			add_child(v)

		if v is Node2D:
			(v as Node2D).global_position = center
			(v as Node2D).z_index = 200

		if v.has_method("setup"):
			v.call("setup", facing, lifetime)

		return

	# Fallback debug rectangle if no visual scene is assigned.
	var visual := ColorRect.new()
	visual.name = "HeartbladeSlashVisual"
	visual.color = Color(0.5, 1.0, 0.7, 0.35)
	visual.size = size
	visual.position = -size * 0.5
	visual.global_position = center
	visual.z_index = 200

	var scene2 := get_tree().current_scene
	if scene2 != null:
		scene2.add_child(visual)
	else:
		add_child(visual)

	await get_tree().create_timer(max(0.03, lifetime)).timeout

	if is_instance_valid(visual):
		visual.queue_free()

func _get_player_facing() -> Vector2:
	if _player == null:
		return Vector2.DOWN

	if "facing" in _player:
		var f: Vector2 = _player.facing
		if f.length() > 0.01:
			return f.normalized()

	return Vector2.DOWN

func _is_restoration_combat_active() -> bool:
	var tree := get_tree()
	if tree == null:
		return false

	for n in tree.get_nodes_in_group("restoration_encounter"):
		if n != null and n.has_method("is_encounter_active"):
			if bool(n.call("is_encounter_active")):
				return true

	return false

func _debug_toast(msg: String, kind: String = "info", duration: float = 1.0) -> void:
	if not show_debug_toasts:
		return

	if QuestEvents != null and QuestEvents.has_signal("toast_requested"):
		QuestEvents.toast_requested.emit(msg, kind, duration)
