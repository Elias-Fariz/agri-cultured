# res://scripts/ui/CinematicUIHider.gd
extends Node
class_name CinematicUIHider

@export var hide_group_name: StringName = &"cutscene_hide_ui"
@export var debug_enabled: bool = false

var _hide_depth: int = 0

# Each entry:
# {
#   "node": CanvasItem,
#   "visible": bool
# }
var _saved_targets: Array[Dictionary] = []
var _saved_instance_ids: Dictionary = {}


func hide_cinematic_ui() -> void:
	_hide_depth += 1

	# If another cinematic already hid the UI, don't overwrite original visibility.
	if _hide_depth > 1:
		return

	_saved_targets.clear()
	_saved_instance_ids.clear()

	var grouped_nodes := get_tree().get_nodes_in_group(hide_group_name)

	if debug_enabled:
		print("[CinematicUIHider] Group nodes found: ", grouped_nodes.size())

	for n in grouped_nodes:
		if n == null or not is_instance_valid(n):
			continue

		var targets := _get_hide_targets_for_node(n)

		if debug_enabled:
			print("[CinematicUIHider] node=", n.name, " class=", n.get_class(), " targets=", targets.size())

		for item in targets:
			_save_and_hide_item(item)


func show_cinematic_ui() -> void:
	if _hide_depth <= 0:
		return

	_hide_depth -= 1

	# Still hidden by another cinematic.
	if _hide_depth > 0:
		return

	if debug_enabled:
		print("[CinematicUIHider] Restoring targets: ", _saved_targets.size())

	for entry in _saved_targets:
		var item := entry.get("node", null) as CanvasItem
		if item == null or not is_instance_valid(item):
			continue

		item.visible = bool(entry.get("visible", true))

		if debug_enabled:
			print("[CinematicUIHider] restore ", item.get_path(), " visible=", item.visible)

	_saved_targets.clear()
	_saved_instance_ids.clear()


func force_show_cinematic_ui() -> void:
	_hide_depth = 1
	show_cinematic_ui()


func _save_and_hide_item(item: CanvasItem) -> void:
	if item == null or not is_instance_valid(item):
		return

	var id := item.get_instance_id()
	if _saved_instance_ids.has(id):
		return

	_saved_instance_ids[id] = true
	_saved_targets.append({
		"node": item,
		"visible": item.visible
	})

	item.visible = false

	if debug_enabled:
		print("[CinematicUIHider] hide target=", item.get_path())


func _get_hide_targets_for_node(n: Node) -> Array[CanvasItem]:
	var targets: Array[CanvasItem] = []

	# Case 1:
	# The grouped node itself is visible, such as a Control, TextureRect, Panel, etc.
	if n is CanvasItem:
		targets.append(n as CanvasItem)
		return targets

	# Case 2:
	# The grouped node is a BaseOverlay / CanvasLayer with a visual_node_path.
	# We hide the configured visual node instead of calling hide_overlay(),
	# so BaseOverlay's internal open/closed state is preserved.
	if n.has_method("get"):
		var visual_path = n.get("visual_node_path")
		if typeof(visual_path) == TYPE_NODE_PATH and visual_path != NodePath(""):
			var visual_node := n.get_node_or_null(visual_path)
			if visual_node != null and visual_node is CanvasItem:
				targets.append(visual_node as CanvasItem)
				return targets

	# Case 3:
	# The grouped node is probably a CanvasLayer or plain Node.
	# Hide its first CanvasItem children/direct visual contents.
	for child in n.get_children():
		if child is CanvasItem:
			targets.append(child as CanvasItem)

	# Case 4:
	# If no direct CanvasItem children were found, search a little deeper.
	# This protects UI scenes whose visible Control is nested under another Node.
	if targets.is_empty():
		_collect_canvasitem_descendants(n, targets)

	return targets


func _collect_canvasitem_descendants(n: Node, out: Array[CanvasItem]) -> void:
	for child in n.get_children():
		if child is CanvasItem:
			out.append(child as CanvasItem)
			continue

		_collect_canvasitem_descendants(child, out)
