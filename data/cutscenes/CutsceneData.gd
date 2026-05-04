extends Resource
class_name CutsceneData

@export var id: String = ""
@export var scene_name: String = ""

@export var actors: Array[CutsceneActorData] = []
@export var markers: CutsceneMarkerSet
@export var dialogue: CutsceneDialogueData
@export var effects: Array[CutsceneEffectData] = []

# Gate for cinematic steps
@export var steps: Array[CutsceneStepData] = []

# -------------------------------------------------------------------
# Rewards granted when this cutscene finishes successfully.
# These use the same reward language as QuestData:
# money, items, flags, tools, and spawns.
# -------------------------------------------------------------------

@export_group("Completion Rewards")

@export var reward_money: int = 0
@export var reward_items: Dictionary[String, int] = {}
@export var reward_flags: Array[String] = []
@export var reward_tool_ids: Array[String] = []

@export var reward_crafting_recipe_ids: Array[String] = []
@export var reward_cooking_recipe_ids: Array[String] = []

# Optional: cutscene can start/accept quests directly.
# Example: after a Heart scene, immediately add a follow-up quest.
@export var reward_quests: Array[QuestData] = []

# Optional: scene spawns, same style as quest rewards.
@export var reward_spawns: Array[QuestSpawnRewardData] = []

# If true, this cutscene's completion rewards are only granted once per cutscene id.
# Recommended true for almost everything.
@export var rewards_once: bool = true


func get_completion_reward_dict() -> Dictionary:
	var reward: Dictionary = {}

	if reward_money > 0:
		reward["money"] = reward_money

	if reward_items.size() > 0:
		reward["items"] = reward_items

	if reward_flags.size() > 0:
		reward["flags"] = reward_flags.duplicate()

	if reward_tool_ids.size() > 0:
		reward["tools"] = reward_tool_ids.duplicate()
		
	if reward_crafting_recipe_ids.size() > 0:
		reward["crafting_recipes"] = reward_crafting_recipe_ids.duplicate()

	if reward_cooking_recipe_ids.size() > 0:
		reward["cooking_recipes"] = reward_cooking_recipe_ids.duplicate()

	var spawn_dicts: Array = []
	for spawn_reward in reward_spawns:
		if spawn_reward != null and spawn_reward.is_valid():
			spawn_dicts.append(spawn_reward.to_dict())

	if spawn_dicts.size() > 0:
		reward["spawns"] = spawn_dicts

	return reward


func has_completion_rewards() -> bool:
	if reward_money > 0:
		return true
	if reward_items.size() > 0:
		return true
	if reward_flags.size() > 0:
		return true
	if reward_tool_ids.size() > 0:
		return true
	if reward_spawns.size() > 0:
		return true
	if reward_quests.size() > 0:
		return true
	if reward_crafting_recipe_ids.size() > 0:
		return true
	if reward_cooking_recipe_ids.size() > 0:
		return true

	return false
