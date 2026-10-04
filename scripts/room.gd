@tool
extends Node2D
## The supplied stone tile is the room's only environmental texture.

const STONE: Texture2D = preload("res://assets/stone.png")
const TILE := 32
const ORIGIN := Vector2(32, 64)
const COLUMNS := 22
const ROWS := 12
const SPAWN := Vector2(384, 352)
const ACCENT := Color("af9be9")

@onready var knight: CharacterBody2D = $Knight

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	configure_input()
	make_boundary("North", Rect2(32, 64, 704, 32))
	make_boundary("South", Rect2(32, 416, 704, 32))
	make_boundary("West", Rect2(32, 64, 32, 384))
	make_boundary("East", Rect2(704, 64, 32, 384))
	make_interface()
	print("Violet Keep ready — WASD / arrows: move · Shift: run · R: reset · Esc: quit")

func configure_input() -> void:
	bind_keys("move_left", [KEY_A, KEY_LEFT])
	bind_keys("move_right", [KEY_D, KEY_RIGHT])
	bind_keys("move_up", [KEY_W, KEY_UP])
	bind_keys("move_down", [KEY_S, KEY_DOWN])
	bind_keys("sprint", [KEY_SHIFT])
	bind_keys("reset", [KEY_R])
	bind_keys("quit", [KEY_ESCAPE])

func bind_keys(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key: Key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)

func make_boundary(body_name: String, bounds: Rect2) -> void:
	var body := StaticBody2D.new()
	body.name = body_name
	body.position = bounds.get_center()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = bounds.size
	collision.shape = shape
	body.add_child(collision)
	$Boundaries.add_child(body)

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed("reset"):
		knight.call("reset_to", SPAWN)
	if event.is_action_pressed("quit"):
		get_tree().quit()

func make_interface() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	make_label(hud, "THE VIOLET KEEP", Vector2(32, 19), 21, Color("e1d6fb"))
	make_label(hud, "CABALLERITO  /  ROOM 01", Vector2(487, 26), 12, ACCENT)
	make_label(hud, "WASD / ARROWS  move     SHIFT  run", Vector2(32, 466), 13, Color("c5bdd8"))
	make_label(hud, "R  reset     ESC  quit", Vector2(578, 466), 13, Color("9284b1"))
	make_label(hud, "A quiet room. A little knight. Room to wander.", Vector2(32, 491), 10, Color("75678e"))

func make_label(parent: Node, caption: String, at: Vector2, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = caption
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)

func _draw() -> void:
	draw_rect(Rect2(40, 78, 704, 384), Color("04040e"))
	draw_rect(Rect2(30, 62, 708, 388), Color("3a2b51"))
	for row in range(ROWS):
		for column in range(COLUMNS):
			var at := ORIGIN + Vector2(column, row) * TILE
			var rect := Rect2(at, Vector2(TILE, TILE))
			var border := row == 0 or row == ROWS - 1 or column == 0 or column == COLUMNS - 1
			if border:
				draw_wall(rect, row)
			else:
				var brightness := 0.70 + float((column * 7 + row * 3) % 5) * 0.025
				if column == 10 or column == 11:
					brightness += 0.13
				draw_texture_rect(STONE, rect, false, Color(brightness, brightness, brightness * 1.13))
				draw_rect(rect, Color(0.18, 0.14, 0.3, 0.15), false, 1.0)
	draw_rect(Rect2(64, 96, 640, 10), Color(0, 0, 0.03, 0.38))
	draw_rect(Rect2(64, 96, 7, 320), Color(0, 0, 0.03, 0.28))
	draw_rect(Rect2(697, 96, 7, 320), Color(0, 0, 0.03, 0.28))
	draw_rect(Rect2(64, 409, 640, 7), Color(0, 0, 0.03, 0.22))
	# A threshold and compass mark the central aisle.
	draw_rect(Rect2(352, 90, 64, 4), Color("8870b1"))
	draw_line(Vector2(384, 238), Vector2(384, 274), Color("655381"), 2.0)
	draw_line(Vector2(366, 256), Vector2(402, 256), Color("655381"), 2.0)
	draw_polyline(PackedVector2Array([Vector2(384, 244), Vector2(396, 256), Vector2(384, 268), Vector2(372, 256), Vector2(384, 244)]), Color("655381"), 2.0)
	draw_rect(Rect2(382, 254, 4, 4), ACCENT)
	for x in [176, 592]:
		draw_rect(Rect2(x - 6, 84, 12, 12), Color("19122c"))
		draw_rect(Rect2(x - 4, 77, 8, 9), Color("6f459b"))
		draw_rect(Rect2(x - 2, 75, 4, 8), Color("c5b2ff"))
		draw_rect(Rect2(x - 1, 77, 2, 4), Color("f0e5ff"))

func draw_wall(rect: Rect2, row: int) -> void:
	draw_texture_rect(STONE, rect, false, Color(1.95, 1.6, 2.3))
	draw_rect(Rect2(rect.position, Vector2(32, 3)), Color("766187"))
	draw_rect(Rect2(rect.position + Vector2(0, 30), Vector2(32, 2)), Color("151023"))
	draw_rect(rect, Color("21192f"), false, 1.0)
	if row == 0:
		draw_rect(Rect2(rect.position + Vector2(0, 20), Vector2(32, 12)), Color(0.02, 0.01, 0.05, 0.3))
