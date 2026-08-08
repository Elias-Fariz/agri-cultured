extends BaseOverlay
class_name WhisperOverlay

@export var whisper_label_path: NodePath
@export var whisper_audio_path: NodePath
@export var bob_holder_path: NodePath

@onready var whisper_label: Label = (
	get_node_or_null(whisper_label_path) as Label
)

@onready var whisper_audio: AudioStreamPlayer = (
	get_node_or_null(whisper_audio_path) as AudioStreamPlayer
)

@onready var bob_holder: Control = (
	get_node_or_null(bob_holder_path) as Control
)

@export_group("Timing")

@export var default_fade_in_duration: float = 0.9
@export var default_hold_duration: float = 1.6
@export var default_fade_out_duration: float = 1.0
@export var default_gap_duration: float = 0.35


@export_group("Appearance")

# The strongest alpha the current weak Valley Heart reaches.
# Keeping this below 1.0 can make the first whispers feel delicate.
@export_range(0.0, 1.0, 0.05)
var maximum_alpha: float = 0.90

@export_group("Motion")

@export var enable_gentle_bob: bool = true

# Maximum vertical movement in pixels.
@export var bob_distance: float = 3.0

# Seconds for one full up-and-down cycle.
@export var bob_cycle_duration: float = 3.2

var _bob_active: bool = false
var _bob_time: float = 0.0
var _bob_base_position: Vector2 = Vector2.ZERO


@export_group("Audio")

# If true, WhisperAudio plays throughout the whole sequence.
@export var play_ambient_audio: bool = true


@export_group("Debug")

@export var debug_enabled: bool = false


signal whisper_sequence_finished


var _is_whispering: bool = false
var _current_tween: Tween = null


func _ready() -> void:
	super._ready()

	add_to_group("whisper_ui")

	if whisper_label != null:
		whisper_label.text = ""
		whisper_label.modulate.a = 0.0

	if bob_holder != null:
		_bob_base_position = bob_holder.position

	if debug_enabled:
		print("[WhisperOverlay] whisper_label = ", whisper_label)
		print("[WhisperOverlay] whisper_audio = ", whisper_audio)
		print("[WhisperOverlay] bob_holder = ", bob_holder)
		print("[WhisperOverlay] visual_node_path = ", visual_node_path)

func _process(delta: float) -> void:
	if not _bob_active:
		return

	if bob_holder == null:
		return

	if bob_cycle_duration <= 0.0:
		return

	_bob_time += delta

	var phase := (
		_bob_time
		/ bob_cycle_duration
		* TAU
	)

	var y_offset := sin(phase) * bob_distance

	bob_holder.position = (
		_bob_base_position
		+ Vector2(0.0, y_offset)
	)

func _start_gentle_bob() -> void:
	if not enable_gentle_bob:
		return

	if bob_holder == null:
		return

	_bob_time = 0.0
	_bob_base_position = bob_holder.position
	_bob_active = true


func _stop_gentle_bob() -> void:
	_bob_active = false
	_bob_time = 0.0

	if bob_holder != null:
		bob_holder.position = _bob_base_position

# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------

func is_whispering() -> bool:
	return _is_whispering


func show_sequence(
	phrases: Array[String],
	fade_in_duration: float = -1.0,
	hold_duration: float = -1.0,
	fade_out_duration: float = -1.0,
	gap_duration: float = -1.0
) -> void:
	if _is_whispering:
		return

	var cleaned_phrases := _clean_phrases(phrases)

	if cleaned_phrases.is_empty():
		return

	if whisper_label == null:
		push_warning(
			"WhisperOverlay: whisper_label is null. "
			+ "Check whisper_label_path in the Inspector."
		)
		return

	var fade_in := _resolve_duration(
		fade_in_duration,
		default_fade_in_duration
	)

	var hold := _resolve_duration(
		hold_duration,
		default_hold_duration
	)

	var fade_out := _resolve_duration(
		fade_out_duration,
		default_fade_out_duration
	)

	var gap := _resolve_duration(
		gap_duration,
		default_gap_duration
	)

	_is_whispering = true

	show_overlay()

	_start_gentle_bob()
	_start_whisper_audio()

	for phrase in cleaned_phrases:
		await _show_phrase(
			phrase,
			fade_in,
			hold,
			fade_out
		)

		if gap > 0.0:
			await get_tree().create_timer(gap).timeout

	_stop_whisper_audio()
	_stop_gentle_bob()

	if whisper_label != null:
		whisper_label.text = ""
		whisper_label.modulate.a = 0.0

	hide_overlay()

	_is_whispering = false

	whisper_sequence_finished.emit()


func show_sequence_and_wait(
	phrases: Array[String],
	fade_in_duration: float = -1.0,
	hold_duration: float = -1.0,
	fade_out_duration: float = -1.0,
	gap_duration: float = -1.0
) -> void:
	await show_sequence(
		phrases,
		fade_in_duration,
		hold_duration,
		fade_out_duration,
		gap_duration
	)


func show_sequence_for_cutscene_and_wait(
	phrases: Array[String],
	fade_in_duration: float = -1.0,
	hold_duration: float = -1.0,
	fade_out_duration: float = -1.0,
	gap_duration: float = -1.0
) -> void:
	var old_is_modal := is_modal

	# CutsceneDirector already owns the gameplay lock and time pause.
	# This prevents WhisperOverlay from unlocking/resuming them
	# when the whisper finishes.
	is_modal = false

	await show_sequence(
		phrases,
		fade_in_duration,
		hold_duration,
		fade_out_duration,
		gap_duration
	)

	is_modal = old_is_modal


# -------------------------------------------------------------------
# Phrase presentation
# -------------------------------------------------------------------

func _show_phrase(
	text: String,
	fade_in: float,
	hold: float,
	fade_out: float
) -> void:
	if whisper_label == null:
		return

	_kill_current_tween()

	whisper_label.text = text
	whisper_label.modulate.a = 0.0

	if debug_enabled:
		print("[WhisperOverlay] Whisper: ", text)

	# Fade in.
	_current_tween = create_tween()

	_current_tween.set_trans(Tween.TRANS_SINE)
	_current_tween.set_ease(Tween.EASE_OUT)

	_current_tween.tween_property(
		whisper_label,
		"modulate:a",
		maximum_alpha,
		max(fade_in, 0.01)
	)

	await _current_tween.finished

	_current_tween = null

	# Hold.
	if hold > 0.0:
		await get_tree().create_timer(hold).timeout

	# Fade out.
	_current_tween = create_tween()

	_current_tween.set_trans(Tween.TRANS_SINE)
	_current_tween.set_ease(Tween.EASE_IN)

	_current_tween.tween_property(
		whisper_label,
		"modulate:a",
		0.0,
		max(fade_out, 0.01)
	)

	await _current_tween.finished

	_current_tween = null


# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------

func _clean_phrases(phrases: Array[String]) -> Array[String]:
	var result: Array[String] = []

	for phrase in phrases:
		var cleaned := String(phrase).strip_edges()

		if cleaned != "":
			result.append(cleaned)

	return result


func _resolve_duration(
	requested: float,
	fallback: float
) -> float:
	if requested < 0.0:
		return max(fallback, 0.0)

	return max(requested, 0.0)


func _start_whisper_audio() -> void:
	if not play_ambient_audio:
		return

	if whisper_audio == null:
		return

	if whisper_audio.stream == null:
		return

	whisper_audio.stop()
	whisper_audio.play()


func _stop_whisper_audio() -> void:
	if whisper_audio == null:
		return

	whisper_audio.stop()


func _kill_current_tween() -> void:
	if _current_tween != null:
		if is_instance_valid(_current_tween):
			_current_tween.kill()

	_current_tween = null
