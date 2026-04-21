extends BaseOverlay

@onready var box: Panel = $Box

# --- Existing portrait / text UI ---
@onready var portrait_frame: Control = $Box/Margin/Root/PortraitCol/PortraitFrame
@onready var portrait_rect: TextureRect = $Box/Margin/Root/PortraitCol/PortraitFrame/Portrait
@onready var friendship_label: Label = $Box/Margin/Root/PortraitCol/FriendshipLabel

@onready var name_label: Label = $Box/Margin/Root/TextCol/NameLabel
@onready var text_label: Label = $Box/Margin/Root/TextCol/TextLabel
@onready var hint_label: Label = $Box/Margin/Root/TextCol/HintLabel

# Optional default portrait
@export var default_portrait: Texture2D
@export var hide_portrait_if_missing: bool = false

# Legacy line mode
var _lines: Array[String] = []
var _index: int = 0

# New beat mode
var _sequence: DialogueSequenceData = null
var _beats: Array[DialogueBeatData] = []
var _beat_index: int = 0
var _using_sequence_mode: bool = false

var _active: bool = false

@export var chars_per_second: float = 45.0

var _full_text: String = ""
var _typing: bool = false
var _char_index: int = 0
var _char_accum: float = 0.0

@export var blips_per_second: float = 36.0
@export var blip_random_pitch: float = 0.12
@export var blip_skip_punctuation: bool = true

var _blip_accum: float = 0.0
var _last_blip_char: String = ""

signal dialogue_closed

func _ready() -> void:
	hide_dialogue()

# -------------------------------------------------------------------
# Legacy simple dialogue (kept for compatibility)
# -------------------------------------------------------------------

func show_dialogue(speaker_name: String, lines: Array[String], friendship: int = -1, speaker_id: String = "") -> void:
	if lines.is_empty():
		return

	_using_sequence_mode = false
	_sequence = null
	_beats.clear()
	_beat_index = 0

	_lines = lines
	_index = 0
	_active = true

	_apply_speaker_state(speaker_name, friendship, speaker_id)

	show_line(_lines[_index])
	hint_label.text = "E: Next   Esc: Close"

	_set_voice_for_speaker(speaker_name)
	super.show_overlay()

# -------------------------------------------------------------------
# New sequence dialogue
# -------------------------------------------------------------------

func show_dialogue_sequence(sequence: DialogueSequenceData) -> void:
	if sequence == null:
		return

	var valid_beats := sequence.get_valid_beats()
	if valid_beats.is_empty():
		return

	_using_sequence_mode = true
	_sequence = sequence
	_beats = valid_beats
	_beat_index = 0

	_lines.clear()
	_index = 0
	_active = true

	_show_current_beat()
	hint_label.text = "E: Next   Esc: Close"

	super.show_overlay()

func hide_dialogue() -> void:
	_active = false
	_typing = false
	_talk_blip_stop()

	_lines = []
	_index = 0

	_sequence = null
	_beats.clear()
	_beat_index = 0
	_using_sequence_mode = false

	super.hide_overlay()

	emit_signal("dialogue_closed")

	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("camera_clear_focus"):
		player.camera_clear_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	if event.is_action_pressed("ui_cancel"):
		hide_dialogue()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("interact"):
		# If still typing, finish current beat/line instantly
		if _typing:
			_typing = false
			_char_index = _full_text.length()
			text_label.text = _full_text
			_talk_blip_stop()
			get_viewport().set_input_as_handled()
			return

		# Otherwise advance
		if _using_sequence_mode:
			_beat_index += 1
			if _beat_index >= _beats.size():
				hide_dialogue()
			else:
				_show_current_beat()
		else:
			_index += 1
			if _index >= _lines.size():
				hide_dialogue()
			else:
				show_line(_lines[_index])

		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _active:
		return
	if not _typing:
		return

	_char_accum += delta * chars_per_second
	var new_index := int(_char_accum)

	if new_index > _char_index:
		_char_index = min(new_index, _full_text.length())
		text_label.text = _full_text.substr(0, _char_index)

		_blip_accum += delta
		var blip_interval: float = 1.0 / max(blips_per_second, 1.0)

		if _blip_accum >= blip_interval:
			_blip_accum = 0.0

			var newest_char := ""
			if _char_index > 0 and _char_index <= _full_text.length():
				newest_char = _full_text.substr(_char_index - 1, 1)

			_talk_blip_play(newest_char)

		if _char_index >= _full_text.length():
			_typing = false
			_talk_blip_stop()

func _show_current_beat() -> void:
	if _beat_index < 0 or _beat_index >= _beats.size():
		return

	var beat := _beats[_beat_index]
	if beat == null:
		hide_dialogue()
		return

	_apply_beat_state(beat)
	show_line(beat.text)

func _apply_beat_state(beat: DialogueBeatData) -> void:
	var speaker_id := String(beat.speaker_id).strip_edges()

	# Narration / speakerless support
	if beat.should_use_narration_mode():
		name_label.text = ""
		friendship_label.visible = false
		_apply_portrait_texture(null)
		_set_voice_for_speaker("")
		return

	var npc := _find_npc_by_id(speaker_id)

	var display_name := ""
	if npc != null and ("display_name" in npc):
		display_name = String(npc.get("display_name"))

	display_name = beat.get_effective_speaker_name(display_name)

	var friendship := -1
	if speaker_id != "":
		friendship = int(GameState.get_friendship(speaker_id))

	_apply_speaker_state(display_name, friendship, speaker_id, beat)

	_set_voice_for_speaker(display_name)

func _apply_speaker_state(speaker_name: String, friendship: int = -1, speaker_id: String = "", beat: DialogueBeatData = null) -> void:
	# Friendship display
	if friendship >= 0:
		friendship_label.visible = true
		friendship_label.text = "Friendship: %s (%d)" % [_hearts(friendship), friendship]
	else:
		friendship_label.visible = false

	# Portrait
	_apply_portrait_for_speaker(speaker_id, speaker_name, beat)

	name_label.text = speaker_name

func _hearts(friendship: int) -> String:
	var hearts := clampi(friendship / 10, 0, 10)
	return "♥".repeat(hearts) + "♡".repeat(10 - hearts)

func show_line(text: String) -> void:
	_full_text = text
	_char_index = 0
	_char_accum = 0.0
	_typing = true

	text_label.text = ""
	_talk_blip_reset()

func _talk_blip_reset() -> void:
	_blip_accum = 0.0
	_last_blip_char = ""

func _talk_blip_stop() -> void:
	if has_node("TalkBlipPlayer"):
		$TalkBlipPlayer.stop()

func _talk_blip_play(next_char: String) -> void:
	if not has_node("TalkBlipPlayer"):
		return

	if blip_skip_punctuation:
		if next_char == " ":
			return
		if next_char in [".", ",", "!", "?", ":", ";", "-", "—", "(", ")", "\"", "'"]:
			return

	var p := $TalkBlipPlayer

	if blip_random_pitch > 0.0:
		p.pitch_scale = 1.0 + randf_range(-blip_random_pitch, blip_random_pitch)
	else:
		p.pitch_scale = 1.0

	p.stop()
	p.play()

func _set_voice_for_speaker(speaker_name: String) -> void:
	# Later: swap streams based on speaker or beat voice clip
	pass

# -------------------------------------------------------------------
# Portrait plumbing
# -------------------------------------------------------------------

func _apply_portrait_for_speaker(speaker_id: String, speaker_name: String, beat: DialogueBeatData = null) -> void:
	# Beat portrait override wins
	if beat != null and beat.portrait_override != null:
		_apply_portrait_texture(beat.portrait_override)
		return

	var tex: Texture2D = null

	if speaker_id.strip_edges() != "":
		var npc := _find_npc_by_id(speaker_id)
		if npc != null:
			if "portrait" in npc:
				var v = npc.get("portrait")
				if v is Texture2D:
					tex = v

	if tex == null:
		tex = default_portrait

	_apply_portrait_texture(tex)

func _apply_portrait_texture(tex: Texture2D) -> void:
	if tex != null:
		portrait_rect.texture = tex
		portrait_rect.visible = true
		portrait_frame.visible = true
	else:
		portrait_rect.texture = null
		portrait_rect.visible = false
		portrait_frame.visible = not hide_portrait_if_missing

func _find_npc_by_id(id: String) -> Node:
	for n in get_tree().get_nodes_in_group("npc"):
		if n != null and ("npc_id" in n):
			if String(n.get("npc_id")) == id:
				return n
	return null
