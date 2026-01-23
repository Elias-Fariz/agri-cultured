# GiftUI.gd
extends BaseOverlay

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var npc_name_label: Label = $Panel/VBox/NPCNameLabel
@onready var item_list: ItemList = $Panel/VBox/ItemList
@onready var reaction_preview: RichTextLabel = $Panel/VBox/ReactionPreview
@onready var give_button: Button = $Panel/VBox/GiveButton
@onready var cancel_button: Button = $Panel/VBox/CancelButton

# Optional: if you added a LineEdit called SearchBox
@onready var search_box: LineEdit = $Panel/VBox/SearchBox if has_node("Panel/VBox/SearchBox") else null

var _npc: Node = null
var _items: Array[String] = []          # sorted item_ids shown
var _index_to_item: Dictionary = {}     # list index -> item_id

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	item_list.item_selected.connect(_on_item_selected)
	give_button.pressed.connect(_on_give_pressed)
	cancel_button.pressed.connect(hide_overlay)

	if search_box != null:
		search_box.text_changed.connect(_refresh_list)

	give_button.disabled = true
	reaction_preview.text = ""

func open_for_npc(npc: Node) -> void:
	_npc = npc
	var name_txt := "Someone"
	if _npc != null and _npc.has_method("get"):
		# if you have display_name variable, you can expose getter later
		pass
	if _npc != null and _npc.has_method("get_npc_id"):
		# we’ll still show friendly name using node name fallback
		name_txt = _npc.name
	npc_name_label.text = "To: " + name_txt

	_refresh_list()
	show_overlay()

func _refresh_list(_unused: String = "") -> void:
	item_list.clear()
	_index_to_item.clear()
	_items.clear()

	var inv: Dictionary = GameState.inventory
	if inv.is_empty():
		reaction_preview.text = "You don’t have anything to give."
		give_button.disabled = true
		return

	var q := ""
	if search_box != null:
		q = search_box.text.strip_edges().to_lower()

	# Build item_ids
	var item_ids: Array[String] = []
	for k in inv.keys():
		var item_id := String(k)
		if int(inv[k]) <= 0:
			continue
		if q != "" and item_id.to_lower().find(q) == -1:
			continue
		item_ids.append(item_id)

	# Sort with gift-tag priority + NPC preference hinting
	item_ids.sort_custom(func(a: String, b: String) -> bool:
		return _compare_items(a, b)
	)

	_items = item_ids

	var idx := 0
	for item_id in _items:
		var count := int(inv.get(item_id, 0))
		item_list.add_item("%s x%d" % [item_id, count])
		_index_to_item[idx] = item_id
		idx += 1

	reaction_preview.text = "Select an item to preview the reaction."
	give_button.disabled = true

func _compare_items(a: String, b: String) -> bool:
	# Higher score first
	var sa := _gift_sort_score(a)
	var sb := _gift_sort_score(b)
	if sa != sb:
		return sa > sb
	# fallback alphabetical
	return a.naturalnocasecmp_to(b) < 0

func _gift_sort_score(item_id: String) -> int:
	var score := 0

	# 1) Gift tag priority (crafted gifts should be tagged "gift")
	var data_a = ItemDb.get_item(item_id) if ItemDb and ItemDb.has_method("get_item") else null
	if data_a != null:
		if data_a.has_method("get_tags"):
			var tags: Array = data_a.call("get_tags")
			if tags.has("gift"):
				score += 100
		elif "tags" in data_a:
			# only if your ItemData is Dictionary-like; if not, ignore
			pass

	# 2) NPC preference hint (if NPC has prefs)
	if _npc != null and _npc.has_method("_gift_reaction_tier"):
		var tier := String(_npc.call("_gift_reaction_tier", item_id))
		match tier:
			"love": score += 50
			"like": score += 25
			"dislike": score -= 10
			"hate": score -= 25

	return score

func _on_item_selected(index: int) -> void:
	if not _index_to_item.has(index):
		return
	var item_id := String(_index_to_item[index])

	reaction_preview.text = _preview_reaction(item_id)
	give_button.disabled = false

func _preview_reaction(item_id: String) -> String:
	if _npc == null:
		return "Gift to: (no NPC selected)"

	if _npc.has_method("_gift_reaction_tier"):
		var tier := String(_npc.call("_gift_reaction_tier", item_id))
		match tier:
			"love": return "Reaction: [b]Loved[/b]"
			"like": return "Reaction: [b]Liked[/b]"
			"dislike": return "Reaction: [b]Disliked[/b]"
			"hate": return "Reaction: [b]Hated[/b]"
	return "Reaction: Neutral"

func _on_give_pressed() -> void:
	var sel := item_list.get_selected_items()
	if sel.is_empty():
		return
	var index := int(sel[0])
	if not _index_to_item.has(index):
		return
	var item_id := String(_index_to_item[index])

	if _npc == null:
		return

	if _npc.has_method("receive_gift"):
		_npc.call("receive_gift", item_id, 1)

	hide_overlay()
