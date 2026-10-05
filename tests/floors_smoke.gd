extends SceneTree
## The five-floor rules: enemy counts per floor, the red floor 3, the long
## and fast floor 4, and the floor 5 sanctum with its final cutscene.

const Generator := preload("res://scripts/dungeon_generator.gd")
const Knight := preload("res://scripts/knight.gd")
const SEED := 1234

var failures := 0
var room: Node2D
var knight: CharacterBody2D

func _initialize() -> void:
	# Default keys, whatever the player has rebound.
	root.get_node("Settings").use_defaults()
	call_deferred("run_checks")

func run_checks() -> void:
	var generator := Generator.new()
	var long_floors := 0
	for seed_value in range(1, 61):
		var rooms: Dictionary = generator.generate(seed_value, 22, 8)
		if rooms.size() == 22 and Generator.exit_distance(rooms) >= 8:
			long_floors += 1
	check(long_floors == 60, "60 seeded floor-4 plans: 22 rooms, stairs at least 8 doors away")

	Engine.time_scale = 4.0
	room = load("res://scenes/room.tscn").instantiate()
	room.dungeon_seed = SEED
	room.fade_time = 0.0
	root.add_child(room)
	knight = room.get_node("Knight")
	await ticks(3)
	var heart: AtlasTexture = room.get_node("HUD/Hearts").get_child(0).texture
	check(heart.atlas.resource_path.ends_with("heart_stone.png"), "A rock has stone hearts")

	var counts := await enemies_per_room()
	check(counts.min() >= 2 and counts.max() <= 3, "Floor 2: two or three enemies per room (%s)" % [counts])
	check(room.floor_tint == Color.WHITE and not room.hell_overlay.visible, "Floor 2 keeps its colours")

	await go_to_floor(3)
	counts = await enemies_per_room()
	check(counts.min() >= 5 and counts.max() <= 7, "Floor 3: five to seven enemies per room (%s)" % [counts])
	check(room.floor_tint == room.RED_TINT, "Floor 3 is a dim red")
	var floor_3_tint: Color = room.floor_tint

	await go_to_floor(4)
	check(room.rooms.size() >= 20, "Floor 4 has at least 20 rooms (%d)" % room.rooms.size())
	check(Generator.exit_distance(room.rooms) >= 8, "Floor 4 stairs are at least 8 rooms away (%d)" % Generator.exit_distance(room.rooms))
	check(room.hell_overlay.visible and room.floor_tint.r > floor_3_tint.r and room.floor_tint.g < floor_3_tint.g, "Floor 4 is a much deeper red, with the hell overlay")
	check(room.props.modulate == Color.WHITE, "Enemies and torches are not tinted, so red eyes stand out")
	var enemy := first_enemy_room()
	var sprite: Sprite2D = enemy.get_node("Sprite")
	check(enemy.chase_speed == Knight.RUN_SPEED, "Floor 4 enemies chase as fast as the player runs")
	check(sprite.texture.resource_path.ends_with("_red.png"), "Floor 4 enemies have red eyes")
	var kinds := {}
	for cell: Vector2i in room.rooms:
		room.enter_room(cell, -1)
		for node in room.props.get_children():
			if node.has_signal("touched"):
				kinds[node.scene_file_path.get_file()] = true
	check(kinds.has("slime.tscn") and kinds.has("skeleton.tscn"), "Both slimes and skeletons appear (%s)" % [kinds.keys()])

	await go_to_floor(5)
	check(room.rooms.size() == 1 and room.current.kind == "final" and room.current.door_count() == 0, "Floor 5 is a single final room")
	check(is_instance_valid(room.finale_mage), "The mage waits in the sanctum")
	check(room.finale_mage.get_node("Sprite").scale.x >= 3.0, "The mage is drawn big")
	check(room.floor_tint == Color.WHITE and not room.hell_overlay.visible, "The sanctum is not red")
	room.enemies = true
	room.rebuild()
	check(count_enemies() == 0, "No enemies in the sanctum")
	knight.call("reset_to", room.MAGE_SPOT + Vector2(0, 200))
	press(KEY_W, true)
	for attempt in range(60):
		if room.finale_started:
			break
		await ticks(1)
	press(KEY_W, false)
	check(room.finale_started, "Walking up to the mage starts the final cutscene")
	await ticks(20)
	check(room.finale_line.text != "", "The mage speaks")
	var laughed := false
	for attempt in range(1500):
		laughed = laughed or room.laughing
		if room.victory_shown:
			break
		await ticks(1)
	check(laughed, "The mage laughs")
	check(room.victory_shown and knight.rock, "The win screen appears and the player is still a rock")
	room.continue_endless(room.get_node("Victory"))
	await ticks(3)
	check(room.endless and room.floor_number == 6 and room.rooms.size() > 1 and not room.transitioning, "Endless mode continues to floor 6")
	room.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: All floor checks.")
	quit(0 if failures == 0 else 1)

func go_to_floor(number: int) -> void:
	room.enemies = false
	room.floor_number = number
	room.start_floor()
	await ticks(2)

## Visits every room with enemies on and counts what spawns.
func enemies_per_room() -> Array:
	room.enemies = true
	var counts := []
	for cell: Vector2i in room.rooms:
		if room.rooms[cell].kind == "normal":
			room.enter_room(cell, -1)
			counts.append(count_enemies())
	room.enemies = false
	await ticks(1)
	return counts

func first_enemy_room() -> CharacterBody2D:
	room.enemies = true
	for cell: Vector2i in room.rooms:
		room.enter_room(cell, -1)
		for node in room.props.get_children():
			if node.has_signal("touched"):
				return node
	return null

func count_enemies() -> int:
	return room.props.get_children().filter(func(node: Node) -> bool: return node.has_signal("touched")).size()

func press(keycode: Key, pressed: bool) -> void:
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
