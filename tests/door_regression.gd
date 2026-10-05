extends SceneTree
## All door directions and both forms, including slow side-door overlaps.

const Generator := preload("res://scripts/dungeon_generator.gd")
const KEYS := [KEY_W, KEY_D, KEY_S, KEY_A]
var room: Node2D
var knight: CharacterBody2D
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	room = load("res://scenes/room.tscn").instantiate()
	room.dungeon_seed = 1234
	room.fade_time = 0.0
	root.add_child(room)
	knight = room.get_node("Knight")
	await ticks(3)
	check(room.ROOM_SIZE == Vector2(704, 768), "Room keeps its width and doubles its height")
	var camera: Camera2D = knight.get_node("Camera2D")
	check(camera.is_current() and camera.zoom == Vector2.ONE, "Player Camera2D is active at normal zoom")
	# A central room with four empty neighbours isolates door movement.
	var hall := Generator.Room.new()
	hall.kind = "start"
	hall.doors.fill(true)
	room.rooms = {Vector2i.ZERO: hall}
	for direction in range(4):
		var neighbour := Generator.Room.new()
		neighbour.cell = Generator.OFFSETS[direction]
		neighbour.doors[Generator.opposite(direction)] = true
		room.rooms[neighbour.cell] = neighbour
	for rock in [false, true]:
		knight.call("set_rock", rock)
		for direction in range(4):
			await cross_door(direction, 4.0, room.DOOR_SPAWNS[direction], true, rock)
		# A small step exposes callbacks rejected before the centre crosses
		# the old 8px trigger margin (the feet are 9px wide on either side).
		await cross_door(Generator.EAST, 0.1, Vector2(712.4, room.CENTER.y + 2), false, rock)
		await cross_door(Generator.WEST, 0.1, Vector2(55.6, room.CENTER.y + 2), false, rock)
		for direction in [Generator.EAST, Generator.WEST]:
			var gap: Rect2 = room.DOOR_GAPS[direction]
			for feet_y in [gap.position.y + 6.25, gap.end.y - 0.25]:
				var start: Vector2 = room.DOOR_SPAWNS[direction]
				start.y = feet_y
				await cross_door(direction, 1.0, start, false, rock)
				await cross_door(direction, 4.0, start, true, rock)
	room.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: Every doorway works for the knight and rock, walking and running.")
	quit(0 if failures == 0 else 1)

func cross_door(direction: int, time_scale: float, start: Vector2, sprint: bool, rock: bool) -> void:
	Engine.time_scale = time_scale
	room.enter_room(Vector2i.ZERO, -1)
	knight.call("reset_to", start)
	await ticks(3)
	press(KEYS[direction], true)
	if sprint:
		press(KEY_SHIFT, true)
	for attempt in range(90):
		await ticks(1)
		if room.current.cell != Vector2i.ZERO:
			break
	press(KEYS[direction], false)
	press(KEY_SHIFT, false)
	await ticks(2)
	var form := "rock" if rock else "knight"
	var mode := "sprinting" if sprint else "slow walking"
	check(room.current.cell == Generator.OFFSETS[direction], "%s %s through direction %d from %s (position %s)" % [form, mode, direction, start, knight.position])
	check(not room.transitioning and knight.is_physics_processing(), "Movement resumes after the door transition")
	var camera: Camera2D = knight.get_node("Camera2D")
	check(camera.get_screen_center_position().distance_to(knight.global_position) < 0.1, "Camera follows the player after moving and changing rooms")

func press(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)

func ticks(count: int) -> void:
	for frame in range(count):
		await physics_frame
	await process_frame

func check(condition: bool, caption: String) -> void:
	if condition:
		print("PASS: ", caption)
	else:
		failures += 1
		push_error("FAIL: " + caption)
