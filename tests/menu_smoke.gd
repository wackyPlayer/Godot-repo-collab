extends SceneTree
## The main menu, key rebinding, saved settings and the three-signal brain link.

var failures := 0
var settings: Node
var brain: Node

func _initialize() -> void:
	settings = root.get_node("Settings")
	brain = root.get_node("BrainLink")
	settings.path = "user://test_settings.cfg"
	settings.use_defaults()
	call_deferred("run_checks")

func run_checks() -> void:
	# Rebinding and saving.
	settings.set_key("sprint", 0, KEY_X)
	check(has_key("sprint", KEY_X) and not has_key("sprint", KEY_SHIFT), "Run can be rebound to X")
	settings.set_defaults()
	settings.load_settings()
	check(settings.keys.sprint == [KEY_X], "Rebound keys are saved and loaded")
	settings.reset_controls()
	check(has_key("sprint", KEY_SHIFT), "Reset restores the default keys")
	check(settings.signal_for_word(" blink ") == "blink" and settings.signal_for_word("eyes_closed") == "eyes" and settings.signal_for_word("banana") == "", "Signal words match in any case")

	# The brain link, over real UDP on a test port.
	settings.brain_enabled = true
	settings.brain_port = 47123
	settings.brain_cooldown = 0.0
	settings.apply()
	check(brain.is_listening() and brain.status.contains("47123"), "Brain link listens on the chosen port")
	check(brain.heading_vector() == Vector2.UP and not brain.moving, "The heading starts up, standing still")
	await command("MOUTH")
	check(Input.is_action_pressed("move_up"), "Closing the mouth starts walking along the heading")
	await command("BLINK")
	check(Input.is_action_pressed("move_right") and not Input.is_action_pressed("move_up"), "A blink turns clockwise while walking")
	await command("blink")
	await command("BLINK")
	check(Input.is_action_pressed("move_left") and brain.heading_vector() == Vector2.LEFT, "Blinks keep turning: right, down, left")
	await command("EYES")
	check(Input.is_action_pressed("sprint"), "Closing the eyes starts running")
	await command("EYES")
	check(not Input.is_action_pressed("sprint"), "Closing them again stops running")
	await command("MOUTH")
	check(not Input.is_action_pressed("move_left"), "Closing the mouth again stops walking")
	settings.brain_cooldown = 0.5
	var turned_to: int = brain.heading
	await command("BLINK")
	await command("BLINK")
	check(brain.heading == (turned_to + 1) % 4, "A repeated signal within the cooldown counts once")
	settings.brain_cooldown = 0.0
	var key := InputEventKey.new()
	key.physical_keycode = KEY_M
	key.pressed = true
	Input.parse_input_event(key)
	await wait(0.1)
	check(brain.moving, "The M key sends the mouth signal too")
	settings.signal_actions["eyes"] = "reset"
	await command("EYES")
	check(brain.last_action == "reset" and not brain.running, "A signal can be mapped to another action")
	settings.signal_actions["eyes"] = "run"
	brain.release_all()
	await command("SHAKE")
	check(brain.moving and brain.last_signal == "shake", "A head shake starts walking too")
	await command("nod")
	check(brain.last_signal == "nod" and brain.last_action == "swing", "A nod swings the sword")
	check(settings.signal_doing("go") == "Close mouth or Head shake", "Hints name every signal that does an action")
	brain.release_all()
	await command("dance")
	check(brain.last_command_text().contains("not a signal word"), "Unknown words are reported, not acted on")

	# The menu itself.
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var names: Array = menu.main_buttons.get_children().map(func(node: Node) -> String: return node.name)
	check(names == ["Play", "Settings", "Quit"], "Main menu has Play, Settings and Quit")
	menu.open_settings()
	var tabs: TabContainer = menu.settings_panel.find_children("*", "TabContainer", true, false)[0]
	check(menu.settings_panel.visible and tabs.get_tab_count() == 3, "Settings has Controls, Brain interface and Audio & display tabs")
	menu.start_rebind("move_up", 0)
	var press := InputEventKey.new()
	press.physical_keycode = KEY_I
	press.pressed = true
	menu._input(press)
	check(has_key("move_up", KEY_I) and menu.key_buttons["move_up:0"].text == "I", "Clicking a key and pressing I rebinds Move up")
	settings.reset_controls()
	menu.close_settings()
	check(menu.main_buttons.visible, "Back returns to the main buttons")
	# Hands-free menus: blink to the next button, close the mouth to press it.
	menu.main_buttons.get_child(0).grab_focus()
	await command("BLINK")
	check(root.gui_get_focus_owner() == menu.main_buttons.get_child(1), "A blink moves to the next menu button")
	await command("MOUTH")
	check(menu.settings_panel.visible, "Closing the mouth presses it (Settings opens)")
	menu.close_settings()
	settings.brain_enabled = false
	settings.apply()
	check(not brain.is_listening() and brain.status == "Off", "Turning the link off closes the port")
	menu.queue_free()
	await process_frame

	settings.use_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.path))
	if failures == 0:
		print("PASS: All menu and brain interface checks.")
	quit(0 if failures == 0 else 1)

func command(word: String) -> void:
	brain.send_test(word)
	await wait(0.1)

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func has_key(action: String, keycode: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
