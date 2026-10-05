extends Node
## Autoloaded as "BrainLink": plays the game from three signals a headset can
## detect: a blink, a closed mouth and closed eyes.
##
## A signal arrives either as a UDP text message (a word such as BLINK, sent
## by the detector to the port in Settings) or as a key press (B, M, E by
## default), whichever the detection software can output. Settings maps each
## signal to one action:
##   turn  - turn the heading clockwise (up, right, down, left)
##   go    - start or stop walking along the heading
##   run   - running on or off
##   reset - back to the door you came in by
##   swing - swing the sword (once you have it)
##   drink - drink a potion (if you carry one)
## In menus, a blink moves to the next button and a closed mouth presses it.
## tools/send_brain_command.py sends test signals without a headset.

signal signal_received(signal_name: String, action: String)

const HEADINGS := ["move_up", "move_right", "move_down", "move_left"]
const HEADING_VECTORS: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]

var peer := PacketPeerUDP.new()
var status := "Off"
var heading := 0
var moving := false
var running := false
var last_signal := ""
var last_action := ""
var last_msec := -1
## Signal -> when it last counted, for the repeat cooldown.
var last_seen := {}
## Actions this link is holding down, so it only sends changes.
var held := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var settings := get_node_or_null("/root/Settings")
	if settings:
		settings.changed.connect(restart)
	restart()

func restart() -> void:
	release_all()
	peer.close()
	if not enabled():
		status = "Off"
		return
	var port: int = get_node("/root/Settings").brain_port
	if peer.bind(port, "*") == OK:
		status = "Listening on UDP port %d" % port
	else:
		status = "Could not open UDP port %d (is another program using it?)" % port

func enabled() -> bool:
	var settings := get_node_or_null("/root/Settings")
	return settings != null and settings.brain_enabled

func is_listening() -> bool:
	return peer.is_bound()

func heading_vector() -> Vector2:
	return HEADING_VECTORS[heading]

func _process(_delta: float) -> void:
	while peer.is_bound() and peer.get_available_packet_count() > 0:
		var word := peer.get_packet().get_string_from_utf8()
		var signal_name: String = get_node("/root/Settings").signal_for_word(word)
		if signal_name != "":
			receive(signal_name)
		else:
			last_signal = word.strip_edges().to_upper()
			last_action = "unknown"
			last_msec = Time.get_ticks_msec()

func _input(event: InputEvent) -> void:
	if not enabled() or not event is InputEventKey or not event.pressed or event.echo:
		return
	# Typing in a text field is typing, not a signal.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var key := event as InputEventKey
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	var signal_name: String = get_node("/root/Settings").signal_for_key(code)
	if signal_name != "":
		get_viewport().set_input_as_handled()
		receive(signal_name)

## Handles one detected signal. Returns the action it ran, or "".
func receive(signal_name: String) -> String:
	var settings := get_node_or_null("/root/Settings")
	var now := Time.get_ticks_msec()
	if last_seen.has(signal_name) and now - last_seen[signal_name] < settings.brain_cooldown * 1000.0:
		return ""
	last_seen[signal_name] = now
	var action: String = settings.signal_actions.get(signal_name, "none")
	var focus := get_viewport().gui_get_focus_owner()
	if focus is BaseButton and focus.is_visible_in_tree():
		action = menu_action(focus as BaseButton, signal_name)
	else:
		game_action(action)
	last_signal = signal_name
	last_action = action
	last_msec = now
	signal_received.emit(signal_name, action)
	return action

## Menus: a blink moves to the next button, a closed mouth presses it.
func menu_action(focus: BaseButton, signal_name: String) -> String:
	if signal_name == "blink":
		var next := focus.find_next_valid_focus()
		if next:
			next.grab_focus()
		return "next button"
	if signal_name == "mouth":
		if focus.toggle_mode:
			focus.button_pressed = not focus.button_pressed
		else:
			focus.pressed.emit()
		return "press button"
	return "none"

func game_action(action: String) -> void:
	match action:
		"turn":
			heading = (heading + 1) % HEADINGS.size()
			update_motion()
		"go":
			moving = not moving
			update_motion()
		"run":
			running = not running
			hold("sprint", running)
		"reset", "swing", "drink":
			# One tap of the matching key action.
			var key_action: String = {"reset": "reset", "swing": "attack", "drink": "drink"}[action]
			hold(key_action, true)
			hold(key_action, false)

func update_motion() -> void:
	for index in range(HEADINGS.size()):
		hold(HEADINGS[index], moving and index == heading)

## Stops walking and running, e.g. when a menu opens.
func release_all() -> void:
	moving = false
	running = false
	for action: String in held.keys():
		hold(action, false)

func hold(action: String, pressed: bool) -> void:
	if held.get(action, false) == pressed:
		return
	held[action] = pressed
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

## Sends a word to this game's own port, to check the hook-up works.
func send_test(word: String) -> void:
	var settings := get_node_or_null("/root/Settings")
	var sender := PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1", settings.brain_port if settings else 1000)
	sender.put_packet(word.to_utf8_buffer())
	sender.close()

## For the settings screen: "Last signal: Blink -> Turn (clockwise), 3 s ago".
func last_command_text() -> String:
	if last_msec < 0:
		return "No signals received yet."
	var seconds := (Time.get_ticks_msec() - last_msec) / 1000
	var settings := get_node_or_null("/root/Settings")
	if last_action == "unknown":
		return "Last message: %s (not a signal word), %d s ago" % [last_signal, seconds]
	var action := last_action
	if settings and settings.BRAIN_ACTIONS.any(func(pair: Array) -> bool: return pair[0] == last_action):
		action = settings.action_label(last_action)
	return "Last signal: %s -> %s, %d s ago" % [settings.signal_label(last_signal) if settings else last_signal, action, seconds]
