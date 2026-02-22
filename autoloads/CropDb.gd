# res://crops/CropDb.gd
extends Node

@export var crops: Array[CropData] = []  # drag your CropData resources here

var _by_id: Dictionary = {} # crop_id -> CropData

func _ready() -> void:
	_rebuild_index()

func _rebuild_index() -> void:
	_by_id.clear()
	for c in crops:
		if c == null:
			continue
		var id := c.crop_id.strip_edges()
		if id == "":
			continue
		_by_id[id] = c

func get_crop(crop_id: String) -> CropData:
	return _by_id.get(crop_id, null)

func is_allowed_in_season(crop: CropData, season_name: String) -> bool:
	if crop == null:
		return false
	if crop.allowed_seasons.is_empty():
		return true
	return crop.allowed_seasons.has(season_name)

func get_effective_stage_days(crop: CropData, stage_index: int, season_name: String) -> int:
	if crop == null:
		return 1
	var base := 1
	if stage_index >= 0 and stage_index < crop.days_per_stage.size():
		base = int(crop.days_per_stage[stage_index])
	base = max(1, base)

	if season_name == "Sunwake":
		base = max(1, base - int(crop.sunwake_stage_days_bonus))
	elif season_name == "Duskhaven":
		base = base + int(crop.duskhaven_stage_days_penalty)

	return max(1, base)

func should_chill_today(crop: CropData, season_name: String) -> bool:
	if crop == null:
		return false
	if season_name != "Duskhaven":
		return false
	var p := clampf(crop.duskhaven_chill_chance, 0.0, 1.0)
	return randf() < p

func get_harvest_item(crop: CropData, stage_index: int) -> String:
	if crop == null:
		return ""

	if crop.harvest_items_by_stage.size() > 0 and crop.harvest_items_by_stage.has(stage_index):
		return String(crop.harvest_items_by_stage[stage_index])

	return crop.harvest_item

func get_harvest_yield(crop: CropData, stage_index: int, season_name: String) -> int:
	if crop == null:
		return 1

	var qty := 1

	# stage-specific yield overrides
	if crop.harvest_yields_by_stage.size() > 0 and crop.harvest_yields_by_stage.has(stage_index):
		qty = int(crop.harvest_yields_by_stage[stage_index])
	elif crop.harvest_yield_min > 0 or crop.harvest_yield_max > 0:
		var mn :Variant= max(0, crop.harvest_yield_min)
		var mx :Variant= max(mn, crop.harvest_yield_max)
		qty = randi_range(mn, mx)
	else:
		qty = max(1, crop.harvest_yield)

	# seasonal multiplier (round to feel fair)
	var mul := 1.0
	if season_name == "Sunwake":
		mul = crop.sunwake_yield_multiplier
	elif season_name == "Duskhaven":
		mul = crop.duskhaven_yield_multiplier

	var final_qty := int(round(float(qty) * max(0.01, mul)))
	return max(1, final_qty)

func get_ripe_stage(crop: CropData) -> int:
	if crop == null:
		return -1
	if crop.ripe_stage >= 0:
		return crop.ripe_stage
	return crop.stage_atlas_coords.size() - 1

func get_overripe_stage(crop: CropData) -> int:
	if crop == null:
		return -1
	return crop.overripe_stage
