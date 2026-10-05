extends SceneTree
## Plays through the prologue: walk, run, meet the mage, get turned to stone,
## and leave through the door that opens.

var failures := 0
var tutorial: Node2D
var knight: CharacterBody2D

func _initialize() -> void:
	# Default keys, whatever the player has rebound.
	root.get_node("Settings").use_defaults()
	call_deferred("run_checks")

func run_checks() -> void:
	Engine.time_scale = 4.0
	await check_headset()
	tutorial = load("res://scenes/tutorial.tscn").instantiate()
	tutorial.fade_time = 0.0
	root.add_child(tutorial)
	knight = tutorial.get_node("Knight")
	await ticks(3)
	var camera: Camera2D = knight.get_node("Camera2D")
	check(camera.is_current() and camera.zoom == Vector2.ONE, "Prologue uses the player camera at normal zoom")
	check(not knight.rock and tutorial.step == tutorial.Step.WALK, "Prologue starts as a knight with the walking lesson")
	check(not tutorial.current.doors[0], "North door starts sealed")
	check(tutorial.mage_sprite.scale.x >= 3.0, "The mage is drawn big")
	var red_heart: AtlasTexture = tutorial.get_node("HUD/Hearts").get_child(0).texture
	check(red_heart.atlas.resource_path.ends_with("heart.png"), "A knight has red hearts")
	check(tutorial.status_label.text.begins_with("FLOOR 1 OF 5"), "The round chamber is floor 1 of 5")
	check(tutorial.props.get_child_count() == tutorial.TORCH_ANGLES.size(), "Torches line the chamber wall")
	await hold([KEY_A], 60)
	check(knight.position.distance_to(tutorial.CENTER) < tutorial.RING_INNER, "The round wall keeps the knight inside")
	knight.call("reset_to", tutorial.SPAWN)
	tutorial.walked = 0.0
	await hold([KEY_D], 12)
	check(tutorial.step == tutorial.Step.RUN, "Walking finishes the first lesson")
	knight.call("reset_to", Vector2(220, 450))
	await hold([KEY_D, KEY_SHIFT], 12)
	check(tutorial.step == tutorial.Step.APPROACH, "Running finishes the second lesson")
	knight.call("reset_to", Vector2(384, 300))
	await hold([KEY_W], 20)
	check(tutorial.step == tutorial.Step.CURSE, "Approaching the mage starts the curse")
	for attempt in range(600):
		if tutorial.step == tutorial.Step.ESCAPE:
			break
		await ticks(1)
	check(tutorial.step == tutorial.Step.ESCAPE, "Curse scene plays through")
	check(knight.rock and knight.get_node("KnightSprite").texture.resource_path.ends_with("knight_rock.png"), "The knight is now a rock")
	check(not is_instance_valid(tutorial.mage), "The mage vanishes")
	var heart: AtlasTexture = tutorial.get_node("HUD/Hearts").get_child(0).texture
	check(heart.atlas.resource_path.ends_with("heart_stone.png"), "Hearts turn to stone with the knight")
	check(tutorial.current.doors[0], "North door opens")
	knight.call("reset_to", tutorial.CENTER - Vector2(0, tutorial.RING_INNER - 30))
	await hold([KEY_W], 20)
	check(tutorial.left, "Walking through the north door leaves for the dungeon")
	await ticks(3)
	if failures == 0:
		print("PASS: All prologue checks.")
	quit(0 if failures == 0 else 1)

## The Unicorn detector connecting after the chamber opened: blink, shake and
## nod only, so no running lesson.
func check_headset() -> void:
	var settings: Node = root.get_node("Settings")
	settings.path = "user://test_tutorial_settings.cfg"
	settings.brain_port = 47125
	settings.apply()
	var chamber: Node2D = load("res://scenes/tutorial.tscn").instantiate()
	chamber.fade_time = 0.0
	root.add_child(chamber)
	await ticks(3)
	root.get_node("BrainLink").send_test("HELLO BLINK SHAKE NOD")
	await ticks(10)
	check(chamber.prompt.text == "Head shake to start or stop walking. Blink to turn.", "The lesson switches to the headset's signals when it connects")
	check(chamber.controls_label.text.begins_with("Blink turn"), "So does the reminder at the bottom")
	chamber.walked = chamber.LESSON_DISTANCE + 1.0
	await ticks(3)
	check(chamber.step == chamber.Step.APPROACH, "With no signal set to run, the running lesson is skipped")
	chamber.queue_free()
	await ticks(2)
	settings.use_defaults()

func hold(keys: Array, count: int) -> void:
	for keycode: Key in keys:
		key(keycode, true)
	await ticks(count)
	for keycode: Key in keys:
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
