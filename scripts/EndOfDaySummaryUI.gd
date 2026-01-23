extends BaseOverlay

@onready var day_label: Label = $Panel/VBox/DayLabel
@onready var money_label: Label = $Panel/VBox/MoneyLabel
@onready var shipped_text: RichTextLabel = $Panel/VBox/ShippedRichText
@onready var quest_text: RichTextLabel = $Panel/VBox/QuestsScroll/QuestRichText
@onready var unlocked_text: RichTextLabel = $Panel/VBox/UnlockedRichText
@onready var continue_button: Button = $Panel/VBox/ContinueButton

@onready var completed_text: RichTextLabel = $Panel/VBox/CompletedScroll/CompletedRichText


@export var max_listed_items: int = 8

var opened: bool = false

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	continue_button.pressed.connect(_on_continue_pressed)

func show_summary() -> void:
	_refresh()
	opened = true
	super.show_overlay()

func _on_continue_pressed() -> void:
	# Close the overlay first
	opened = false
	super.hide_overlay()

	# Flush on the next frame so the toast isn't "consumed" behind the UI
	call_deferred("_flush_day_start_toasts_deferred")

func _flush_day_start_toasts_deferred() -> void:
	# Wait 1 frame to ensure UI is really gone
	await get_tree().process_frame

	# 1) Show any queued "day start" toasts first
	GameState.flush_day_start_toasts()

	# 2) Next frame, try cutscene (so it doesn't fight with toasts)
	await get_tree().process_frame
	if GameState.has_method("try_play_pending_cutscene"):
		GameState.try_play_pending_cutscene()

func is_open() -> bool:
	return opened

func _refresh() -> void:
	var s: Dictionary = GameState.yesterday_summary
	if s.is_empty():
		day_label.text = "Day ? Summary"
		money_label.text = "Money earned: $0"
		shipped_text.text = "Shipped: (nothing today)"
		unlocked_text.text = "Unlocked: (none)"
		return

	day_label.text = "Day " + str(int(s.get("day_ended", 0))) + " Summary"
	money_label.text = "Money earned: $" + str(int(s.get("money_earned", 0)))

	# --- Shipped list ---
	var shipped: Dictionary = s.get("shipped", {})
	if shipped.is_empty():
		shipped_text.text = "Shipped: (nothing today)"
	else:
		var lines: Array[String] = ["Shipped:"]
		for k in shipped.keys():
			var item_id := String(k)
			var qty := int(shipped[k])
			lines.append("• %s x%d" % [item_id, qty])
		shipped_text.text = "\n".join(lines)

	# --- Unlocked list ---
	var unlocked: Array = s.get("areas_unlocked", [])
	if unlocked.is_empty():
		unlocked_text.text = "Unlocked: (none)"
	else:
		unlocked_text.text = "Unlocked: " + ", ".join(_to_str_array(unlocked))

	var accepted: Array = s.get("quests_accepted", [])
	var completed: Array = s.get("quests_completed", [])
	print("[EOD] accepted=", accepted, " completed=", completed)
	_set_quests_text(accepted, completed)

	# Always scroll to top when opening summary
	var sc := $Panel/VBox/QuestsScroll
	if sc is ScrollContainer:
		sc.scroll_vertical = 0
	
	var sc2 := $Panel/VBox/CompletedScroll
	if sc2 is ScrollContainer:
		sc2.scroll_vertical = 0


func _set_quests_text(accepted: Array, completed: Array) -> void:
	# Completed should "win" over Accepted.
	var accepted_clean: Array[String] = []
	var completed_clean: Array[String] = []

	for v in completed:
		var t := String(v).strip_edges()
		if t != "" and not completed_clean.has(t):
			completed_clean.append(t)

	for v2 in accepted:
		var t2 := String(v2).strip_edges()
		if t2 == "":
			continue
		if completed_clean.has(t2):
			continue
		if not accepted_clean.has(t2):
			accepted_clean.append(t2)

	# --- Accepted block (existing QuestRichText) ---
	var a_lines: Array[String] = ["Accepted:"]
	if accepted_clean.is_empty():
		a_lines.append("• (none)")
	else:
		var shown := 0
		for title in accepted_clean:
			if shown >= max_listed_items:
				break
			a_lines.append("• " + title)
			shown += 1
		if accepted_clean.size() > max_listed_items:
			a_lines.append("• …and %d more" % (accepted_clean.size() - max_listed_items))

	quest_text.text = "\n".join(a_lines)

	# --- Completed block (new CompletedRichText) ---
	var c_lines: Array[String] = ["Completed:"]
	if completed_clean.is_empty():
		c_lines.append("• (none)")
	else:
		var shown2 := 0
		for title2 in completed_clean:
			if shown2 >= max_listed_items:
				break
			c_lines.append("• " + title2)
			shown2 += 1
		if completed_clean.size() > max_listed_items:
			c_lines.append("• …and %d more" % (completed_clean.size() - max_listed_items))

	completed_text.text = "\n".join(c_lines)
	print("[EOD] quest_text final:\n", quest_text.text)
	print("[EOD] completed_text final:\n", completed_text.text)

func _bb_bullets_section(header: String, items: Array) -> Array[String]:
	var out: Array[String] = []
	out.append("[b]%s:[/b]" % _safe_bb(header))

	if items.is_empty():
		out.append("• (none)")
		return out

	var shown := 0
	for v in items:
		if shown >= max_listed_items:
			break
		var title := _safe_bb(String(v))
		if title.strip_edges() == "":
			continue
		out.append("• " + title)
		shown += 1

	if items.size() > max_listed_items:
		out.append("• …and %d more" % (items.size() - max_listed_items))

	# If everything was blank strings somehow, don’t show an empty section
	if shown == 0:
		out.append("• (none)")

	return out


func _safe_bb(s: String) -> String:
	return s.replace("[", "").replace("]", "")


func _to_str_array(a: Array) -> Array[String]:
	var out: Array[String] = []
	for v in a:
		out.append(String(v))
	return out
