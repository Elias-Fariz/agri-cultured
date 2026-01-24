# ValleyHeartVisuals.gd
extends Node

@export var progress: HeartProgressData

# For each domain id, point to the Visuals node in that wing
@export var land_visuals_path: NodePath
@export var sea_visuals_path: NodePath
@export var people_visuals_path: NodePath
@export var craft_visuals_path: NodePath

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_refresh_all()

	# NEW: listen for updates
	var hm := get_node_or_null("/root/HeartProgress")
	if hm != null and hm.has_signal("heart_progress_changed"):
		hm.heart_progress_changed.connect(_on_heart_progress_changed)

func _on_heart_progress_changed(_domain_id: String) -> void:
	_refresh_all()

func _refresh_all() -> void:
	_refresh_domain("land", land_visuals_path)
	_refresh_domain("sea", sea_visuals_path)
	_refresh_domain("people", people_visuals_path)
	_refresh_domain("craft", craft_visuals_path)

func _refresh_domain(domain_id: String, visuals_path: NodePath) -> void:
	if progress == null:
		return
	var d := progress.get_domain(domain_id)
	if d == null:
		return

	var visuals := get_node_or_null(visuals_path)
	if visuals == null:
		return

	# Reveal sprout sprites: Sprout1..SproutN based on sprouts_done
	for i in range(1, d.sprouts_total + 1):
		var n := visuals.get_node_or_null("Sprout%d" % i)
		if n != null:
			n.visible = (i <= d.sprouts_done)

	# Reveal root sprites: Root1..RootN based on roots_done
	for i in range(1, d.roots_total + 1):
		var n2 := visuals.get_node_or_null("Root%d" % i)
		if n2 != null:
			n2.visible = (i <= d.roots_done)
