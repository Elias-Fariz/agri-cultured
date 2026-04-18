extends Interactable
class_name ShopCounter

@export var shop_title: String = "Shop"
@export var shop_id: String = "GeneralStore"

@export var shop_open_hour: int = 9
@export var shop_close_hour: int = 18

@export var shop_closed_lines: Array[String] = [
	"Sorry, we’re closed for the day.",
	"Come back tomorrow during business hours!"
]

# Optional future hook:
# leave blank for now unless you want to require a specific NPC to be present later
@export var required_shopkeeper_npc_id: String = ""

func _do_interact() -> void:
	var hour := int(TimeManager.minutes / 60)

	if hour < shop_open_hour or hour >= shop_close_hour:
		_show_closed_dialogue()
		return

	# Optional future behavior:
	# if you later want the shop to only work when a shopkeeper is present,
	# this is where we would check for that NPC.

	var shop_ui := get_tree().get_first_node_in_group("shop_ui")
	if shop_ui == null:
		push_warning("ShopCounter: No node in group 'shop_ui' found.")
		return

	# Optional title support
	if shop_ui.has_method("set_title"):
		shop_ui.call("set_title", shop_title)

	# Optional shop_id support for seasonal or different shops
	if "shop_id" in shop_ui:
		shop_ui.shop_id = shop_id
	elif shop_ui.has_method("set_shop_id"):
		shop_ui.call("set_shop_id", shop_id)

	if shop_ui.has_method("show_overlay"):
		shop_ui.call("show_overlay")

func _show_closed_dialogue() -> void:
	var ui := get_tree().get_first_node_in_group("dialogue_ui")
	if ui == null:
		push_warning("ShopCounter: No node in group 'dialogue_ui' found.")
		return

	var lines := shop_closed_lines
	if lines.is_empty():
		lines = ["Sorry, we’re closed right now. Come back tomorrow!"]

	# No friendship / NPC id context needed for a simple counter message
	ui.show_dialogue(shop_title, lines, 0, "")
