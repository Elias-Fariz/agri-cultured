# HeartVisualController.gd
extends Node

# A single mapping entry: if milestone is completed, show this node.
# Keep this simple and inspector-friendly.
@export var bindings: Array[HeartVisualBinding] = []

@export var debug_enabled: bool = true

var _hp: Node = null


func _ready() -> void:
	_hp = get_node_or_null("/root/HeartProgress")
	if _hp == null:
		push_warning("HeartVisualController: /root/HeartProgress not found.")
		return

	# Initial sync (this is what makes sprites appear even if Heart wasn’t loaded earlier)
	_sync_all("ready")

	# Listen for changes while this scene is open
	if _hp.has_signal("changed"):
		var cb := Callable(self, "_on_heart_changed")
		if not _hp.is_connected("changed", cb):
			_hp.connect("changed", cb)
			if debug_enabled:
				print("[HeartVisualController] Connected to HeartProgress.changed")


func _exit_tree() -> void:
	if _hp != null and _hp.has_signal("changed"):
		var cb := Callable(self, "_on_heart_changed")
		if _hp.is_connected("changed", cb):
			_hp.disconnect("changed", cb)


func _on_heart_changed() -> void:
	_sync_all("changed")


func _sync_all(reason: String) -> void:
	if _hp == null:
		return

	if debug_enabled:
		print("[HeartVisualController] Sync visuals (", reason, ") bindings=", bindings.size())

	for b in bindings:
		if b == null:
			continue
		_apply_binding(b)


func _apply_binding(b: HeartVisualBinding) -> void:
	var node := get_node_or_null(b.node_path)
	if node == null:
		if debug_enabled:
			print("[HeartVisualController] Missing node at path:", b.node_path)
		return

	var should_show := _is_binding_complete(b)

	# Show/Hide logic
	if node is CanvasItem:
		(node as CanvasItem).visible = should_show
	else:
		# Fallback for non-visual nodes
		node.set("visible", should_show)

	if debug_enabled:
		if should_show:
			print("[HeartVisualController] ",
				b.domain_id, "/", b.milestone_id,
				" => SHOW",
				" node=", node.name)
		else:
			print("[HeartVisualController] ",
				b.domain_id, "/", b.milestone_id,
				" => HIDE",
				" node=", node.name)


func _is_binding_complete(b: HeartVisualBinding) -> bool:
	# Preferred: milestone-based (your future-proof path)
	if b.domain_id.strip_edges() != "" and b.milestone_id.strip_edges() != "":
		if _hp.has_method("has_milestone"):
			return bool(_hp.call("has_milestone", b.domain_id, b.milestone_id))

	# Fallback: counter threshold (very handy right now)
	# Example: action_id="harvest", amount_required=1
	if b.action_id.strip_edges() != "" and b.amount_required > 0:
		if _hp.has_method("get_count"):
			var have := int(_hp.call("get_count", b.action_id))
			return have >= b.amount_required

	return false
