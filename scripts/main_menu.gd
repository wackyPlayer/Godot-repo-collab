extends Control
## The main menu: Play, Settings and Quit. Settings has three tabs: Controls
## (rebind keys), Brain interface (the g.tec Unicorn hook-up, see
## brain_link.gd) and Audio & display. Built in code so the scene stays tiny;
## every option lives in the Settings autoload.

const TUTORIAL := "res://scenes/tutorial.tscn"
const TORCH: PackedScene = preload("res://scenes/torch.tscn")
const FLOOR_TILES: Texture2D = preload("res://assets/floor_tiles.png")
const WALL: Texture2D = preload("res://assets/wall.png")
const ROCK: Texture2D = preload("res://assets/knight_rock.png")
const MAGE: Texture2D = preload("res://assets/mage_idle.png")
const ACCENT := Color("af9be9")
const TEXT := Color("c5bdd8")
const DIM := Color("8a7cab")
const SCREEN := Vector2(768, 512)

var main_buttons: VBoxContainer
var settings_panel: PanelContainer
## "action:slot" -> the button showing that key.
var key_buttons := {}
## "action:slot" while waiting for a key press, else "".
var waiting := ""
var brain_status: Label
var brain_last: Label
var footer: Label
var mage: Sprite2D
var time := 0.0

func _ready() -> void:
	theme = build_theme()
	BrainLink.release_all()
	var music := get_node_or_null("/root/Music")
	if music:
		music.call("play", "keep")
	build_scenery()
	build_main_buttons()
	build_settings()
	footer = add_label(self, "", 10, DIM)
	footer.position = Vector2(16, 490)
	refresh_status()

func _process(delta: float) -> void:
	time += delta
	mage.frame = int(time * 2.0) % 2
	refresh_status()

# --- Main screen --------------------------------------------------------------

func _draw() -> void:
	for row in range(16):
		for column in range(24):
			var shade := 0.55 + float((column * 7 + row * 3) % 5) * 0.03
			draw_texture_rect(FLOOR_TILES, Rect2(column * 32, row * 32, 32, 32), false, Color(shade, shade, shade * 1.1))
	for column in range(24):
		draw_texture_rect(WALL, Rect2(column * 32, 0, 32, 32), false, Color(1.1, 0.95, 1.25))
		draw_texture_rect(WALL, Rect2(column * 32, 32, 32, 32), false, Color(0.9, 0.78, 1.05))
	draw_rect(Rect2(0, 61, SCREEN.x, 3), Color("151023"))
	draw_rect(Rect2(0, 64, SCREEN.x, 14), Color(0, 0, 0.03, 0.35))
	# A soft dark band behind the title and buttons keeps them readable.
	draw_rect(Rect2(214, 84, 340, 300), Color(0.02, 0.015, 0.05, 0.55))

func build_scenery() -> void:
	for x in [96.0, 300.0, 468.0, 672.0]:
		var torch: Node2D = TORCH.instantiate()
		torch.position = Vector2(x, 58)
		add_child(torch)
	var rock := Sprite2D.new()
	rock.texture = ROCK
	rock.vframes = 4
	rock.scale = Vector2(0.75, 0.75)
	rock.position = Vector2(150, 420)
	add_child(rock)
	mage = Sprite2D.new()
	mage.texture = MAGE
	mage.vframes = 2
	mage.centered = false
	mage.offset = Vector2(-8, -28)
	mage.scale = Vector2(4, 4)
	mage.position = Vector2(620, 456)
	add_child(mage)

func build_main_buttons() -> void:
	var title := add_label(self, "A ROCKY TOWER", 38, Color("e1d6fb"))
	title.position = Vector2(0, 98)
	title.size.x = SCREEN.x
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := add_label(self, "Caballerito and the mage's curse", 13, ACCENT)
	subtitle.position = Vector2(0, 148)
	subtitle.size.x = SCREEN.x
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_buttons = VBoxContainer.new()
	main_buttons.position = Vector2(284, 196)
	main_buttons.size = Vector2(200, 0)
	main_buttons.add_theme_constant_override("separation", 10)
	add_child(main_buttons)
	for choice in [["Play", play], ["Settings", open_settings], ["Quit", func() -> void: get_tree().quit()]]:
		var button := Button.new()
		button.name = choice[0]
		button.text = choice[0]
		button.custom_minimum_size = Vector2(200, 38)
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(choice[1])
		main_buttons.add_child(button)
	main_buttons.get_child(0).grab_focus()

func play() -> void:
	get_tree().change_scene_to_file(TUTORIAL)

func open_settings() -> void:
	main_buttons.visible = false
	settings_panel.visible = true
	refresh_keys()

func close_settings() -> void:
	waiting = ""
	settings_panel.visible = false
	main_buttons.visible = true
	main_buttons.get_child(1).grab_focus()

func refresh_status() -> void:
	footer.text = "Brain interface: %s" % BrainLink.status
	if brain_status:
		brain_status.text = BrainLink.status
		brain_last.text = BrainLink.last_command_text()

# --- Settings -------------------------------------------------------------------

func build_settings() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.name = "Settings"
	settings_panel.position = Vector2(44, 30)
	settings_panel.size = Vector2(680, 452)
	settings_panel.visible = false
	add_child(settings_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	settings_panel.add_child(column)
	add_label(column, "SETTINGS", 18, Color("e1d6fb"))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	tabs.add_child(build_controls_tab())
	tabs.add_child(build_brain_tab())
	tabs.add_child(build_audio_tab())
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(120, 30)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.pressed.connect(close_settings)
	column.add_child(back)

func scroll_page(page_name: String) -> Array:
	var scroll := ScrollContainer.new()
	scroll.name = page_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	scroll.add_child(page)
	return [scroll, page]

func build_controls_tab() -> Control:
	var parts := scroll_page("Controls")
	var page: VBoxContainer = parts[1]
	add_label(page, "Click a key, then press the new key. Backspace clears it, Esc cancels.", 11, DIM)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	page.add_child(grid)
	for row in Settings.ACTIONS:
		var label := add_label(grid, row.label, 13, TEXT)
		label.custom_minimum_size = Vector2(160, 0)
		for slot in range(2):
			var button := Button.new()
			button.custom_minimum_size = Vector2(150, 28)
			button.pressed.connect(start_rebind.bind(row.action, slot))
			grid.add_child(button)
			key_buttons["%s:%d" % [row.action, slot]] = button
	add_label(grid, "Menu", 13, TEXT)
	add_label(grid, "Esc (fixed)", 13, DIM)
	add_label(grid, "", 13, DIM)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.custom_minimum_size = Vector2(170, 28)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		Settings.reset_controls()
		refresh_keys())
	page.add_child(reset)
	return parts[0]

func start_rebind(action: String, slot: int) -> void:
	refresh_keys()
	waiting = "%s:%d" % [action, slot]
	key_buttons[waiting].text = "Press a key..."

func refresh_keys() -> void:
	for id: String in key_buttons:
		var parts := id.split(":")
		if parts[0] == "signal":
			key_buttons[id].text = Settings.key_name(Settings.signal_keys[parts[1]])
			continue
		var list: Array = Settings.keys.get(parts[0], [])
		var slot := int(parts[1])
		key_buttons[id].text = Settings.key_name(list[slot]) if slot < list.size() else "-"

func _input(event: InputEvent) -> void:
	if waiting == "" or not event is InputEventKey or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	var parts := waiting.split(":")
	waiting = ""
	if parts[0] == "signal":
		if code == KEY_BACKSPACE:
			Settings.set_signal_key(parts[1], KEY_NONE)
		elif code != KEY_ESCAPE:
			Settings.set_signal_key(parts[1], code)
	elif code == KEY_BACKSPACE:
		Settings.set_key(parts[0], int(parts[1]), KEY_NONE)
	elif code != KEY_ESCAPE:
		Settings.set_key(parts[0], int(parts[1]), code)
	refresh_keys()

func _unhandled_input(event: InputEvent) -> void:
	if settings_panel.visible and event.is_action_pressed("quit"):
		close_settings()
		get_viewport().set_input_as_handled()

func build_brain_tab() -> Control:
	var parts := scroll_page("Brain interface")
	var page: VBoxContainer = parts[1]
	var help := add_label(page, "Play with a headset that detects three things: a blink, a closed mouth and closed eyes. The detector can send each one as a UDP text message (the word below, to the port below) or as a key press (the key below). In menus, a blink moves to the next button and a closed mouth presses it.", 11, DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(620, 0)
	var enabled := CheckBox.new()
	enabled.text = "Use the brain interface"
	enabled.button_pressed = Settings.brain_enabled
	enabled.toggled.connect(func(on: bool) -> void:
		Settings.brain_enabled = on
		save_and_apply())
	page.add_child(enabled)
	var port := SpinBox.new()
	port.min_value = 1
	port.max_value = 65535
	port.value = Settings.brain_port
	port.value_changed.connect(func(value: float) -> void:
		Settings.brain_port = int(value)
		save_and_apply())
	add_row(page, "UDP port", port)
	brain_status = add_label(page, "", 12, ACCENT)
	brain_last = add_label(page, "", 11, DIM)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	page.add_child(grid)
	for heading in ["Signal", "Does", "UDP word(s)", "Key", ""]:
		add_label(grid, heading, 11, DIM)
	for row in Settings.SIGNALS:
		var label := add_label(grid, row.label, 12, TEXT)
		label.custom_minimum_size = Vector2(90, 0)
		var does := OptionButton.new()
		for pair in Settings.BRAIN_ACTIONS:
			does.add_item(pair[1])
		does.selected = Settings.BRAIN_ACTIONS.map(func(pair: Array) -> String: return pair[0]).find(Settings.signal_actions[row.signal])
		does.item_selected.connect(func(index: int) -> void:
			Settings.signal_actions[row.signal] = Settings.BRAIN_ACTIONS[index][0]
			Settings.save_settings())
		grid.add_child(does)
		var field := LineEdit.new()
		field.text = Settings.signal_words[row.signal]
		field.custom_minimum_size = Vector2(170, 0)
		field.text_changed.connect(func(text: String) -> void:
			Settings.signal_words[row.signal] = text
			Settings.save_settings())
		grid.add_child(field)
		var key := Button.new()
		key.custom_minimum_size = Vector2(70, 28)
		key.pressed.connect(start_signal_rebind.bind(row.signal))
		key_buttons["signal:%s" % row.signal] = key
		grid.add_child(key)
		var test := Button.new()
		test.text = "Test"
		test.pressed.connect(func() -> void: BrainLink.send_test(Settings.split_words(Settings.signal_words[row.signal])[0]))
		grid.add_child(test)
	var cooldown := SpinBox.new()
	cooldown.min_value = 0.0
	cooldown.max_value = 3.0
	cooldown.step = 0.05
	cooldown.suffix = "s"
	cooldown.value = Settings.brain_cooldown
	cooldown.value_changed.connect(func(value: float) -> void:
		Settings.brain_cooldown = value
		Settings.save_settings())
	add_row(page, "Ignore repeats", cooldown)
	refresh_keys()
	return parts[0]

func start_signal_rebind(signal_name: String) -> void:
	refresh_keys()
	waiting = "signal:%s" % signal_name
	key_buttons[waiting].text = "Press..."

func build_audio_tab() -> Control:
	var parts := scroll_page("Audio & display")
	var page: VBoxContainer = parts[1]
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = Settings.music_volume
	volume.custom_minimum_size = Vector2(260, 24)
	var percent := add_label(null, "%d%%" % roundi(Settings.music_volume * 100), 12, TEXT)
	volume.value_changed.connect(func(value: float) -> void:
		Settings.music_volume = value
		percent.text = "%d%%" % roundi(value * 100)
		save_and_apply())
	var volume_row := add_row(page, "Music volume", volume)
	volume_row.add_child(percent)
	var fullscreen := CheckBox.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = Settings.fullscreen
	fullscreen.toggled.connect(func(on: bool) -> void:
		Settings.fullscreen = on
		save_and_apply())
	page.add_child(fullscreen)
	return parts[0]

func save_and_apply() -> void:
	Settings.save_settings()
	Settings.apply()

# --- Building blocks ---------------------------------------------------------

func add_label(parent: Node, caption: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if parent:
		parent.add_child(label)
	return label

func add_row(parent: Node, caption: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := add_label(row, caption, 12, TEXT)
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(control)
	parent.add_child(row)
	return row

static func box(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	return style

## A 14px pixel-art checkbox: an outlined square, filled when checked.
static func check_icon(checked: bool) -> ImageTexture:
	var image := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	image.fill(Color("0e0a1a"))
	for i in range(14):
		for edge in [0, 13]:
			image.set_pixel(i, edge, ACCENT)
			image.set_pixel(edge, i, ACCENT)
	if checked:
		image.fill_rect(Rect2i(3, 3, 8, 8), Color("e1d6fb"))
	return ImageTexture.create_from_image(image)

## One look for every control in the menu, matching the in-game HUD.
static func build_theme() -> Theme:
	var look := Theme.new()
	look.default_font_size = 13
	for type in ["Button", "OptionButton"]:
		look.set_stylebox("normal", type, box(Color("1a1430"), Color("3d3158")))
		look.set_stylebox("hover", type, box(Color("2d2350"), ACCENT))
		look.set_stylebox("pressed", type, box(Color("2d2350"), ACCENT))
		look.set_stylebox("focus", type, box(Color(0, 0, 0, 0), ACCENT))
		look.set_stylebox("disabled", type, box(Color("120d22"), Color("2a2240")))
		look.set_color("font_color", type, TEXT)
		for state in ["font_hover_color", "font_focus_color", "font_pressed_color"]:
			look.set_color(state, type, Color("f0e5ff"))
	# CheckBox would otherwise inherit the Button background.
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(4)
		look.set_stylebox(state, "CheckBox", empty)
	look.set_icon("checked", "CheckBox", check_icon(true))
	look.set_icon("unchecked", "CheckBox", check_icon(false))
	look.set_color("font_color", "CheckBox", TEXT)
	look.set_color("font_hover_color", "CheckBox", Color("f0e5ff"))
	look.set_color("font_pressed_color", "CheckBox", TEXT)
	look.set_color("font_hover_pressed_color", "CheckBox", Color("f0e5ff"))
	for state in ["normal", "focus", "read_only"]:
		look.set_stylebox(state, "LineEdit", box(Color("0e0a1a"), ACCENT if state == "focus" else Color("3d3158")))
	look.set_color("font_color", "LineEdit", Color("e1d6fb"))
	look.set_stylebox("panel", "PanelContainer", box(Color("120d22"), ACCENT))
	look.set_stylebox("panel", "TabContainer", box(Color("0e0a1a"), Color("3d3158")))
	look.set_stylebox("tab_selected", "TabContainer", box(Color("2d2350"), ACCENT))
	look.set_stylebox("tab_unselected", "TabContainer", box(Color("1a1430"), Color("3d3158")))
	look.set_stylebox("tab_hovered", "TabContainer", box(Color("231b40"), ACCENT))
	look.set_color("font_selected_color", "TabContainer", Color("f0e5ff"))
	look.set_color("font_unselected_color", "TabContainer", DIM)
	look.set_color("font_hovered_color", "TabContainer", TEXT)
	return look
