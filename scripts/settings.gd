extends Node
## Autoloaded as "Settings": key bindings, the brain interface, audio and
## display options. Saved to user://settings.cfg and applied on start.

signal changed

## Keyboard actions; add a row here to make another action rebindable.
const ACTIONS := [
	{"action": "move_up", "label": "Move up", "keys": [KEY_W, KEY_UP]},
	{"action": "move_down", "label": "Move down", "keys": [KEY_S, KEY_DOWN]},
	{"action": "move_left", "label": "Move left", "keys": [KEY_A, KEY_LEFT]},
	{"action": "move_right", "label": "Move right", "keys": [KEY_D, KEY_RIGHT]},
	{"action": "sprint", "label": "Run", "keys": [KEY_SHIFT]},
	{"action": "reset", "label": "Back to door", "keys": [KEY_R]},
	{"action": "attack", "label": "Swing sword", "keys": [KEY_SPACE, KEY_J]},
	{"action": "drink", "label": "Drink potion", "keys": [KEY_Q]},
]
## Not rebindable: Esc always opens the menu.
const MENU_KEY := KEY_ESCAPE

## The things a headset detector can report. Each arrives as a UDP word or a
## key press (whichever the detector can send) and triggers one brain action.
## Head shake and nod come from the Unicorn's gyroscope (Neu_to_text_new5.py
## sends BLINK, SHAKE and NOD).
const SIGNALS := [
	{"signal": "blink", "label": "Blink", "words": "BLINK", "key": KEY_B, "action": "turn"},
	{"signal": "mouth", "label": "Close mouth", "words": "MOUTH, MOUTH_CLOSED, JAW", "key": KEY_M, "action": "go"},
	{"signal": "eyes", "label": "Eyes closed", "words": "EYES, EYES_CLOSED", "key": KEY_E, "action": "run"},
	{"signal": "shake", "label": "Head shake", "words": "SHAKE, HEAD_SHAKE", "key": KEY_N, "action": "go"},
	{"signal": "nod", "label": "Nod", "words": "NOD", "key": KEY_Y, "action": "swing"},
]
const BRAIN_ACTIONS := [
	["turn", "Turn (clockwise)"],
	["go", "Go / stop"],
	["run", "Run on / off"],
	["reset", "Back to door"],
	["swing", "Swing sword"],
	["drink", "Drink potion"],
	["none", "Nothing"],
]
## Short wording for the in-game reminder, which has one line to fit in.
const ACTION_HINTS := {"turn": "turn", "go": "go/stop", "run": "run", "reset": "back", "swing": "swing", "drink": "drink"}
const DEFAULT_PORT := 1000

## Tests point this at a scratch file so they never touch a player's settings.
var path := "user://settings.cfg"
var keys := {}
var signal_words := {}
var signal_keys := {}
var signal_actions := {}
var brain_enabled := false
## True while the link is on only because a headset said hello: not saved,
## and it turns off again when the headset goes quiet.
var brain_auto_enabled := false
var brain_port := DEFAULT_PORT
## The same signal within this many seconds counts once (detectors can
## report one blink several times).
var brain_cooldown := 0.4
var music_volume := 0.8
var fullscreen := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_defaults()
	load_settings()
	apply()

func set_defaults() -> void:
	for row in ACTIONS:
		keys[row.action] = row["keys"].duplicate()
	for row in SIGNALS:
		signal_words[row.signal] = row.words
		signal_keys[row.signal] = row.key
		signal_actions[row.signal] = row.action
	brain_enabled = false
	brain_auto_enabled = false
	brain_port = DEFAULT_PORT
	brain_cooldown = 0.4
	music_volume = 0.8
	fullscreen = false

## Tests call this so a player's saved bindings never change their keys.
func use_defaults() -> void:
	set_defaults()
	apply()

func reset_controls() -> void:
	for row in ACTIONS:
		keys[row.action] = row["keys"].duplicate()
	apply()
	save_settings()

func load_settings() -> void:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	for row in ACTIONS:
		var list: Array = saved(file, "keys", row.action, keys[row.action])
		keys[row.action] = list.filter(func(code: Variant) -> bool: return code is int and code != KEY_NONE)
	for row in SIGNALS:
		signal_words[row.signal] = saved(file, "brain_words", row.signal, signal_words[row.signal])
		signal_keys[row.signal] = saved(file, "brain_keys", row.signal, signal_keys[row.signal])
		var action: String = saved(file, "brain_actions", row.signal, signal_actions[row.signal])
		if BRAIN_ACTIONS.any(func(pair: Array) -> bool: return pair[0] == action):
			signal_actions[row.signal] = action
	brain_enabled = saved(file, "brain", "enabled", brain_enabled)
	brain_port = clampi(saved(file, "brain", "port", brain_port), 1, 65535)
	brain_cooldown = clampf(saved(file, "brain", "cooldown", brain_cooldown), 0.0, 3.0)
	music_volume = clampf(saved(file, "audio", "music_volume", music_volume), 0.0, 1.0)
	fullscreen = saved(file, "display", "fullscreen", fullscreen)

## A value from the settings file, or `fallback` if it holds something of
## another type (a hand-edited or damaged file). Ints and floats convert.
static func saved(file: ConfigFile, section: String, key: String, fallback: Variant) -> Variant:
	var value: Variant = file.get_value(section, key, fallback)
	if typeof(value) == typeof(fallback):
		return value
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if typeof(value) in numbers and typeof(fallback) in numbers:
		return type_convert(value, typeof(fallback))
	return fallback

func save_settings() -> void:
	var file := ConfigFile.new()
	for row in ACTIONS:
		file.set_value("keys", row.action, keys[row.action])
	for row in SIGNALS:
		file.set_value("brain_words", row.signal, signal_words[row.signal])
		file.set_value("brain_keys", row.signal, signal_keys[row.signal])
		file.set_value("brain_actions", row.signal, signal_actions[row.signal])
	file.set_value("brain", "enabled", brain_enabled and not brain_auto_enabled)
	file.set_value("brain", "port", brain_port)
	file.set_value("brain", "cooldown", brain_cooldown)
	file.set_value("audio", "music_volume", music_volume)
	file.set_value("display", "fullscreen", fullscreen)
	file.save(path)

## Pushes every setting into the engine and tells listeners (BrainLink).
func apply() -> void:
	for row in ACTIONS:
		bind(row.action, keys[row.action])
	bind("quit", [MENU_KEY])
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(music_volume, 0.0001)))
	if DisplayServer.get_name() != "headless":
		# Only on a real change, so a maximized window stays maximized.
		var mode := DisplayServer.window_get_mode()
		var is_fullscreen := mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		if fullscreen != is_fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	changed.emit()

func bind(action: StringName, keycodes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for keycode: int in keycodes:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action, event)

## Sets one key slot (0 or 1) of an action; KEY_NONE clears it.
func set_key(action: String, slot: int, keycode: int) -> void:
	var list: Array = keys[action].duplicate()
	while list.size() <= slot:
		list.append(KEY_NONE)
	list[slot] = keycode
	keys[action] = list.filter(func(code: int) -> bool: return code != KEY_NONE)
	# One key, one job: a brain signal on the same key would swallow it.
	for row in SIGNALS:
		if keycode != KEY_NONE and signal_keys[row.signal] == keycode:
			signal_keys[row.signal] = KEY_NONE
	apply()
	save_settings()

func set_signal_key(signal_name: String, keycode: int) -> void:
	signal_keys[signal_name] = keycode
	if keycode != KEY_NONE:
		# The key leaves any action or other signal that had it.
		for row in ACTIONS:
			keys[row.action] = keys[row.action].filter(func(code: int) -> bool: return code != keycode)
		for row in SIGNALS:
			if row.signal != signal_name and signal_keys[row.signal] == keycode:
				signal_keys[row.signal] = KEY_NONE
		apply()
	save_settings()

func key_name(keycode: int) -> String:
	return OS.get_keycode_string(keycode) if keycode != KEY_NONE else "-"

## "W / Up" style text for menus.
func keys_text(action: String) -> String:
	var names: Array = keys.get(action, []).map(key_name)
	return " / ".join(names) if not names.is_empty() else "unbound"

func first_key(action: String) -> String:
	var list: Array = keys.get(action, [])
	return key_name(list[0]) if not list.is_empty() else "?"

## Which signal a received word means ("blink", "mouth", "nod"...), or "".
func signal_for_word(word: String) -> String:
	word = word.strip_edges().to_upper()
	if word == "":
		return ""
	for row in SIGNALS:
		if word in split_words(signal_words[row.signal]):
			return row.signal
	return ""

func signal_for_key(keycode: int) -> String:
	for row in SIGNALS:
		if keycode != KEY_NONE and signal_keys[row.signal] == keycode:
			return row.signal
	return ""

func signal_label(signal_name: String) -> String:
	for row in SIGNALS:
		if row.signal == signal_name:
			return row.label
	return signal_name

func action_label(action: String) -> String:
	for pair in BRAIN_ACTIONS:
		if pair[0] == action:
			return pair[1]
	return action

## The signals hints should mention: the ones the connected detector said
## it sends, or all of them.
func hint_signals() -> Array:
	var brain := get_node_or_null("/root/BrainLink")
	if brain and brain.detector_connected() and not brain.detector_signals.is_empty():
		return SIGNALS.filter(func(row: Dictionary) -> bool: return row.signal in brain.detector_signals)
	return SIGNALS

## "Blink turn   Close mouth go/stop   ..." for the in-game HUD. Short, so
## all five signals fit beside the right-hand reminder.
func brain_hint() -> String:
	var parts: Array[String] = []
	for row in hint_signals():
		var action: String = signal_actions[row.signal]
		if action != "none":
			parts.append("%s %s" % [row.label, ACTION_HINTS.get(action, action)])
	return "   ".join(parts)

## The signal(s) that trigger an action, e.g. "Blink" for "turn" or
## "Close mouth or Head shake" for "go", or "".
func signal_doing(action: String) -> String:
	var labels: Array[String] = []
	for row in hint_signals():
		if signal_actions[row.signal] == action:
			labels.append(row.label)
	return " or ".join(labels)

static func split_words(text: String) -> Array:
	return Array(text.to_upper().split(",", false)).map(func(item: String) -> String: return item.strip_edges()).filter(func(item: String) -> bool: return item != "")
