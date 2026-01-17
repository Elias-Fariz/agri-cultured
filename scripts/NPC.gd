extends CharacterBody2D

@export var npc_id: String = "npc_mayor"

@export var display_name: String
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

func _ready() -> void:
	# ... your existing NPC init ...
	_update_quest_icon()
	print("NPC ready:", npc_id)
	if nav_agent:
		nav_agent.path_desired_distance = 4.0
		nav_agent.target_desired_distance = 4.0

	_current_schedule_target = null

	if not Engine.is_editor_hint():
		TimeManager.time_changed.connect(_on_time_changed_for_schedule)
		_on_time_changed_for_schedule(TimeManager.minutes)
		
		if QuestEvents:
			print("Yeah, I'm in here!")
			QuestEvents.quest_state_changed.connect(_on_quest_state_changed)
		
	_wander_timer.timeout.connect(_on_wander_timer_timeout)
	_schedule_next_wander()

func start_dialogue() -> void:
	_update_quest_icon()
	
	var ui := get_tree().get_first_node_in_group("dialogue_ui")
	if ui== null:
		print("No DialogueUI found in group 'dialogue_ui'. Add DialogueUI.tscn to the scene and put it in that group.")
		return

	# Make sure it's actually our DialogueUI script, not just any CanvasLayer
	if not ui.has_method("show_dialogue"):
		print("Node in group 'dialogue_ui' does not have show_dialogue(). Reattach DialogueUI.gd to the DialogueUI CanvasLayer.")
		print("Found node:", ui.name, " type:", ui.get_class())
		return
		
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
		
	var f := GameState.get_friendship(npc_id)
	
	# SHOP CHECK FIRST
	if opens_shop:
		var hour := int(TimeManager.minutes / 60)

		if hour < shop_open_hour or hour >= shop_close_hour:
			# Shop is closed → use dialogue instead of opening UI
			var lines := shop_closed_lines
			if lines.is_empty():
				lines = ["Sorry, we’re closed right now. Come back tomorrow!"]

			ui.show_dialogue(display_name, lines, f)
		else:
			# Shop is open → show ShopUI overlay
			var shop_ui := get_tree().get_first_node_in_group("shop_ui")
			if shop_ui:
				if shop_ui.has_method("set_title"):
					shop_ui.set_title(shop_title)
				shop_ui.show_overlay()
		return

	# ... existing quest + friendship dialogue logic below ...
	
	# --- I KNEW IT! Do it before the shop so that this focus thing only happens with communicating NPCs
	
	if player == null:
		print("NPC Dialogue: No node in group 'player' found.")
	elif player.has_method("camera_focus_on_world_point"):
		print("NPC Dialogue: Focusing camera on NPC: ", global_position)
		player.camera_focus_on_world_point(global_position + Vector2(0, -10))
	else:
		print("NPC Dialogue: Player has no camera_focus_on_world_point()")
	
	QuestEvents.talked_to.emit(npc_id)
	
	# --- QUESTDATA-BASED QUEST FLOW (GENERAL) ---
	
	# --- Legacy quest flow below (kept for compatibility) ---

	# --- QUEST PRIORITY 1: TURN-IN READY ---
	if GameState.has_turn_in_ready(npc_id):
		var ready_id: String = GameState.get_first_turn_in_ready_id_for(npc_id) # you already discussed this helper

		# Find matching QuestData so we can use its turn_in_lines
		var qd_ready: QuestData = _find_questdata_by_id(ready_id)

		var turnin_lines: Array[String] = []
		if qd_ready != null and not qd_ready.turn_in_lines.is_empty():
			turnin_lines = qd_ready.turn_in_lines
		else:
			turnin_lines = ["You did it! Here’s your reward."]

		GameState.claim_quest_reward(ready_id)
		QuestEvents.quest_state_changed.emit()
		_update_quest_icon()

		ui.show_dialogue(display_name, turnin_lines, f)
		return


	# --- QUEST PRIORITY 2: OFFER FIRST UNLOCKED QUEST ---
	var offer_q: QuestData = _get_offerable_questdata()
	if offer_q != null:
		GameState.add_quest(offer_q.to_dict())
		QuestEvents.quest_state_changed.emit()
		_update_quest_icon()

		var offer_lines: Array[String] = offer_q.offer_lines
		if offer_lines.is_empty():
			offer_lines = ["Could you help me with something?"]

		ui.show_dialogue(display_name, offer_lines, f)
		return
		
	# --- QUEST PRIORITY 3: LOCKED BARK (low chance), else NORMAL DIALOGUE ---
	var locked_q: QuestData = _get_first_locked_questdata_not_done()
	if locked_q != null:
		if randf() < locked_q.locked_bark_chance:
			var bark_lines: Array[String] = locked_q.locked_lines
			if bark_lines.is_empty():
				bark_lines = ["Not yet… but soon."]  # tiny fallback
			ui.show_dialogue(display_name, bark_lines, f)
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
				ui.show_dialogue(display_name, qd.in_progress_lines, f)
				return

			if not inprog_lines.is_empty():
				ui.show_dialogue(display_name, inprog_lines, f)
				return
	
	# If this NPC doesn’t have a quest attached, use normal dialogue.
	if quest_id == "":
		ui.show_dialogue(display_name, _get_time_based_dialogue(), f)
		return
		
	# --- Quest-aware behavior below ---

	# 1) Quest already active and not completed → in-progress lines
	if GameState.active_quests.has(quest_id):
		if quest_in_progress_lines.size() > 0:
			ui.show_dialogue(display_name, quest_in_progress_lines, f)
		else:
			ui.show_dialogue(display_name, dialogue_lines, f)
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
				ui.show_dialogue(display_name, quest_completed_lines, f)
			else:
				ui.show_dialogue(display_name, ["Thank you so much for your help!"], f)
		else:
			# Already claimed, show “after” lines
			if quest_after_thanks_lines.size() > 0:
				ui.show_dialogue(display_name, quest_after_thanks_lines, f)
			else:
				ui.show_dialogue(display_name, dialogue_lines, f)
		return

	# 3) Quest not started yet → offer + automatically accept
	var new_quest := _build_quest()
	if new_quest.is_empty():
		# Fallback to normal if something went wrong
		ui.show_dialogue(display_name, dialogue_lines, f)
		return

	GameState.add_quest(new_quest)
	_update_quest_icon()

	if quest_request_lines.size() > 0:
		ui.show_dialogue(display_name, quest_request_lines, f)
	else:
		ui.show_dialogue(display_name, dialogue_lines, f)

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
	
	print(GameState.has_turn_in_ready(npc_id))
	print(npc_id)
	
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
	# print("Proximity ENTER: ", body)
	_show_overhead_chatter()


func _on_ProximityArea_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	# print("Proximity EXIT: ", body)
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
	for q in quest_offers:
		if q != null and q.id == qid:
			return q
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
