extends SceneTree
## The sword, the potion and the bubble, and picking used items up again.

const SEED := 1234

var failures := 0
var room: Node2D
var knight: CharacterBody2D

func _initialize() -> void:
	root.get_node("Settings").use_defaults()
	call_deferred("run_checks")

func run_checks() -> void:
	Engine.time_scale = 4.0
	room = load("res://scenes/room.tscn").instantiate()
	room.dungeon_seed = SEED
	room.fade_time = 0.0
	room.enemies = false
	root.add_child(room)
	knight = room.get_node("Knight")
	await ticks(3)
	await check_sword()
	await check_potion()
	await check_bubble()
	room.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: All item checks.")
	quit(0 if failures == 0 else 1)

func check_sword() -> void:
	knight.call("reset_to", room.CENTER)
	knight.aim = Vector2.RIGHT
	var ahead: Node = room.spawn_enemy("skeleton", room.CENTER + Vector2(30, 0))
	var behind: Node = room.spawn_enemy("slime", room.CENTER + Vector2(-60, 0))
	for enemy in [ahead, behind]:
		enemy.trap(30.0)
	room.swing()
	await ticks(10)
	check(is_instance_valid(ahead) and is_instance_valid(behind), "No sword, no swing")
	room.collect("sword")
	key(KEY_SPACE)
	await ticks(10)
	check(not is_instance_valid(ahead), "Space swings the sword and defeats the enemy in front")
	check(is_instance_valid(behind), "Enemies behind the swing are untouched")
	check(room.inventory.sword == 1, "The sword is kept after swinging")
	behind.queue_free()
	await ticks(2)

func check_potion() -> void:
	var cell := treasure_cell()
	room.enter_room(cell, -1)
	room.collect("potion")
	check(room.rooms[cell].item_taken, "Picking up the potion takes it from its room")
	knight.invulnerable = 0.0
	room.take_damage(knight.position + Vector2(10, 0))
	knight.invulnerable = 0.0
	room.take_damage(knight.position + Vector2(10, 0))
	check(room.health == 1, "Two hits leave one heart")
	key(KEY_Q)
	await ticks(3)
	check(knight.speed_boost > 1.0, "Drinking the potion speeds the player up")
	check(room.inventory.potion == 0 and not room.rooms[cell].item_taken, "The potion is used up and waits in its room again")
	for attempt in range(200):
		if room.health == room.MAX_HEALTH:
			break
		await ticks(1)
	check(room.health == room.MAX_HEALTH, "The potion regenerates hearts over time")
	room.enter_room(cell, -1)
	check(room.props.get_children().any(func(node: Node) -> bool: return node is Area2D and node.get_child_count() > 2), "Coming back, the potion is there to pick up again")
	knight.boost_left = 0.01
	await ticks(2)
	check(knight.speed_boost == 1.0, "The speed boost wears off")

func check_bubble() -> void:
	var cell := treasure_cell()
	room.enter_room(cell, -1)
	room.collect("bubble")
	knight.call("reset_to", room.CENTER + Vector2(0, 200))
	knight.invulnerable = 0.0
	var slime: Node = room.spawn_enemy("slime", knight.position + Vector2(36, 0))
	for attempt in range(80):
		if slime.is_trapped():
			break
		await ticks(1)
	check(slime.is_trapped(), "An enemy that hits the player is trapped in the bubble")
	check(room.health == room.MAX_HEALTH, "The bubble takes the hit")
	check(room.inventory.bubble == 0 and not room.rooms[cell].item_taken, "The bubble is used up and waits in its room again")
	knight.invulnerable = 0.0
	knight.position = slime.position
	await ticks(10)
	check(room.health == room.MAX_HEALTH, "A trapped enemy cannot hurt")
	room.collect("sword")
	knight.aim = Vector2.RIGHT
	knight.position = slime.position - Vector2(24, 0)
	room.swing()
	await ticks(10)
	check(not is_instance_valid(slime), "The sword pops a trapped enemy")
	knight.invulnerable = 0.0
	var other: Node = room.spawn_enemy("slime", knight.position + Vector2(36, 0))
	for attempt in range(80):
		if room.health < room.MAX_HEALTH:
			break
		await ticks(1)
	check(room.health == room.MAX_HEALTH - 1 and not other.is_trapped(), "Without a bubble, the next hit costs a heart")

func treasure_cell() -> Vector2i:
	for cell: Vector2i in room.rooms:
		if room.rooms[cell].kind == "treasure":
			return cell
	return Vector2i.ZERO

func key(keycode: Key) -> void:
	for pressed in [true, false]:
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
