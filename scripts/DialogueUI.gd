extends BaseOverlay

@onready var box: Panel = $Box

# --- Existing portrait / text UI ---
@onready var portrait_frame: Control = $Box/Margin/Root/PortraitCol/PortraitFrame
@onready var portrait_rect: TextureRect = $Box/Margin/Root/PortraitCol/PortraitFrame/Portrait
@onready var friendship_label: Label = $Box/Margin/Root/TextCol/FriendshipLabel

@onready var name_label: Label = $Box/Margin/Root/TextCol/NameLabel
@onready var text_label: Label = $Box/Margin/Root/TextCol/TextLabel
@onready var hint_label: Label = $Box/Margin/Root/TextCol/HintLabel

# Optional default portrait
@export var default_portrait: Texture2D
@export var hide_portrait_if_missing: bool = false

# -------------------------------------------------------------------
# NEW: lightweight portrait-based stage visuals
# -------------------------------------------------------------------

@export var hide_portrait_when_stage_slot_none: bool = false
@export var enable_stage_visuals: bool = true
@export var stage_slot_size: Vector2 = Vector2(240, 332)
@export var stage_bottom_overlap: float = 28.0
@export var stage_active_alpha: float = 1.0
@export var stage_inactive_alpha: float = 0.38
@export var stage_narration_alpha: float = 0.70
@export var stage_active_scale: float = 1.0
@export var stage_inactive_scale: float = 0.92

var _stage_layer: Control = null
var _stage_rects: Dictionary = {}          # slot -> TextureRect
var _stage_slot_speaker: Dictionary = {}   # slot -> speaker_id

# Legacy line mode
var _lines: Array[String] = []
var _index: int = 0

# New beat mode
var _sequence: DialogueSequenceData = null
var _beats: Array[DialogueBeatData] = []
var _beat_index: int = 0
var _using_sequence_mode: bool = false

var _active: bool = false

# Stability guards.
var _closing_dialogue: bool = false
var _advancing_dialogue: bool = false
@export var dialogue_input_cooldown: float = 0.08
var _dialogue_input_cooldown_left: float = 0.0

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
	_ensure_stage_layer()
	_layout_stage_slots()
	hide_dialogue()

func _notification(what: int) -> void:
	if what == Control.NOTIFICATION_RESIZED:
		_layout_stage_slots()

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

	_clear_stage_visuals()
	_apply_speaker_state(speaker_name, friendship, speaker_id)
	_apply_legacy_stage_for_speaker(speaker_id)

	show_line(_lines[_index])
	hint_label.text = "E: Next   Esc: Close"

	_set_voice_for_speaker(speaker_name)
	_layout_stage_slots()
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

	_clear_stage_visuals()
	_show_current_beat()
	hint_label.text = "E: Next   Esc: Close"

	_layout_stage_slots()
	super.show_overlay()

func hide_dialogue() -> void:
	if _closing_dialogue:
		return

	_closing_dialogue = true

	_active = false
	_typing = false
	_talk_blip_stop()

	_lines = []
	_index = 0

	_sequence = null
	_beats.clear()
	_beat_index = 0
	_using_sequence_mode = false

	_clear_stage_visuals()

	super.hide_overlay()

	emit_signal("dialogue_closed")

	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("camera_clear_focus"):
		player.camera_clear_focus()

	# Release the guard on the next frame so repeated close calls in the same frame are ignored.
	await get_tree().process_frame
	_closing_dialogue = false
	_advancing_dialogue = false

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	if _closing_dialogue:
		get_viewport().set_input_as_handled()
		return

	if _dialogue_input_cooldown_left > 0.0:
		return

	if event.is_action_pressed("ui_cancel"):
		_dialogue_input_cooldown_left = dialogue_input_cooldown
		hide_dialogue()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("interact"):
		_dialogue_input_cooldown_left = dialogue_input_cooldown

		# If still typing, finish current beat/line instantly.
		if _typing:
			_typing = false
			_char_index = _full_text.length()
			text_label.text = _full_text
			_talk_blip_stop()
			get_viewport().set_input_as_handled()
			return

		if _advancing_dialogue:
			get_viewport().set_input_as_handled()
			return

		_advancing_dialogue = true

		# Otherwise advance.
		if _using_sequence_mode:
			_beat_index += 1
			if _beat_index >= _beats.size():
				hide_dialogue()
			else:
				_show_current_beat()
				_advancing_dialogue = false
		else:
			_index += 1
			if _index >= _lines.size():
				hide_dialogue()
			else:
				show_line(_lines[_index])
				_advancing_dialogue = false

		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_dialogue_input_cooldown_left = max(0.0, _dialogue_input_cooldown_left - delta)

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
	var no_stage := _beat_requests_no_stage(beat)

	# Narration / speakerless support
	if beat.should_use_narration_mode():
		name_label.text = ""
		friendship_label.visible = false
		_apply_portrait_texture(null)

		if no_stage:
			_hide_stage_layer_for_beat()
		else:
			_show_stage_layer_for_beat()
			_apply_stage_for_narration()

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

	if no_stage:
		_hide_stage_layer_for_beat()
	else:
		_show_stage_layer_for_beat()
		_apply_stage_for_beat(beat)

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
	# Beat portrait override wins.
	if beat != null and beat.portrait_override != null:
		_apply_portrait_texture(beat.portrait_override)
		return

	var tex: Texture2D = null

	if speaker_id.strip_edges() != "":
		var npc := _find_npc_by_id(speaker_id)
		if npc != null:
			# New flexible dialogue art catalog.
			if "dialogue_art" in npc:
				var art = npc.get("dialogue_art")
				if art != null and art is NPCDialogueArtData:
					var key := "default"
					if beat != null:
						key = beat.get_effective_portrait_key()
					tex = (art as NPCDialogueArtData).get_portrait_texture(key)

			# Old/simple fallback.
			if tex == null and "portrait" in npc:
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

# -------------------------------------------------------------------
# NEW: stage visuals
# -------------------------------------------------------------------

func _ensure_stage_layer() -> void:
	if not enable_stage_visuals:
		return

	if _stage_layer != null and is_instance_valid(_stage_layer):
		return

	_stage_layer = Control.new()
	_stage_layer.name = "StageLayer"
	_stage_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_layer.offset_left = 0
	_stage_layer.offset_top = 0
	_stage_layer.offset_right = 0
	_stage_layer.offset_bottom = 0
	add_child(_stage_layer)
	move_child(_stage_layer, 0) # behind the dialogue box

	for slot_name in ["left", "center", "right"]:
		var rect := TextureRect.new()
		rect.name = "Stage_%s" % slot_name
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.visible = false
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		rect.modulate = Color(1, 1, 1, 1)
		_stage_layer.add_child(rect)

		_stage_rects[slot_name] = rect
		_stage_slot_speaker[slot_name] = ""

func _layout_stage_slots() -> void:
	if not enable_stage_visuals:
		return
	if _stage_layer == null:
		return

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var w := stage_slot_size.x
	var h := stage_slot_size.y

	var bottom_y := box.global_position.y + stage_bottom_overlap

	var centers := {
		"left": vp_size.x * 0.32,
		"center": vp_size.x * 0.50,
		"right": vp_size.x * 0.68
	}

	for slot_name in centers.keys():
		var rect: TextureRect = _stage_rects.get(slot_name, null)
		if rect == null:
			continue

		rect.size = Vector2(w, h)
		rect.position = Vector2(float(centers[slot_name]) - w * 0.5, bottom_y - h)

func _clear_stage_visuals() -> void:
	if _stage_layer == null:
		return

	for slot_name in _stage_rects.keys():
		var rect: TextureRect = _stage_rects[slot_name]
		rect.texture = null
		rect.visible = false
		rect.modulate = Color(1, 1, 1, 1)
		rect.scale = Vector2.ONE
		_stage_slot_speaker[slot_name] = ""
	
	_show_stage_layer_for_beat()

func _apply_legacy_stage_for_speaker(speaker_id: String) -> void:
	if not enable_stage_visuals:
		return

	var tex := _resolve_stage_texture_for_speaker(speaker_id, null)
	if tex == null:
		return

	_set_stage_slot_visual("center", speaker_id, tex)
	_refresh_stage_slot_focus("center", true)

func _apply_stage_for_beat(beat: DialogueBeatData) -> void:
	if not enable_stage_visuals:
		return

	if _beat_requests_no_stage(beat):
		_hide_stage_layer_for_beat()
		return

	_show_stage_layer_for_beat()

	var speaker_id := String(beat.speaker_id).strip_edges()
	if speaker_id == "":
		return

	var slot := _choose_stage_slot_for_beat(beat)

	# Safety: if "none" somehow reaches this point, stop before trying
	# to use it as a real stage slot.
	if slot == "none":
		_hide_stage_layer_for_beat()
		return

	var tex := _resolve_stage_texture_for_speaker(speaker_id, beat)

	if tex != null:
		_set_stage_slot_visual(slot, speaker_id, tex)

	_refresh_stage_slot_focus(slot, beat.dim_others)

func _apply_stage_for_narration() -> void:
	if not enable_stage_visuals:
		return

	for slot_name in _stage_rects.keys():
		var rect: TextureRect = _stage_rects[slot_name]
		if not rect.visible:
			continue
		rect.modulate = Color(1, 1, 1, stage_narration_alpha)
		rect.scale = Vector2.ONE * stage_inactive_scale

func _choose_stage_slot_for_beat(beat: DialogueBeatData) -> String:
	var requested := beat.get_effective_stage_slot()

	if requested == "none":
		return "none"

	if requested != "auto":
		return requested

	var speaker_id := String(beat.speaker_id).strip_edges()

	# If this speaker already owns a slot, keep them there
	var existing := _find_stage_slot_for_speaker(speaker_id)
	if existing != "":
		return existing

	# If nobody is staged yet, center the first speaker
	if _get_stage_visible_count() == 0:
		return "center"

	# If center is occupied and this is the second speaker, move center occupant to left
	# and place the new speaker on the right for a nice first conversation layout.
	if _get_stage_visible_count() == 1:
		var center_owner := String(_stage_slot_speaker.get("center", ""))
		if center_owner != "":
			if String(_stage_slot_speaker.get("left", "")) == "":
				_move_stage_slot_assignment("center", "left")
				return "right"

	# Otherwise fill empty side slots first
	if String(_stage_slot_speaker.get("left", "")) == "":
		return "left"
	if String(_stage_slot_speaker.get("right", "")) == "":
		return "right"

	# Fallback to center
	return "center"

func _find_stage_slot_for_speaker(speaker_id: String) -> String:
	for slot_name in _stage_slot_speaker.keys():
		if String(_stage_slot_speaker[slot_name]) == speaker_id:
			return slot_name
	return ""

func _get_stage_visible_count() -> int:
	var count := 0
	for slot_name in _stage_rects.keys():
		var rect: TextureRect = _stage_rects[slot_name]
		if rect.visible:
			count += 1
	return count

func _move_stage_slot_assignment(from_slot: String, to_slot: String) -> void:
	var from_rect: TextureRect = _stage_rects.get(from_slot, null)
	var to_rect: TextureRect = _stage_rects.get(to_slot, null)
	if from_rect == null or to_rect == null:
		return

	to_rect.texture = from_rect.texture
	to_rect.visible = from_rect.visible
	to_rect.modulate = from_rect.modulate
	to_rect.scale = from_rect.scale

	_stage_slot_speaker[to_slot] = _stage_slot_speaker.get(from_slot, "")

	from_rect.texture = null
	from_rect.visible = false
	from_rect.modulate = Color(1, 1, 1, 1)
	from_rect.scale = Vector2.ONE
	_stage_slot_speaker[from_slot] = ""

func _set_stage_slot_visual(slot_name: String, speaker_id: String, tex: Texture2D) -> void:
	var rect: TextureRect = _stage_rects.get(slot_name, null)
	if rect == null:
		return

	rect.texture = tex
	rect.visible = tex != null
	rect.scale = Vector2.ONE
	rect.modulate = Color(1, 1, 1, 1)

	_stage_slot_speaker[slot_name] = speaker_id

func _refresh_stage_slot_focus(active_slot: String, dim_others: bool) -> void:
	for slot_name in _stage_rects.keys():
		var rect: TextureRect = _stage_rects[slot_name]
		if not rect.visible:
			continue

		if not dim_others:
			rect.modulate = Color(1, 1, 1, stage_active_alpha)
			rect.scale = Vector2.ONE * stage_active_scale
			continue

		if slot_name == active_slot:
			rect.modulate = Color(1, 1, 1, stage_active_alpha)
			rect.scale = Vector2.ONE * stage_active_scale
		else:
			rect.modulate = Color(1, 1, 1, stage_inactive_alpha)
			rect.scale = Vector2.ONE * stage_inactive_scale

func _resolve_stage_texture_for_speaker(speaker_id: String, beat: DialogueBeatData = null) -> Texture2D:
	# Exact stage texture override on the beat wins.
	if beat != null and beat.stage_texture_override != null:
		return beat.stage_texture_override

	var tex: Texture2D = null

	if speaker_id.strip_edges() != "":
		var npc := _find_npc_by_id(speaker_id)
		if npc != null:
			# New flexible dialogue art catalog.
			if "dialogue_art" in npc:
				var art = npc.get("dialogue_art")
				if art != null and art is NPCDialogueArtData:
					var key := "default"
					if beat != null:
						key = beat.get_effective_stage_pose_key()
					tex = (art as NPCDialogueArtData).get_stage_texture(key)

			if tex != null:
				return tex

			# Emergency fallback: if a beat has a special portrait override
			# but no stage pose exists, allow it to show on stage.
			if beat != null and beat.portrait_override != null:
				return beat.portrait_override

			# Old/simple fallback: NPC portrait.
			if "portrait" in npc:
				var v = npc.get("portrait")
				if v is Texture2D:
					return v

	return default_portrait

func _beat_requests_no_stage(beat: DialogueBeatData) -> bool:
	if beat == null:
		return false
	return beat.get_effective_stage_slot() == "none"

func _hide_stage_layer_for_beat() -> void:
	if _stage_layer == null:
		return

	_stage_layer.visible = false

func _show_stage_layer_for_beat() -> void:
	if _stage_layer == null:
		return

	_stage_layer.visible = true
