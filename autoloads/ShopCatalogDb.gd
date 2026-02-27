# res://autoloads/ShopCatalogDb.gd
extends Node

# Drag your ShopCatalogData .tres files into this array in the Inspector
@export var catalogs: Array[ShopCatalogData] = []

# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------
func get_shop_items(shop_id: String) -> Array:
	# Returns Array[Dictionary] shaped like your existing ShopUI expects:
	# { "id": item_id, "name": display_name, "price": base_price }
	var season := _get_current_season_int()
	var cat := _find_best_catalog(shop_id, season)

	if cat == null:
		return []

	var out: Array = []
	for e in cat.entries:
		if e == null:
			continue
		if not e.is_valid():
			continue
		if not _is_entry_unlocked(e):
			continue

		var item_id := e.item_id
		var display_name := _resolve_display_name(e)
		var price := int(e.base_price)

		out.append({
			"id": item_id,
			"name": display_name,
			"price": price
		})

	return out

# -------------------------------------------------------------------
# Catalog selection
# -------------------------------------------------------------------
func _find_best_catalog(shop_id: String, season: int) -> ShopCatalogData:
	var any_match: ShopCatalogData = null

	for c in catalogs:
		if c == null:
			continue
		if String(c.shop_id) != shop_id:
			continue

		# Exact season match wins immediately
		if int(c.season) == season:
			return c

		# Keep a fallback "Any season" if present
		if int(c.season) == -1:
			any_match = c

	return any_match

func _get_current_season_int() -> int:
	if CalendarSystem != null and CalendarSystem.has_method("get_season"):
		return int(CalendarSystem.get_season())
	# Safe fallback
	return 0

# -------------------------------------------------------------------
# Unlock filtering (matches your current quest pattern)
# -------------------------------------------------------------------
func _is_entry_unlocked(e: ShopCatalogEntry) -> bool:
	# Day gate (optional)
	if e.requires_day_min > 0 and TimeManager != null:
		if int(TimeManager.day) < int(e.requires_day_min):
			return false

	# Quest prereqs (safe + matches your QuestData gating approach)
	if not e.requires_completed_quests.is_empty():
		if GameState == null:
			return false
		for qid in e.requires_completed_quests:
			var quest_id := String(qid).strip_edges()
			if quest_id == "":
				continue
			# IMPORTANT: We do NOT modify completed_quests; we only read it.
			if not GameState.completed_quests.has(quest_id):
				return false

	return true

# -------------------------------------------------------------------
# Display name resolution
# -------------------------------------------------------------------
func _resolve_display_name(e: ShopCatalogEntry) -> String:
	if e.display_name_override.strip_edges() != "":
		return e.display_name_override

	# Try ItemDb (if it has a name/display_name field), otherwise fallback to item_id
	if ItemDb != null and ItemDb.has_method("get_item"):
		var data = ItemDb.get_item(e.item_id)
		if data != null:
			# Support either data.display_name or data.name if present
			if data is Resource:
				var dn := str(data.get("display_name"))
				if dn.strip_edges() != "":
					return dn
				var n := str(data.get("name"))
				if n.strip_edges() != "":
					return n

	return e.item_id
