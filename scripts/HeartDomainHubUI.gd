# res://ui/HeartDomainHubUI.gd
extends BaseOverlay
class_name HeartDomainHubUI

@onready var title_label: Label = $Panel/VBox/Title
@onready var subtitle_label: Label = $Panel/VBox/Subtitle
@onready var domains_box: VBoxContainer = $Panel/VBox/DomainButtons
@onready var hint_label: Label = $Panel/VBox/Hint
@onready var close_button: Button = $Panel/VBox/CloseButton

@export var detail_scene: PackedScene = preload("res://ui/HeartProgressUI.tscn")

var _detail: HeartProgressUI = null

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	close_button.pressed.connect(hide_overlay)

	title_label.text = "Valley Heart"
	subtitle_label.text = "Choose a wing. Each path grows a different kind of strength."
	hint_label.text = "You don’t have to do everything today. Pick what feels kind."

	_build_domain_buttons()

func show_overlay() -> void:
	super.show_overlay()
	_build_domain_buttons()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		hide_overlay()
		get_viewport().set_input_as_handled()

func _build_domain_buttons() -> void:
	# Clear old buttons (in case domains changed)
	for c in domains_box.get_children():
		c.queue_free()

	var hp := get_node_or_null("/root/HeartProgress")
	if hp == null or not ("definition" in hp):
		_add_disabled_label("(HeartProgress not found)")
		return

	var def: Resource = hp.get("definition")
	if def == null or not ("milestones" in def):
		_add_disabled_label("(No heart definition loaded)")
		return

	var milestones: Array = def.get("milestones")
	if milestones == null or milestones.is_empty():
		_add_disabled_label("(No milestones defined yet)")
		return

	# Collect unique domain ids dynamically so future domains auto-appear
	var domains: Array[String] = []
	for m in milestones:
		if m == null:
			continue
		var d := String(m.domain_id).strip_edges()
		if d != "" and not domains.has(d):
			domains.append(d)

	domains.sort()

	# Optional “All” button
	_add_domain_button("All Wings", "")

	for d in domains:
		_add_domain_button(_pretty_domain_name(d), d)

func _add_domain_button(label_text: String, domain_id: String) -> void:
	var b := Button.new()
	b.text = label_text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func(): _open_domain(domain_id))
	domains_box.add_child(b)

func _add_disabled_label(text: String) -> void:
	var l := Label.new()
	l.text = text
	domains_box.add_child(l)

func _open_domain(domain_id: String) -> void:
	if _detail == null or not is_instance_valid(_detail):
		_detail = detail_scene.instantiate() as HeartProgressUI
		get_tree().root.add_child(_detail)

		# Add a back button to the detail UI without restructuring:
		# easiest is: reuse Esc to close, and hub stays open underneath *OR*
		# hide hub while detail is open.
		_detail.tree_exited.connect(func():
			# If the detail gets freed, clear reference
			_detail = null
		)

	# Hide this hub while viewing the detail
	hide_overlay()

	_detail.set_domain(domain_id)
	_detail.show_overlay()

	# When detail closes, re-open hub (gentle flow)
	# We'll poll for "opened" state by waiting a frame and checking visibility.
	_wait_for_detail_close_then_return()

func _wait_for_detail_close_then_return() -> void:
	# Fire-and-forget coroutine
	_call_deferred_wait()

func _call_deferred_wait() -> void:
	call_deferred("_wait_loop")

func _wait_loop() -> void:
	while _detail != null and is_instance_valid(_detail) and _detail.visible:
		await get_tree().process_frame
	# When detail closes, show hub again (unless player closed everything)
	show_overlay()

func _pretty_domain_name(domain_id: String) -> String:
	match domain_id:
		"land": return "Land Wing"
		"sea": return "Sea Wing"
		"people": return "People Wing"
		"craft": return "Craft Wing"
		_: return domain_id.capitalize()
