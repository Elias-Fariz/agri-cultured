# HeartVisualController.gd
extends Node

@export var bindings: Array[HeartVisualBinding] = []
@export var debug_enabled: bool = true

var _pending_reveals: Array = []
var _hp: Node = null


func _ready() -> void:
	_hp = get_node_or_null("/root/HeartProgress")
	if _hp == null:
		push_warning("HeartVisualController: /root/HeartProgress not found.")
		return

	_sync_all("ready")

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

	_pending_reveals.clear()

	if debug_enabled:
		print("[HeartVisualController] Sync visuals (", reason, ") bindings=", bindings.size())

	for b in bindings:
		if b == null:
			continue
		_apply_binding(b)

	if debug_enabled:
		print("[HeartVisualController] Pending reveals=", _pending_reveals.size())


func _apply_binding(b: HeartVisualBinding) -> void:
	var node := get_node_or_null(b.node_path)
	if node == null:
		if debug_enabled:
			print("[HeartVisualController] Missing node at path:", b.node_path)
		return

	var unlocked := _is_binding_complete(b)
	if not unlocked:
		_set_visible(node, false)
		return

	# ----- Stable identity -----
	# Now that you're definition-driven, we expect these to be set.
	var domain_id := b.domain_id.strip_edges()
	var milestone_id := b.milestone_id.strip_edges()

	# Still keep your synthetic fallback (useful during early prototyping)
	if domain_id == "":
		domain_id = "misc"

	if milestone_id == "":
		var a := b.action_id.strip_edges()
		var req := int(b.amount_required)
		milestone_id = "counter:%s:%d:%s" % [a, req, str(b.node_path)]

	var reveal_key := "%s:%s" % [domain_id, milestone_id]

	# ----- Reveal gating -----
	var is_revealed := false
	if _hp != null and _hp.has_method("is_revealed"):
		is_revealed = bool(_hp.call("is_revealed", domain_id, milestone_id))
	else:
		# If reveal API is missing, fail open (show)
		is_revealed = true

	# ----- Pull cinematic "kind" from heart_definition via HeartProgress -----
	# This is the important part: sprout vs root comes from the definition,
	# NOT from the binding and NOT from any hardcoded tiers.
	var kind := "sprout"
	if _hp != null and _hp.has_method("get_milestone_kind"):
		kind = str(_hp.call("get_milestone_kind", domain_id, milestone_id)).strip_edges()
		if kind == "":
			kind = "sprout"

	if is_revealed:
		_set_visible(node, true)
		if debug_enabled:
			print("[HeartVisualController] SHOW (revealed) ", reveal_key, " kind=", kind, " node=", node.name)
	else:
		_set_visible(node, false)
		_pending_reveals.append({
			"node": node,
			"key": reveal_key,
			"binding": b,
			"kind": kind,          # ✅ Director can now branch on this
			"domain_id": domain_id,
			"milestone_id": milestone_id
		})
		if debug_enabled:
			print("[HeartVisualController] QUEUE REVEAL ", reveal_key, " kind=", kind, " node=", node.name)

	if debug_enabled:
		print("[HVC DBG] ", domain_id, "/", milestone_id,
			" unlocked=", unlocked,
			" revealed=", is_revealed,
			" kind=", kind,
			" action_id=", b.action_id,
			" stat_key=", b.stat_key,
			" req=", b.amount_required)

func _is_binding_complete(b: HeartVisualBinding) -> bool:
	# Option A: milestone-based
	if b.domain_id.strip_edges() != "" and b.milestone_id.strip_edges() != "":
		if _hp.has_method("has_milestone"):
			return bool(_hp.call("has_milestone", b.domain_id, b.milestone_id))

	# Option C: stat threshold (NEW)
	# Example: stat_key="money_earned_total", amount_required=500
	if b.stat_key.strip_edges() != "" and b.amount_required > 0:
		if _hp.has_method("get_stat"):
			var have := int(_hp.call("get_stat", b.stat_key))
			return have >= b.amount_required

	# Option B: action counter threshold (existing)
	if b.action_id.strip_edges() != "" and b.amount_required > 0:
		if _hp.has_method("get_count"):
			var have := int(_hp.call("get_count", b.action_id))
			return have >= b.amount_required

	return false


func _set_visible(node: Node, v: bool) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = v
	else:
		node.set("visible", v)


func get_pending_reveals() -> Array:
	return _pending_reveals.duplicate(true)


func mark_reveal_done(reveal_key: String) -> void:
	var parts := reveal_key.split(":")
	if parts.size() < 2:
		return

	# domain_id is first chunk, milestone_id is everything after it
	var domain_id := parts[0]
	var milestone_id := reveal_key.substr(domain_id.length() + 1) # keep any ":" inside synthetic ids

	if _hp != null and _hp.has_method("mark_revealed"):
		_hp.call("mark_revealed", domain_id, milestone_id)

	# Refresh to show immediately after the cutscene
	_sync_all("reveal_done")
