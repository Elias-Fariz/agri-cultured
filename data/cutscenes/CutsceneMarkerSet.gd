extends Resource
class_name CutsceneMarkerSet

@export var markers: Array[CutsceneMarkerRef] = []

# --- Legacy fields (keep so heart_intro.tres still works) ---
@export var player_spot: NodePath
@export var npc_spots: Dictionary = {}     # npc_key -> NodePath
@export var camera_focus: NodePath

# NEW name to avoid signature conflicts with any parent/tooling.
func resolve_marker(marker_id: String) -> NodePath:
	marker_id = marker_id.strip_edges()
	if marker_id == "":
		return NodePath()

	# 1) New marker library
	for m in markers:
		if m != null and String(m.id) == marker_id:
			return m.path

	# 2) Legacy convenience aliases
	if marker_id == "player_spot":
		return player_spot
	if marker_id == "camera_focus":
		return camera_focus

	# Optional: legacy npc_spots lookup by id
	if npc_spots != null and npc_spots.has(marker_id):
		var v: Variant = npc_spots[marker_id]
		if v is NodePath:
			return v

	return NodePath()
