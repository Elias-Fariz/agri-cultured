extends BaseOverlay

signal fishing_finished(success: bool, caught_fish_id: String)

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var catch_label: Label = $Panel/VBox/CatchLabel
@onready var sequence_label: Label = $Panel/VBox/SequenceLabel
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var timer_bar: ProgressBar = $Panel/VBox/TimerBar
@onready var hint_label: Label = $Panel/VBox/HintLabel

# Running state
var _running: bool = false
var _closing: bool = false
var _fish_id: String = ""
var _sequence: Array[String] = []
var _index: int = 0

var _time_limit: float = 3.0
var _time_left: float = 3.0
var _mistakes_allowed: int = 1
var _mistakes_left: int = 1

@export var catch_popup_time: float = 0.6

# Failsafe: track whether the tree was paused when we opened.
# If something accidentally destroys this overlay mid-close, we can restore.
var _prev_tree_paused: bool = false
var _captured_pause_state: bool = false


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	catch_label.visible = false
	timer_bar.min_value = 0
	timer_bar.max_value = 1
	timer_bar.value = 1


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------
func start_minigame(fish_id: String, sequence: Array[String], time_limit: float, mistakes_allowed: int) -> void:
	_fish_id = fish_id
	_sequence = sequence.duplicate()
	_time_limit = max(0.3, time_limit)
	_time_left = _time_limit

	_mistakes_allowed = max(0, mistakes_allowed)
	_mistakes_left = _mistakes_allowed

	_index = 0
	_running = false
	_closing = false

	# Capture pause state once, right when we open.
	if not _captured_pause_state:
		_prev_tree_paused = get_tree().paused
		_captured_pause_state = true

	# UI setup
	title_label.text = "Fishing..."
	hint_label.text = "Press the letters in order. Stay calm — you’ve got this."
	_update_sequence_text()
	_update_status_text()

	timer_bar.value = 1.0
	catch_label.visible = true
	catch_label.text = "CATCH!"
	sequence_label.visible = false
	status_label.visible = false
	timer_bar.visible = false

	super.show_overlay()

	_start_after_catch_popup()


func _start_after_catch_popup() -> void:
	await get_tree().create_timer(catch_popup_time).timeout
	if _closing:
		return

	catch_label.visible = false
	sequence_label.visible = true
	status_label.visible = true
	timer_bar.visible = true

	title_label.text = "Reel it in!"
	_running = true


func _process(delta: float) -> void:
	if not _running:
		return

	_time_left -= delta
	timer_bar.value = clamp(_time_left / _time_limit, 0.0, 1.0)

	if _time_left <= 0.0:
		_fail("Too late… The fish slips away.")


func _unhandled_input(event: InputEvent) -> void:
	if not _running:
		return

	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return

	var key := OS.get_keycode_string((event as InputEventKey).keycode).to_upper()
	if key not in ["A", "D", "W", "S"]:
		return

	var expected := _sequence[_index]

	if key == expected:
		_index += 1
		_update_sequence_text()
		if _index >= _sequence.size():
			_success()
	else:
		_mistakes_left -= 1
		_update_status_text()
		if _mistakes_left < 0:
			_fail("Oops… the line goes slack.")


# -----------------------------------------------------------------------------
# Finish paths (SUCCESS / FAIL)
# -----------------------------------------------------------------------------
func _success() -> void:
	if _closing:
		return
	_closing = true
	_running = false

	title_label.text = "Got it!"
	hint_label.text = "You reel it in with steady hands."
	catch_label.visible = false
	sequence_label.text = ""
	status_label.text = ""
	timer_bar.value = 1.0

	# Emit result FIRST (so the spot can award inventory/energy),
	# but we keep the overlay alive to guarantee cleanup runs.
	emit_signal("fishing_finished", true, _fish_id)

	await get_tree().process_frame
	_close_and_restore()


func _fail(msg: String) -> void:
	if _closing:
		return
	_closing = true
	_running = false

	title_label.text = "Missed!"
	hint_label.text = msg
	catch_label.visible = false
	sequence_label.text = ""
	status_label.text = ""
	timer_bar.value = 0.0

	emit_signal("fishing_finished", false, "")

	# Tiny beat for feedback
	await get_tree().create_timer(0.8).timeout
	_close_and_restore()


func _close_and_restore() -> void:
	# Hide overlay first (BaseOverlay may do pause/lock cleanup)
	super.hide_overlay()

	# Failsafe restore (only if we detect we’re “stuck paused” compared to when we opened)
	_force_restore_world_state_if_needed()

	# Free ourselves after cleanup is done
	queue_free()


# -----------------------------------------------------------------------------
# Failsafe world restore
# -----------------------------------------------------------------------------
func _force_restore_world_state_if_needed() -> void:
	# If the tree is paused now but it wasn’t paused when we opened,
	# something got left behind paused → unpause.
	if _captured_pause_state and get_tree().paused and not _prev_tree_paused:
		get_tree().paused = false

	# If your project uses gameplay locks (it does), always attempt to unlock.
	# This is safe in your project because "unlock_gameplay" just restores control.
	if GameState != null and GameState.has_method("unlock_gameplay"):
		GameState.unlock_gameplay()


func _exit_tree() -> void:
	# If this overlay gets destroyed unexpectedly mid-close, still restore.
	_force_restore_world_state_if_needed()


# -----------------------------------------------------------------------------
# Text helpers
# -----------------------------------------------------------------------------
func _update_sequence_text() -> void:
	var parts: Array[String] = []
	for i in range(_sequence.size()):
		if i < _index:
			parts.append("✓")
		else:
			parts.append(_sequence[i])
	sequence_label.text = " ".join(parts)


func _update_status_text() -> void:
	status_label.text = "Mistakes left: %d" % max(_mistakes_left, 0)
