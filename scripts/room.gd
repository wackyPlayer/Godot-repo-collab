@tool
extends Node2D
## Runs the Violet Keep: draws the current room, rebuilds its walls and blocks,
## and walks the knight between procedurally generated rooms.

const Generator := preload("res://scripts/dungeon_generator.gd")
const STONE: Texture2D = preload("res://assets/stone.png")
const FLOOR_TILES: Texture2D = preload("res://assets/floor_tiles.png")
const WALL: Texture2D = preload("res://assets/wall.png")
const BLOCK: PackedScene = preload("res://scenes/stone_block.tscn")
const ORNAMENT: PackedScene = preload("res://scenes/ornament.tscn")
const ITEM_ART := {
	"sword": preload("res://assets/sword.png"),
	"potion": preload("res://assets/potion.png"),
	"bubble": preload("res://assets/bubble.png"),
}
const ITEM_NAMES := {"sword": "a violet sword", "potion": "a blue potion", "bubble": "a bubble charm"}
const TILE := 32
const ORIGIN := Vector2(32, 64)
const COLUMNS := Generator.COLS + 2
const ROWS := Generator.ROWS + 2
const ROOM_SIZE := Vector2(COLUMNS * TILE, ROWS * TILE)
const ROOM_END := ORIGIN + ROOM_SIZE
## Top-left of the walkable interior (inside the perimeter wall).
const INTERIOR := ORIGIN + Vector2(TILE, TILE)
const INTERIOR_SIZE := Vector2(Generator.COLS * TILE, Generator.ROWS * TILE)
const INNER_END := INTERIOR + INTERIOR_SIZE
const CENTER := INTERIOR + INTERIOR_SIZE / 2.0
const START_SPAWN := Vector2(CENTER.x, INNER_END.y - 64)
const ACCENT := Color("af9be9")
const ITEM_COLOR := Color("7fe0d0")
const MAX_ROOMS := 18
## All per-direction tables run north, east, south, west.
const WALLS: Array[Rect2] = [
	Rect2(ORIGIN, Vector2(ROOM_SIZE.x, TILE)),
	Rect2(INNER_END.x, ORIGIN.y, TILE, ROOM_SIZE.y),
	Rect2(ORIGIN.x, INNER_END.y, ROOM_SIZE.x, TILE),
	Rect2(ORIGIN, Vector2(TILE, ROOM_SIZE.y)),
]
## Two wall tiles are left open, centred on each side.
const DOOR_GAPS: Array[Rect2] = [
	Rect2(CENTER.x - TILE, ORIGIN.y, TILE * 2, TILE),
	Rect2(INNER_END.x, CENTER.y - TILE, TILE, TILE * 2),
	Rect2(CENTER.x - TILE, INNER_END.y, TILE * 2, TILE),
	Rect2(ORIGIN.x, CENTER.y - TILE, TILE, TILE * 2),
]
## Walking into the outer half of a doorway moves to the next room.
const DOOR_TRIGGERS: Array[Rect2] = [
	Rect2(CENTER.x - TILE, ORIGIN.y, TILE * 2, 14),
	Rect2(ROOM_END.x - 14, CENTER.y - TILE, 14, TILE * 2),
	Rect2(CENTER.x - TILE, ROOM_END.y - 14, TILE * 2, 14),
	Rect2(ORIGIN.x, CENTER.y - TILE, 14, TILE * 2),
]
## Thin walls just past each doorway keep the knight inside during transitions.
const DOOR_STOPS: Array[Rect2] = [
	Rect2(CENTER.x - TILE, ORIGIN.y - 16, TILE * 2, 16),
	Rect2(ROOM_END.x, CENTER.y - TILE, 16, TILE * 2),
	Rect2(CENTER.x - TILE, ROOM_END.y, TILE * 2, 16),
	Rect2(ORIGIN.x - 16, CENTER.y - TILE, 16, TILE * 2),
]
## Where the knight stands after arriving through each door.
const DOOR_SPAWNS: Array[Vector2] = [
	Vector2(CENTER.x, INTERIOR.y + 34),
	Vector2(INNER_END.x - 22, CENTER.y + 6),
	Vector2(CENTER.x, INNER_END.y - 6),
	Vector2(INTERIOR.x + 22, CENTER.y + 6),
]
const STAIRS := Rect2(CENTER - Vector2(TILE, TILE), Vector2(TILE * 2, TILE * 2))

@export var dungeon_seed := 0 ## 0 rolls a new dungeon every run.
@export var first_floor_rooms := 8
@export var fade_time := 0.12

var generator := Generator.new()
var rooms: Dictionary = {}
var current: Generator.Room
var floor_number := 1
var inventory := {"sword": 0, "potion": 0, "bubble": 0}
var run_seed := 0
var entry_point := START_SPAWN
var entry_faces_left := false
var transitioning := false
var status_label: Label
var progress_label: Label
var caption_label: Label
var minimap: Control
var item_slots := {}
var fade: ColorRect

@onready var knight: CharacterBody2D = $Knight
@onready var boundaries: Node2D = $Boundaries
@onready var blocks: Node2D = $Blocks
@onready var props: Node2D = $Props
@onready var front_walls: Node2D = $FrontWalls

func _ready() -> void:
	front_walls.draw.connect(draw_front_walls)
	if Engine.is_editor_hint():
		return
	configure_input()
	make_interface()
	run_seed = dungeon_seed if dungeon_seed != 0 else randi()
	print("Violet Keep seed %d — WASD / arrows: move · Shift: run · R: back to door · Esc: quit" % run_seed)
	begin()

## The dungeon is explored in rock form; tutorial.gd overrides this.
func begin() -> void:
	knight.call("set_rock", true)
	start_floor()
	fade.color.a = 1.0
	fade_to(0.0)

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

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed("reset") and not transitioning:
		knight.call("reset_to", entry_point, entry_faces_left)
	if event.is_action_pressed("quit"):
		get_tree().quit()

# --- Floor and room flow -----------------------------------------------------

func start_floor() -> void:
	var count := mini(first_floor_rooms + (floor_number - 1) * 2, MAX_ROOMS)
	rooms = generator.generate(hash([run_seed, floor_number]), count)
	enter_room(Vector2i.ZERO, -1)

## `via` is the door the knight arrives through, or -1 for the floor's start.
func enter_room(cell: Vector2i, via: int) -> void:
	current = rooms[cell]
	current.visited = true
	for direction in range(4):
		if current.doors[direction]:
			rooms[cell + Generator.OFFSETS[direction]].seen = true
	# Move the knight before the new triggers exist, so the door it just used
	# cannot fire again in the next room.
	entry_point = START_SPAWN if via < 0 else DOOR_SPAWNS[via]
	entry_faces_left = via == Generator.EAST
	knight.call("reset_to", entry_point, entry_faces_left)
	rebuild()
	queue_redraw()
	front_walls.queue_redraw()
	update_hud()

func travel(direction: int) -> void:
	knight.set_physics_process(false)
	await fade_to(1.0)
	enter_room(current.cell + Generator.OFFSETS[direction], Generator.opposite(direction))
	await fade_to(0.0)
	knight.set_physics_process(true)
	transitioning = false

func descend() -> void:
	knight.set_physics_process(false)
	await fade_to(1.0)
	floor_number += 1
	start_floor()
	await fade_to(0.0)
	knight.set_physics_process(true)
	transitioning = false

func fade_to(alpha: float) -> void:
	if fade_time <= 0.0:
		fade.color.a = alpha
		return
	var tween := create_tween()
	tween.tween_property(fade, "color:a", alpha, fade_time)
	await tween.finished

func _on_door_entered(body: Node2D, direction: int) -> void:
	# Physics can report a stale overlap right after a room swap; trust only
	# a knight still in an open doorway. Check the whole passage: the feet
	# can overlap a side trigger before their centre reaches that trigger.
	var inside := DOOR_GAPS[direction].has_point(knight.position)
	if body == knight and has_door(direction) and inside and not transitioning:
		transitioning = true
		travel.call_deferred(direction)

func _on_stairs_entered(body: Node2D) -> void:
	if body == knight and not transitioning:
		transitioning = true
		descend.call_deferred()

func _on_item_entered(body: Node2D, pickup: Area2D) -> void:
	if body != knight or current.item_taken:
		return
	current.item_taken = true
	inventory[current.item] += 1
	pickup.queue_free()
	update_hud()

# --- Building the room ------------------------------------------------------

func rebuild() -> void:
	for container: Node in [boundaries, blocks, props]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	for direction in range(4):
		if current.doors[direction]:
			for part in split_wall(WALLS[direction], DOOR_GAPS[direction], direction % 2 == 0):
				make_wall(part)
			if direction % 2 == 1:
				make_door_lintel(direction)
			make_wall(DOOR_STOPS[direction])
			make_area(DOOR_TRIGGERS[direction], boundaries).body_entered.connect(_on_door_entered.bind(direction))
		else:
			make_wall(WALLS[direction])
	var solid := {}
	for cell in current.blocks:
		solid[cell] = true
	for cell in current.blocks:
		var block: Node2D = BLOCK.instantiate()
		# Art and collider both fill exactly this floor tile.
		block.position = INTERIOR + Vector2(cell) * TILE + Vector2(TILE / 2, TILE / 2)
		var mask := 0
		for direction in range(4):
			if solid.has(cell + Generator.OFFSETS[direction]):
				mask |= 1 << direction
		block.set("neighbours", mask)
		blocks.add_child(block)
	for cell in current.ornaments:
		var ornament: Node2D = ORNAMENT.instantiate()
		ornament.position = INTERIOR + Vector2(cell) * TILE + Vector2(TILE / 2, TILE - 6)
		blocks.add_child(ornament)
	if current.kind == "exit":
		make_area(STAIRS.grow(-12), props).body_entered.connect(_on_stairs_entered)
	if current.kind == "treasure" and not current.item_taken:
		make_item()

static func split_wall(wall: Rect2, gap: Rect2, horizontal: bool) -> Array[Rect2]:
	if horizontal:
		return [Rect2(wall.position, Vector2(gap.position.x - wall.position.x, wall.size.y)),
			Rect2(gap.end.x, wall.position.y, wall.end.x - gap.end.x, wall.size.y)]
	return [Rect2(wall.position, Vector2(wall.size.x, gap.position.y - wall.position.y)),
		Rect2(wall.position.x, gap.end.y, wall.size.x, wall.end.y - gap.end.y)]

func make_wall(bounds: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = bounds.get_center()
	body.add_child(make_shape(bounds.size))
	boundaries.add_child(body)

func make_area(bounds: Rect2, parent: Node) -> Area2D:
	var area := Area2D.new()
	area.position = bounds.get_center()
	area.monitorable = false
	area.add_child(make_shape(bounds.size))
	parent.add_child(area)
	return area

static func make_shape(size: Vector2) -> CollisionShape2D:
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	return collision

func make_door_lintel(direction: int) -> void:
	# Sort the tile above a side doorway at the jamb's base, just like a
	# pillar. Feet below it place the head in front; feet above stay behind.
	# Blocks is already Y-sorted with the knight, and cleared on room swaps.
	var lintel := Node2D.new()
	lintel.name = "DoorLintel%d" % direction
	lintel.position = DOOR_GAPS[direction].position
	lintel.draw.connect(draw_door_lintel.bind(lintel, direction))
	blocks.add_child(lintel)

func make_item() -> void:
	var pickup := make_area(Rect2(CENTER.x - 10, CENTER.y - 4, 20, 16), props)
	pickup.position = CENTER + Vector2(0, 10)
	pickup.get_child(0).position = Vector2(0, -6)
	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([Vector2(-9, -2), Vector2(9, -2), Vector2(9, 1), Vector2(-9, 1)])
	shadow.color = Color(0, 0, 0.02, 0.45)
	pickup.add_child(shadow)
	var art := Sprite2D.new()
	art.texture = ITEM_ART[current.item]
	art.scale = Vector2(0.25, 0.25)
	art.offset = Vector2(0, -88)
	pickup.add_child(art)
	var bob := art.create_tween().set_loops()
	bob.tween_property(art, "position:y", -3.0, 0.6).set_trans(Tween.TRANS_SINE)
	bob.tween_property(art, "position:y", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	pickup.body_entered.connect(_on_item_entered.bind(pickup))

# --- HUD -------------------------------------------------------------------

func make_interface() -> void:
	var curtain := CanvasLayer.new()
	curtain.layer = 5
	add_child(curtain)
	fade = ColorRect.new()
	fade.color = Color(0.028, 0.022, 0.064, 0.0)
	fade.size = Vector2(768, 512)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curtain.add_child(fade)
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 10
	add_child(hud)
	# The camera moves the room beneath the HUD; keep text and icons readable.
	for bounds in [Rect2(0, 0, 768, 60), Rect2(0, 458, 768, 54)]:
		var panel := ColorRect.new()
		panel.position = bounds.position
		panel.size = bounds.size
		panel.color = Color("070510")
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(panel)
	make_label(hud, "THE VIOLET KEEP", Vector2(32, 19), 21, Color("e1d6fb"))
	status_label = make_label(hud, "", Vector2(236, 18), 12, ACCENT)
	progress_label = make_label(hud, "", Vector2(236, 35), 10, Color("8a7cab"))
	make_label(hud, "WASD / ARROWS  move     SHIFT  run", Vector2(32, 466), 13, Color("c5bdd8"))
	make_label(hud, "R  back to door     ESC  quit", Vector2(530, 466), 13, Color("9284b1"))
	caption_label = make_label(hud, "", Vector2(32, 491), 10, Color("75678e"))
	var slots := HBoxContainer.new()
	slots.position = Vector2(440, 14)
	slots.add_theme_constant_override("separation", 6)
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(slots)
	for item: String in ITEM_ART:
		var icon := TextureRect.new()
		icon.texture = ITEM_ART[item]
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = ITEM_NAMES[item]
		slots.add_child(icon)
		item_slots[item] = icon
	minimap = Control.new()
	minimap.position = Vector2(560, 6)
	minimap.size = Vector2(176, 52)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(draw_minimap)
	hud.add_child(minimap)

func make_label(parent: Node, caption: String, at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func update_hud() -> void:
	var explored := 0
	for room: Generator.Room in rooms.values():
		if room.visited:
			explored += 1
	status_label.text = "FLOOR %d  /  %s" % [floor_number, current.layout.to_upper()]
	progress_label.text = "%d OF %d ROOMS EXPLORED" % [explored, rooms.size()]
	for item: String in item_slots:
		# Items not found yet show as dark silhouettes.
		item_slots[item].modulate = Color.WHITE if inventory[item] > 0 else Color(0.3, 0.25, 0.45, 0.55)
	match current.kind:
		"start":
			caption_label.text = "Stone, but still moving. Somewhere below, the curse can be broken." if floor_number == 1 else "Floor %d. The stairs sealed behind you." % floor_number
		"exit":
			caption_label.text = "Stairs spiral down into the dark. Step on them to descend."
		"treasure":
			caption_label.text = "Something glints here." if not current.item_taken else "You found %s." % ITEM_NAMES[current.item]
		_:
			caption_label.text = "Seed %d" % run_seed
	minimap.queue_redraw()

func draw_minimap() -> void:
	var low := Vector2i(999, 999)
	var high := Vector2i(-999, -999)
	for cell: Vector2i in rooms:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	var span := high - low + Vector2i.ONE
	var pitch := Vector2(minf(minimap.size.x / span.x, 18.0), minf(minimap.size.y / span.y, 11.0))
	var origin := Vector2(minimap.size.x - pitch.x * span.x, (minimap.size.y - pitch.y * span.y) / 2.0)
	var cell_size := pitch - Vector2(3, 3)
	for room: Generator.Room in rooms.values():
		if not room.visited:
			continue
		var center := origin + Vector2(room.cell - low) * pitch + cell_size / 2.0
		for direction in [Generator.EAST, Generator.SOUTH]:
			var other: Generator.Room = rooms.get(room.cell + Generator.OFFSETS[direction])
			if room.doors[direction] and other and (other.visited or other.seen):
				minimap.draw_line(center, center + Vector2(Generator.OFFSETS[direction]) * pitch, Color("3d3158"), 1.0)
	for room: Generator.Room in rooms.values():
		if not (room.visited or room.seen):
			continue
		var rect := Rect2(origin + Vector2(room.cell - low) * pitch, cell_size)
		if room == current:
			minimap.draw_rect(rect, ACCENT)
		elif room.visited:
			minimap.draw_rect(rect, Color("574a7a"))
		else:
			minimap.draw_rect(rect, Color("1a1430"))
			minimap.draw_rect(rect, Color("3d3158"), false, 1.0)
		var dot := Rect2(rect.get_center() - Vector2(1.5, 1.5), Vector2(3, 3))
		if room.kind == "exit":
			minimap.draw_rect(dot.grow(0.5), Color("0a0716"))
		elif room.kind == "treasure" and not room.item_taken:
			minimap.draw_rect(dot, ITEM_COLOR)

# --- Drawing ----------------------------------------------------------------

func has_door(direction: int) -> bool:
	return current != null and current.doors[direction]

## Returns the direction of the open doorway covering a wall tile, or -1.
func doorway_at(column: int, row: int) -> int:
	var edges := [row == 0, column == COLUMNS - 1, row == ROWS - 1, column == 0]
	for direction in range(4):
		var along := column if direction % 2 == 0 else row
		var middle := COLUMNS / 2 if direction % 2 == 0 else ROWS / 2
		if edges[direction] and has_door(direction) and (along == middle - 1 or along == middle):
			return direction
	return -1

func _draw() -> void:
	var kind := current.kind if current else "start"
	# Each floor down is drawn a little colder and darker.
	var depth_tint := 1.0 - 0.05 * clampf(floor_number - 1, 0, 5)
	draw_rect(Rect2(ORIGIN + Vector2(8, 14), ROOM_SIZE), Color("04040e"))
	draw_rect(Rect2(ORIGIN - Vector2(2, 2), ROOM_SIZE + Vector2(4, 4)), Color("3a2b51"))
	for row in range(ROWS):
		for column in range(COLUMNS):
			var at := ORIGIN + Vector2(column, row) * TILE
			var rect := Rect2(at, Vector2(TILE, TILE))
			var doorway := doorway_at(column, row)
			if doorway >= 0:
				draw_doorway(rect, doorway)
			elif is_front_wall(column, row):
				continue
			elif row == 0:
				draw_wall(rect, self, true)
			else:
				var brightness := (0.70 + float((column * 7 + row * 3) % 5) * 0.025) * depth_tint
				if (column == 10 or column == 11) and (has_door(Generator.NORTH) or has_door(Generator.SOUTH)):
					brightness += 0.13
				var floor_art := FLOOR_TILES if current and current.tiled_floor else STONE
				if floor_art == FLOOR_TILES:
					brightness += 0.35
				draw_texture_rect(floor_art, rect, false, Color(brightness, brightness, brightness * 1.13))
				draw_rect(rect, Color(0.18, 0.14, 0.3, 0.15), false, 1.0)
	draw_rect(Rect2(INTERIOR, Vector2(INTERIOR_SIZE.x, 10)), Color(0, 0, 0.03, 0.38))
	# Side shadows meet the north/south strips without dark double overlaps.
	var side_shadow_height := INTERIOR_SIZE.y - 17
	draw_rect(Rect2(INTERIOR + Vector2(0, 10), Vector2(7, side_shadow_height)), Color(0, 0, 0.03, 0.28))
	draw_rect(Rect2(INNER_END.x - 7, INTERIOR.y + 10, 7, side_shadow_height), Color(0, 0, 0.03, 0.28))
	draw_rect(Rect2(INTERIOR.x, INNER_END.y - 7, INTERIOR_SIZE.x, 7), Color(0, 0, 0.03, 0.22))
	# The north face and its trim sit behind the knight.
	draw_edge(Rect2(INTERIOR - Vector2(3, 3), Vector2(INTERIOR_SIZE.x + 6, 3)), Color("766187"), Generator.NORTH, self)
	for direction in range(4):
		if has_door(direction):
			draw_door_threshold(direction)
	match kind:
		"start":
			draw_compass(Color("655381"))
		"treasure":
			draw_compass(Color("2f6a68"))
		"exit":
			draw_stairs()
	for x in [176, 592]:
		draw_rect(Rect2(x - 6, 84, 12, 12), Color("19122c"))
		draw_rect(Rect2(x - 4, 77, 8, 9), Color("6f459b"))
		draw_rect(Rect2(x - 2, 75, 4, 8), Color("c5b2ff"))
		draw_rect(Rect2(x - 1, 77, 2, 4), Color("f0e5ff"))

## The side and south walls cover sprites outside the room. The upper side
## door jambs are separate Y-sorted pieces so they do not cover a head when
## the feet are already standing inside the open passage.
static func is_front_wall(column: int, row: int) -> bool:
	return column == 0 or column == COLUMNS - 1 or row == ROWS - 1

func draw_front_walls() -> void:
	for row in range(ROWS):
		for column in range(COLUMNS):
			if not is_front_wall(column, row):
				continue
			var rect := Rect2(ORIGIN + Vector2(column, row) * TILE, Vector2(TILE, TILE))
			# Open passages are ground, already drawn below the knight.
			var upper_jamb := row == ROWS / 2 - 2 and (
				(column == 0 and has_door(Generator.WEST)) or
				(column == COLUMNS - 1 and has_door(Generator.EAST)))
			if doorway_at(column, row) < 0 and not upper_jamb:
				# Corner tiles continue the vertical wall. A north-face base
				# shadow here would draw a false seam across that wall.
				draw_wall(rect, front_walls)
	# The inner trim turns around the floor opening. Its vertical runs start
	# at the north edge, instead of cutting through the north wall's face.
	# Both the inner and outer outlines leave the entire doorway open.
	var light := Color("766187")
	draw_edge(Rect2(INTERIOR - Vector2(3, 3), Vector2(3, INTERIOR_SIZE.y + 6)), light, Generator.WEST)
	draw_edge(Rect2(INNER_END.x, INTERIOR.y - 3, 3, INTERIOR_SIZE.y + 6), light, Generator.EAST)
	draw_edge(Rect2(INTERIOR.x - 3, INNER_END.y, INTERIOR_SIZE.x + 6, 3), light, Generator.SOUTH)
	draw_edge(Rect2(ORIGIN, Vector2(ROOM_SIZE.x, 3)), light, Generator.NORTH)
	draw_edge(Rect2(ORIGIN, Vector2(3, ROOM_SIZE.y)), light, Generator.WEST)
	draw_edge(Rect2(ROOM_END.x - 3, ORIGIN.y, 3, ROOM_SIZE.y), light, Generator.EAST)
	draw_edge(Rect2(ORIGIN.x, ROOM_END.y - 3, ROOM_SIZE.x, 3), light, Generator.SOUTH)
	for direction in range(4):
		if has_door(direction):
			draw_door_frame(front_walls, direction)
	var outline := Color("21192f")
	draw_edge(Rect2(ORIGIN, Vector2(ROOM_SIZE.x, 1)), outline, Generator.NORTH)
	draw_edge(Rect2(ROOM_END.x - 1, ORIGIN.y, 1, ROOM_SIZE.y), outline, Generator.EAST)
	draw_edge(Rect2(ORIGIN.x, ROOM_END.y - 1, ROOM_SIZE.x, 1), outline, Generator.SOUTH)
	draw_edge(Rect2(ORIGIN, Vector2(1, ROOM_SIZE.y)), outline, Generator.WEST)

## Draws a continuous wall edge, skipping the doorway on that side.
func draw_edge(strip: Rect2, color: Color, side: int, canvas: CanvasItem = null) -> void:
	var target := front_walls if canvas == null else canvas
	if not has_door(side):
		target.draw_rect(strip, color)
		return
	var gap := DOOR_GAPS[side]
	if side % 2 == 1:
		# This tile and its trim are drawn by the Y-sorted upper jamb.
		gap = Rect2(gap.position - Vector2(0, TILE), gap.size + Vector2(0, TILE))
	for part in split_wall(strip, gap, side % 2 == 0):
		target.draw_rect(part, color)

## Brick tiles join without seams. The north wall is seen face-on, so it is
## shaded toward its base where it meets the floor.
func draw_wall(rect: Rect2, canvas: CanvasItem = self, north_face := false) -> void:
	canvas.draw_texture_rect(WALL, rect, false, Color(1.25, 1.1, 1.4))
	if north_face:
		canvas.draw_rect(Rect2(rect.position + Vector2(0, 20), Vector2(32, 12)), Color(0.02, 0.01, 0.05, 0.3))
		canvas.draw_rect(Rect2(rect.position + Vector2(0, 30), Vector2(32, 2)), Color("151023"))

## A dim strip of floor that fades into darkness toward the next room.
func draw_doorway(rect: Rect2, direction: int, canvas: CanvasItem = self) -> void:
	canvas.draw_texture_rect(STONE, rect, false, Color(0.5, 0.45, 0.62))
	for band in range(4):
		var depth := float(band) * 8.0
		var strip: Rect2
		match direction:
			Generator.NORTH:
				strip = Rect2(rect.position.x, rect.position.y + depth, 32, 8)
			Generator.SOUTH:
				strip = Rect2(rect.position.x, rect.end.y - depth - 8, 32, 8)
			Generator.WEST:
				strip = Rect2(rect.position.x + depth, rect.position.y, 8, 32)
			_:
				strip = Rect2(rect.end.x - depth - 8, rect.position.y, 8, 32)
		canvas.draw_rect(strip, Color(0.016, 0.012, 0.04, 0.9 - band * 0.25))

func draw_door_frame(canvas: CanvasItem, direction: int) -> void:
	var gap := DOOR_GAPS[direction]
	var post := Color("8f7bb0")
	# Only the solid jambs belong above the character.
	if direction % 2 == 0:
		canvas.draw_rect(Rect2(gap.position.x - 4, gap.position.y, 4, 32), post)
		canvas.draw_rect(Rect2(gap.end.x, gap.position.y, 4, 32), post)
	else:
		canvas.draw_rect(Rect2(gap.position.x, gap.end.y, 32, 4), post)

func draw_door_lintel(canvas: Node2D, direction: int) -> void:
	draw_wall(Rect2(0, -TILE, TILE, TILE), canvas)
	var inner_x := 0 if direction == Generator.EAST else TILE - 3
	var outer_x := TILE - 3 if direction == Generator.EAST else 0
	var outline_x := TILE - 1 if direction == Generator.EAST else 0
	canvas.draw_rect(Rect2(inner_x, -TILE, 3, TILE), Color("766187"))
	canvas.draw_rect(Rect2(outer_x, -TILE, 3, TILE), Color("766187"))
	canvas.draw_rect(Rect2(0, -4, TILE, 4), Color("8f7bb0"))
	canvas.draw_rect(Rect2(outline_x, -TILE, 1, TILE), Color("21192f"))

func draw_door_threshold(direction: int) -> void:
	# This is floor trim, so the knight walks over it rather than behind it.
	var gap := DOOR_GAPS[direction]
	var threshold := Color("8870b1")
	if direction % 2 == 0:
		var inner_y := gap.end.y - 3 if direction == Generator.NORTH else gap.position.y
		draw_rect(Rect2(gap.position.x, inner_y, 64, 3), threshold)
	else:
		var inner_x := gap.end.x - 3 if direction == Generator.WEST else gap.position.x
		draw_rect(Rect2(inner_x, gap.position.y, 3, 64), threshold)

func draw_compass(color: Color) -> void:
	draw_line(CENTER + Vector2(0, -18), CENTER + Vector2(0, 18), color, 2.0)
	draw_line(CENTER + Vector2(-18, 0), CENTER + Vector2(18, 0), color, 2.0)
	draw_polyline(PackedVector2Array([CENTER + Vector2(0, -12), CENTER + Vector2(12, 0), CENTER + Vector2(0, 12), CENTER + Vector2(-12, 0), CENTER + Vector2(0, -12)]), color, 2.0)
	draw_rect(Rect2(CENTER - Vector2(2, 2), Vector2(4, 4)), ACCENT)

func draw_stairs() -> void:
	draw_rect(STAIRS.grow(4), Color("19122c"))
	draw_rect(STAIRS, Color("05040b"))
	# Each step is narrower and darker, so the flight reads as going down.
	for step in range(5):
		var shade := 1.5 - step * 0.28
		var strip := Rect2(STAIRS.position.x + 4 + step * 3, STAIRS.position.y + 4 + step * 12, 56 - step * 6, 10)
		draw_texture_rect(WALL, strip, false, Color(shade, shade * 0.9, shade * 1.2))
		draw_rect(Rect2(strip.position, Vector2(strip.size.x, 2)), Color(0.8, 0.7, 1.0, shade * 0.6))
		draw_rect(Rect2(strip.position + Vector2(0, 10), Vector2(strip.size.x, 2)), Color(0, 0, 0.02, 0.8))
	draw_rect(STAIRS.grow(4), ACCENT, false, 1.0)
