extends CharacterBody2D
class_name AnimalBase

# --- Movement & grid settings ---
@export var move_speed: float = 40.0
@export var grid_size: float = 32.0

var _path: Array[Vector2] = []
var _current_path_index: int = -1
var _has_destination: bool = false

# --- Idle wandering ---
@export var enable_idle_wander: bool = true
@export var wander_interval_min: float = 2.0
@export var wander_interval_max: float = 5.0
@export var wander_tile_distance: int = 2  # animals wander farther than NPCs

var _anchor_position: Vector2 = Vector2.ZERO
@onready var _wander_timer: Timer = $WanderTimer

# --- Feeding / product logic ---
@export var animal_id: String = ""
@export var product_item: String = "Egg"      # override per animal (Egg, Milk)
@export var produces_per_feed: int = 1

var fed_today: bool = false
var has_product_ready: bool = false

const GRID_SIZE: float = 32.0  # your tile size

# --- Overhead chatter / emotes ---
@export var idle_chatter_lines: Array[String] = []   # e.g. ["cluck", "cluck cluck", "*scratch*"]
@export var feed_chatter: String = "*munch*"
@export var pet_chatter: String = "*love*"
@export var collect_chatter: String = "*happy*"

@onready var chatter_label: Label = $BubbleAnchor/ChatterLabel
@onready var chatter_timer: Timer = $ChatterTimer
@onready var proximity_area: Area2D = $ProximityArea

@export var pen_area_path: NodePath   # assign your PenArea here in the Inspector
@export var pen_margin: float = 4.0   # keeps animals slightly inside edges

var _pen_rect_global: Rect2
var _has_pen: bool = false

var _last_pet_day: int = -999999
var f := GameState.get_friendship(animal_id)

var _pen_min_cell: Vector2i
var _pen_max_cell: Vector2i

func _ready() -> void:
	# Anchor = where the animal starts
	_anchor_position = _snap_to_grid(global_position)

	# Idle wandering
	_wander_timer.timeout.connect(_on_wander_timer_timeout)
	_schedule_next_wander()

	# Listen for day changes
	TimeManager.day_changed.connect(_on_day_changed)
	_refresh_pen_rect()


# =============================
#  GRID SNAP / MOVEMENT
# =============================

# Copy your NPC's _snap_to_grid implementation here
func _snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(
		round(pos.x / GRID_SIZE) * GRID_SIZE,
		round(pos.y / GRID_SIZE) * GRID_SIZE
	)

func set_destination(world_position: Vector2) -> void:
	# Snap start & target to grid, same as NPC version
	var start := _snap_to_grid(global_position)
	global_position = start

	var target := _snap_to_grid(world_position)
	target = _clamp_to_pen(target)

	_path.clear()
	_current_path_index = -1
	_has_destination = false

	# L-shaped path: vertical then horizontal
	var mid := Vector2(start.x, target.y)

	_path.append(mid)
	_path.append(target)

	_current_path_index = 0
	_has_destination = true


func _physics_process(delta: float) -> void:
	# Stop when UI overlays are active
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


# =============================
#  IDLE WANDER (like NPCs)
# =============================

func _schedule_next_wander() -> void:
	if not enable_idle_wander:
		return

	var wait_time := randf_range(wander_interval_min, wander_interval_max)
	_wander_timer.wait_time = wait_time
	_wander_timer.start()


func _on_wander_timer_timeout() -> void:
	if not enable_idle_wander:
		return

	if GameState.is_gameplay_locked():
		_schedule_next_wander()
		return

	# Don't interrupt another movement (e.g., being called to the pen)
	if _has_destination:
		_schedule_next_wander()
		return

	if _anchor_position == Vector2.ZERO:
		_anchor_position = _snap_to_grid(global_position)

	# If we are outside the pen somehow, go back inside immediately
	if _has_pen and not _pen_rect_global.has_point(global_position):
		var back := _clamp_to_pen(_snap_to_grid(global_position))
		set_destination(back)
		_schedule_next_wander()
		return

	_attempt_idle_wander()
	_schedule_next_wander()


func _attempt_idle_wander() -> void:
	# If we don't have a pen, fall back to simple behavior
	if not _has_pen:
		_attempt_idle_wander_no_pen()
		return

	# Anchor in cell coordinates
	var anchor_cell := Vector2i(
		int(round(_anchor_position.x / grid_size)),
		int(round(_anchor_position.y / grid_size))
	)

	# Build a small list of candidate cells within range (2 tiles or whatever)
	var candidates: Array[Vector2i] = []

	for dx in range(-wander_tile_distance, wander_tile_distance + 1):
		for dy in range(-wander_tile_distance, wander_tile_distance + 1):
			# Keep it “cozy”: prefer Manhattan moves (no diagonals)
			if abs(dx) + abs(dy) == 0:
				continue
			if abs(dx) + abs(dy) > wander_tile_distance:
				continue

			var c := anchor_cell + Vector2i(dx, dy)

			# Must be inside pen bounds
			if c.x < _pen_min_cell.x or c.x > _pen_max_cell.x:
				continue
			if c.y < _pen_min_cell.y or c.y > _pen_max_cell.y:
				continue

			candidates.append(c)

	# If pen is tiny (or margin too big), candidates might be empty
	if candidates.is_empty():
		return

	candidates.shuffle()

	for c in candidates:
		var world_target := Vector2(c.x * grid_size, c.y * grid_size)

		# Skip if basically current position
		if world_target.distance_to(global_position) < 1.0:
			continue

		# Later you can add obstacle checks here
		set_destination(world_target)
		return

func _attempt_idle_wander_no_pen() -> void:
	var dirs := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	dirs.shuffle()

	for dir in dirs:
		var candidate: Vector2 = _anchor_position + dir * grid_size * float(wander_tile_distance)
		candidate = _snap_to_grid(candidate)

		if candidate.distance_to(global_position) < 1.0:
			continue

		set_destination(candidate)
		return


func _can_wander_to(world_pos: Vector2) -> bool:
	if _has_pen and not _pen_rect_global.has_point(world_pos):
		return false

	# Later, this is where fence collisions / obstacle checks go.
	return true


# =============================
#  FEEDING & PRODUCT CYCLE
# =============================

func _on_day_changed(day: int) -> void:
	# If fed yesterday, then we have product ready today.
	if fed_today:
		has_product_ready = true

	# Reset fed flag for the new day
	fed_today = false


func feed() -> bool:
	# Returns true if feeding actually happened
	if fed_today:
		return false

	fed_today = true
	# Optional: play animation / show hearts / sound
	return true


func collect_product() -> bool:
	# Returns true if product was collected
	if not has_product_ready:
		return false

	GameState.inventory_add(product_item, produces_per_feed)
	has_product_ready = false

	# Optional: hearts, sound, etc.
	return true


# =============================
#  INTERACTION ENTRY POINT
# =============================

# We'll implement interact() in the next section once we define
# how we read the player's current item/tool.

func interact() -> void:
	# print("\n=== AnimalBase.interact() called ===")
	# print("Animal ID:", animal_id)

	var tool := GameState.current_tool
	var tool_name := GameState.get_tool_name()
	# print("Current tool:", tool, "(", tool_name, ")")

	# 1) Bucket: try to collect product
	if tool == GameState.ToolType.BUCKET:
		# print("Tool is BUCKET → trying to collect product.")
		_handle_bucket_interaction()
		return

	# 2) Hand: try to feed if not fed yet, otherwise pet
	if tool == GameState.ToolType.HAND:
		# print("Tool is HAND → trying to feed or pet.")

		if not fed_today:
			# print("Animal not fed today → attempting to feed from inventory.")
			var fed_successfully := _handle_feed_interaction()
			# print("Feeding result:", fed_successfully)
			if fed_successfully:
				print("Feeding succeeded → stopping interact() here.")
				return
			else:
				print("Feeding failed (maybe no Animal Feed).")

		# print("Either already fed or no feed available → petting instead.")
		_handle_pet_interaction()
		return

	# 3) Any other tool: just pet
	# print("Tool is not BUCKET or HAND → treating as pet.")
	_handle_pet_interaction()

func _handle_feed_interaction() -> bool:
	# print("[Feed] Entered _handle_feed_interaction()")
	# print("[Feed] fed_today before:", fed_today)

	if fed_today:
		print("[Feed] Animal already fed today → abort feeding.")
		return false

	var has_feed := GameState.inventory_has("Animal Feed", 1)
	# print("[Feed] GameState.inventory_has('Animal Feed', 1) =", has_feed)

	if not has_feed:
		print("[Feed] No Animal Feed in inventory → cannot feed.")
		return false

	var removed := GameState.inventory_remove("Animal Feed", 1)
	# print("[Feed] inventory_remove('Animal Feed', 1) =", removed)

	if not removed:
		print("[Feed] Failed to remove Animal Feed → abort.")
		return false

	fed_today = true
	print("[Feed] Animal successfully fed. fed_today now:", fed_today)

	# 🎈 CHATTTER: munch
	_show_chatter(feed_chatter)

	return true

func _handle_bucket_interaction() -> void:
	# print("[Bucket] Entered _handle_bucket_interaction()")
	# print("[Bucket] has_product_ready =", has_product_ready)

	if not has_product_ready:
		print("[Bucket] No product ready → nothing to collect.")
		return

	var collected := collect_product()
	print("[Bucket] collect_product() returned:", collected)

	if collected:
		print("[Bucket] Product collected →", product_item, "x", produces_per_feed)
		# 🎈 CHATTTER: happy/thanks
		_show_chatter(collect_chatter)

func _handle_pet_interaction() -> void:
	print("[Pet] Petting animal:", animal_id)

	# +1 friendship once per day
	_gain_friendship_once_per_day(1)

	_show_chatter(pet_chatter)

func _show_chatter(text: String) -> void:
	if chatter_label == null:
		return

	chatter_label.text = text
	chatter_label.visible = true

	if chatter_timer:
		chatter_timer.start(1.5)  # show for ~1.5 seconds (tune as you like)

func _hide_chatter() -> void:
	if chatter_label == null:
		return
	chatter_label.visible = false


func _show_idle_chatter() -> void:
	if idle_chatter_lines.is_empty():
		return

	var idx := randi() % idle_chatter_lines.size()
	var text := idle_chatter_lines[idx]
	_show_chatter(text)

func _on_ProximityArea_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	# Player came near → occasional idle cluck/moo
	print("Proximity ENTER: ", body)
	_show_idle_chatter()

func _on_ProximityArea_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	# You can either hide chatter immediately or let timer handle it.
	# We'll just let the timer finish; no extra code needed here for now.
	print("Proximity EXIT: ", body)
	_hide_chatter()


func _on_ChatterTimer_timeout() -> void:
	_hide_chatter()

func _refresh_pen_rect() -> void:
	# ... your existing code to set _pen_rect_global and _has_pen ...

	if not _has_pen:
		return

	# Convert pen rect into grid cell bounds
	var min_world := _pen_rect_global.position
	var max_world := _pen_rect_global.position + _pen_rect_global.size

	_pen_min_cell = Vector2i(
		int(floor(min_world.x / grid_size)),
		int(floor(min_world.y / grid_size))
	)

	_pen_max_cell = Vector2i(
		int(floor(max_world.x / grid_size)),
		int(floor(max_world.y / grid_size))
	)

	# Safety: ensure min <= max
	if _pen_max_cell.x < _pen_min_cell.x:
		_pen_max_cell.x = _pen_min_cell.x
	if _pen_max_cell.y < _pen_min_cell.y:
		_pen_max_cell.y = _pen_min_cell.y

func _clamp_to_pen(pos: Vector2) -> Vector2:
	if not _has_pen:
		return pos

	return Vector2(
		clamp(pos.x, _pen_rect_global.position.x, _pen_rect_global.position.x + _pen_rect_global.size.x),
		clamp(pos.y, _pen_rect_global.position.y, _pen_rect_global.position.y + _pen_rect_global.size.y)
	)

func _gain_friendship_once_per_day(amount: int) -> void:
	var day := TimeManager.day
	if _last_pet_day == day:
		return

	_last_pet_day = day
	GameState.add_friendship(animal_id, amount)
