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

## The three things the headset can detect. Each arrives as a UDP word or a
## key press (whichever the detector can send) and triggers one brain action.
const SIGNALS := [
	{"signal": "blink", "label": "Blink", "words": "BLINK", "key": KEY_B, "action": "turn"},
	{"signal": "mouth", "label": "Close mouth", "words": "MOUTH, MOUTH_CLOSED, JAW", "key": KEY_M, "action": "go"},
	{"signal": "eyes", "label": "Eyes closed", "words": "EYES, EYES_CLOSED", "key": KEY_E, "action": "run"},
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
const DEFAULT_PORT := 1000

## Tests point this at a scratch file so they never touch a player's settings.
var path := "user://settings.cfg"
var keys := {}
var signal_words := {}
var signal_keys := {}
var signal_actions := {}
var brain_enabled := false
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
		keys[row.action] = file.get_value("keys", row.action, keys[row.action])
	for row in SIGNALS:
		signal_words[row.signal] = file.get_value("brain_words", row.signal, signal_words[row.signal])
		signal_keys[row.signal] = file.get_value("brain_keys", row.signal, signal_keys[row.signal])
		signal_actions[row.signal] = file.get_value("brain_actions", row.signal, signal_actions[row.signal])
	brain_enabled = file.get_value("brain", "enabled", brain_enabled)
	brain_port = file.get_value("brain", "port", brain_port)
	brain_cooldown = file.get_value("brain", "cooldown", brain_cooldown)
	music_volume = file.get_value("audio", "music_volume", music_volume)
	fullscreen = file.get_value("display", "fullscreen", fullscreen)

func save_settings() -> void:
	var file := ConfigFile.new()
	for row in ACTIONS:
		file.set_value("keys", row.action, keys[row.action])
	for row in SIGNALS:
		file.set_value("brain_words", row.signal, signal_words[row.signal])
		file.set_value("brain_keys", row.signal, signal_keys[row.signal])
		file.set_value("brain_actions", row.signal, signal_actions[row.signal])
	file.set_value("brain", "enabled", brain_enabled)
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
	apply()
	save_settings()

func set_signal_key(signal_name: String, keycode: int) -> void:
	signal_keys[signal_name] = keycode
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

## Which signal a received word means ("blink", "mouth", "eyes"), or "".
func signal_for_word(word: String) -> String:
	word = word.strip_edges().to_upper()
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

## "Blink: turn   Close mouth: go / stop   ..." for the in-game HUD.
func brain_hint() -> String:
	var parts: Array[String] = []
	for row in SIGNALS:
		var action: String = signal_actions[row.signal]
		if action != "none":
			parts.append("%s  %s" % [row.label, action_label(action).to_lower()])
	return "     ".join(parts)

## The signal that triggers an action, e.g. "Blink" for "turn", or "".
func signal_doing(action: String) -> String:
	for row in SIGNALS:
		if signal_actions[row.signal] == action:
			return row.label
	return ""

static func split_words(text: String) -> Array:
	return Array(text.to_upper().split(",", false)).map(func(item: String) -> String: return item.strip_edges())
