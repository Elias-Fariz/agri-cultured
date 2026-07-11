extends BaseOverlay

@onready var day_label: Label = $Root/Panel/VBox/DayLabel
@onready var money_label: Label = $Root/Panel/VBox/MoneyLabel
@onready var shipped_text: RichTextLabel = $Root/Panel/VBox/ShippedRichText
@onready var quest_text: RichTextLabel = $Root/Panel/VBox/QuestsScroll/QuestRichText
@onready var unlocked_text: RichTextLabel = $Root/Panel/VBox/UnlockedRichText
@onready var continue_button: Button = $Root/Panel/VBox/ContinueButton
@onready var completed_text: RichTextLabel = $Root/Panel/VBox/CompletedScroll/CompletedRichText

@onready var background_texture: TextureRect = $Root/BackgroundTexture
@onready var dimmer: ColorRect = $Root/Dimmer

@export var summary_background: Texture2D
@export_range(0.0, 1.0, 0.05) var dim_amount: float = 0.45

@export var max_listed_items: int = 8
@export var debug_enabled: bool = true

@export var continue_fade_out_time: float = 0.18
@export var morning_fade_in_time: float = 0.35

var opened: bool = false
var _closing: bool = false


func _ready() -> void:
	super._ready()
	if background_texture != null:
		background_texture.texture = summary_background

	if dimmer != null:
		dimmer.color = Color(0, 0, 0, dim_amount)
	
	if Engine.is_editor_hint():
		return

	continue_button.pressed.connect(_on_continue_pressed)


func show_summary() -> void:
	_closing = false
	_refresh()
	opened = true
	super.show_overlay()

	await get_tree().process_frame
	if continue_button != null:
		continue_button.grab_focus()


func _on_continue_pressed() -> void:
	if _closing:
		return

	_closing = true

	if FadeOverlay != null:
		await FadeOverlay.fade_out(continue_fade_out_time)

	opened = false
	super.hide_overlay()

	await get_tree().process_frame

	if FadeOverlay != null:
		await FadeOverlay.fade_in(morning_fade_in_time)

	if GameState != null and GameState.has_method("unlock_gameplay"):
		GameState.unlock_gameplay()

	if TimeManager != null:
		TimeManager.resume_time()

	call_deferred("_flush_day_start_toasts_deferred")

	_closing = false


func _flush_day_start_toasts_deferred() -> void:
	await get_tree().process_frame
	GameState.flush_day_start_toasts()

	await get_tree().process_frame
	if GameState.has_method("try_play_pending_cutscene"):
		GameState.try_play_pending_cutscene()


func is_open() -> bool:
	return opened


func _refresh() -> void:
	var s: Dictionary = {}
	if GameState != null and ("yesterday_summary" in GameState):
		s = GameState.yesterday_summary

	if debug_enabled:
		print("[EOD UI] yesterday_summary=", s)

	if s == null or s.is_empty():
		day_label.text = "Day ? Summary"
		money_label.text = "Money earned: $0"
		shipped_text.text = "Shipped: (nothing today)"
		unlocked_text.text = "Unlocked: (none)"
		quest_text.text = "Accepted:\n• (none)"
		completed_text.text = "Completed:\n• (none)"
		return

	var day_ended := int(s.get("day_ended", s.get("day", s.get("day_index", 0))))
	day_label.text = "Day " + str(day_ended) + " Summary"

	var money_earned := int(s.get("money_earned", s.get("payout", s.get("money", 0))))
	money_label.text = "Money earned: $" + str(money_earned)

	var shipped: Dictionary = s.get("shipped", s.get("shipped_items", s.get("shipping", {})))
	if shipped == null:
		shipped = {}

	if shipped.is_empty():
		shipped_text.text = "Shipped: (nothing today)"
	else:
		var lines: Array[String] = []
		lines.append("Shipped:")
		for k in shipped.keys():
			var item_id := String(k)
			var qty := int(shipped[k])
			lines.append("• %s x%d" % [item_id, qty])

		var base_total := int(s.get("ship_base_total", -1))
		var final_total := int(s.get("ship_final_total", -1))
		var bonus := int(s.get("ship_heart_bonus", 0))
		var mul := float(s.get("ship_heart_mul", 1.0))

		if final_total < 0:
			final_total = int(s.get("payout", -1))

		if bonus <= 0 and final_total >= 0 and mul > 1.0:
			var est_base := int(round(float(final_total) / mul))
			var est_bonus: Variant = max(0, final_total - est_base)
			base_total = est_base if base_total < 0 else base_total
			bonus = est_bonus

		if bonus > 0 and final_total >= 0:
			lines.append("")
			if base_total >= 0:
				lines.append("Shipped Total: %dg" % base_total)
			lines.append("Valley Heart Blessing (x%.2f): +%dg" % [mul, bonus])
			lines.append("Payout: %dg" % final_total)

		shipped_text.text = "\n".join(lines)

	var unlocked: Array = s.get("areas_unlocked", s.get("unlocked", s.get("unlocks", [])))
	if unlocked == null:
		unlocked = []

	if unlocked.is_empty():
		unlocked_text.text = "Unlocked: (none)"
	else:
		unlocked_text.text = "Unlocked: " + ", ".join(_to_str_array(unlocked))

	var accepted: Array = s.get("quests_accepted", s.get("accepted", []))
	var completed: Array = s.get("quests_completed", s.get("completed", []))
	_set_quests_text(accepted, completed)

	var sc := $Root/Panel/VBox/QuestsScroll
	if sc is ScrollContainer:
		sc.scroll_vertical = 0

	var sc2 := $Root/Panel/VBox/CompletedScroll
	if sc2 is ScrollContainer:
		sc2.scroll_vertical = 0


func _set_quests_text(accepted: Array, completed: Array) -> void:
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


func _to_str_array(a: Array) -> Array[String]:
	var out: Array[String] = []
	for v in a:
		out.append(String(v))
	return out
