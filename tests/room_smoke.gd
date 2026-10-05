extends SceneTree
## Exercises dungeon generation, input, physics, hitboxes, doors and stairs.

const Generator := preload("res://scripts/dungeon_generator.gd")
const SEED := 1234

var failures := 0
var room: Node2D
var knight: CharacterBody2D

func _initialize() -> void:
	# Default keys, whatever the player has rebound.
	root.get_node("Settings").use_defaults()
	call_deferred("run_checks")

func run_checks() -> void:
	check_generator()
	Engine.time_scale = 4.0
	room = load("res://scenes/room.tscn").instantiate()
	room.dungeon_seed = SEED
	room.enemies = false
	room.fade_time = 0.0
	root.add_child(room)
	knight = room.get_node("Knight")
	await ticks(3)
	var sprite: Sprite2D = knight.get_node("KnightSprite")
	check(sprite.vframes == 4, "Four frames per knight animation")
	check(knight.rock and sprite.texture.resource_path.ends_with("knight_rock.png"), "The dungeon is explored in rock form")
	check(room.current.kind == "start" and room.current.blocks.size() == 4, "Floor starts in the four-pillar hall")

	await check_movement()
	await check_hitboxes(sprite)
	await check_health()
	await check_trail()
	await check_carving()
	await check_doors()
	await check_gem_and_stairs()

	room.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: All dungeon, movement, collision and door checks.")
	quit(0 if failures == 0 else 1)

func check_generator() -> void:
	var generator := Generator.new()
	var bad_rooms := 0
	for seed_value in range(1, 301):
		var count := 8 + seed_value % 11
		var rooms: Dictionary = generator.generate(seed_value, count)
		var exits := 0
		for room_data: Generator.Room in rooms.values():
			if room_data.kind == "exit":
				exits += 1
				if room_data.door_count() != 1:
					bad_rooms += 1
			for direction in range(4):
				var other: Generator.Room = rooms.get(room_data.cell + Generator.OFFSETS[direction])
				if room_data.doors[direction] and (other == null or not other.doors[Generator.opposite(direction)]):
					bad_rooms += 1
			var blocked := {}
			for cell in room_data.blocks:
				blocked[cell] = true
			if not Generator.is_traversable(blocked, room_data):
				bad_rooms += 1
		if rooms.has(Generator.BELOW_START) or rooms[Vector2i.ZERO].doors[Generator.SOUTH]:
			bad_rooms += 1
		if rooms.size() != count or exits != 1 or reachable(rooms) != count or rooms[Vector2i.ZERO].kind != "start":
			bad_rooms += 1
	check(bad_rooms == 0, "300 seeded floors: right size, one dead-end exit, matching doors, every door reachable, nothing below the start")
	var a: Dictionary = generator.generate(42, 12)
	var b: Dictionary = generator.generate(42, 12)
	var same := a.keys() == b.keys()
	for cell in a:
		same = same and a[cell].blocks == b[cell].blocks and a[cell].torches == b[cell].torches and a[cell].doors == b[cell].doors and a[cell].layout == b[cell].layout
	check(same, "Same seed builds the same floor")

func reachable(rooms: Dictionary) -> int:
	var seen := {Vector2i.ZERO: true}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for direction in range(4):
			var next: Vector2i = cell + Generator.OFFSETS[direction]
			if rooms[cell].doors[direction] and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size()

func check_movement() -> void:
	var start: Vector2 = room.CENTER + Vector2(0, 32)
	knight.call("reset_to", start)
	key(KEY_D, true)
	await ticks(3)
	check(knight.position.x > start.x + 20, "Physical D key moves right")
	key(KEY_D, false)
	await ticks(2)
	var stopped := knight.position
	await ticks(3)
	check(knight.position.is_equal_approx(stopped), "Release stops movement")

	knight.call("reset_to", start)
	key(KEY_RIGHT, true)
	key(KEY_UP, true)
	await ticks(3)
	check(is_equal_approx(knight.velocity.length(), knight.WALK_SPEED), "Diagonal movement has equal speed")
	key(KEY_RIGHT, false)
	key(KEY_UP, false)
	await ticks(2)

	knight.call("reset_to", start)
	key(KEY_D, true)
	key(KEY_SHIFT, true)
	await ticks(3)
	check(is_equal_approx(knight.velocity.length(), knight.RUN_SPEED), "Shift increases movement speed")
	key(KEY_D, false)
	key(KEY_SHIFT, false)
	await ticks(2)

func check_hitboxes(sprite: Sprite2D) -> void:
	# The art's base sits right of the frame centre; the shift recentres it.
	knight.call("face", false)
	check(is_equal_approx(sprite.position.x, -knight.ROCK_SHIFT), "Base centred on collider facing right")
	knight.call("face", true)
	check(is_equal_approx(sprite.position.x, knight.ROCK_SHIFT), "Base centred on collider facing left")
	knight.call("set_rock", false)
	check(is_equal_approx(sprite.position.x, knight.SPRITE_SHIFT) and sprite.texture.resource_path.ends_with("knight_idle.png"), "Knight form uses its own sheet and shift")
	knight.call("set_rock", true)
	# Walls: the foot collider is 18x6 (the body's width) with the origin at the bottom of the feet.
	await push(Vector2(200, 160), KEY_A, 0, 73.0, "west wall")
	await push(Vector2(600, 160), KEY_D, 0, 695.0, "east wall")
	await push(Vector2(200, 200), KEY_W, 1, 102.0, "north wall")
	await push(Vector2(200, room.INNER_END.y - 160), KEY_S, 1, room.INNER_END.y, "south wall")
	# Find the north-west pillar in the taller layout; its art stays one tile.
	var cell: Vector2i = room.current.blocks[0]
	for candidate: Vector2i in room.current.blocks:
		if candidate.y < cell.y or (candidate.y == cell.y and candidate.x < cell.x):
			cell = candidate
	var bounds := Rect2(room.INTERIOR + Vector2(cell) * room.TILE, Vector2(room.TILE, room.TILE))
	var center := bounds.get_center()
	await push(center + Vector2(0, 80), KEY_W, 1, bounds.end.y + 6, "block from the south")
	await push(center - Vector2(0, 80), KEY_S, 1, bounds.position.y, "block from the north")
	await push(center - Vector2(64, 0), KEY_D, 0, bounds.position.x - 9, "block from the west")
	await push(center + Vector2(64, 0), KEY_A, 0, bounds.end.x + 9, "block from the east")
	knight.call("reset_to", center - Vector2(0, 24))
	check(knight.position.y < center.y and room.get_node("Blocks").y_sort_enabled, "Knight standing north of a block sorts behind it")

func check_doors() -> void:
	var direction: int = room.current.doors.find(true)
	var keys := [KEY_W, KEY_D, KEY_S, KEY_A]
	var inward := -Vector2(Generator.OFFSETS[direction]) * 40.0
	var target: Vector2i = room.current.cell + Generator.OFFSETS[direction]
	knight.call("reset_to", room.DOOR_SPAWNS[direction])
	await walk_until_room_changes(keys[direction])
	var back := Generator.opposite(direction)
	check(room.current.cell == target, "Walking through a door enters the neighbouring room (%s -> %s, wanted %s)" % [Vector2i.ZERO, room.current.cell, target])
	check(knight.position.distance_to(room.DOOR_SPAWNS[back]) < 1.0, "Knight arrives at the matching door")
	check(room.rooms[target].visited and room.rooms[Vector2i.ZERO].visited, "Visited rooms are remembered")
	knight.position += Vector2(Generator.OFFSETS[direction]) * 30.0
	var reset_event := InputEventKey.new()
	reset_event.physical_keycode = KEY_R
	reset_event.pressed = true
	room._unhandled_input(reset_event)
	check(knight.position.is_equal_approx(room.DOOR_SPAWNS[back]), "R returns to the door you came in by")
	await walk_until_room_changes(keys[back])
	check(room.current.cell == Vector2i.ZERO, "Walking back returns to the start room")
	check(inward != Vector2.ZERO, "Start room has at least one door")

func check_gem_and_stairs() -> void:
	var treasure := Vector2i(99, 99)
	var exit := Vector2i(99, 99)
	for cell: Vector2i in room.rooms:
		match room.rooms[cell].kind:
			"treasure":
				treasure = cell
			"exit":
				exit = cell
	if room.rooms.has(treasure):
		room.enter_room(treasure, -1)
		await walk_to_center()
		var item: String = room.current.item
		check(room.inventory[item] == 1 and room.current.item_taken, "Walking over the %s picks it up" % item)
	room.enter_room(exit, -1)
	await walk_to_center()
	await ticks(3)
	check(room.floor_number == 3 and room.current.cell == Vector2i.ZERO, "Stairs lead from floor 2 to floor 3")
	check(room.rooms.size() == room.first_floor_rooms + 2, "Each floor down has more rooms")
	check(room.props.get_children().filter(func(node: Node) -> bool: return node.has_node("Flame")).size() >= 2, "Rooms have animated torches")

## Holds a key only until the knight reaches another room.
func walk_until_room_changes(keycode: Key) -> void:
	var leaving: Vector2i = room.current.cell
	key(keycode, true)
	for attempt in range(40):
		await ticks(1)
		if room.current.cell != leaving:
			break
	key(keycode, false)
	await ticks(2)

## Stone chips fly while the rock moves, and only then.
func check_carving() -> void:
	var chips: CPUParticles2D = knight.get_node("Carving")
	knight.call("reset_to", room.CENTER)
	await ticks(3)
	check(not chips.emitting, "A still rock throws no chips")
	key(KEY_D, true)
	await ticks(4)
	check(chips.emitting and chips.direction.x < 0.0, "A moving rock throws chips back behind it")
	key(KEY_D, false)
	await ticks(3)
	check(not chips.emitting, "Chips stop when the rock stops")
	knight.call("set_rock", false)
	key(KEY_A, true)
	await ticks(4)
	check(not chips.emitting, "A knight throws no chips")
	key(KEY_A, false)
	await ticks(2)
	knight.call("set_rock", true)

## The rock drags a trail behind it that is gone 20 seconds later.
func check_trail() -> void:
	var trail: Node2D = room.trail
	knight.call("reset_to", room.CENTER)
	await ticks(2)
	var before: int = trail.current_marks().size()
	key(KEY_D, true)
	await ticks(10)
	key(KEY_D, false)
	await ticks(2)
	check(trail.current_marks().size() > before + 5, "The rock leaves a trail (%d marks)" % trail.current_marks().size())
	trail.clock += 18.0
	await ticks(2)
	check(trail.current_marks().size() > 0, "The trail is still there before 20 seconds")
	trail.clock += 2.5
	await ticks(2)
	check(trail.current_marks().is_empty(), "The trail is gone after 20 seconds")
	knight.call("set_rock", false)
	key(KEY_A, true)
	await ticks(10)
	key(KEY_A, false)
	await ticks(2)
	check(trail.current_marks().size() <= 1, "A knight leaves no trail")
	knight.call("set_rock", true)

## Hearts, slime contact, invulnerability, potions and running out of hearts.
func check_health() -> void:
	var hearts: Array = room.get_node("HUD/Hearts").get_children()
	check(hearts.size() == 3 and room.health == 3, "Health bar starts with three full hearts")
	knight.call("reset_to", room.CENTER)
	var slime: CharacterBody2D = room.spawn_enemy("slime", room.CENTER + Vector2(40, 0))
	for attempt in range(60):
		if room.health < 3:
			break
		await ticks(1)
	check(room.health == 2 and knight.is_invulnerable(), "Touching a slime costs a heart")
	await ticks(12)
	var region: Rect2 = hearts[2].texture.region
	check(region.position.y == room.HeartFrame.BROKEN * 128, "The lost heart shows the broken frame")
	room.take_damage(slime.position)
	check(room.health == 2, "No damage while blinking after a hit")
	slime.queue_free()
	room.heal()
	check(room.health == 3, "Healing refills a heart")
	for hit in range(3):
		knight.invulnerable = 0.0
		room.take_damage(knight.position + Vector2(10, 0))
	for attempt in range(60):
		if room.has_node("GameOver"):
			break
		await ticks(1)
	check(room.health == 0 and room.has_node("GameOver"), "Running out of hearts shows the game over menu")
	room.retry_floor(room.get_node("GameOver"))
	await ticks(3)
	check(room.health == 3 and not room.transitioning and room.floor_number == 2, "Retrying restores the hearts on the same floor")
	check(knight.modulate.a == 1.0 and knight.is_physics_processing(), "The player can move again after retrying")

func walk_to_center() -> void:
	knight.call("reset_to", room.CENTER + Vector2(0, 96))
	key(KEY_W, true)
	await ticks(12)
	key(KEY_W, false)
	await ticks(2)

func push(start: Vector2, keycode: Key, axis: int, limit: float, label: String) -> void:
	knight.call("reset_to", start)
	key(keycode, true)
	await ticks(40)
	var value: float = knight.position[axis]
	check(absf(value - limit) < 1.0, "Solid %s (stopped at %.1f, expected %.1f)" % [label, value, limit])
	key(keycode, false)
	await ticks(2)

func key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)

func ticks(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
