extends Node

# ---------------------------------------------------------
# Tutorial Hint Manager
# ---------------------------------------------------------
# Decides WHEN a contextual hint should appear.
#
# For now, hints reuse the normal ToastManager through
# QuestEvents.toast_requested.
#
# Later, "tutorial" kind can receive its own visual style,
# icon, sound, animation, etc.
# ---------------------------------------------------------

const SEEN_FLAG_PREFIX := "tutorial_hint_seen:"

# Prevent several scrapbook discoveries granted on the same
# cutscene frame from creating a wall of notifications.
const SCRAPBOOK_NOTICE_COOLDOWN_MSEC := 1200

var _last_scrapbook_notice_msec: int = -999999


# ---------------------------------------------------------
# Alpha 02 hint library
# ---------------------------------------------------------

var hints: Dictionary = {
	"inventory": {
		"text": "You're carrying something.\nPress T to open your inventory.",
		"duration": 4.0,
	},

	"seed_pouch": {
		"text": "Seed Pouch\nUse it on tilled soil to plant your selected seed.",
		"duration": 4.0,
	},

	"seed_switch": {
		"text": "You have more than one kind of seed.\nUse the seed-switch control to choose between them.",
		"duration": 4.5,
	},

	"shipping_bin": {
		"text": "Shipping Bin\nItems placed here are sold at the end of the day.",
		"duration": 4.0,
	},

	"scrapbook_intro": {
		"text": "Your scrapbook has something new.\nPress J to see what you've learned.",
		"duration": 4.5,
	},
}


# ---------------------------------------------------------
# Public API
# ---------------------------------------------------------

func request_hint(hint_id: String) -> bool:
	hint_id = hint_id.strip_edges()

	if hint_id == "":
		return false

	if has_seen_hint(hint_id):
		return false

	if not hints.has(hint_id):
		push_warning(
			"[TutorialHintManager] Unknown hint id: " + hint_id
		)
		return false

	var data: Dictionary = Dictionary(hints[hint_id])

	var text := String(data.get("text", "")).strip_edges()
	var duration := float(data.get("duration", 3.5))

	if text == "":
		return false

	# Mark BEFORE displaying so rapid duplicate events cannot
	# create several copies of the same tutorial.
	mark_hint_seen(hint_id)

	_emit_hint(text, duration)

	return true


func request_custom_hint(
	hint_id: String,
	text: String,
	duration: float = 3.5
) -> bool:
	hint_id = hint_id.strip_edges()
	text = text.strip_edges()

	if hint_id == "" or text == "":
		return false

	if has_seen_hint(hint_id):
		return false

	mark_hint_seen(hint_id)

	_emit_hint(text, duration)

	return true


func has_seen_hint(hint_id: String) -> bool:
	hint_id = hint_id.strip_edges()

	if hint_id == "":
		return false

	if GameState == null:
		return false

	return GameState.has_flag(
		SEEN_FLAG_PREFIX + hint_id
	)


func mark_hint_seen(hint_id: String) -> void:
	hint_id = hint_id.strip_edges()

	if hint_id == "":
		return

	if GameState == null:
		return

	GameState.set_flag(
		SEEN_FLAG_PREFIX + hint_id,
		true
	)


# ---------------------------------------------------------
# Scrapbook helpers
# ---------------------------------------------------------

func notify_scrapbook_discovery(
	character_id: String,
	is_full_meeting: bool = true
) -> void:
	character_id = character_id.strip_edges()

	if character_id == "":
		return

	var now := Time.get_ticks_msec()

	if (
		now - _last_scrapbook_notice_msec
		< SCRAPBOOK_NOTICE_COOLDOWN_MSEC
	):
		return

	_last_scrapbook_notice_msec = now

	var display_name := _get_character_display_name(
		character_id
	)

	if not has_seen_hint("scrapbook_intro"):
		mark_hint_seen("scrapbook_intro")

		_show_scrapbook_intro_delayed(
			display_name
		)
		return

	if is_full_meeting:
		_emit_hint(
			"Scrapbook updated: " + display_name,
			2.8
		)
	else:
		_emit_hint(
			"A new name found its way into your scrapbook.",
			2.8
		)


func _get_character_display_name(character_id: String) -> String:
	match character_id:
		"npc_mayor":
			return "Mayor Alder"

		"npc_tansy":
			return "Tansy"

		"npc_maren":
			return "Maren"

		"npc_ash":
			return "Ash"

	return character_id.replace("_", " ").capitalize()


# ---------------------------------------------------------
# Output
# ---------------------------------------------------------

func _emit_hint(text: String, duration: float) -> void:
	if QuestEvents == null:
		return

	if not QuestEvents.has_signal("toast_requested"):
		return

	QuestEvents.toast_requested.emit(
		text,
		"tutorial",
		duration
	)

func _show_scrapbook_intro_delayed(
	display_name: String
) -> void:
	await get_tree().create_timer(1.25).timeout

	_emit_hint(
		"Scrapbook updated: %s\nPress J to see what you've learned."
		% display_name,
		4.5
	)
