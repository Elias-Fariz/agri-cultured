# res://data/shops/ShopCatalogEntry.gd
extends Resource
class_name ShopCatalogEntry

@export var item_id: String = ""                 # Must match ItemDb ID
@export var display_name_override: String = ""   # Optional; blank => use ItemDb or item_id
@export var base_price: int = 0                  # Shop price before discounts
@export var stock_limit: int = -1                # -1 = infinite (we’ll use later)

# Unlock gating (matches your existing quest gating style)
# If requires_completed_quests has entries, the item appears only after those quests are completed.
@export var requires_completed_quests: PackedStringArray = PackedStringArray()

# Extra “tags” for future rules (seasonal promos, category pricing, etc.)
@export var tags: PackedStringArray = PackedStringArray()

# Optional: day-based gating (nice to have; safe to ignore if left 0)
@export var requires_day_min: int = 0

func is_valid() -> bool:
	return item_id.strip_edges() != "" and base_price >= 0
