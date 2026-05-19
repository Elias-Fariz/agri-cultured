extends Resource
class_name NPCDialogueArtData

@export var npc_id: String = ""

# Bottom-left dialogue portrait fallback.
@export var default_portrait: Texture2D

# Full/half-body staged dialogue fallback.
@export var default_stage_pose: Texture2D

# Flexible catalogs.
# Example portrait keys:
# default, happy, sad, nervous
@export var portraits: Array[DialogueArtEntry] = []

# Example stage keys:
# default, happy, nervous, holding_bread, fidget_apron, weapon_ready
@export var stage_poses: Array[DialogueArtEntry] = []


func get_portrait_texture(key: String = "") -> Texture2D:
	var clean_key := _clean_key(key)

	var found := _find_texture_in_entries(portraits, clean_key)
	if found != null:
		return found

	# If someone asks for "happy" and it does not exist, fallback to default.
	if clean_key != "default":
		found = _find_texture_in_entries(portraits, "default")
		if found != null:
			return found

	if default_portrait != null:
		return default_portrait

	return null


func get_stage_texture(key: String = "") -> Texture2D:
	var clean_key := _clean_key(key)

	var found := _find_texture_in_entries(stage_poses, clean_key)
	if found != null:
		return found

	# If the requested pose does not exist, use the default stage pose.
	if clean_key != "default":
		found = _find_texture_in_entries(stage_poses, "default")
		if found != null:
			return found

	if default_stage_pose != null:
		return default_stage_pose

	# Emergency fallback only.
	# This keeps old NPCs working before they have full-body art.
	var portrait_fallback := get_portrait_texture("default")
	if portrait_fallback != null:
		return portrait_fallback

	return null


func _find_texture_in_entries(entries: Array[DialogueArtEntry], key: String) -> Texture2D:
	for entry in entries:
		if entry == null:
			continue
		if entry.get_clean_key() != key:
			continue
		if entry.texture == null:
			continue
		return entry.texture

	return null


func _clean_key(key: String) -> String:
	var k := key.strip_edges().to_lower()
	if k == "":
		return "default"
	return k
