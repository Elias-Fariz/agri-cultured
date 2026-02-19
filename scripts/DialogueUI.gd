extends BaseOverlay

@onready var box: Panel = $Box

# --- NEW NODE PATHS (match your updated DialogueUI.tscn) ---
@onready var portrait_frame: Control = $Box/Margin/Root/PortraitCol/PortraitFrame
@onready var portrait_rect: TextureRect = $Box/Margin/Root/PortraitCol/PortraitFrame/Portrait
@onready var friendship_label: Label = $Box/Margin/Root/PortraitCol/FriendshipLabel

@onready var name_label: Label = $Box/Margin/Root/TextCol/NameLabel
@onready var text_label: Label = $Box/Margin/Root/TextCol/TextLabel
@onready var hint_label: Label = $Box/Margin/Root/TextCol/HintLabel

# Optional default portrait (silhouette). Set this in Inspector.
@export var default_portrait: Texture2D
@export var hide_portrait_if_missing: bool = false

var _lines: Array[String] = []
var _index: int = 0
var _active: bool = false

@export var chars_per_second: float = 45.0

var _full_text: String = ""
var _typing: bool = false
var _char_index: int = 0
var _char_accum: float = 0.0

@export var blips_per_second: float = 36.0
@export var blip_random_pitch: float = 0.12   # 0.0 = none, 0.12 = cozy variation
@export var blip_skip_punctuation: bool = true

var _blip_accum: float = 0.0
var _last_blip_char: String = ""

signal dialogue_closed


func _ready() -> void:
	hide_dialogue()


# ✅ IMPORTANT: we keep your original signature compatible,
# but add an optional npc_id at the end.
func show_dialogue(speaker_name: String, lines: Array[String], friendship: int = -1, speaker_id: String = "") -> void:
	if lines.is_empty():
		return

	_lines = lines
	_index = 0
	_active = true

	# Friendship display
	if friendship >= 0:
		friendship_label.visible = true
		friendship_label.text = "Friendship: %s (%d)" % [_hearts(friendship), friendship]
	else:
		friendship_label.visible = false

	# Portrait (safe fallback)
	_apply_portrait_for_speaker(speaker_id, speaker_name)

	name_label.text = speaker_name
	show_line(_lines[_index])
	hint_label.text = "E: Next   Esc: Close"

	_set_voice_for_speaker(speaker_name)
	super.show_overlay()


func hide_dialogue() -> void:
	_active = false
	_typing = false
	_talk_blip_stop()
	_lines = []
	_index = 0
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
		# 1) If we're still typing, finish instantly (don't advance index yet)
		if _typing:
			_typing = false
			_char_index = _full_text.length()
			text_label.text = _full_text
			_talk_blip_stop()
			get_viewport().set_input_as_handled()
			return

		# 2) Otherwise, advance to next line
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

		# --- TALK BLIPS while typing ---
		_blip_accum += delta
		var blip_interval: float = 1.0 / max(blips_per_second, 1.0)

		if _blip_accum >= blip_interval:
			_blip_accum = 0.0

			# Grab the newest revealed character (the last visible char)
			var newest_char := ""
			if _char_index > 0 and _char_index <= _full_text.length():
				newest_char = _full_text.substr(_char_index - 1, 1)

			_talk_blip_play(newest_char)

		if _char_index >= _full_text.length():
			_typing = false
			_talk_blip_stop()


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
	# Later: swap streams based on speaker
	pass


# -------------------------------------------------------------------
# Portrait plumbing
# -------------------------------------------------------------------

func _apply_portrait_for_speaker(speaker_id: String, speaker_name: String) -> void:
	var tex: Texture2D = null

	# 1) Best: find NPC by npc_id and read its exported portrait
	if speaker_id.strip_edges() != "":
		var npc := _find_npc_by_id(speaker_id)
		if npc != null:
			# We don't assume a class; just look for a "portrait" property safely.
			# In Godot, exported vars are accessible like fields.
			if "portrait" in npc:
				var v = npc.get("portrait")
				if v is Texture2D:
					tex = v

	# 2) Fallback: default silhouette if provided
	if tex == null:
		tex = default_portrait

	# Apply
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
