@tool
extends Node2D
## Runs A rocky tower: draws the current room, rebuilds its walls and blocks,
## and walks the knight between procedurally generated rooms. The tower has
## five floors: floor 1 is the round chamber (tutorial.gd), floors 2-4 are
## generated here, and floor 5 is the mage's sanctum with the final cutscene.
## Winning unlocks an endless mode.

const Generator := preload("res://scripts/dungeon_generator.gd")
const STONE: Texture2D = preload("res://assets/stone.png")
const FLOOR_TILES: Texture2D = preload("res://assets/floor_tiles.png")
const WALL: Texture2D = preload("res://assets/wall.png")
const BLOCK: PackedScene = preload("res://scenes/stone_block.tscn")
const TORCH: PackedScene = preload("res://scenes/torch.tscn")
const Knight := preload("res://scripts/knight.gd")
const RockTrail := preload("res://scripts/rock_trail.gd")
const HeadingArrow := preload("res://scripts/heading_arrow.gd")
const ENEMY_SCENES := {
	"slime": preload("res://scenes/slime.tscn"),
	"skeleton": preload("res://scenes/skeleton.tscn"),
}
const MAGE: PackedScene = preload("res://scenes/mage.tscn")
## Red hearts while a knight, stone hearts while a rock.
const HEART: Texture2D = preload("res://assets/heart.png")
const HEART_STONE: Texture2D = preload("res://assets/heart_stone.png")
const MAX_HEALTH := 3
## Frames of the heart sheet: a bright flash, full, emptied, and broken.
enum HeartFrame { FLASH, FULL, EMPTY, BROKEN }
## Enemies never spawn this close to the door the player came in by.
const ENEMY_SAFE_DISTANCE := 192.0
## Floor 3 is a dim red and crawling with enemies. The tints colour the room
## itself (floor, walls, blocks), never the player, enemies or torches.
const RED_FLOOR := 3
const RED_TINT := Color(0.8, 0.36, 0.32)
## Floor 4 is red as hell: a deep red that pulses, a vignette and embers.
const HELL_TINT := Color(1.3, 0.22, 0.16)
const HELL_TINT_BRIGHT := Color(1.6, 0.3, 0.18)
## Floor 4 is a long maze: 20+ rooms, stairs at least 8 doors from the
## start, and enemies as fast as the player's run, with red eyes.
const FAST_FLOOR := 4
const FAST_FLOOR_ROOMS := 22
## Floor 4 enemies are tough: this many sword hits each.
const FAST_FLOOR_ENEMY_HITS := 5
const FAST_FLOOR_EXIT_DISTANCE := 8
const ENRAGED_SIGHT := 300.0
## Where the mage waits in the sanctum.
const MAGE_SPOT := CENTER - Vector2(0, 160)
const FINALE_RANGE := 200.0
const TUTORIAL := "res://scenes/tutorial.tscn"
const MAIN_MENU := "res://scenes/main_menu.tscn"
const FIRST_DUNGEON_FLOOR := 2
const FINAL_FLOOR := 5
## Every room has a pair of torches on the north wall; the generator adds more.
const FIXED_TORCH_X: Array[float] = [176.0, 592.0]
const ITEM_ART := {
	"sword": preload("res://assets/sword.png"),
	"potion": preload("res://assets/potion.png"),
	"bubble": preload("res://assets/bubble.png"),
}
const ITEM_NAMES := {"sword": "a violet sword", "potion": "a blue potion", "bubble": "a bubble charm"}
## The sword is kept once found. Potions and bubbles are used up, and then
## reappear in the room they came from, so they must be picked up again.
const SWING_TIME := 0.18
const SWING_COOLDOWN := 0.35
const SWING_REACH := 46.0
const SWING_ARC := deg_to_rad(80.0)
## Drinking a potion: a heart back every REGEN_STEP seconds, REGEN_HEARTS
## times, and faster movement for BOOST_TIME seconds.
const REGEN_HEARTS := 3
const REGEN_STEP := 1.5
const BOOST_TIME := 8.0
const BOOST_FACTOR := 1.5
## A bubble traps the enemy that hit you for this long. With
## BUBBLE_BLOCKS_DAMAGE the hit itself does no harm.
const BUBBLE_TIME := 8.0
const BUBBLE_BLOCKS_DAMAGE := true
const TILE := 32
const ORIGIN := Vector2(32, 64)
const COLUMNS := Generator.COLS + 2
const ROWS := Generator.ROWS + 2
const ROOM_SIZE := Vector2(COLUMNS * TILE, ROWS * TILE)
const ROOM_END := ORIGIN + ROOM_SIZE
## Top-left of the walkable interior (inside the perimeter wall).
const INTERIOR := ORIGIN + Vector2(TILE, TILE)
const INTERIOR_SIZE := Vector2(Generator.COLS * TILE, Generator.ROWS * TILE)
const INNER_END := INTERIOR + INTERIOR_SIZE
const CENTER := INTERIOR + INTERIOR_SIZE / 2.0
const START_SPAWN := Vector2(CENTER.x, INNER_END.y - 64)
const ACCENT := Color("af9be9")
const ITEM_COLOR := Color("7fe0d0")
const MAX_ROOMS := 18
## All per-direction tables run north, east, south, west.
const WALLS: Array[Rect2] = [
	Rect2(ORIGIN, Vector2(ROOM_SIZE.x, TILE)),
	Rect2(INNER_END.x, ORIGIN.y, TILE, ROOM_SIZE.y),
	Rect2(ORIGIN.x, INNER_END.y, ROOM_SIZE.x, TILE),
	Rect2(ORIGIN, Vector2(TILE, ROOM_SIZE.y)),
]
## Two wall tiles are left open, centred on each side.
const DOOR_GAPS: Array[Rect2] = [
	Rect2(CENTER.x - TILE, ORIGIN.y, TILE * 2, TILE),
	Rect2(INNER_END.x, CENTER.y - TILE, TILE, TILE * 2),
	Rect2(CENTER.x - TILE, INNER_END.y, TILE * 2, TILE),
	Rect2(ORIGIN.x, CENTER.y - TILE, TILE, TILE * 2),
]
## Walking into the outer half of a doorway moves to the next room.
const DOOR_TRIGGERS: Array[Rect2] = [
	Rect2(CENTER.x - TILE, ORIGIN.y, TILE * 2, 14),
	Rect2(ROOM_END.x - 14, CENTER.y - TILE, 14, TILE * 2),
	Rect2(CENTER.x - TILE, ROOM_END.y - 14, TILE * 2, 14),
	Rect2(ORIGIN.x, CENTER.y - TILE, 14, TILE * 2),
]
## Thin walls just past each doorway keep the knight inside during transitions.
const DOOR_STOPS: Array[Rect2] = [
	Rect2(CENTER.x - TILE, ORIGIN.y - 16, TILE * 2, 16),
	Rect2(ROOM_END.x, CENTER.y - TILE, 16, TILE * 2),
	Rect2(CENTER.x - TILE, ROOM_END.y, TILE * 2, 16),
	Rect2(ORIGIN.x - 16, CENTER.y - TILE, 16, TILE * 2),
]
## Where the knight stands after arriving through each door.
const DOOR_SPAWNS: Array[Vector2] = [
	Vector2(CENTER.x, INTERIOR.y + 34),
	Vector2(INNER_END.x - 22, CENTER.y + 6),
	Vector2(CENTER.x, INNER_END.y - 6),
	Vector2(INTERIOR.x + 22, CENTER.y + 6),
]
const STAIRS := Rect2(CENTER - Vector2(TILE, TILE), Vector2(TILE * 2, TILE * 2))

@export var dungeon_seed := 0 ## 0 rolls a new dungeon every run.
@export var first_floor_rooms := 8
@export var fade_time := 0.12
## Off in movement tests, so wandering slimes cannot nudge the player.
@export var enemies := true

var generator := Generator.new()
var rooms: Dictionary = {}
var current: Generator.Room
var floor_number := FIRST_DUNGEON_FLOOR
## Set after beating floor 5 and choosing to keep going.
var endless := false
var victory_shown := false
var rooms_explored := 0
var health := MAX_HEALTH
var hearts: Array[TextureRect] = []
var floor_tint := Color.WHITE
var hell_overlay: CanvasLayer
var hell_pulse: Tween
var trail: Node2D
var finale_mage: Node2D
var finale_started := false
var laughing := false
var finale_line: Label
var finale_time := 0.0
## Where cutscenes have panned the camera; screen shake wobbles around it.
var camera_pan := Vector2.ZERO
var start_msec := 0
var inventory := {"sword": 0, "potion": 0, "bubble": 0}
## For each carried item, where it was found: [floor, room cell].
var item_sources := {"sword": [], "potion": [], "bubble": []}
var swing_ready := true
var item_counts := {}
var run_seed := 0
var entry_point := START_SPAWN
var entry_faces_left := false
var transitioning := false
var status_label: Label
var progress_label: Label
var caption_label: Label
var fps_label: Label
var minimap: Control
var item_slots := {}
var fade: ColorRect

@onready var knight: CharacterBody2D = $Knight
@onready var boundaries: Node2D = $Boundaries
@onready var blocks: Node2D = $Blocks
@onready var props: Node2D = $Props
@onready var front_walls: Node2D = $FrontWalls

func _ready() -> void:
	front_walls.draw.connect(draw_front_walls)
	if Engine.is_editor_hint():
		return
	configure_input()
	make_interface()
	var arrow := HeadingArrow.new()
	arrow.name = "HeadingArrow"
	arrow.z_index = 1
	knight.add_child(arrow)
	trail = RockTrail.new()
	trail.name = "RockTrail"
	trail.target = knight
	add_child(trail)
	run_seed = dungeon_seed if dungeon_seed != 0 else randi()
	print("A rocky tower, seed %d" % run_seed)
	begin()

## The dungeon is explored in rock form; tutorial.gd overrides this.
func begin() -> void:
	knight.call("set_rock", true)
	refresh_hearts()
	start_msec = Time.get_ticks_msec()
	start_floor()
	fade.color.a = 1.0
	fade_to(0.0)

## The Settings autoload owns the key bindings (and lets players change
## them); these defaults only apply if a scene runs without it.
func configure_input() -> void:
	if get_node_or_null("/root/Settings"):
		return
	bind_keys("move_left", [KEY_A, KEY_LEFT])
	bind_keys("move_right", [KEY_D, KEY_RIGHT])
	bind_keys("move_up", [KEY_W, KEY_UP])
	bind_keys("move_down", [KEY_S, KEY_DOWN])
	bind_keys("sprint", [KEY_SHIFT])
	bind_keys("reset", [KEY_R])
	bind_keys("quit", [KEY_ESCAPE])

func bind_keys(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key: Key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed("reset") and not transitioning:
		knight.call("reset_to", entry_point, entry_faces_left)
	if event.is_action_pressed("attack"):
		swing()
	if event.is_action_pressed("drink"):
		drink_potion()
	if event.is_action_pressed("quit"):
		get_tree().change_scene_to_file(MAIN_MENU)

# --- Floor and room flow -----------------------------------------------------

func start_floor() -> void:
	apply_floor_tint()
	trail.clear_all()
	if is_final_floor():
		rooms = {Vector2i.ZERO: make_sanctum()}
	else:
		var min_distance := FAST_FLOOR_EXIT_DISTANCE if is_fast_floor() else 0
		rooms = generator.generate(hash([run_seed, floor_number]), floor_room_count(), min_distance)
	if endless:
		play_music("finale" if floor_number % 2 == 1 else "keep")
	else:
		play_music("finale" if is_final_floor() else "keep")
	enter_room(Vector2i.ZERO, -1)

func is_final_floor() -> bool:
	return floor_number == FINAL_FLOOR and not endless

func is_red_floor() -> bool:
	return floor_number == RED_FLOOR and not endless

func is_fast_floor() -> bool:
	return floor_number == FAST_FLOOR and not endless

func apply_floor_tint() -> void:
	if hell_pulse:
		hell_pulse.kill()
		hell_pulse = null
	hell_overlay.visible = is_fast_floor()
	if is_fast_floor():
		set_floor_tint(HELL_TINT)
		hell_pulse = create_tween().set_loops()
		hell_pulse.tween_method(set_floor_tint, HELL_TINT, HELL_TINT_BRIGHT, 1.1).set_trans(Tween.TRANS_SINE)
		hell_pulse.tween_method(set_floor_tint, HELL_TINT_BRIGHT, HELL_TINT, 1.1).set_trans(Tween.TRANS_SINE)
	else:
		set_floor_tint(RED_TINT if is_red_floor() else Color.WHITE)

## Tints the room's own drawing, its blocks and its front walls.
func set_floor_tint(color: Color) -> void:
	floor_tint = color
	self_modulate = color
	blocks.modulate = color
	front_walls.modulate = color

func floor_room_count() -> int:
	if endless:
		return mini(first_floor_rooms + (floor_number - FINAL_FLOOR) * 2, MAX_ROOMS)
	if is_fast_floor():
		return FAST_FLOOR_ROOMS
	return first_floor_rooms + (floor_number - FIRST_DUNGEON_FLOOR) * 2

## Floor 5 is a single hall: no doors, no enemies, just the mage.
func make_sanctum() -> Generator.Room:
	var sanctum := Generator.Room.new()
	sanctum.kind = "final"
	sanctum.layout = "The Sanctum"
	sanctum.tiled_floor = true
	sanctum.blocks.assign([Vector2i(4, 5), Vector2i(15, 5), Vector2i(4, 10), Vector2i(15, 10), Vector2i(4, 15), Vector2i(15, 15)])
	sanctum.torches.assign([0, 7, 12, 19])
	return sanctum

func play_music(track: String) -> void:
	var music := get_node_or_null("/root/Music")
	if music:
		music.call("play", track)

## `via` is the door the knight arrives through, or -1 for the floor's start.
func enter_room(cell: Vector2i, via: int) -> void:
	current = rooms[cell]
	if not current.visited:
		rooms_explored += 1
	current.visited = true
	for direction in range(4):
		if current.doors[direction]:
			rooms[cell + Generator.OFFSETS[direction]].seen = true
	# Move the knight before the new triggers exist, so the door it just used
	# cannot fire again in the next room.
	entry_point = START_SPAWN if via < 0 else DOOR_SPAWNS[via]
	entry_faces_left = via == Generator.EAST
	knight.call("reset_to", entry_point, entry_faces_left)
	if trail:
		trail.show_room(cell)
	rebuild()
	queue_redraw()
	front_walls.queue_redraw()
	update_hud()

func travel(direction: int) -> void:
	knight.set_physics_process(false)
	await fade_to(1.0)
	enter_room(current.cell + Generator.OFFSETS[direction], Generator.opposite(direction))
	await fade_to(0.0)
	knight.set_physics_process(true)
	transitioning = false

func descend() -> void:
	knight.set_physics_process(false)
	await fade_to(1.0)
	floor_number += 1
	start_floor()
	await fade_to(0.0)
	knight.set_physics_process(true)
	transitioning = false

func fade_to(alpha: float) -> void:
	if fade_time <= 0.0:
		fade.color.a = alpha
		return
	var tween := create_tween()
	tween.tween_property(fade, "color:a", alpha, fade_time)
	await tween.finished

func _on_door_entered(body: Node2D, direction: int) -> void:
	# Physics can report a stale overlap right after a room swap; trust only
	# a knight still in an open doorway. Check the whole passage: the feet
	# can overlap a side trigger before their centre reaches that trigger.
	var inside := DOOR_GAPS[direction].has_point(knight.position)
	if body == knight and has_door(direction) and inside and not transitioning:
		transitioning = true
		travel.call_deferred(direction)

func _on_stairs_entered(body: Node2D) -> void:
	if body == knight and not transitioning:
		transitioning = true
		descend.call_deferred()

func _on_item_entered(body: Node2D, pickup: Area2D) -> void:
	# As with doors, ignore a stale overlap reported just after a room swap.
	var close := knight.position.distance_to(pickup.position) < 32.0
	if body != knight or current.item_taken or not close:
		return
	collect(current.item)
	pickup.queue_free()

func collect(item: String) -> void:
	current.item_taken = true
	inventory[item] += 1
	item_sources[item].append([floor_number, current.cell])
	update_hud()

## Uses up a potion or bubble. It reappears in the room it came from, the
## next time that room is entered.
func use_item(item: String) -> void:
	inventory[item] -= 1
	var source: Array = item_sources[item].pop_back()
	if source and source[0] == floor_number and rooms.has(source[1]):
		rooms[source[1]].item_taken = false
	update_hud()

# --- Items ---------------------------------------------------------------------

## The sword sweeps an arc in the direction the player last moved (or the
## brain heading) and defeats every enemy it touches, trapped ones included.
func swing() -> void:
	if inventory.sword <= 0 or not swing_ready or transitioning or health <= 0:
		return
	swing_ready = false
	var brain := get_node_or_null("/root/BrainLink")
	var aim: Vector2 = brain.heading_vector() if brain and brain.enabled() else knight.get("aim")
	var body := knight.position + Vector2(0, -10)
	var pivot := Node2D.new()
	pivot.position = Vector2(0, -10)
	pivot.z_index = 1
	knight.add_child(pivot)
	var blade := Sprite2D.new()
	blade.texture = ITEM_ART.sword
	blade.scale = Vector2(0.25, 0.25)
	# The art points up and to the right; turn it to point along +X.
	blade.rotation = PI / 4.0
	blade.position = Vector2(16, 0)
	# Brightened so the dark blade reads against the dark floor.
	blade.modulate = Color(1.7, 1.6, 2.0)
	pivot.add_child(blade)
	# A white swoosh along the arc, fading out.
	var swoosh := Line2D.new()
	swoosh.position = Vector2(0, -10)
	swoosh.z_index = 1
	swoosh.width = 3.0
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.85)])
	swoosh.gradient = fade
	for step in range(9):
		var angle := lerpf(aim.angle() - SWING_ARC, aim.angle() + SWING_ARC, step / 8.0)
		swoosh.add_point(Vector2.from_angle(angle) * 28.0)
	knight.add_child(swoosh)
	var trail_fade := swoosh.create_tween()
	trail_fade.tween_property(swoosh, "modulate:a", 0.0, SWING_TIME + 0.12)
	trail_fade.tween_callback(swoosh.queue_free)
	var sweep := pivot.create_tween()
	pivot.rotation = aim.angle() - SWING_ARC
	sweep.tween_property(pivot, "rotation", aim.angle() + SWING_ARC, SWING_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	sweep.tween_callback(pivot.queue_free)
	for node in props.get_children():
		if not node.has_method("defeat"):
			continue
		var offset: Vector2 = node.position + Vector2(0, -10) - body
		if offset.length() <= SWING_REACH and absf(aim.angle_to(offset)) <= SWING_ARC + 0.3:
			var defeated: bool = node.call("take_hit", knight.position)
			burst(node.position + Vector2(0, -12), Color("e1d6fb"), 10 if defeated else 5)
	await get_tree().create_timer(SWING_COOLDOWN).timeout
	swing_ready = true

## Regenerates hearts over a few seconds and speeds the player up.
func drink_potion() -> void:
	if inventory.potion <= 0 or transitioning or health <= 0:
		return
	use_item("potion")
	knight.call("boost", BOOST_TIME, BOOST_FACTOR)
	burst(knight.position + Vector2(0, -12), Color("7fc8ff"), 12)
	caption_label.text = "You drink the potion: hearts mend and your steps quicken."
	var regen := create_tween()
	for step in range(REGEN_HEARTS):
		regen.tween_interval(REGEN_STEP)
		regen.tween_callback(heal)

# --- Building the room ------------------------------------------------------

func rebuild() -> void:
	clear_room()
	build_walls()
	place_blocks()
	place_torches()
	if current.kind == "exit":
		make_area(STAIRS.grow(-12), props).body_entered.connect(_on_stairs_entered)
	if current.kind == "treasure" and not current.item_taken:
		make_item()
	if current.kind == "final" and not finale_started:
		finale_mage = MAGE.instantiate()
		finale_mage.position = MAGE_SPOT
		blocks.add_child(finale_mage)
	spawn_enemies()

func clear_room() -> void:
	for container: Node in [boundaries, blocks, props]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()

func build_walls() -> void:
	for direction in range(4):
		if current.doors[direction]:
			for part in split_wall(WALLS[direction], DOOR_GAPS[direction], direction % 2 == 0):
				make_wall(part)
			if direction % 2 == 1:
				make_door_lintel(direction)
			make_wall(DOOR_STOPS[direction])
			make_area(DOOR_TRIGGERS[direction], boundaries).body_entered.connect(_on_door_entered.bind(direction))
		else:
			make_wall(WALLS[direction])

func place_blocks() -> void:
	var solid := {}
	for cell in current.blocks:
		solid[cell] = true
	for cell in current.blocks:
		var block: Node2D = BLOCK.instantiate()
		# Art and collider both fill exactly this floor tile.
		block.position = INTERIOR + Vector2(cell) * TILE + Vector2(TILE / 2, TILE / 2)
		var mask := 0
		for direction in range(4):
			if solid.has(cell + Generator.OFFSETS[direction]):
				mask |= 1 << direction
		block.set("neighbours", mask)
		blocks.add_child(block)

## Torches hang on the north wall face, behind anything standing in the room.
func place_torches() -> void:
	var xs: Array[float] = FIXED_TORCH_X.duplicate()
	for column in current.torches:
		xs.append(INTERIOR.x + column * TILE + TILE / 2.0)
	for x in xs:
		make_torch(Vector2(x, INTERIOR.y - 2))

## Slimes and skeletons. The same room always gets the same spawn points.
func spawn_enemies() -> void:
	if not enemies or current.kind not in ["normal", "exit"]:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, floor_number, current.cell])
	var count := enemy_count(rng)
	var blocked := {}
	for cell in current.blocks:
		blocked[cell] = true
	for cell in Generator.required_floor(current):
		blocked[cell] = true
	for attempt in range(count * 12):
		if count <= 0:
			return
		var cell := Vector2i(rng.randi_range(1, Generator.COLS - 2), rng.randi_range(1, Generator.ROWS - 2))
		var at := INTERIOR + Vector2(cell) * TILE + Vector2(TILE / 2, TILE - 4)
		if blocked.has(cell) or at.distance_to(entry_point) < ENEMY_SAFE_DISTANCE:
			continue
		blocked[cell] = true
		spawn_enemy("skeleton" if rng.randf() < 0.45 else "slime", at)
		count -= 1

func enemy_count(rng: RandomNumberGenerator) -> int:
	if endless:
		return clampi(3 + (floor_number - FINAL_FLOOR) / 2 + rng.randi_range(0, 1), 3, 7)
	match floor_number:
		2:
			return rng.randi_range(2, 3)
		RED_FLOOR:
			return rng.randi_range(5, 7)
		FAST_FLOOR:
			return rng.randi_range(3, 4)
	return 0

func spawn_enemy(kind: String, at: Vector2) -> CharacterBody2D:
	var enemy: CharacterBody2D = ENEMY_SCENES[kind].instantiate()
	enemy.position = at
	enemy.set("target", knight)
	enemy.connect("touched", take_damage.bind(enemy))
	if is_fast_floor():
		enemy.call("enrage", Knight.RUN_SPEED, ENRAGED_SIGHT)
		enemy.set("max_hits", FAST_FLOOR_ENEMY_HITS)
	props.add_child(enemy)
	return enemy

func make_torch(at: Vector2) -> Node2D:
	var torch: Node2D = TORCH.instantiate()
	torch.position = at
	props.add_child(torch)
	return torch

static func split_wall(wall: Rect2, gap: Rect2, horizontal: bool) -> Array[Rect2]:
	if horizontal:
		return [Rect2(wall.position, Vector2(gap.position.x - wall.position.x, wall.size.y)),
			Rect2(gap.end.x, wall.position.y, wall.end.x - gap.end.x, wall.size.y)]
	return [Rect2(wall.position, Vector2(wall.size.x, gap.position.y - wall.position.y)),
		Rect2(wall.position.x, gap.end.y, wall.size.x, wall.end.y - gap.end.y)]

func make_wall(bounds: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = bounds.get_center()
	body.add_child(make_shape(bounds.size))
	boundaries.add_child(body)

func make_area(bounds: Rect2, parent: Node) -> Area2D:
	var area := Area2D.new()
	area.position = bounds.get_center()
	area.monitorable = false
	# Doors, stairs and pickups only care about the player.
	area.collision_mask = Knight.LAYER
	area.add_child(make_shape(bounds.size))
	parent.add_child(area)
	return area

static func make_shape(size: Vector2) -> CollisionShape2D:
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	return collision

func make_door_lintel(direction: int) -> void:
	# Sort the tile above a side doorway at the jamb's base, just like a
	# pillar. Feet below it place the head in front; feet above stay behind.
	# Blocks is already Y-sorted with the knight, and cleared on room swaps.
	var lintel := Node2D.new()
	lintel.name = "DoorLintel%d" % direction
	lintel.position = DOOR_GAPS[direction].position
	lintel.draw.connect(draw_door_lintel.bind(lintel, direction))
	blocks.add_child(lintel)

func make_item() -> void:
	var pickup := make_area(Rect2(CENTER.x - 10, CENTER.y - 4, 20, 16), props)
	pickup.position = CENTER + Vector2(0, 10)
	pickup.get_child(0).position = Vector2(0, -6)
	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([Vector2(-9, -2), Vector2(9, -2), Vector2(9, 1), Vector2(-9, 1)])
	shadow.color = Color(0, 0, 0.02, 0.45)
	pickup.add_child(shadow)
	var art := Sprite2D.new()
	art.texture = ITEM_ART[current.item]
	art.scale = Vector2(0.25, 0.25)
	art.offset = Vector2(0, -88)
	pickup.add_child(art)
	var bob := art.create_tween().set_loops()
	bob.tween_property(art, "position:y", -3.0, 0.6).set_trans(Tween.TRANS_SINE)
	bob.tween_property(art, "position:y", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	pickup.body_entered.connect(_on_item_entered.bind(pickup))

# --- HUD -------------------------------------------------------------------

func make_interface() -> void:
	var curtain := CanvasLayer.new()
	curtain.layer = 5
	add_child(curtain)
	fade = ColorRect.new()
	fade.color = Color(0.028, 0.022, 0.064, 0.0)
	fade.size = Vector2(768, 512)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curtain.add_child(fade)
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 10
	add_child(hud)
	# The camera moves the room beneath the HUD; keep text and icons readable.
	for bounds in [Rect2(0, 0, 768, 60), Rect2(0, 458, 768, 54)]:
		var panel := ColorRect.new()
		panel.position = bounds.position
		panel.size = bounds.size
		panel.color = Color("070510")
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(panel)
	make_label(hud, "A ROCKY TOWER", Vector2(32, 19), 21, Color("e1d6fb"))
	status_label = make_label(hud, "", Vector2(236, 18), 12, ACCENT)
	progress_label = make_label(hud, "", Vector2(236, 35), 10, Color("8a7cab"))
	make_label(hud, controls_hint(), Vector2(32, 466), 13, Color("c5bdd8"))
	var right := make_label(hud, "%s  back to door     Esc  menu" % key_hint("reset", "R"), Vector2(400, 466), 13, Color("9284b1"))
	right.size.x = 336
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label = make_label(hud, "FPS --", Vector2(32, 491), 10, Color("9284b1"))
	caption_label = make_label(hud, "", Vector2(96, 491), 10, Color("75678e"))
	var fps_timer := Timer.new()
	fps_timer.wait_time = 0.25
	fps_timer.autostart = true
	fps_timer.timeout.connect(func() -> void: fps_label.text = "FPS %d" % Engine.get_frames_per_second())
	hud.add_child(fps_timer)
	# The health bar sits over the top-left corner of the view.
	make_hell_overlay()
	var heart_row := HBoxContainer.new()
	heart_row.name = "Hearts"
	heart_row.position = Vector2(14, 66)
	heart_row.add_theme_constant_override("separation", 2)
	heart_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(heart_row)
	for index in range(MAX_HEALTH):
		var heart := TextureRect.new()
		var frame := AtlasTexture.new()
		frame.atlas = HEART
		heart.texture = frame
		heart.custom_minimum_size = Vector2(32, 32)
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart_row.add_child(heart)
		hearts.append(heart)
		set_heart_frame(index, HeartFrame.FULL)
	var slots := HBoxContainer.new()
	slots.position = Vector2(440, 14)
	slots.add_theme_constant_override("separation", 6)
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(slots)
	for item: String in ITEM_ART:
		var icon := TextureRect.new()
		icon.texture = ITEM_ART[item]
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = ITEM_NAMES[item]
		slots.add_child(icon)
		item_slots[item] = icon
		# "x2" when carrying more than one.
		var count := make_label(icon, "", Vector2(16, 14), 10, Color("f0e5ff"))
		count.add_theme_constant_override("outline_size", 4)
		count.add_theme_color_override("font_outline_color", Color("07050f"))
		item_counts[item] = count
	minimap = Control.new()
	minimap.position = Vector2(560, 6)
	minimap.size = Vector2(176, 52)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(draw_minimap)
	hud.add_child(minimap)

## Floor 4's screen dressing: red edges and embers rising from below. It sits
## under the HUD and the fade curtain, and is hidden on every other floor.
func make_hell_overlay() -> void:
	hell_overlay = CanvasLayer.new()
	hell_overlay.name = "HellOverlay"
	hell_overlay.layer = 4
	hell_overlay.visible = false
	add_child(hell_overlay)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(0.6, 0.0, 0.0, 0.0), Color(0.6, 0.0, 0.0, 0.0), Color(0.55, 0.0, 0.02, 0.6)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.05, 0.5)
	var vignette := TextureRect.new()
	vignette.texture = texture
	vignette.size = Vector2(768, 512)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hell_overlay.add_child(vignette)
	var embers := CPUParticles2D.new()
	embers.position = Vector2(384, 470)
	embers.amount = 48
	embers.lifetime = 4.5
	embers.preprocess = 4.5
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(400, 8)
	embers.direction = Vector2.UP
	embers.spread = 25.0
	embers.gravity = Vector2(0, -12)
	embers.initial_velocity_min = 25.0
	embers.initial_velocity_max = 70.0
	embers.scale_amount_min = 1.5
	embers.scale_amount_max = 3.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1.0, 0.75, 0.3, 0.95), Color(1.0, 0.15, 0.05, 0.0)])
	embers.color_ramp = ramp
	hell_overlay.add_child(embers)

# --- Health ------------------------------------------------------------------

func set_heart_frame(index: int, frame: HeartFrame) -> void:
	var atlas := hearts[index].texture as AtlasTexture
	atlas.atlas = HEART_STONE if knight.get("rock") else HEART
	var size := atlas.atlas.get_width()
	atlas.region = Rect2(0, frame * size, size, size)

## Redraws every heart, e.g. after the knight turns to stone.
func refresh_hearts() -> void:
	for index in range(MAX_HEALTH):
		set_heart_frame(index, HeartFrame.FULL if index < health else HeartFrame.BROKEN)

## Steps one heart through a few frames of the sheet.
func animate_heart(index: int, frames: Array, step := 0.07) -> void:
	var tween := hearts[index].create_tween()
	for frame: HeartFrame in frames:
		tween.tween_callback(set_heart_frame.bind(index, frame))
		tween.tween_interval(step)

## Called by anything that hurts the player, with where the hurt came from.
func take_damage(from: Vector2, attacker: Node = null) -> void:
	if transitioning or health <= 0 or knight.call("is_invulnerable"):
		return
	# A carried bubble springs out and traps whatever hit the player.
	if attacker and inventory.bubble > 0 and attacker.has_method("trap") and not attacker.call("is_trapped"):
		use_item("bubble")
		attacker.call("trap", BUBBLE_TIME)
		burst(attacker.position + Vector2(0, -16), Color("bfe4ff"), 12)
		caption_label.text = "Your bubble caught it!"
		if BUBBLE_BLOCKS_DAMAGE:
			knight.call("hurt", from)
			return
	health -= 1
	knight.call("hurt", from)
	# The lost heart flashes, empties and cracks.
	animate_heart(health, [HeartFrame.FLASH, HeartFrame.FULL, HeartFrame.FLASH, HeartFrame.EMPTY, HeartFrame.BROKEN])
	if health == 0:
		game_over()

func heal() -> void:
	if health >= MAX_HEALTH:
		return
	animate_heart(health, [HeartFrame.FLASH, HeartFrame.FULL])
	health += 1

func restore_health() -> void:
	health = MAX_HEALTH
	for index in range(MAX_HEALTH):
		set_heart_frame(index, HeartFrame.FULL)

func game_over() -> void:
	transitioning = true
	knight.set_physics_process(false)
	knight.velocity = Vector2.ZERO
	burst(knight.position + Vector2(0, -10), Color("8f86a8"), 18)
	var crumble := knight.create_tween()
	crumble.tween_property(knight, "modulate:a", 0.0, 0.5)
	await crumble.finished
	var where := "floor %d" % floor_number
	show_menu("GameOver", "YOU CRUMBLED", [
		"Out of hearts on %s." % where,
		"%d rooms explored" % rooms_explored,
	], [
		["Try %s again" % where, retry_floor],
		["Back to the round chamber", func() -> void: get_tree().change_scene_to_file(TUTORIAL)],
		["Main menu", func() -> void: get_tree().change_scene_to_file(MAIN_MENU)],
	])

## Rebuilds the same floor (same seed, same layout) with full hearts.
func retry_floor(layer: CanvasLayer) -> void:
	layer.queue_free()
	await fade_to(1.0)
	restore_health()
	knight.modulate.a = 1.0
	start_floor()
	await fade_to(0.0)
	knight.set_physics_process(true)
	transitioning = false

## How to use an item, with the player's own key or brain signal.
func item_hint(item: String) -> String:
	match item:
		"sword":
			var signal_name := brain_signal_for("swing")
			return "%s to swing it." % (signal_name if signal_name != "" else key_hint("attack", "Space"))
		"potion":
			var signal_name := brain_signal_for("drink")
			return "%s to drink it: hearts mend and you speed up." % (signal_name if signal_name != "" else key_hint("drink", "Q"))
		"bubble":
			return "It will trap the next enemy that hits you."
	return ""

## The first key bound to an action, as the player set it in Settings.
func key_hint(action: String, fallback: String) -> String:
	var settings := get_node_or_null("/root/Settings")
	return settings.call("first_key", action) if settings else fallback

## The bottom-left reminder: brain signals when the headset is in use.
func controls_hint() -> String:
	var settings := get_node_or_null("/root/Settings")
	if settings and settings.brain_enabled:
		return settings.brain_hint()
	return "%s  move     %s  run     %s  swing     %s  drink" % [move_keys_text(), key_hint("sprint", "Shift"), key_hint("attack", "Space"), key_hint("drink", "Q")]

## Tutorial wording for an action: the brain signal if the headset is on.
func brain_signal_for(action: String) -> String:
	var settings := get_node_or_null("/root/Settings")
	if settings and settings.brain_enabled:
		return settings.signal_doing(action)
	return ""

func move_keys_text() -> String:
	return "/".join(["move_up", "move_left", "move_down", "move_right"].map(
		func(action: String) -> String: return key_hint(action, "WASD"[["move_up", "move_left", "move_down", "move_right"].find(action)])))

func make_label(parent: Node, caption: String, at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func update_hud() -> void:
	var explored := 0
	for room: Generator.Room in rooms.values():
		if room.visited:
			explored += 1
	var floor_text := "FLOOR %d  /  ENDLESS" % floor_number if endless else "FLOOR %d OF %d" % [floor_number, FINAL_FLOOR]
	status_label.text = "%s  /  %s" % [floor_text, current.layout.to_upper()]
	progress_label.text = "%d OF %d ROOMS EXPLORED" % [explored, rooms.size()]
	for item: String in item_slots:
		# Items not found yet show as dark silhouettes.
		item_slots[item].modulate = Color.WHITE if inventory[item] > 0 else Color(0.3, 0.25, 0.45, 0.55)
		item_counts[item].text = "x%d" % inventory[item] if inventory[item] > 1 else ""
	match current.kind:
		"start":
			if endless:
				caption_label.text = "The endless depths, floor %d. How far down does the tower go?" % floor_number
			elif floor_number == FIRST_DUNGEON_FLOOR:
				caption_label.text = "Stone, but still moving. Slimes and skeletons roam these halls."
			elif is_red_floor():
				caption_label.text = "The tower runs red. Every room is crawling."
			elif is_fast_floor():
				caption_label.text = "Their eyes burn red and they run as fast as you. The stairs are far."
			else:
				caption_label.text = "Floor %d. The stairs sealed behind you." % floor_number
		"exit":
			if floor_number == FINAL_FLOOR - 1 and not endless:
				caption_label.text = "These stairs lead down to the mage's sanctum."
			else:
				caption_label.text = "Stairs spiral down into the dark. Step on them to descend."
		"final":
			caption_label.text = "" if finale_started else "The mage waits at the end of the hall."
		"treasure":
			caption_label.text = "Something glints here." if not current.item_taken else "You found %s. %s" % [ITEM_NAMES[current.item], item_hint(current.item)]
		_:
			caption_label.text = "Seed %d" % run_seed
	minimap.queue_redraw()

func draw_minimap() -> void:
	var low := Vector2i(999, 999)
	var high := Vector2i(-999, -999)
	for cell: Vector2i in rooms:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	var span := high - low + Vector2i.ONE
	var pitch := Vector2(minf(minimap.size.x / span.x, 18.0), minf(minimap.size.y / span.y, 11.0))
	var origin := Vector2(minimap.size.x - pitch.x * span.x, (minimap.size.y - pitch.y * span.y) / 2.0)
	var cell_size := pitch - Vector2(3, 3)
	for room: Generator.Room in rooms.values():
		if not room.visited:
			continue
		var center := origin + Vector2(room.cell - low) * pitch + cell_size / 2.0
		for direction in [Generator.EAST, Generator.SOUTH]:
			var other: Generator.Room = rooms.get(room.cell + Generator.OFFSETS[direction])
			if room.doors[direction] and other and (other.visited or other.seen):
				minimap.draw_line(center, center + Vector2(Generator.OFFSETS[direction]) * pitch, Color("3d3158"), 1.0)
	for room: Generator.Room in rooms.values():
		if not (room.visited or room.seen):
			continue
		var rect := Rect2(origin + Vector2(room.cell - low) * pitch, cell_size)
		if room == current:
			minimap.draw_rect(rect, ACCENT)
		elif room.visited:
			minimap.draw_rect(rect, Color("574a7a"))
		else:
			minimap.draw_rect(rect, Color("1a1430"))
			minimap.draw_rect(rect, Color("3d3158"), false, 1.0)
		var dot := Rect2(rect.get_center() - Vector2(1.5, 1.5), Vector2(3, 3))
		if room.kind == "exit":
			minimap.draw_rect(dot.grow(0.5), Color("0a0716"))
		elif room.kind == "treasure" and not room.item_taken:
			minimap.draw_rect(dot, ITEM_COLOR)

# --- Drawing ----------------------------------------------------------------

func has_door(direction: int) -> bool:
	return current != null and current.doors[direction]

## Returns the direction of the open doorway covering a wall tile, or -1.
func doorway_at(column: int, row: int) -> int:
	var edges := [row == 0, column == COLUMNS - 1, row == ROWS - 1, column == 0]
	for direction in range(4):
		var along := column if direction % 2 == 0 else row
		var middle := COLUMNS / 2 if direction % 2 == 0 else ROWS / 2
		if edges[direction] and has_door(direction) and (along == middle - 1 or along == middle):
			return direction
	return -1

func _draw() -> void:
	var kind := current.kind if current else "start"
	# Each floor down is drawn a little colder and darker.
	var depth_tint := 1.0 - 0.05 * clampf(floor_number - 1, 0, 5)
	draw_rect(Rect2(ORIGIN + Vector2(8, 14), ROOM_SIZE), Color("04040e"))
	draw_rect(Rect2(ORIGIN - Vector2(2, 2), ROOM_SIZE + Vector2(4, 4)), Color("3a2b51"))
	for row in range(ROWS):
		for column in range(COLUMNS):
			var at := ORIGIN + Vector2(column, row) * TILE
			var rect := Rect2(at, Vector2(TILE, TILE))
			var doorway := doorway_at(column, row)
			if doorway >= 0:
				draw_doorway(rect, doorway)
			elif is_front_wall(column, row):
				continue
			elif row == 0:
				draw_wall(rect, self, true)
			else:
				var brightness := (0.70 + float((column * 7 + row * 3) % 5) * 0.025) * depth_tint
				if (column == 10 or column == 11) and (has_door(Generator.NORTH) or has_door(Generator.SOUTH)):
					brightness += 0.13
				var floor_art := FLOOR_TILES if current and current.tiled_floor else STONE
				if floor_art == FLOOR_TILES:
					brightness += 0.35
				draw_texture_rect(floor_art, rect, false, Color(brightness, brightness, brightness * 1.13))
				draw_rect(rect, Color(0.18, 0.14, 0.3, 0.15), false, 1.0)
	draw_rect(Rect2(INTERIOR, Vector2(INTERIOR_SIZE.x, 10)), Color(0, 0, 0.03, 0.38))
	# Side shadows meet the north/south strips without dark double overlaps.
	var side_shadow_height := INTERIOR_SIZE.y - 17
	draw_rect(Rect2(INTERIOR + Vector2(0, 10), Vector2(7, side_shadow_height)), Color(0, 0, 0.03, 0.28))
	draw_rect(Rect2(INNER_END.x - 7, INTERIOR.y + 10, 7, side_shadow_height), Color(0, 0, 0.03, 0.28))
	draw_rect(Rect2(INTERIOR.x, INNER_END.y - 7, INTERIOR_SIZE.x, 7), Color(0, 0, 0.03, 0.22))
	# The north face and its trim sit behind the knight.
	draw_edge(Rect2(INTERIOR - Vector2(3, 3), Vector2(INTERIOR_SIZE.x + 6, 3)), Color("766187"), Generator.NORTH, self)
	for direction in range(4):
		if has_door(direction):
			draw_door_threshold(direction)
	match kind:
		"start":
			draw_compass(Color("655381"))
		"treasure":
			draw_compass(Color("2f6a68"))
		"exit":
			draw_stairs()
		"final":
			draw_sanctum()

## The side and south walls cover sprites outside the room. The upper side
## door jambs are separate Y-sorted pieces so they do not cover a head when
## the feet are already standing inside the open passage.
static func is_front_wall(column: int, row: int) -> bool:
	return column == 0 or column == COLUMNS - 1 or row == ROWS - 1

func draw_front_walls() -> void:
	for row in range(ROWS):
		for column in range(COLUMNS):
			if not is_front_wall(column, row):
				continue
			var rect := Rect2(ORIGIN + Vector2(column, row) * TILE, Vector2(TILE, TILE))
			# Open passages are ground, already drawn below the knight.
			var upper_jamb := row == ROWS / 2 - 2 and (
				(column == 0 and has_door(Generator.WEST)) or
				(column == COLUMNS - 1 and has_door(Generator.EAST)))
			if doorway_at(column, row) < 0 and not upper_jamb:
				# Corner tiles continue the vertical wall. A north-face base
				# shadow here would draw a false seam across that wall.
				draw_wall(rect, front_walls)
	# The inner trim turns around the floor opening. Its vertical runs start
	# at the north edge, instead of cutting through the north wall's face.
	# Both the inner and outer outlines leave the entire doorway open.
	var light := Color("766187")
	draw_edge(Rect2(INTERIOR - Vector2(3, 3), Vector2(3, INTERIOR_SIZE.y + 6)), light, Generator.WEST)
	draw_edge(Rect2(INNER_END.x, INTERIOR.y - 3, 3, INTERIOR_SIZE.y + 6), light, Generator.EAST)
	draw_edge(Rect2(INTERIOR.x - 3, INNER_END.y, INTERIOR_SIZE.x + 6, 3), light, Generator.SOUTH)
	draw_edge(Rect2(ORIGIN, Vector2(ROOM_SIZE.x, 3)), light, Generator.NORTH)
	draw_edge(Rect2(ORIGIN, Vector2(3, ROOM_SIZE.y)), light, Generator.WEST)
	draw_edge(Rect2(ROOM_END.x - 3, ORIGIN.y, 3, ROOM_SIZE.y), light, Generator.EAST)
	draw_edge(Rect2(ORIGIN.x, ROOM_END.y - 3, ROOM_SIZE.x, 3), light, Generator.SOUTH)
	for direction in range(4):
		if has_door(direction):
			draw_door_frame(front_walls, direction)
	var outline := Color("21192f")
	draw_edge(Rect2(ORIGIN, Vector2(ROOM_SIZE.x, 1)), outline, Generator.NORTH)
	draw_edge(Rect2(ROOM_END.x - 1, ORIGIN.y, 1, ROOM_SIZE.y), outline, Generator.EAST)
	draw_edge(Rect2(ORIGIN.x, ROOM_END.y - 1, ROOM_SIZE.x, 1), outline, Generator.SOUTH)
	draw_edge(Rect2(ORIGIN, Vector2(1, ROOM_SIZE.y)), outline, Generator.WEST)

## Draws a continuous wall edge, skipping the doorway on that side.
func draw_edge(strip: Rect2, color: Color, side: int, canvas: CanvasItem = null) -> void:
	var target := front_walls if canvas == null else canvas
	if not has_door(side):
		target.draw_rect(strip, color)
		return
	var gap := DOOR_GAPS[side]
	if side % 2 == 1:
		# This tile and its trim are drawn by the Y-sorted upper jamb.
		gap = Rect2(gap.position - Vector2(0, TILE), gap.size + Vector2(0, TILE))
	for part in split_wall(strip, gap, side % 2 == 0):
		target.draw_rect(part, color)

## Brick tiles join without seams. The north wall is seen face-on, so it is
## shaded toward its base where it meets the floor.
func draw_wall(rect: Rect2, canvas: CanvasItem = self, north_face := false) -> void:
	canvas.draw_texture_rect(WALL, rect, false, Color(1.25, 1.1, 1.4))
	if north_face:
		canvas.draw_rect(Rect2(rect.position + Vector2(0, 20), Vector2(32, 12)), Color(0.02, 0.01, 0.05, 0.3))
		canvas.draw_rect(Rect2(rect.position + Vector2(0, 30), Vector2(32, 2)), Color("151023"))

## A dim strip of floor that fades into darkness toward the next room.
func draw_doorway(rect: Rect2, direction: int, canvas: CanvasItem = self) -> void:
	canvas.draw_texture_rect(STONE, rect, false, Color(0.5, 0.45, 0.62))
	for band in range(4):
		var depth := float(band) * 8.0
		var strip: Rect2
		match direction:
			Generator.NORTH:
				strip = Rect2(rect.position.x, rect.position.y + depth, 32, 8)
			Generator.SOUTH:
				strip = Rect2(rect.position.x, rect.end.y - depth - 8, 32, 8)
			Generator.WEST:
				strip = Rect2(rect.position.x + depth, rect.position.y, 8, 32)
			_:
				strip = Rect2(rect.end.x - depth - 8, rect.position.y, 8, 32)
		canvas.draw_rect(strip, Color(0.016, 0.012, 0.04, 0.9 - band * 0.25))

func draw_door_frame(canvas: CanvasItem, direction: int) -> void:
	var gap := DOOR_GAPS[direction]
	var post := Color("8f7bb0")
	# Only the solid jambs belong above the character.
	if direction % 2 == 0:
		canvas.draw_rect(Rect2(gap.position.x - 4, gap.position.y, 4, 32), post)
		canvas.draw_rect(Rect2(gap.end.x, gap.position.y, 4, 32), post)
	else:
		canvas.draw_rect(Rect2(gap.position.x, gap.end.y, 32, 4), post)

func draw_door_lintel(canvas: Node2D, direction: int) -> void:
	draw_wall(Rect2(0, -TILE, TILE, TILE), canvas)
	var inner_x := 0 if direction == Generator.EAST else TILE - 3
	var outer_x := TILE - 3 if direction == Generator.EAST else 0
	var outline_x := TILE - 1 if direction == Generator.EAST else 0
	canvas.draw_rect(Rect2(inner_x, -TILE, 3, TILE), Color("766187"))
	canvas.draw_rect(Rect2(outer_x, -TILE, 3, TILE), Color("766187"))
	canvas.draw_rect(Rect2(0, -4, TILE, 4), Color("8f7bb0"))
	canvas.draw_rect(Rect2(outline_x, -TILE, 1, TILE), Color("21192f"))

func draw_door_threshold(direction: int) -> void:
	# This is floor trim, so the knight walks over it rather than behind it.
	var gap := DOOR_GAPS[direction]
	var threshold := Color("8870b1")
	if direction % 2 == 0:
		var inner_y := gap.end.y - 3 if direction == Generator.NORTH else gap.position.y
		draw_rect(Rect2(gap.position.x, inner_y, 64, 3), threshold)
	else:
		var inner_x := gap.end.x - 3 if direction == Generator.WEST else gap.position.x
		draw_rect(Rect2(inner_x, gap.position.y, 3, 64), threshold)

func draw_compass(color: Color) -> void:
	draw_line(CENTER + Vector2(0, -18), CENTER + Vector2(0, 18), color, 2.0)
	draw_line(CENTER + Vector2(-18, 0), CENTER + Vector2(18, 0), color, 2.0)
	draw_polyline(PackedVector2Array([CENTER + Vector2(0, -12), CENTER + Vector2(12, 0), CENTER + Vector2(0, 12), CENTER + Vector2(-12, 0), CENTER + Vector2(0, -12)]), color, 2.0)
	draw_rect(Rect2(CENTER - Vector2(2, 2), Vector2(4, 4)), ACCENT)

func draw_stairs() -> void:
	draw_rect(STAIRS.grow(4), Color("19122c"))
	draw_rect(STAIRS, Color("05040b"))
	# Each step is narrower and darker, so the flight reads as going down.
	for step in range(5):
		var shade := 1.5 - step * 0.28
		var strip := Rect2(STAIRS.position.x + 4 + step * 3, STAIRS.position.y + 4 + step * 12, 56 - step * 6, 10)
		draw_texture_rect(WALL, strip, false, Color(shade, shade * 0.9, shade * 1.2))
		draw_rect(Rect2(strip.position, Vector2(strip.size.x, 2)), Color(0.8, 0.7, 1.0, shade * 0.6))
		draw_rect(Rect2(strip.position + Vector2(0, 10), Vector2(strip.size.x, 2)), Color(0, 0, 0.02, 0.8))
	draw_rect(STAIRS.grow(4), ACCENT, false, 1.0)

## A runner from the entrance to the mage's rune circle.
func draw_sanctum() -> void:
	var runner := Rect2(CENTER.x - 16, MAGE_SPOT.y + 60, 32, START_SPAWN.y - MAGE_SPOT.y - 40)
	draw_rect(runner, Color("241536"))
	draw_rect(Rect2(runner.position, Vector2(2, runner.size.y)), Color("6f459b"))
	draw_rect(Rect2(runner.end.x - 2, runner.position.y, 2, runner.size.y), Color("6f459b"))
	draw_circle(MAGE_SPOT, 64, Color("0b0818"))
	draw_arc(MAGE_SPOT, 64, 0, TAU, 96, ACCENT, 2.0)
	draw_arc(MAGE_SPOT, 50, 0, TAU, 96, Color("6f459b"), 2.0)
	for start in [-PI / 2, PI / 2]:
		var points := PackedVector2Array()
		for corner in range(4):
			points.append(MAGE_SPOT + Vector2.from_angle(start + TAU * corner / 3.0) * 50)
		draw_polyline(points, Color("c5b2ff"), 1.0)

# --- Ending -----------------------------------------------------------------

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(finale_mage):
		return
	var sprite: Sprite2D = finale_mage.get_node("Sprite")
	# The art faces left; it turns to watch the rock. Laughing shakes it.
	sprite.flip_h = knight.position.x > finale_mage.position.x + 4.0
	finale_time += delta * (10.0 if laughing else 2.0)
	sprite.frame = int(finale_time) % 2
	sprite.position.y = -2.0 * sprite.scale.y if laughing and int(finale_time) % 2 == 0 else 0.0
	if not finale_started and knight.position.distance_to(finale_mage.position) < FINALE_RANGE:
		play_finale()

## The final cutscene: the mage gloats, laughs, and leaves the player a rock.
func play_finale() -> void:
	finale_started = true
	transitioning = true
	knight.set_physics_process(false)
	knight.velocity = Vector2.ZERO
	knight.call("face", knight.position.x > finale_mage.position.x)
	update_hud()
	# The mage is tall: frame the shot between the two of them.
	await pan_camera((finale_mage.position - knight.position) / 2.0 + Vector2(0, -30))
	# Subtitles sit low on screen, clear of the HUD and the mage.
	finale_line = make_label($HUD, "", Vector2(0, 404), 15, Color("f0e5ff"))
	finale_line.size = Vector2(768, 24)
	finale_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	finale_line.add_theme_constant_override("outline_size", 6)
	finale_line.add_theme_color_override("font_outline_color", Color("07050f"))
	await mage_says("So the little rock rolled all the way down here.", 2.2)
	await mage_says("You came for a cure? There is no cure. There never was.", 2.6)
	await laugh(1.8)
	await mage_says("You'll be a rock... FOREVER!", 2.0)
	await laugh(2.2)
	finale_line.text = ""
	burst(finale_mage.position + Vector2(0, -42), Color("c5b2ff"), 18)
	var leave := finale_mage.create_tween()
	leave.tween_property(finale_mage, "modulate:a", 0.0, 0.4)
	await leave.finished
	finale_mage.queue_free()
	await wait(1.0)
	await fade_to(1.0)
	show_victory()

func mage_says(line: String, seconds: float) -> void:
	finale_line.text = line
	await wait(seconds)

## "HA HA HA" with the mage bouncing and the camera shaking.
func laugh(seconds: float) -> void:
	laughing = true
	finale_line.text = "HA HA HA HA HA!"
	var camera: Camera2D = knight.get_node_or_null("Camera2D")
	var elapsed := 0.0
	while elapsed < seconds:
		if camera:
			camera.offset = camera_pan + Vector2(randf_range(-3, 3), randf_range(-3, 3))
		await wait(0.05)
		elapsed += 0.05
	if camera:
		camera.offset = camera_pan
	laughing = false

## Slides the player's camera to an offset (Vector2.ZERO recentres it).
func pan_camera(offset: Vector2, seconds := 0.6) -> void:
	camera_pan = offset
	var camera: Camera2D = knight.get_node_or_null("Camera2D")
	if not camera:
		return
	var tween := camera.create_tween()
	tween.tween_property(camera, "offset", offset, seconds).set_trans(Tween.TRANS_SINE)
	await tween.finished

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func show_victory() -> void:
	victory_shown = true
	var seconds := (Time.get_ticks_msec() - start_msec) / 1000
	var found := 0
	for count: int in inventory.values():
		found += count
	show_menu("Victory", "YOU WIN", [
		"You reached the bottom of the rocky tower... and you are still a rock. Forever.",
		"%d:%02d in the tower  /  %d rooms explored  /  %d items found" % [seconds / 60, seconds % 60, rooms_explored, found],
	], [
		["Keep going: endless mode (still a rock)", continue_endless],
		["Play again from the start", func() -> void: get_tree().change_scene_to_file(TUTORIAL)],
		["Main menu", func() -> void: get_tree().change_scene_to_file(MAIN_MENU)],
	])

## A dimmed full-screen panel with a title, lines of text and buttons. The
## first choice's callable receives the menu's layer so it can close it.
func show_menu(layer_name: String, title: String, lines: Array, choices: Array) -> void:
	var layer := CanvasLayer.new()
	layer.name = layer_name
	layer.layer = 20
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.015, 0.05, 0.85)
	shade.size = Vector2(768, 512)
	layer.add_child(shade)
	var box := VBoxContainer.new()
	box.position = Vector2(164, 116)
	box.size = Vector2(440, 280)
	box.add_theme_constant_override("separation", 12)
	layer.add_child(box)
	var heading := make_label(box, title, Vector2.ZERO, 26, Color("e1d6fb"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for index in range(lines.size()):
		var label := make_label(box, lines[index], Vector2.ZERO, 12 if index == 0 else 11, ACCENT if index == 0 else Color("8a7cab"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var buttons: Array[Button] = []
	for index in range(choices.size()):
		var button := make_button(choices[index][0])
		var action: Callable = choices[index][1]
		button.pressed.connect(action.bind(layer) if index == 0 else action)
		box.add_child(button)
		buttons.append(button)
	buttons[0].grab_focus()

func make_button(caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(0, 30)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("c5bdd8"))
	button.add_theme_color_override("font_focus_color", Color("f0e5ff"))
	button.add_theme_color_override("font_hover_color", Color("f0e5ff"))
	for state in ["normal", "hover", "focus", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("1a1430") if state == "normal" else Color("2d2350")
		style.border_color = ACCENT if state != "normal" else Color("3d3158")
		style.set_border_width_all(1)
		button.add_theme_stylebox_override(state, style)
	return button

func continue_endless(layer: CanvasLayer) -> void:
	layer.queue_free()
	endless = true
	pan_camera(Vector2.ZERO, 0.0)
	await fade_to(1.0)
	floor_number += 1
	start_floor()
	await fade_to(0.0)
	knight.set_physics_process(true)
	transitioning = false

## Little squares that fly out and fade, for dust and magic.
func burst(at: Vector2, color: Color, count: int) -> void:
	for index in range(count):
		var bit := ColorRect.new()
		bit.size = Vector2(2, 2)
		bit.color = color
		bit.position = at
		bit.z_index = 2
		add_child(bit)
		var angle := TAU * index / count
		var fly := bit.create_tween()
		fly.set_parallel()
		fly.tween_property(bit, "position", at + Vector2.from_angle(angle) * randf_range(10, 22), 0.45).set_ease(Tween.EASE_OUT)
		fly.tween_property(bit, "modulate:a", 0.0, 0.45)
		fly.chain().tween_callback(bit.queue_free)
