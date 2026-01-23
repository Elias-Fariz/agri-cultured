# NPCGiftPreferences.gd
extends Resource
class_name NPCGiftPreferences

# --------------------------------------------------------------------
# Specific item overrides (highest priority)
# Store ITEM IDs here (e.g., "Shell Necklace", "Flower", "Apple")
# --------------------------------------------------------------------
@export var loves: Array[String] = []
@export var likes: Array[String] = []
@export var dislikes: Array[String] = []
@export var hates: Array[String] = []

# --------------------------------------------------------------------
# Tag-based preferences (broad rules, lower priority than item overrides)
# Store TAGS here (e.g., "fish", "mineral", "crafted", "forage", "flower")
# Tags are matched case-insensitively.
# --------------------------------------------------------------------
@export var loves_tags: Array[String] = []
@export var likes_tags: Array[String] = []
@export var dislikes_tags: Array[String] = []
@export var hates_tags: Array[String] = []

# Optional: reaction lines (kept short, NPC flavor)
@export var loved_lines: Array[String] = ["Oh! This is my favorite! Thank you!"]
@export var liked_lines: Array[String] = ["Aw, thank you! I like this."]
@export var neutral_lines: Array[String] = ["Thanks!"]
@export var disliked_lines: Array[String] = ["Oh… I’ll… take it, I guess."]
@export var hated_lines: Array[String] = ["…Please don’t give me this again."]

# --------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------

func get_reaction_tier_for_item(item_id: String, item_tags: Array[String]) -> String:
	# Normalize
	var id := _norm(item_id)
	print(item_tags)

	# 1) Specific item overrides (always win)
	if _contains_norm(loves, id):
		return "love"
	if _contains_norm(likes, id):
		return "like"
	if _contains_norm(hates, id):
		return "hate"
	if _contains_norm(dislikes, id):
		return "dislike"

	# 2) Tag-based preferences (broad rules)
	# Normalize tags once
	var tags_norm: Array[String] = []
	for t in item_tags:
		var tn := _norm(t)
		if tn != "":
			tags_norm.append(tn)

	if _any_tag_matches(loves_tags, tags_norm):
		return "love"
	if _any_tag_matches(likes_tags, tags_norm):
		return "like"
	if _any_tag_matches(hates_tags, tags_norm):
		return "hate"
	if _any_tag_matches(dislikes_tags, tags_norm):
		return "dislike"

	# 3) Default
	return "neutral"


func get_lines_for_tier(tier: String) -> Array[String]:
	match tier:
		"love": return loved_lines
		"like": return liked_lines
		"dislike": return disliked_lines
		"hate": return hated_lines
		_: return neutral_lines


# --------------------------------------------------------------------
# Helpers (no has_variable(), no editor-only trickery)
# --------------------------------------------------------------------

func _norm(s: String) -> String:
	return (s if s != null else "").strip_edges().to_lower()

func _contains_norm(arr: Array[String], needle_norm: String) -> bool:
	if needle_norm == "":
		return false
	for v in arr:
		if _norm(v) == needle_norm:
			return true
	return false

func _any_tag_matches(pref_tags: Array[String], tags_norm: Array[String]) -> bool:
	if pref_tags.is_empty() or tags_norm.is_empty():
		return false

	# Build a small set for faster lookup (tags list is usually small anyway)
	var pref_set: Dictionary = {}
	for pt in pref_tags:
		var ptn := _norm(pt)
		if ptn != "":
			pref_set[ptn] = true

	for tn in tags_norm:
		if pref_set.has(tn):
			return true

	return false
