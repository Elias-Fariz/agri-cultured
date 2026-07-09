extends BaseOverlay
class_name NarrationOverlay

@export var text_label_path: NodePath
@export var continue_hint_path: NodePath

@onready var text_label: Label = get_node_or_null(text_label_path) as Label
@onready var continue_hint: Label = get_node_or_null(continue_hint_path) as Label

@export var close_actions: Array[StringName] = [
	&"interact",
	&"ui_accept",
	&"ui_cancel"
]

@export var show_text_instantly: bool = true
@export var typewriter_characters_per_second: float = 55.0

@export var open_sfx_path: NodePath
@export var close_sfx_path: NodePath

@export var debug_enabled: bool = true

var _is_typing: bool = false
var _full_text: String = ""
var _typing_tween: Tween = null


func _ready() -> void:
	super._ready()

	if debug_enabled:
		print("[NarrationOverlay] text_label = ", text_label)
		print("[NarrationOverlay] continue_hint = ", continue_hint)
		print("[NarrationOverlay] visual_node_path = ", visual_node_path)
		print("[NarrationOverlay] visual node = ", get_node_or_null(visual_node_path))

	if continue_hint != null:
		continue_hint.visible = false


func show_text(text: String) -> void:
	text = text.strip_edges()
	if text == "":
		return

	_full_text = text

	# Let BaseOverlay handle:
	# - showing the visual_node_path
	# - modal ownership
	# - gameplay lock
	# - time pause
	show_overlay()

	_play_sfx(open_sfx_path)
	_set_text(text)


func _set_text(text: String) -> void:
	if _typing_tween != null:
		_typing_tween.kill()
		_typing_tween = null

	if text_label == null:
		push_warning("NarrationOverlay: text_label is null. Check text_label_path in the Inspector.")
		return

	if continue_hint != null:
		continue_hint.visible = false

	if debug_enabled:
		print("[NarrationOverlay] Setting text: ", text)

	if show_text_instantly:
		_is_typing = false
		text_label.text = text
		_show_continue_hint()
		return

	_is_typing = true
	text_label.text = ""

	var duration :Variant= max(
		0.05,
		float(text.length()) / max(typewriter_characters_per_second, 1.0)
	)

	_typing_tween = create_tween()
	_typing_tween.tween_method(
		_set_visible_character_count.bind(text),
		0,
		text.length(),
		duration
	)

	await _typing_tween.finished

	_is_typing = false
	text_label.text = text
	_show_continue_hint()

func _set_visible_character_count(count: int, source_text: String) -> void:
	if text_label == null:
		return

	count = clamp(count, 0, source_text.length())
	text_label.text = source_text.substr(0, count)


func _show_continue_hint() -> void:
	if continue_hint != null:
		continue_hint.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return

	for action in close_actions:
		if event.is_action_pressed(action):
			_advance_or_close()
			get_viewport().set_input_as_handled()
			return


func _advance_or_close() -> void:
	if _is_typing:
		_finish_typing_now()
		return

	close_narration()


func _finish_typing_now() -> void:
	if _typing_tween != null:
		_typing_tween.kill()
		_typing_tween = null

	_is_typing = false

	if text_label != null:
		text_label.text = _full_text

	_show_continue_hint()


func close_narration() -> void:
	if not is_open():
		return

	if _typing_tween != null:
		_typing_tween.kill()
		_typing_tween = null

	_is_typing = false

	_play_sfx(close_sfx_path)

	# Let BaseOverlay handle:
	# - hiding the visual_node_path
	# - releasing modal ownership
	# - gameplay unlock
	# - time resume
	hide_overlay()


func _play_sfx(path: NodePath) -> void:
	if path == NodePath():
		return

	var player := get_node_or_null(path)
	if player == null:
		return

	if player is AudioStreamPlayer:
		(player as AudioStreamPlayer).stop()
		(player as AudioStreamPlayer).play()
	elif player is AudioStreamPlayer2D:
		(player as AudioStreamPlayer2D).stop()
		(player as AudioStreamPlayer2D).play()
