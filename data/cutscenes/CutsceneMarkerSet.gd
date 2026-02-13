# res://data/cutscenes/CutsceneMarkerSet.gd
extends Resource
class_name CutsceneMarkerSet

# The key idea:
# - markers_by_id maps "lia_start" -> NodePath("CutsceneMarkers/LiaStart")
# - steps reference marker IDs (strings), not raw NodePaths.
@export var markers_by_id: Dictionary = {}  # String -> NodePath

func get_marker_path(marker_id: String) -> NodePath:
	marker_id = marker_id.strip_edges()
	if marker_id == "":
		return NodePath("")
	if not markers_by_id.has(marker_id):
		return NodePath("")
	var v: Variant = markers_by_id[marker_id]
	if v is NodePath:
		return v
	return NodePath("")
