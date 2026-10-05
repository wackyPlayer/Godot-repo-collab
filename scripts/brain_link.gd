extends Node
## Autoloaded as "BrainLink": plays the game from signals a headset can
## detect: a blink, a closed mouth, closed eyes, a head shake and a nod.
##
## A signal arrives either as a UDP text message (a word such as BLINK, sent
## by the detector to the port in Settings) or as a key press (B, M, E, N, Y
## by default), whichever the detection software can output. Settings maps each
## signal to one action:
##   turn  - turn the heading clockwise (up, right, down, left)
##   go    - start or stop walking along the heading
##   run   - running on or off
##   reset - back to the door you came in by
##   swing - swing the sword (once you have it)
##   drink - drink a potion (if you carry one)
## In menus, a blink moves to the next button and a closed mouth, head shake
## or nod presses it.
##
## A detector can also say "HELLO BLINK SHAKE NOD" every second. While the
## link is off it still listens on this computer for that, and the first
## hello turns it on, so starting the detector is all the set-up needed.
## Hints then only mention the signals the detector named.
## tools/send_brain_command.py sends test signals without a headset.

signal signal_received(signal_name: String, action: String)
## The link turned on or off, or a headset connected, dropped or changed the
## signals it sends: hints that name signals should be rewritten.
signal state_changed

const HEADINGS := ["move_up", "move_right", "move_down", "move_left"]
const HEADING_VECTORS: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
## A detector counts as connected this long after its last hello.
const HELLO_TIMEOUT_MSEC := 3000

## Signals from other computers (only while on).
var peer := PacketPeerUDP.new()
## Signals from this computer. Always bound, so a hello can turn the link on;
## holding the exact address also keeps a second copy of the game from
## taking this computer's signals away.
var local_peer := PacketPeerUDP.new()
var status := "Off"
## What the sockets were last bound for, so unrelated settings changes (a
## volume drag) don't rebind them and drop signals.
var bound_enabled := false
var bound_port := -1
var last_state := []
## The port status without the detector ("Listening on UDP port 1000").
var port_status := "Off"
## The signals the connected detector said it sends, and when it last said so.
var detector_signals: Array[String] = []
var last_hello_msec := -1
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
		settings.changed.connect(on_settings_changed)
	restart()

func on_settings_changed() -> void:
	if enabled() != bound_enabled or port() != bound_port:
		restart()

func port() -> int:
	var settings := get_node_or_null("/root/Settings")
	return settings.brain_port if settings else 1000

func restart() -> void:
	release_all()
	peer.close()
	local_peer.close()
	bound_enabled = enabled()
	bound_port = port()
	# Only this computer while off, so it never asks for a firewall exception.
	var local_ok := local_peer.bind(bound_port, "127.0.0.1") == OK
	if not bound_enabled:
		port_status = "Off"
	elif peer.bind(bound_port, "*") != OK:
		port_status = "Could not open UDP port %d (is another program using it?)" % bound_port
	elif not local_ok:
		port_status = "Listening on UDP port %d, but another copy of the game on this computer has it too: close that copy" % bound_port
	else:
		port_status = "Listening on UDP port %d" % bound_port
	update_status()

func enabled() -> bool:
	var settings := get_node_or_null("/root/Settings")
	return settings != null and settings.brain_enabled

## On and receiving signals (while off it only listens for a hello).
func is_listening() -> bool:
	return enabled() and (peer.is_bound() or local_peer.is_bound())

func detector_connected() -> bool:
	return last_hello_msec >= 0 and Time.get_ticks_msec() - last_hello_msec < HELLO_TIMEOUT_MSEC

func heading_vector() -> Vector2:
	return HEADING_VECTORS[heading]

func _process(_delta: float) -> void:
	# Read everything first: turning the link on rebinds the port.
	var words: Array[String] = []
	for socket in [local_peer, peer]:
		while socket.is_bound() and socket.get_available_packet_count() > 0:
			words.append(socket.get_packet().get_string_from_utf8().strip_edges().to_upper())
	for word in words:
		if word.begins_with("HELLO"):
			hello(word.trim_prefix("HELLO"))
		elif enabled():
			var signal_name: String = get_node("/root/Settings").signal_for_word(word)
			if signal_name != "":
				receive(signal_name)
			else:
				last_signal = word
				last_action = "unknown"
				last_msec = Time.get_ticks_msec()
	# A link the headset turned on turns off again when it goes quiet, so the
	# next keyboard player isn't left in brain mode.
	var settings := get_node_or_null("/root/Settings")
	if settings and settings.brain_auto_enabled and enabled() and not detector_connected():
		settings.brain_enabled = false
		settings.brain_auto_enabled = false
		settings.apply()
	update_status()

## A detector saying which signals it sends. The first hello of a session
## turns the link on (for this session only); later ones only keep it
## connected, so unticking the setting while the detector runs is respected.
func hello(words: String) -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return
	var was_connected := detector_connected()
	detector_signals.clear()
	for word in words.replace(",", " ").split(" ", false):
		var signal_name: String = settings.signal_for_word(word)
		if signal_name != "" and not signal_name in detector_signals:
			detector_signals.append(signal_name)
	last_hello_msec = Time.get_ticks_msec()
	if not was_connected and not settings.brain_enabled:
		settings.brain_enabled = true
		settings.brain_auto_enabled = true
		settings.apply()

func update_status() -> void:
	if enabled() and detector_connected():
		var settings := get_node_or_null("/root/Settings")
		var names: Array = detector_signals.map(func(signal_name: String) -> String: return settings.signal_label(signal_name))
		status = "Headset connected (%s), UDP port %d" % [", ".join(names), settings.brain_port]
	else:
		status = port_status
	var state := [enabled(), detector_connected(), detector_signals.duplicate()]
	if state != last_state:
		last_state = state
		state_changed.emit()

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
	if focus and focus.is_visible_in_tree():
		action = menu_action(focus, signal_name)
	else:
		game_action(action)
	last_signal = signal_name
	last_action = action
	last_msec = now
	signal_received.emit(signal_name, action)
	return action

## Menus: a blink moves to the next button or tab bar, a closed mouth, head
## shake or nod presses it (a tab bar shows the next tab, a drop-down picks
## its next choice).
func menu_action(focus: Control, signal_name: String) -> String:
	if signal_name == "blink":
		var next := next_menu_control(focus)
		if next:
			next.grab_focus()
		return "next button"
	if not signal_name in ["mouth", "shake", "nod"]:
		return "none"
	if focus is OptionButton:
		var options := focus as OptionButton
		options.select((options.selected + 1) % options.item_count)
		options.item_selected.emit(options.selected)
	elif focus is BaseButton:
		var button := focus as BaseButton
		if button.toggle_mode:
			button.button_pressed = not button.button_pressed
		else:
			button.pressed.emit()
	elif focus is TabBar:
		var tab_bar := focus as TabBar
		tab_bar.current_tab = (tab_bar.current_tab + 1) % tab_bar.tab_count
	else:
		return "none"
	return "press button"

## The next control a blink can stop on, skipping text fields, spin boxes
## and sliders, which a headset can't use.
static func next_menu_control(from: Control) -> Control:
	var next := from.find_next_valid_focus()
	for attempt in range(64):
		if next == null or next == from or next is BaseButton or next is TabBar:
			return next
		next = next.find_next_valid_focus()
	return null

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
	var sender := PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1", port())
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
