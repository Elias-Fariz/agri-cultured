extends CharacterBody2D

@export var npc_id: String = "npc_mayor"

@export var display_name: String
@export var portrait: Texture2D

# Flexible portrait/stage art catalog for dialogue.
# If assigned, DialogueUI can use full-body stage poses separately from the portrait.
@export var dialogue_art: NPCDialogueArtData

@export var dialogue_lines: Array[String] = []

@export var morning_dialogue_lines: Array[String] = []
@export var evening_dialogue_lines: Array[String] = []
@export var night_dialogue_lines: Array[String] = []

@export var overhead_greeting_lines: Array[String] = []  # e.g. ["Hello there!", "Nice day, huh?"]
@export var overhead_idle_lines: Array[String] = []      # e.g. ["Watermelons...", "I should water the crops..."]

@export var morning_overhead_lines: Array[String] = []
@export var day_overhead_lines: Array[String] = []
@export var evening_overhead_lines: Array[String] = []
@export var night_overhead_lines: Array[String] = []

# Optional quest fields — only used if quest_id is non-empty
@export var quest_id: String = ""
@export var quest_title: String = ""
@export var quest_type: String = ""      # e.g. "ship" or "chop_tree"
@export var quest_target: String = ""    # e.g. "Watermelon"
@export var quest_amount: int = 1

@export var quest_reward_money: int = 0
@export var quest_reward_items: Dictionary[String, int] = {}
# e.g. { "Watermelon": 1 }

# Dialogue variants for quest states
@export var quest_request_lines: Array[String] = []       # when offering quest
@export var quest_in_progress_lines: Array[String] = []   # when you haven't finished yet
@export var quest_completed_lines: Array[String] = []     # when you return after finishing (gives reward)
@export var quest_after_thanks_lines: Array[String] = []  # later conversations after it’s all done

@onready var quest_icon: TextureRect = $BubbleAnchor/QuestIcon
@onready var chatter_label: Label = $BubbleAnchor/ChatterLabel
@onready var proximity_area: Area2D = $ProximityArea
@onready var chatter_timer: Timer = $ChatterTimer

@export var opens_shop: bool = false
@export var shop_title: String = "Shop"

@export var shop_open_hour: int = 9   # 9:00
@export var shop_close_hour: int = 18 # 18:00

@export var shop_closed_lines: Array[String] = [
	"Sorry, we’re closed for the day.",
	"Come back tomorrow during business hours!"
]

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

@export var move_speed: float = 40.0  # you already had something like this

var _path: Array[Vector2] = []
var _current_path_index: int = -1
var _has_destination: bool = false

const GRID_SIZE: float = 32.0  # your tile size

@export var morning_spot_path: NodePath
@export var day_spot_path: NodePath
@export var evening_spot_path: NodePath
@export var night_spot_path: NodePath

var _current_schedule_target: Node2D = null

@export var enable_idle_wander: bool = true
@export var wander_interval_min: float = 3.0
@export var wander_interval_max: float = 7.0
@export var wander_tile_distance: int = 1
@export var grid_size: float = 32.0   # match your real tile size

var _anchor_position: Vector2         # where this NPC “belongs” right now

@onready var _wander_timer: Timer = $WanderTimer

@export var mayor_main_quest: QuestData


#var quest_mayor_intro: Dictionary = {
	#"id": "main_mayor_strawberry",
	#"title": "A Mayor’s Request",
	#"description": "Help the Mayor get the town moving again.",
	#"type": "chain",
	#"giver_id": "npc_mayor",
	#"turn_in_id": "npc_mayor",
	#"turn_in_text": "Return to the Mayor to collect your reward.",	
	#"step_index": 0,
	#"steps": [
		#{ "type": "talk_to", "target": "npc_alex",  "amount": 1, "progress": 0, "text": "Talk to Alex." },
		#{ "type": "go_to",   "target": "farm",      "amount": 1, "progress": 0, "text": "Go to the Farm." },
		#{ "type": "ship",    "target": "Strawberry","amount": 1, "progress": 0, "text": "Ship 1 Strawberry." },
	#],
	#"reward": { "money": 250 },
	#"completed": false,
	#"claimed": false,
#}


@export var offered_quest_ids: Array[String] = []

@export var quest_offers: Array[QuestData] = []

var _talked_block_by_npc: Dictionary = {}  # npc_id -> String "day:morning" etc.

@export var gift_prefs: NPCGiftPreferences

func _ready() -> void:
	if not is_in_group("npc"):
		add_to_group("npc")

	# ... your existing NPC init ...
	_update_quest_icon()
	# print("NPC ready:", npc_id)
	if nav_agent:
		nav_agent.path_desired_distance = 4.0
		nav_agent.target_desired_distance = 4.0

	_current_schedule_target = null

	if not Engine.is_editor_hint():
		TimeManager.time_changed.connect(_on_time_changed_for_schedule)
		_on_time_changed_for_schedule(TimeManager.minutes)
		
		if QuestEvents:
			# print("Yeah, I'm in here!")
			QuestEvents.quest_state_changed.connect(_on_quest_state_changed)
		
	_wander_timer.timeout.connect(_on_wander_timer_timeout)
	_schedule_next_wander()

func start_dialogue() -> void:
	_update_quest_icon()
	
	var ui := get_tree().get_first_node_in_group("dialogue_ui")
	if ui== null:
		# print("No DialogueUI found in group 'dialogue_ui'. Add DialogueUI.tscn to the scene and put it in that group.")
		return

	# Make sure it's actually our DialogueUI script, not just any CanvasLayer
	if not ui.has_method("show_dialogue"):
		# print("Node in group 'dialogue_ui' does not have show_dialogue(). Reattach DialogueUI.gd to the DialogueUI CanvasLayer.")
		# print("Found node:", ui.name, " type:", ui.get_class())
		return
	
	var f := GameState.get_friendship(npc_id)

	# --- TALK COOLDOWN: once per time block ---
	if not GameState.can_talk_to_npc(npc_id):
		# Make them feel "uninteractable" during this block.
		# You can optionally show overhead chatter instead, but no UI pop.
		return

	# Mark talked NOW so spam clicking doesn't reopen.
	GameState.mark_talked_to_npc(npc_id)
	
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("play_talk_sfx"):
		player.play_talk_sfx()
		
	var current_day := TimeManager.day  # <-- adjust to your project

	# Gain friendship once per day on talk (recommended)
	if GameState.can_gain_talk_friendship(npc_id, current_day):
		GameState.add_friendship(npc_id, 1)
		GameState.mark_talked_today(npc_id, current_day)
		
	f = GameState.get_friendship(npc_id)

	# ... existing quest + friendship dialogue logic below ...
	
	# --- I KNEW IT! Do it before the shop so that this focus thing only happens with communicating NPCs
	
	if player == null:
		print("NPC Dialogue: No node in group 'player' found.")
	elif player.has_method("camera_focus_on_world_point"):
		# print("NPC Dialogue: Focusing camera on NPC: ", global_position)
		player.camera_focus_on_world_point(global_position + Vector2(0, -10))
	else:
		print("NPC Dialogue: Player has no camera_focus_on_world_point()")
	
	QuestEvents.talked_to.emit(npc_id)
	
	# --- QUESTDATA-BASED QUEST FLOW (GENERAL) ---
	
	# --- Legacy quest flow below (kept for compatibility) ---

	# --- QUEST PRIORITY 1: TURN-IN READY ---
	if GameState.has_turn_in_ready(npc_id):
		var ready_id: String = GameState.get_first_turn_in_ready_id_for(npc_id)
		var qd_ready: QuestData = _find_questdata_by_id(ready_id)

		var used_special := false
		if qd_ready != null:
			used_special = _show_override_dialogue(
				ui,
				qd_ready,
				"turn_in_ready",
				-1,
				qd_ready.turn_in_lines if qd_ready != null else [],
				f
			)

		if not used_special:
			_show_plain_dialogue(ui, display_name, ["You did it! Here’s your reward."], f, npc_id)

		# Important:
		# Wait until the heartfelt override / fallback dialogue is fully finished.
		await _await_dialogue_closed(ui)

		# Complete + claim in one clean step.
		# This keeps story turn-ins from needing a second interaction.
		if GameState.has_method("complete_ready_quest_and_claim_reward"):
			GameState.complete_ready_quest_and_claim_reward(ready_id)
		else:
			# Fallback, just in case you test in an older version.
			GameState.complete_quest(ready_id)
			GameState.claim_quest_reward(ready_id)

		QuestEvents.quest_state_changed.emit()
		_update_quest_icon()
		return
	
	# --- QUEST PRIORITY 2: ACTIVE PARTICIPANT OVERRIDE ---
	var participant_override := _get_best_active_participant_override_quest_and_phase()
	var participant_qd: QuestData = participant_override.get("quest", null)
	if participant_qd != null:
		var participant_phase := String(participant_override.get("phase", "active_any"))
		var participant_step_index := int(participant_override.get("step_index", -1))

		if _show_override_dialogue(ui, participant_qd, participant_phase, participant_step_index, [], f):
			return

	# --- QUEST PRIORITY 3: RECENTLY CLAIMED PARTICIPANT OVERRIDE (same day reminiscence) ---
	var recent_qd := _get_best_recently_claimed_override_quest()
	if recent_qd != null:
		if _show_override_dialogue(ui, recent_qd, "completed_claimed", -1, [], f):
			return

	# --- QUEST PRIORITY 4: OFFER FIRST UNLOCKED QUEST ---
	var offer_q: QuestData = _get_offerable_questdata()
	if offer_q != null:
		GameState.add_quest(offer_q.to_dict())
		QuestEvents.quest_state_changed.emit()
		_update_quest_icon()

		var offer_lines: Array[String] = offer_q.offer_lines
		if offer_lines.is_empty():
			offer_lines = ["Could you help me with something?"]

		ui.show_dialogue(display_name, offer_lines, f, npc_id)
		return
		
	# --- QUEST PRIORITY 5: LOCKED BARK (low chance), else NORMAL DIALOGUE ---
	var locked_q: QuestData = _get_first_locked_questdata_not_done()
	if locked_q != null:
		if randf() < locked_q.locked_bark_chance:
			var bark_lines: Array[String] = locked_q.locked_lines
			if bark_lines.is_empty():
				bark_lines = ["Not yet… but soon."]  # tiny fallback
			ui.show_dialogue(display_name, bark_lines, f, npc_id)
			return

	# 3) If they already accepted a quest from this NPC, optionally show in-progress lines
	# (We’ll leave the “randomize with normal speech” idea for later like you asked 💛)
	for qd in quest_offers:
		if qd == null:
			continue
		if GameState.active_quests.has(qd.id):
			var inprog_lines: Array[String] = []
			if not qd.in_progress_lines.is_empty():
				inprog_lines = qd.in_progress_lines
			
			if not qd.in_progress_lines.is_empty():
				ui.show_dialogue(display_name, qd.in_progress_lines, f, npc_id)
				return

			if not inprog_lines.is_empty():
				ui.show_dialogue(display_name, inprog_lines, f, npc_id)
				return
	
	# If this NPC doesn’t have a quest attached, use festival dialogue if present,
	# otherwise normal time-based dialogue.
	if quest_id == "":
		ui.show_dialogue(display_name, _get_festival_or_time_based_dialogue(), f, npc_id)
		return
		
	# --- Quest-aware behavior below ---

	# 1) Quest already active and not completed → in-progress lines
	if GameState.active_quests.has(quest_id):
		if quest_in_progress_lines.size() > 0:
			ui.show_dialogue(display_name, quest_in_progress_lines, f, npc_id)
		else:
			ui.show_dialogue(display_name, _get_festival_or_lines(dialogue_lines), f, npc_id)
		return

	# 2) Quest completed and not yet claimed → thank + reward
	if GameState.completed_quests.has(quest_id):
		var quest: Dictionary = GameState.completed_quests[quest_id]
		var claimed := bool(quest.get("claimed", false))

		if not claimed:
			# Give reward now
			GameState.claim_quest_reward(quest_id)
			_update_quest_icon()
			GameState.add_friendship(npc_id, 15)
			f = GameState.get_friendship(npc_id)

			if quest_completed_lines.size() > 0:
				ui.show_dialogue(display_name, quest_completed_lines, f, npc_id)
			else:
				ui.show_dialogue(display_name, ["Thank you so much for your help!"], f, npc_id)
		else:
			# Already claimed, show “after” lines
			if quest_after_thanks_lines.size() > 0:
				ui.show_dialogue(display_name, quest_after_thanks_lines, f, npc_id)
			else:
				ui.show_dialogue(display_name, _get_festival_or_lines(dialogue_lines), f, npc_id)
		return

	# 3) Quest not started yet → offer + automatically accept
	var new_quest := _build_quest()
	if new_quest.is_empty():
		# Fallback to festival dialogue if present, otherwise normal dialogue
		ui.show_dialogue(display_name, _get_festival_or_lines(dialogue_lines), f, npc_id)
		return

	GameState.add_quest(new_quest)
	_update_quest_icon()

	if quest_request_lines.size() > 0:
		ui.show_dialogue(display_name, quest_request_lines, f, npc_id)
	else:
		ui.show_dialogue(display_name, _get_festival_or_lines(dialogue_lines), f, npc_id)

func _build_quest() -> Dictionary:
	if quest_id == "":
		return {}

	var reward_dict: Dictionary = {}
	if quest_reward_money != 0:
		reward_dict["money"] = quest_reward_money
	if quest_reward_items.size() > 0:
		reward_dict["items"] = quest_reward_items

	var description_text := ""
	if quest_request_lines.size() > 0:
		description_text = quest_request_lines[0]

	return {
		"id": quest_id,
		"title": quest_title if quest_title != "" else (display_name + "'s Request"),
		"description": description_text,
		"type": quest_type,
		"target": quest_target,
		"amount": quest_amount,
		"progress": 0,
		"reward": reward_dict,
		"completed": false,
		"claimed": false,
	}

func _update_quest_icon() -> void:
	if quest_icon == null:
		return

	var show := false
	
	# print(GameState.has_turn_in_ready(npc_id))
	# print(npc_id)
	
	# Turn-in ready takes priority
	if GameState.has_turn_in_ready(npc_id):
		show = true
	# Else show if NPC has a quest offer ready
	elif _has_offerable_quest():
		show = true
	
	# 1) New: turn-in ready for this NPC? (shows ? icon)
	if GameState.has_turn_in_ready(npc_id):
		show = true
	else:
		# NEW: show icon if any QuestData offer is available
		if _get_offerable_questdata() != null:
			show = true
		# BACKWARD COMPAT: old single quest_id behavior
		elif quest_id != "":
			if not GameState.active_quests.has(quest_id) and not GameState.completed_quests.has(quest_id):
				show = true

	# 2) New: can this NPC offer any quests right now? (shows ! icon)
	if not show:
		for qid in offered_quest_ids:
			if GameState.is_quest_available_to_accept(qid):
				show = true
				break

	# 3) Old system fallback: single quest fields still supported
	if not show and quest_id != "":
		if not GameState.active_quests.has(quest_id) and not GameState.completed_quests.has(quest_id):
			show = true
		elif GameState.completed_quests.has(quest_id):
			var q: Dictionary = GameState.completed_quests[quest_id]
			if not bool(q.get("claimed", false)):
				show = true

	quest_icon.visible = show

func _show_overhead_chatter() -> void:
	if chatter_label == null:
		return

	var pool := _get_overhead_chatter_pool()
	if pool.is_empty():
		return

	var idx := randi() % pool.size()
	var text := pool[idx]

	chatter_label.text = text
	chatter_label.visible = true
	chatter_timer.start()

func _hide_overhead_chatter() -> void:
	if chatter_label == null:
		return
	chatter_label.visible = false
	_update_quest_icon()

func _on_ProximityArea_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):  # assuming your Player is in group "player"
		return
	# # print("Proximity ENTER: ", body)
	_show_overhead_chatter()


func _on_ProximityArea_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	# # print("Proximity EXIT: ", body)
	_hide_overhead_chatter()

func _on_ChatterTimer_timeout() -> void:
	_hide_overhead_chatter()

func _get_overhead_chatter_pool() -> Array[String]:
	var hour := int(TimeManager.minutes / 60)

	# You can tune these ranges however you like
	if hour >= 6 and hour < 10 and morning_overhead_lines.size() > 0:
		return morning_overhead_lines
	if hour >= 10 and hour < 18 and day_overhead_lines.size() > 0:
		return day_overhead_lines
	if hour >= 18 and hour < 22 and evening_overhead_lines.size() > 0:
		return evening_overhead_lines
	if (hour >= 22 or hour < 6) and night_overhead_lines.size() > 0:
		return night_overhead_lines

	# Fallbacks if time-specific arrays are empty
	if overhead_greeting_lines.size() > 0:
		return overhead_greeting_lines
	if overhead_idle_lines.size() > 0:
		return overhead_idle_lines

	return []

func _get_time_based_dialogue() -> Array[String]:
	var hour := int(TimeManager.minutes / 60)

	if hour >= 6 and hour < 10 and morning_dialogue_lines.size() > 0:
		return morning_dialogue_lines
	if hour >= 18 and hour < 22 and evening_dialogue_lines.size() > 0:
		return evening_dialogue_lines
	if (hour >= 22 or hour < 6) and night_dialogue_lines.size() > 0:
		return night_dialogue_lines

	return dialogue_lines

func _snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(
		round(pos.x / GRID_SIZE) * GRID_SIZE,
		round(pos.y / GRID_SIZE) * GRID_SIZE
	)

func set_destination(world_position: Vector2,  is_anchor: bool = false) -> void:
	var start := _snap_to_grid(global_position)
	global_position = start

	# ✅ Snap the marker’s position to the nearest grid tile
	var target := _snap_to_grid(world_position)

	# Optional: store this as our “anchor” for wandering (explained below)
	if is_anchor:
		_anchor_position = target

	_path.clear()
	_current_path_index = -1
	_has_destination = false

	var mid := Vector2(start.x, target.y)

	_path.append(mid)
	_path.append(target)

	_current_path_index = 0
	_has_destination = true

func _physics_process(delta: float) -> void:
	# Don't move while gameplay is locked (dialogue, shop, etc.)
	if GameState.is_gameplay_locked():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if not _has_destination or _current_path_index < 0:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _current_path_index >= _path.size():
		_has_destination = false
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var target := _path[_current_path_index]
	var to_target := target - global_position

	if to_target.length() < 2.0:
		_current_path_index += 1

		if _current_path_index >= _path.size():
			_has_destination = false
			velocity = Vector2.ZERO
			move_and_slide()
			return

		target = _path[_current_path_index]
		to_target = target - global_position

	var dir := to_target.normalized()
	velocity = dir * move_speed
	move_and_slide()

func _get_schedule_target_for_time(minutes: int) -> Node2D:
	var block: int = TimeManager.get_time_block(minutes)

	match block:
		TimeManager.TimeBlock.MORNING:
			return _get_node_from_path(morning_spot_path)
		TimeManager.TimeBlock.DAY:
			return _get_node_from_path(day_spot_path)
		TimeManager.TimeBlock.EVENING:
			return _get_node_from_path(evening_spot_path)
		_:
			return _get_node_from_path(night_spot_path)

func _get_node_from_path(path: NodePath) -> Node2D:
	if path == NodePath(""):
		return null
	var node := get_node_or_null(path)
	if node is Node2D:
		return node as Node2D
	return null

func _on_time_changed_for_schedule(minutes: int) -> void:
	var target_node := _get_schedule_target_for_time(minutes)
	if target_node == null:
		return

	# If we're already heading to (or standing at) this spot, don't reset the path
	if target_node == _current_schedule_target:
		return

	_current_schedule_target = target_node
	set_destination(target_node.global_position, true)

func _schedule_next_wander() -> void:
	if not enable_idle_wander:
		return

	# A little randomness so they don't all step in sync
	var wait_time := randf_range(wander_interval_min, wander_interval_max)
	_wander_timer.wait_time = wait_time
	_wander_timer.start()

func _on_wander_timer_timeout() -> void:
	if not enable_idle_wander:
		return

	# Don't wander if UI is open, etc.
	if GameState.is_gameplay_locked():
		_schedule_next_wander()
		return

	# Don't wander if we're currently moving somewhere
	if _has_destination:
		_schedule_next_wander()
		return

	# If we don't have an anchor yet, use current snapped position
	if _anchor_position == Vector2.ZERO:
		_anchor_position = _snap_to_grid(global_position)

	_attempt_idle_wander()
	_schedule_next_wander()

func _attempt_idle_wander() -> void:
	# Possible directions: stay, left, right, up, down
	var dirs := [
		Vector2.ZERO,
		Vector2.RIGHT,
		Vector2.LEFT,
		Vector2.UP,
		Vector2.DOWN
	]

	dirs.shuffle()

	for dir in dirs:
		var offset: Vector2 = dir * grid_size * float(wander_tile_distance)
		var candidate := _anchor_position + offset

		# Skip if it's exactly where we are and dir is ZERO
		if candidate.distance_to(global_position) < 1.0:
			continue

		if _can_wander_to(candidate):
			# Important: we DO NOT mark this as a new anchor.
			# This keeps all wandering centered around the original schedule spot.
			set_destination(candidate, false)
			return

	# If no candidate worked, we just don't move this time.

func _can_wander_to(world_pos: Vector2) -> bool:
	# For now, just return true.
	# Later you can:
	#  - Check collisions
	#  - Avoid water, walls, etc.
	return true

func _on_quest_state_changed() -> void:
	_update_quest_icon()

func _get_first_questdata_not_done() -> QuestData:
	for q in quest_offers:
		if q == null or q.id == "":
			continue
		if GameState.active_quests.has(q.id):
			continue
		if GameState.completed_quests.has(q.id):
			continue
		return q
	return null

func _has_offerable_quest() -> bool:
	# Mayor special quest resource
	if npc_id == "npc_mayor" and mayor_main_quest != null:
		if mayor_main_quest.is_unlocked():
			var qid: String = mayor_main_quest.id
			if not GameState.active_quests.has(qid) and not GameState.completed_quests.has(qid):
				return true

	# General multi-offer quests (if you use quest_offers too)
	var q_offer: QuestData = _get_offerable_questdata()
	return q_offer != null

func _find_questdata_by_id(qid: String) -> QuestData:
	# 1) Prefer this NPC's own local offers first
	for q in quest_offers:
		if q != null and q.id == qid:
			return q

	# 2) Fall back to global quest catalog
	if QuestCatalogDb != null and QuestCatalogDb.has_method("get_quest"):
		return QuestCatalogDb.get_quest(qid)

	return null

func _get_offerable_questdata() -> QuestData:
	for q in quest_offers:
		if q == null or q.id == "":
			continue
		if not q.is_unlocked():
			continue
		if GameState.active_quests.has(q.id):
			continue
		if GameState.completed_quests.has(q.id):
			continue
		return q
	return null

func _get_first_locked_questdata_not_done() -> QuestData:
	for q in quest_offers:
		if q == null or q.id == "":
			continue
		if GameState.active_quests.has(q.id):
			continue
		if GameState.completed_quests.has(q.id):
			continue
		if not q.is_unlocked():
			return q
	return null

func _get_active_quest_state_by_id(qid: String) -> Dictionary:
	if qid.strip_edges() == "":
		return {}

	if GameState.active_quests.has(qid):
		return GameState.active_quests[qid]

	if GameState.completed_quests.has(qid):
		return GameState.completed_quests[qid]

	return {}

func _get_current_chain_step_dict(quest_state: Dictionary) -> Dictionary:
	if quest_state.is_empty():
		return {}

	if String(quest_state.get("type", "")) != "chain":
		return {}

	var steps_any = quest_state.get("steps", [])
	if typeof(steps_any) != TYPE_ARRAY:
		return {}

	var steps: Array = steps_any
	var step_index := int(quest_state.get("step_index", 0))

	if step_index < 0 or step_index >= steps.size():
		return {}

	var step_any = steps[step_index]
	if typeof(step_any) != TYPE_DICTIONARY:
		return {}

	return step_any

func _does_current_step_target_this_npc(qd: QuestData, quest_state: Dictionary) -> bool:
	if qd == null or quest_state.is_empty():
		return false

	# Explicit turn-in target also counts as quest-critical interaction
	if bool(quest_state.get("completed", false)) and not bool(quest_state.get("claimed", false)):
		return String(qd.turn_in_id) == npc_id

	var step := _get_current_chain_step_dict(quest_state)
	if step.is_empty():
		return false

	var step_type := String(step.get("type", ""))
	var step_target := String(step.get("target", ""))

	# For now, only "talk_to" directly claims this NPC interaction.
	# Later you can extend this for delivery steps, staged scenes, etc.
	if step_type == "talk_to" and step_target == npc_id:
		return true

	return false

func _get_participant_override_priority_score(qd: QuestData, quest_state: Dictionary) -> int:
	if qd == null or quest_state.is_empty():
		return -1

	var score := -1

	# Highest priority: this NPC is the current quest-critical target
	if _does_current_step_target_this_npc(qd, quest_state):
		score = 100
	# General participant in an active quest
	elif qd.has_participant(npc_id):
		score = 50
	else:
		return -1

	# Tracked quest gets a small nudge if there is a tie
	if String(GameState.tracked_quest_id) == String(qd.id):
		score += 5

	return score

func _get_best_active_participant_override_lines() -> Array[String]:
	var best_score := -1
	var best_lines: Array[String] = []

	# Check active quests
	for qid_any in GameState.active_quests.keys():
		var qid := String(qid_any)
		var qd := _find_questdata_by_id(qid)
		if qd == null:
			continue

		var quest_state: Dictionary = GameState.active_quests[qid]
		var score := _get_participant_override_priority_score(qd, quest_state)
		if score < 0:
			continue

		var lines := qd.get_best_override_lines_for_npc(npc_id, quest_state)
		if lines.is_empty():
			continue

		if score > best_score:
			best_score = score
			best_lines = lines

	# Also check completed-but-unclaimed quests in case the participant override
	# should still speak differently during a turn-in-ready state.
	for qid_any in GameState.completed_quests.keys():
		var qid := String(qid_any)
		var qd := _find_questdata_by_id(qid)
		if qd == null:
			continue

		var quest_state: Dictionary = GameState.completed_quests[qid]
		if not bool(quest_state.get("completed", false)):
			continue
		if bool(quest_state.get("claimed", false)):
			continue

		var score := _get_participant_override_priority_score(qd, quest_state)
		if score < 0:
			continue

		var lines := qd.get_best_override_lines_for_npc(npc_id, quest_state)
		if lines.is_empty():
			continue

		if score > best_score:
			best_score = score
			best_lines = lines

	return best_lines

func can_player_interact(player: Node) -> bool:
	# If you already have a cooldown / time-block lock, use that.
	# Examples: _can_talk_now, interactable, is_interactable, locked_until_timeblock, etc.
	# Replace the condition below with your real one.
	if not GameState.can_talk_to_npc(npc_id):
		# Make them feel "uninteractable" during this block.
		# You can optionally show overhead chatter instead, but no UI pop.
		return false

	# Default: allow
	return true


func get_interact_prompt(player: Node) -> String:
	# Only show talk if they can actually talk right now
	if not can_player_interact(player):
		return ""
	return "E: Talk"

func get_npc_id() -> String:
	return npc_id

func receive_gift(item_id: String, qty: int = 1) -> void:
	# Basic safety
	item_id = item_id.strip_edges()
	if item_id == "" or qty <= 0:
		return
	
	# Gift limits (separate from talk cooldown)
	if not GameState.can_gift_to_npc(npc_id):
		QuestEvents.toast_requested.emit(display_name + " can't accept more gifts right now.")
		return
	
	var d := ItemDb.get_item(item_id)
	# print("[Gift] item:", item_id, " data:", d, " tags:", [] if d == null else d.tags)

	# Remove item from inventory
	if not GameState.inventory_remove(item_id, qty):
		return
	
	GameState.mark_gifted_to_npc(npc_id)

	# Determine reaction tier
	var tier := _gift_reaction_tier(item_id)

	# Friendship delta (tune freely)
	var delta := 0
	match tier:
		"love": delta = 8
		"like": delta = 4
		"neutral": delta = 2
		"dislike": delta = 0
		"hate": delta = -2

	GameState.add_friendship(npc_id, delta)

	# Emit quest event (gift action)
	QuestEvents.item_gifted.emit(npc_id, item_id, qty)
	QuestEvents.quest_state_changed.emit() # if you want immediate UI refresh

	# Toast feedback
	if tier == "love":
		QuestEvents.toast_requested.emit(display_name + " loved your gift!")
	elif tier == "like":
		QuestEvents.toast_requested.emit(display_name + " liked your gift!")
	elif tier == "dislike":
		QuestEvents.toast_requested.emit(display_name + " didn’t seem to like that…")
	elif tier == "hate":
		QuestEvents.toast_requested.emit(display_name + " hated that…")
	else:
		QuestEvents.toast_requested.emit(display_name + " accepted your gift.")

	# Dialogue response (keep it short and sweet)
	var ui := get_tree().get_first_node_in_group("dialogue_ui")
	if ui and ui.has_method("show_dialogue"):
		var f := GameState.get_friendship(npc_id)
		var lines: Array[String] = _gift_reaction_lines(tier)
		ui.show_dialogue(display_name, lines, f, npc_id)

func _gift_reaction_tier(item_id: String) -> String:
	if gift_prefs == null:
		return "neutral"

	# Get tags from ItemDb (safe if not found)
	var tags: Array[String] = []
	if ItemDb != null and ItemDb.has_method("get_item_data"):
		var data = ItemDb.call("get_item_data", item_id)
		if data != null:
			# ItemData.tags is Array[String]
			tags = data.tags

	# Use preferences (items override tags)
	if gift_prefs.has_method("get_reaction_tier_for_item"):
		return String(gift_prefs.call("get_reaction_tier_for_item", item_id, tags))

	# Fallback to old behavior if needed
	if gift_prefs.loves.has(item_id):
		return "love"
	if gift_prefs.likes.has(item_id):
		return "like"
	if gift_prefs.hates.has(item_id):
		return "hate"
	if gift_prefs.dislikes.has(item_id):
		return "dislike"
	return "neutral"


func _gift_reaction_lines(tier: String) -> Array[String]:
	if gift_prefs != null and gift_prefs.has_method("get_lines_for_tier"):
		return gift_prefs.call("get_lines_for_tier", tier)
	return ["Thanks!"]

func _get_festival_dialogue_lines() -> Array[String]:
	if FestivalManager == null:
		return []

	if not FestivalManager.is_festival_today():
		return []

	var lines := FestivalManager.get_npc_festival_dialogue(npc_id)
	if lines == null or lines.is_empty():
		return []

	return lines


func _get_festival_or_lines(fallback_lines: Array[String]) -> Array[String]:
	var fest_lines := _get_festival_dialogue_lines()
	if not fest_lines.is_empty():
		return fest_lines
	return fallback_lines


func _get_festival_or_time_based_dialogue() -> Array[String]:
	var fest_lines := _get_festival_dialogue_lines()
	if not fest_lines.is_empty():
		return fest_lines
	return _get_time_based_dialogue()

func _get_best_recently_claimed_override_lines() -> Array[String]:
	for qid_any in GameState.completed_quests.keys():
		var qid := String(qid_any)

		if not GameState.was_quest_claimed_today(qid):
			continue

		var qd := _find_questdata_by_id(qid)
		if qd == null:
			continue

		if not qd.has_participant(npc_id):
			continue

		var quest_state: Dictionary = GameState.completed_quests[qid]
		var lines := qd.get_best_override_lines_for_npc(npc_id, quest_state)

		if not lines.is_empty():
			return lines

	return []

func _await_dialogue_closed(ui: Node) -> void:
	if ui == null:
		return

	if not ui.has_signal("dialogue_closed"):
		await get_tree().process_frame
		return

	await ui.dialogue_closed

func _show_override_dialogue(ui: Node, qd: QuestData, phase: String, step_index: int, fallback_lines: Array[String], friendship: int) -> bool:
	if qd == null:
		return false

	var seq := qd.get_override_sequence_for_npc(npc_id, phase, step_index)
	if seq != null and seq.has_beats():
		if ui.has_method("show_dialogue_sequence"):
			ui.show_dialogue_sequence(seq)
			return true

	var lines: Array[String] = qd.get_override_lines_for_npc(npc_id, phase, step_index)

	if lines.is_empty():
		for line_any in fallback_lines:
			var line := String(line_any).strip_edges()
			if line != "":
				lines.append(line)

	if lines.is_empty():
		return false

	_show_plain_dialogue(ui, display_name, lines, friendship, npc_id)
	return true

func _get_best_active_participant_override_quest_and_phase() -> Dictionary:
	var best_score := -1
	var best_qd: QuestData = null
	var best_phase := ""
	var best_step_index := -1

	for qid_any in GameState.active_quests.keys():
		var qid := String(qid_any)
		var qd := _find_questdata_by_id(qid)
		if qd == null:
			continue

		var quest_state: Dictionary = GameState.active_quests[qid]
		var score := _get_participant_override_priority_score(qd, quest_state)
		if score < 0:
			continue

		var phase := "active_any"
		var step_index := -1

		if qd.quest_type == "chain":
			step_index = int(quest_state.get("step_index", 0))
			var step_lines := qd.get_override_lines_for_npc(npc_id, "active_step", step_index)
			var step_seq := qd.get_override_sequence_for_npc(npc_id, "active_step", step_index)
			if not step_lines.is_empty() or (step_seq != null and step_seq.has_beats()):
				phase = "active_step"

		var any_lines := qd.get_override_lines_for_npc(npc_id, phase, step_index)
		var any_seq := qd.get_override_sequence_for_npc(npc_id, phase, step_index)

		if any_lines.is_empty() and (any_seq == null or not any_seq.has_beats()):
			continue

		if score > best_score:
			best_score = score
			best_qd = qd
			best_phase = phase
			best_step_index = step_index

	return {
		"quest": best_qd,
		"phase": best_phase,
		"step_index": best_step_index
	}

func _get_best_recently_claimed_override_quest() -> QuestData:
	for qid_any in GameState.completed_quests.keys():
		var qid := String(qid_any)

		if not GameState.was_quest_claimed_today(qid):
			continue

		var qd := _find_questdata_by_id(qid)
		if qd == null:
			continue

		if not qd.has_participant(npc_id):
			continue

		var lines := qd.get_override_lines_for_npc(npc_id, "completed_claimed", -1)
		var seq := qd.get_override_sequence_for_npc(npc_id, "completed_claimed", -1)

		if not lines.is_empty() or (seq != null and seq.has_beats()):
			return qd

	return null

func _show_plain_dialogue(ui: Node, speaker_name: String, raw_lines: Array, friendship: int = -1, speaker_id: String = "") -> void:
	if ui == null:
		return
	if not ui.has_method("show_dialogue"):
		return

	var lines: Array[String] = []

	for line_any in raw_lines:
		var line := String(line_any).strip_edges()
		if line != "":
			lines.append(line)

	if lines.is_empty():
		lines.append("...")

	ui.show_dialogue(speaker_name, lines, friendship, speaker_id)
