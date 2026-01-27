# HeartVisualBinding.gd
extends Resource
class_name HeartVisualBinding

enum RevealTier { SPROUT, ROOT }

@export var node_path: NodePath

# Option A: milestone check (best long-term)
@export var domain_id: String = ""
@export var milestone_id: String = ""

# Option B: action counter check (current working path)
@export var action_id: String = ""        # e.g. "harvest"
@export var amount_required: int = 0      # e.g. 1

# Option C: stat threshold check (NEW)
@export var stat_key: String = ""         # e.g. "money_earned_total" or "friendship:Mayor"
# uses amount_required too (keeps inspector simple)

# Presentation tier (sprouts vs roots)
@export var reveal_tier: RevealTier = RevealTier.SPROUT
