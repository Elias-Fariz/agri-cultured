# res://ui/HeartProgressUI.gd
extends BaseOverlay
class_name HeartProgressUI

@onready var title_label: Label = $Panel/Margin/Root/Header/Title
@onready var subtitle_label: Label = $Panel/Margin/Root/Header/Subtitle

@onready var active_text: RichTextLabel = $Panel/Margin/Root/Body/LeftCol/ActiveText
@onready var next_text: RichTextLabel = $Panel/Margin/Root/Body/RightCol/NextText

@onready var progress_bar: ProgressBar = $Panel/Margin/Root/Body/RightCol/ProgressBar
@onready var progress_detail: Label = $Panel/Margin/Root/Body/RightCol/ProgressDetail

@onready var hint_label: Label = $Panel/Margin/Root/Footer/Hint
@onready var close_button: Button = $Panel/Margin/Root/Footer/CloseButton
@onready var close_hint: Label = $Panel/Margin/Root/CloseHint

# NEW: If empty => show “all domains”. If "land" => show only land.
var domain_filter: String = ""

var _opened := false

func set_domain(domain_id: String) -> void:
	domain_filter = domain_id.strip_edges()
	_refresh()

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	close_button.pressed.connect(hide_overlay)

	active_text.bbcode_enabled = true
	next_text.bbcode_enabled = true
	active_text.scroll_active = false
	next_text.scroll_active = false

	var hp := get_node_or_null("/root/HeartProgress")
	if hp != null and hp.has_signal("changed"):
		var cb := Callable(self, "_refresh")
		if not hp.is_connected("changed", cb):
			hp.connect("changed", cb)

	_refresh()

func show_overlay() -> void:
	_opened = true
	_refresh()
	super.show_overlay()

func hide_overlay() -> void:
	_opened = false
	super.hide_overlay()

func _unhandled_input(event: InputEvent) -> void:
	if not _opened:
		return
	if event.is_action_pressed("ui_cancel"):
		hide_overlay()
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	var hp := get_node_or_null("/root/HeartProgress")
	if hp == null:
		title_label.text = "Valley Heart"
		subtitle_label.text = "The Heart is sleeping…"
		active_text.text = "[i](HeartProgress not found)[/i]"
		next_text.text = "[i]No guidance yet.[/i]"
		progress_bar.max_value = 1
		progress_bar.value = 0
		progress_detail.text = ""
		return

	# Title changes depending on domain filter
	if domain_filter == "":
		title_label.text = "Valley Heart"
		subtitle_label.text = "All blessings, gathered in one warm place."
	else:
		title_label.text = "Valley Heart — " + _pretty_domain_name(domain_filter)
		subtitle_label.text = "This wing grows with you, one gentle step at a time."

	close_hint.text = "Press Esc to close"
	hint_label.text = "Sprouts are quick… Roots take time… and you’re doing wonderfully."

	_refresh_active_blessings(hp)
	_refresh_next_blessing(hp)

func _pretty_domain_name(domain_id: String) -> String:
	match domain_id:
		"land": return "Land Wing"
		"sea": return "Sea Wing"
		"people": return "People Wing"
		"craft": return "Craft Wing"
		_: return domain_id.capitalize()

func _refresh_active_blessings(hp: Node) -> void:
	# NOTE:
	# These are global “effect getters” right now (sell multiplier, shop discount, etc.).
	# In the future, you can add per-domain grouping if you want,
	# but for now we’ll still list them, and we’ll label them nicely.
	var sell_mul := 1.0
	var shop_mul := 1.0
	var sleep_bonus := 0

	if hp.has_method("get_sell_multiplier"):
		sell_mul = float(hp.call("get_sell_multiplier"))
	if hp.has_method("get_shop_discount_multiplier"):
		shop_mul = float(hp.call("get_shop_discount_multiplier"))
	if hp.has_method("get_energy_bonus_on_sleep"):
		sleep_bonus = int(hp.call("get_energy_bonus_on_sleep"))

	var lines: Array[String] = []
	lines.append("[b]Active Blessings[/b]")
	lines.append("[color=#bbbbbb]Tiny changes add up. The Heart rewards gentle consistency.[/color]")
	lines.append("")

	var any := false

	if sell_mul > 1.0001:
		any = true
		var pct := int(round((sell_mul - 1.0) * 100.0))
		lines.append("• [b]Harvest’s Gratitude[/b]: +%d%% shipping payout [color=#bbbbbb](x%.2f)[/color]" % [pct, sell_mul])

	if shop_mul < 0.9999:
		any = true
		var pct2 := int(round((1.0 - shop_mul) * 100.0))
		lines.append("• [b]Gentle Bargain[/b]: %d%% cheaper shop prices [color=#bbbbbb](x%.2f)[/color]" % [pct2, shop_mul])

	if sleep_bonus > 0:
		any = true
		lines.append("• [b]Restful Warmth[/b]: +%d energy when you sleep in bed" % sleep_bonus)

	if not any:
		lines.append("• [i](None yet)[/i]")
		lines.append("")
		lines.append("[color=#bbbbbb]Tip: Keep going at your pace. The Heart notices your effort.[/color]")

	active_text.text = "\n".join(lines)

func _refresh_next_blessing(hp: Node) -> void:
	var next_m: Resource = _find_next_incomplete_milestone(hp, domain_filter)
	if next_m == null:
		next_text.text = "[b]Next Blessing[/b]\n\n[i]You’ve reached everything currently defined for this wing.\nThe Heart is quietly proud of you.[/i]"
		progress_bar.max_value = 1
		progress_bar.value = 1
		progress_detail.text = "Complete"
		if domain_filter == "":
			hint_label.text = "You did it… take a breath. The Heart will be here when new paths open."
		else:
			hint_label.text = "This wing is blooming. When you’re ready, explore another one."
		return

	var required := int(next_m.required_amount)
	var counter_key := String(next_m.counter_key)
	var filter_item := String(next_m.filter_item_id)
	var hint := String(next_m.hint).strip_edges()

	var have := 0
	if filter_item != "":
		if hp.has_method("get_item_count"):
			have = int(hp.call("get_item_count", filter_item))
	else:
		if hp.has_method("get_count"):
			have = int(hp.call("get_count", counter_key))

	progress_bar.max_value = max(1, required)
	progress_bar.value = clamp(have, 0, required)
	progress_detail.text = "%d / %d" % [min(have, required), required]

	var requirement := _pretty_requirement(counter_key, required, filter_item)
	var reward_preview := _describe_rewards_for_milestone(hp, next_m)

	var lines: Array[String] = []
	lines.append("[b]Next Blessing[/b]")
	lines.append("[color=#bbbbbb]A gentle promise, waiting for your next small step.[/color]")
	lines.append("")
	lines.append("[b]To awaken it:[/b] " + requirement)
	lines.append("")
	lines.append("[b]You’ll receive:[/b]")
	if reward_preview.strip_edges() != "":
		lines.append(reward_preview)
	else:
		lines.append("• [i](No reward_ids set for this milestone yet)[/i]")

	next_text.text = "\n".join(lines)

	if hint != "":
		hint_label.text = hint
	else:
		hint_label.text = "No rush. The Heart isn’t measuring speed—only steadiness."

func _pretty_requirement(counter_key: String, required: int, filter_item: String) -> String:
	var key := counter_key.strip_edges()

	var verb := "Do"
	if key.find("harvest") != -1:
		verb = "Harvest"
	elif key.find("ship") != -1:
		verb = "Ship"
	elif key.find("craft") != -1:
		verb = "Craft"
	elif key.find("gift") != -1:
		verb = "Gift"

	if filter_item != "":
		return "%s [b]%d[/b] × [b]%s[/b]" % [verb, required, filter_item]

	if key == "":
		return "Complete [b]%d[/b] steps" % required

	return "%s [b]%d[/b] time(s)" % [verb, required]

func _find_next_incomplete_milestone(hp: Node, filter_domain: String) -> Resource:
	if not ("definition" in hp):
		return null
	var def: Resource = hp.get("definition")
	if def == null:
		return null
	if not ("milestones" in def):
		return null

	var list: Array = def.get("milestones")
	if list == null or list.is_empty():
		return null

	var milestones: Array = list.duplicate()

	milestones.sort_custom(func(a, b):
		if a == null or b == null:
			return false
		var ad := String(a.domain_id)
		var bd := String(b.domain_id)
		if ad != bd:
			return ad < bd
		return int(a.order) < int(b.order)
	)

	for m in milestones:
		if m == null:
			continue

		var domain_id := String(m.domain_id)
		var milestone_id := String(m.id)
		if domain_id == "" or milestone_id == "":
			continue

		if filter_domain != "" and domain_id != filter_domain:
			continue

		if hp.has_method("has_milestone"):
			if bool(hp.call("has_milestone", domain_id, milestone_id)) == false:
				return m

	return null

func _describe_rewards_for_milestone(hp: Node, milestone: Resource) -> String:
	if milestone == null:
		return ""

	var reward_ids: Array = milestone.reward_ids
	if reward_ids == null or reward_ids.is_empty():
		return ""

	var catalog
	if "reward_catalog" in hp:
		catalog = hp.get("reward_catalog")
	if catalog == null:
		return "• [i](Reward catalog not loaded)[/i]"

	var rewards_arr: Array = []
	if "rewards" in catalog:
		rewards_arr = catalog.get("rewards")
	if rewards_arr == null:
		rewards_arr = []

	var out_lines: Array[String] = []
	for rid_any in reward_ids:
		var rid := str(rid_any)
		if rid == "":
			continue

		var rdef := _find_reward_def_by_id(rewards_arr, rid)
		if rdef == null:
			out_lines.append("• [i]%s[/i] [color=#bbbbbb](not found in heart_rewards.tres)[/color]" % rid)
			continue

		var desc := String(rdef.description).strip_edges()
		if desc == "":
			desc = "A blessing unfolds."
		out_lines.append("• " + desc)

	return "\n".join(out_lines)

func _find_reward_def_by_id(rewards_arr: Array, rid: String) -> Resource:
	for r in rewards_arr:
		if r == null:
			continue
		if str(r.id) == rid:
			return r
	return null
