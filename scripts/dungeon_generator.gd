extends RefCounted
## Plans one floor of the tower: a branching grid of rooms joined by doors, each
## with an interior picked from hand-drawn templates or scattered stone.
## Pure data. room.gd turns it into collision and drawing.

enum { NORTH, EAST, SOUTH, WEST }
const OFFSETS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## Interior size in tiles (the walkable area inside the perimeter wall).
const COLS := 20
const ROWS := 22
## Keeps the floor plan compact enough for the minimap.
const MAX_X := 4
const MAX_Y := 3
## You arrive in the start room from below (the stairs or the round
## chamber), so no room is ever placed directly south of it.
const BELOW_START := Vector2i(0, 1)
const LOOP_CHANCE := 0.15
const TILED_FLOOR_CHANCE := 0.3
const ITEMS: Array[String] = ["sword", "potion", "bubble"]
const SCATTER_DENSITY := 0.09
const MID_ROW := ROWS / 2
const CENTER_CELLS: Array[Vector2i] = [Vector2i(9, MID_ROW - 1), Vector2i(10, MID_ROW - 1), Vector2i(9, MID_ROW), Vector2i(10, MID_ROW)]
## The 2x2 floor cells in front of each door, indexed by direction.
const DOOR_CELLS := [
	[Vector2i(9, 0), Vector2i(10, 0), Vector2i(9, 1), Vector2i(10, 1)],
	[Vector2i(18, MID_ROW - 1), Vector2i(19, MID_ROW - 1), Vector2i(18, MID_ROW), Vector2i(19, MID_ROW)],
	[Vector2i(9, ROWS - 2), Vector2i(10, ROWS - 2), Vector2i(9, ROWS - 1), Vector2i(10, ROWS - 1)],
	[Vector2i(0, MID_ROW - 1), Vector2i(1, MID_ROW - 1), Vector2i(0, MID_ROW), Vector2i(1, MID_ROW)],
]

## "#" is a stone block, "." is floor. Existing 20x10 templates are centred
## in the taller interior, preserving their connected walls and block sizes.
## Templates may be mirrored; doors and the centre are cleared afterwards.
const START_LAYOUT := {"name": "Entry Hall", "rows": [
	"....................",
	"....................",
	"....................",
	".....#........#.....",
	"....................",
	"....................",
	"....................",
	".....#........#.....",
	"....................",
	"....................",
]}
const EXIT_LAYOUT := {"name": "Stairwell", "rows": [
	"....................",
	"....................",
	"....................",
	".......#....#.......",
	"....................",
	"....................",
	".......#....#.......",
	"....................",
	"....................",
	"....................",
]}
const TREASURE_LAYOUT := {"name": "Vault", "rows": [
	"....................",
	"....................",
	"....................",
	"........#..#........",
	"......#......#......",
	"......#......#......",
	"........#..#........",
	"....................",
	"....................",
	"....................",
]}
const LAYOUTS := [
	{"name": "Colonnade", "rows": [
		"....................",
		"..#..#..#..#..#..#..",
		"....................",
		"....................",
		"....................",
		"....................",
		"....................",
		"....................",
		"..#..#..#..#..#..#..",
		"....................",
	]},
	{"name": "Crossing", "rows": [
		"....................",
		".###............###.",
		".#................#.",
		"....................",
		"......##....##......",
		"......##....##......",
		"....................",
		".#................#.",
		".###............###.",
		"....................",
	]},
	{"name": "Ring", "rows": [
		"....................",
		"....................",
		"......###..###......",
		"......#......#......",
		"....................",
		"....................",
		"......#......#......",
		"......###..###......",
		"....................",
		"....................",
	]},
	{"name": "Pillar Field", "rows": [
		"....................",
		"...#....#..#....#...",
		"....................",
		"......#......#......",
		"..#..............#..",
		"..#..............#..",
		"......#......#......",
		"....................",
		"...#....#..#....#...",
		"....................",
	]},
	{"name": "Gallery", "rows": [
		"....................",
		"....................",
		"..######....######..",
		"....................",
		"....................",
		"....................",
		"....................",
		"..######....######..",
		"....................",
		"....................",
	]},
	{"name": "Cloister", "rows": [
		"....................",
		".##.####....####.##.",
		".#................#.",
		".#..##........##..#.",
		"....#..........#....",
		"....#..........#....",
		".#..##........##..#.",
		".#................#.",
		".##.####....####.##.",
		"....................",
	]},
	{"name": "Chevrons", "rows": [
		"....................",
		"..#..............#..",
		"...#............#...",
		"....#..........#....",
		"....................",
		"....................",
		"....#..........#....",
		"...#............#...",
		"..#..............#..",
		"....................",
	]},
	{"name": "Alcoves", "rows": [
		"....................",
		"....................",
		"...####......####...",
		"...#............#...",
		"....................",
		"....................",
		"...#............#...",
		"...####......####...",
		"....................",
		"....................",
	]},
	{"name": "Aisles", "rows": [
		"....................",
		"....#....##....#....",
		"....#..........#....",
		"....#..........#....",
		"....................",
		"....................",
		"....#..........#....",
		"....#..........#....",
		"....#....##....#....",
		"....................",
	]},
	{"name": "Watchposts", "rows": [
		"....................",
		"....................",
		"...#....#..#....#...",
		"....................",
		"....................",
		"....................",
		"....................",
		"...#....#..#....#...",
		"....................",
		"....................",
	]},
	{"name": "Bastions", "rows": [
		"....................",
		"..##............##..",
		"..##............##..",
		"....................",
		".......#....#.......",
		".......#....#.......",
		"....................",
		"..##............##..",
		"..##............##..",
		"....................",
	]},
	{"name": "Buttresses", "rows": [
		"##................##",
		"#..................#",
		"....................",
		"........#..#........",
		"....................",
		"....................",
		"........#..#........",
		"....................",
		"#..................#",
		"##................##",
	]},
]


class Room:
	var cell: Vector2i
	var doors: Array[bool] = [false, false, false, false]
	## "start", "normal", "treasure" (holds an item) or "exit" (stairs down).
	var kind := "normal"
	var depth := 0
	var layout := ""
	## Interior cells holding a stone block.
	var blocks: Array[Vector2i] = []
	## Interior columns with an extra torch on the north wall.
	var torches: Array[int] = []
	var tiled_floor := false
	var item := ""
	var seen := false
	var visited := false
	var item_taken := false

	func door_count() -> int:
		return doors.count(true)


static func opposite(direction: int) -> int:
	return (direction + 2) % 4


## Returns {Vector2i cell: Room}. The same seed always yields the same floor.
## `min_exit_distance` is the fewest doors between the start and the stairs.
func generate(seed_value: int, room_count: int, min_exit_distance := 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	room_count = clampi(room_count, 4, (MAX_X * 2 + 1) * (MAX_Y * 2 + 1) / 2)
	var rooms := {}
	# If no attempt reaches the stairs distance, fall back to the farthest
	# playable floor, never one without stairs or with the wrong size.
	var best := {}
	var best_distance := -1
	for attempt in range(400):
		var plan := grow_plan(rng, room_count)
		if plan.size() != room_count or not assign_kinds(rng, plan):
			continue
		add_loops(rng, plan)
		var distance := exit_distance(plan)
		if distance > best_distance:
			best = plan
			best_distance = distance
		if distance >= min_exit_distance:
			break
	rooms = best
	if rooms.is_empty():
		push_error("Dungeon generator: no playable %d-room floor for seed %d" % [room_count, seed_value])
	elif best_distance < min_exit_distance:
		push_warning("Dungeon generator: stairs only %d doors from the start (wanted %d)" % [best_distance, min_exit_distance])
	for room: Room in rooms.values():
		build_interior(rng, room)
	return rooms


## Doors to walk through from the start room to the stairs (-1 if none).
static func exit_distance(rooms: Dictionary) -> int:
	var distance := {Vector2i.ZERO: 0}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if rooms[cell].kind == "exit":
			return distance[cell]
		for direction in range(4):
			var next: Vector2i = cell + OFFSETS[direction]
			if rooms[cell].doors[direction] and not distance.has(next):
				distance[next] = distance[cell] + 1
				queue.append(next)
	return -1


## Isaac-style growth: a new room may touch only the room it grows from,
## which keeps the plan branching with plenty of dead ends.
func grow_plan(rng: RandomNumberGenerator, room_count: int) -> Dictionary:
	var start := Room.new()
	start.kind = "start"
	var rooms := {Vector2i.ZERO: start}
	var order: Array[Vector2i] = [Vector2i.ZERO]
	var guard := 0
	while rooms.size() < room_count and guard < 4000:
		guard += 1
		var from: Vector2i = order[rng.randi() % order.size()]
		var direction := rng.randi() % 4
		var cell := from + OFFSETS[direction]
		if rooms.has(cell) or cell == BELOW_START or absi(cell.x) > MAX_X or absi(cell.y) > MAX_Y:
			continue
		if neighbour_count(rooms, cell) > 1:
			continue
		var room := Room.new()
		room.cell = cell
		room.depth = rooms[from].depth + 1
		rooms[cell] = room
		link(rooms[from], room, direction)
		order.append(cell)
	return rooms


## The deepest dead end holds the stairs; up to two other dead ends hold items.
func assign_kinds(rng: RandomNumberGenerator, rooms: Dictionary) -> bool:
	var dead_ends: Array[Room] = []
	for room: Room in rooms.values():
		if room.kind != "start" and room.door_count() == 1:
			dead_ends.append(room)
	if dead_ends.size() < 2:
		return false
	dead_ends.sort_custom(func(a: Room, b: Room) -> bool: return a.depth > b.depth)
	dead_ends[0].kind = "exit"
	var others := dead_ends.slice(1)
	# Two vaults never hold the same item (a second sword would do nothing).
	var items := ITEMS.duplicate()
	for index in range(mini(2, others.size())):
		var pick := rng.randi() % others.size()
		others[pick].kind = "treasure"
		others[pick].item = items.pop_at(rng.randi() % items.size())
		others.remove_at(pick)
	return true


## A few extra doors between ordinary neighbours make small loops so the
## floor is not a pure tree. Special rooms stay dead ends.
func add_loops(rng: RandomNumberGenerator, rooms: Dictionary) -> void:
	for room: Room in rooms.values():
		if room.kind != "normal":
			continue
		for direction in [EAST, SOUTH]:
			var other: Room = rooms.get(room.cell + OFFSETS[direction])
			if other and other.kind == "normal" and not room.doors[direction] and rng.randf() < LOOP_CHANCE:
				link(room, other, direction)


func build_interior(rng: RandomNumberGenerator, room: Room) -> void:
	room.tiled_floor = room.kind in ["treasure", "exit"] or rng.randf() < TILED_FLOOR_CHANCE
	for attempt in range(16):
		var template: Dictionary
		match room.kind:
			"start":
				template = START_LAYOUT
			"exit":
				template = EXIT_LAYOUT
			"treasure":
				template = TREASURE_LAYOUT
			_:
				template = scatter_layout(rng) if rng.randf() < 0.25 else LAYOUTS[rng.randi() % LAYOUTS.size()]
		var flip_x := rng.randf() < 0.5
		var flip_y := rng.randf() < 0.5
		var blocked := parse(template.rows, flip_x, flip_y)
		for cell in required_floor(room):
			blocked.erase(cell)
		if is_traversable(blocked, room):
			room.layout = template.name
			room.blocks.assign(blocked.keys())
			place_torches(rng, room)
			return
	room.layout = "Empty Hall"


## Torches hang on the wall, so they never block the floor. Columns 3-4 and
## 16-17 already carry the room's fixed pair, and 9-10 are the north door.
func place_torches(rng: RandomNumberGenerator, room: Room) -> void:
	var free_columns: Array[int] = [0, 1, 6, 7, 12, 13, 18, 19]
	for index in range(rng.randi_range(0, 2)):
		var column: int = free_columns.pop_at(rng.randi() % free_columns.size())
		room.torches.append(column)


func scatter_layout(rng: RandomNumberGenerator) -> Dictionary:
	var rows: Array[String] = []
	for row in range(ROWS):
		var half := ""
		for column in range(COLS / 2):
			half += "#" if rng.randf() < SCATTER_DENSITY else "."
		rows.append(half + half.reverse())
	return {"name": "Rubble Hall", "rows": rows}


static func parse(rows: Array, flip_x: bool, flip_y: bool) -> Dictionary:
	var blocked := {}
	var row_offset: int = (ROWS - rows.size()) / 2
	for row in range(rows.size()):
		var line: String = rows[row]
		for column in range(COLS):
			if line[column] == "#":
				var placed_row := row + row_offset
				var cell := Vector2i(COLS - 1 - column if flip_x else column, ROWS - 1 - placed_row if flip_y else placed_row)
				blocked[cell] = true
	return blocked


static func required_floor(room: Room) -> Array[Vector2i]:
	var cells: Array[Vector2i] = CENTER_CELLS.duplicate()
	for direction in range(4):
		if room.doors[direction]:
			cells.append_array(DOOR_CELLS[direction])
	return cells


## Flood fill from the centre: every door approach must be reachable.
static func is_traversable(blocked: Dictionary, room: Room) -> bool:
	var reached := {CENTER_CELLS[0]: true}
	var queue: Array[Vector2i] = [CENTER_CELLS[0]]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset in OFFSETS:
			var next := cell + offset
			if next.x < 0 or next.y < 0 or next.x >= COLS or next.y >= ROWS:
				continue
			if blocked.has(next) or reached.has(next):
				continue
			reached[next] = true
			queue.append(next)
	for cell in required_floor(room):
		if not reached.has(cell):
			return false
	return true


static func neighbour_count(rooms: Dictionary, cell: Vector2i) -> int:
	var count := 0
	for offset in OFFSETS:
		if rooms.has(cell + offset):
			count += 1
	return count


static func link(a: Room, b: Room, direction: int) -> void:
	a.doors[direction] = true
	b.doors[opposite(direction)] = true
