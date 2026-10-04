extends SceneTree
## Exercises the actual input, physics, sprite sheets, and reset handler.

var failures := 0
var room: Node2D
var knight: CharacterBody2D

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	Engine.time_scale = 8.0
	room = load("res://scenes/room.tscn").instantiate()
	root.add_child(room)
	knight = room.get_node("Knight")
	await ticks(3)
	check(room.get_node("Boundaries").get_child_count() == 4, "Four solid room boundaries")
	check(knight.get_node("KnightSprite").vframes == 4, "Four frames per knight animation")
	check(knight.get_node("KnightSprite").texture.resource_path.ends_with("knight_idle.png"), "Idle sheet loaded")

	var start := Vector2(384, 288)
	knight.call("reset_to", start)
	key(KEY_D, true)
	await ticks(3)
	var walking_distance := knight.position.distance_to(start)
	check(knight.position.x > start.x + 20, "Physical D key moves right")
	check(knight.get_node("KnightSprite").texture.resource_path.ends_with("knight_walk.png"), "Movement selects walk sheet")
	key(KEY_D, false)
	await ticks(2)
	var stopped := knight.position
	await ticks(3)
	check(knight.position.is_equal_approx(stopped), "Release stops movement")
	check(knight.get_node("KnightSprite").texture.resource_path.ends_with("knight_idle.png"), "Stopping selects idle sheet")

	knight.call("reset_to", start)
	key(KEY_RIGHT, true)
	key(KEY_UP, true)
	await ticks(3)
	var diagonal_distance := knight.position.distance_to(start)
	check(absf(diagonal_distance - walking_distance) < 2.0, "Diagonal movement has equal speed")
	key(KEY_RIGHT, false)
	key(KEY_UP, false)
	await ticks(2)

	knight.call("reset_to", start)
	key(KEY_D, true)
	key(KEY_SHIFT, true)
	await ticks(3)
	check(knight.position.distance_to(start) > walking_distance * 1.4, "Shift increases movement speed")
	key(KEY_D, false)
	key(KEY_SHIFT, false)
	await ticks(2)

	await check_wall(Vector2(384, 256), KEY_W, "north", 1, 100.0, true)
	await check_wall(Vector2(384, 256), KEY_S, "south", 1, 412.0, false)
	await check_wall(Vector2(384, 256), KEY_A, "west", 0, 71.0, true)
	await check_wall(Vector2(384, 256), KEY_D, "east", 0, 697.0, false)

	knight.call("reset_to", Vector2(240, 260))
	key(KEY_W, true)
	await ticks(30)
	check(knight.position.y >= 218.0 and knight.position.y < 230.0, "Pillar blocks feet from the south")
	key(KEY_W, false)
	await ticks(2)
	knight.call("reset_to", Vector2(190, 204))
	key(KEY_D, true)
	await ticks(30)
	check(knight.position.x <= 218.1 and knight.position.x > 210.0, "Pillar blocks feet from the west")
	key(KEY_D, false)
	await ticks(2)

	var reset_event := InputEventKey.new()
	reset_event.physical_keycode = KEY_R
	reset_event.pressed = true
	room._unhandled_input(reset_event)
	check(knight.position.is_equal_approx(Vector2(384, 352)), "R restores the spawn position")
	check(knight.velocity.is_zero_approx(), "Reset clears velocity")
	room.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: All room movement, animation, input and collision checks.")
	quit(0 if failures == 0 else 1)

func check_wall(start: Vector2, keycode: Key, label: String, axis: int, limit: float, minimum: bool) -> void:
	knight.call("reset_to", start)
	key(keycode, true)
	await ticks(50)
	var value: float = knight.position[axis]
	check(value >= limit - 0.2 if minimum else value <= limit + 0.2, "Solid %s boundary" % label)
	check(absf(value - limit) < 1.0, "Knight reaches %s wall" % label)
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
