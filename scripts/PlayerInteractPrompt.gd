extends Node

@export var sense_area_path: NodePath
@export var prompt_label_path: NodePath
@export var prompt_anchor_path: NodePath

# Optional: if your Player exposes a facing vector, set this to a method name like "get_facing_dir"
@export var player_facing_method: StringName = &""

# Tuning
@export var max_show_distance: float = 64.0
@export var require_in_front: bool = true
@export var front_dot_threshold: float = 0.2
@export var update_interval: float = 0.05

# Debug
@export var debug_enabled: bool = false

var _sense_area: Area2D
var _label: Label
var _anchor: CanvasItem

var _nearby: Array[Node] = []
var _t_accum := 0.0

func _ready() -> void:
	_sense_area = get_node_or_null(sense_area_path) as Area2D
	_label = get_node_or_null(prompt_label_path) as Label
	_anchor = get_node_or_null(prompt_anchor_path) as CanvasItem
	
	print("[Prompt] label path=", prompt_label_path, " found=", _label)
	if _label:
		print("[Prompt] label node path=", _label.get_path())
		print("[Prompt] label initial text=", _label.text)
		print("[Prompt] label visible=", _label.visible)

	if debug_enabled:
		print("[Prompt] ready. sense_area=", _sense_area, " label=", _label, " anchor=", _anchor)

	if _sense_area:
		# Ensure monitoring is on
		_sense_area.monitoring = true
		_sense_area.monitorable = true

		_sense_area.area_entered.connect(_on_area_entered)
		_sense_area.area_exited.connect(_on_area_exited)
		_sense_area.body_entered.connect(_on_body_entered)
		_sense_area.body_exited.connect(_on_body_exited)

	_hide()

func _process(delta: float) -> void:
	_t_accum += delta
	if _t_accum < update_interval:
		return
	_t_accum = 0.0

	# If gameplay locked (modal overlay/dialogue), hide prompt.
	if _is_gameplay_locked():
		_hide()
		return

	var best := _pick_best_target()
	if best == null:
		_hide()
		return

	# Respect target gate
	var can_now := true
	if best.has_method("can_player_interact"):
		can_now = bool(best.call("can_player_interact", get_parent()))

	# Get prompt text
	var text := ""
	if best.has_method("get_interact_prompt"):
		text = str(best.call("get_interact_prompt", get_parent()))
	else:
		text = "E: Interact"

	if text.strip_edges() == "":
		_hide()
		return

	_show(text)

func _on_area_entered(a: Area2D) -> void:
	_try_add(a)

func _on_area_exited(a: Area2D) -> void:
	_nearby.erase(a)

func _on_body_entered(b: Node) -> void:
	_try_add(b)

func _on_body_exited(b: Node) -> void:
	_nearby.erase(b)

func _try_add(n: Node) -> void:
	if n == null:
		return
	if _nearby.has(n):
		return

	# Prefer explicit group, but also allow method-based detection
	if n.is_in_group("interactables") or n.has_method("interact") or n.has_method("get_interact_prompt"):
		_nearby.append(n)
		if debug_enabled:
			print("[Prompt] added nearby:", n.name, " type=", n.get_class())

func _pick_best_target() -> Node:
	var player := get_parent() as Node2D
	if player == null:
		return null

	var player_pos := player.global_position
	var facing := _get_player_facing(player)

	# Clean invalid references
	for i in range(_nearby.size() - 1, -1, -1):
		if not is_instance_valid(_nearby[i]):
			_nearby.remove_at(i)

	var best: Node = null
	var best_score := -INF

	for n in _nearby:
		if not (n is Node2D):
			continue
		var target := n as Node2D
		var to_target := target.global_position - player_pos
		var dist := to_target.length()
		if dist > max_show_distance:
			continue

		var dir := to_target.normalized()

		var dot := facing.dot(dir)
		if require_in_front and dot < front_dot_threshold:
			continue

		# closer + more in front
		var score := (dot * 2.0) - (dist / max_show_distance)

		if n.has_method("get_interact_priority"):
			score += float(n.call("get_interact_priority")) * 0.5

		if score > best_score:
			best_score = score
			best = n

	if debug_enabled and best != null:
		print("[Prompt] best target:", best.name)

	return best

func _get_player_facing(player: Node) -> Vector2:
	# Fallback: assume facing down
	return player.facing

func _is_gameplay_locked() -> bool:
	# Robust autoload lookup:
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("is_gameplay_locked"):
		return bool(gs.call("is_gameplay_locked"))

	# Optional dialogue visibility check
	var dialogue_ui := get_tree().get_first_node_in_group("dialogue_ui")
	if dialogue_ui and (dialogue_ui is CanvasItem) and (dialogue_ui as CanvasItem).visible:
		return true

	return false

func _show(text: String) -> void:
	if _label == null:
		return
	_label.text = text
	_label.visible = true
	if _anchor:
		_anchor.visible = true

func _hide() -> void:
	if _label:
		_label.visible = false
	if _anchor:
		_anchor.visible = false

func get_best_target() -> Node:
	return _pick_best_target()
