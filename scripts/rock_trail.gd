extends Node2D
## The scuffs and gravel a rock leaves as it drags across the floor. Each mark
## fades out and is gone LIFETIME seconds after it was made. Marks are kept per
## room, so walking back into a room shows where the rock went recently.
## Sits at y = 0 in the Y-sorted room, so it draws over the floor but under
## blocks, enemies and the player.

const LIFETIME := 20.0
## The last few seconds of a mark's life are spent fading out.
const FADE_TIME := 5.0
const SPACING := 6.0
## Scraped stone shows paler than the floor around it.
const SCRAPE := Color(0.72, 0.64, 0.86)
const GRAVEL := Color(0.8, 0.74, 0.9)

## The player; marks are only made while it is a rock and free to move.
var target: CharacterBody2D
## Room key -> marks in the order they were made, oldest first. Each mark is
## {"at": Vector2, "born": float, "angle": float, "joined": bool}.
var marks := {}
var room_key := Vector2i.ZERO
## Game time in seconds; follows Engine.time_scale like everything else.
var clock := 0.0
var last_mark := Vector2.INF

func show_room(key: Vector2i) -> void:
	room_key = key
	last_mark = Vector2.INF
	queue_redraw()

func clear_all() -> void:
	marks.clear()
	last_mark = Vector2.INF
	queue_redraw()

func current_marks() -> Array:
	if not marks.has(room_key):
		marks[room_key] = []
	return marks[room_key]

func _process(delta: float) -> void:
	clock += delta
	var list := current_marks()
	while not list.is_empty() and clock - list[0].born > LIFETIME:
		list.pop_front()
	if is_instance_valid(target) and target.get("rock") and target.is_physics_processing():
		var here := target.position + Vector2(0, -2)
		# A jump (a door, or R) starts a new stroke instead of a long smear.
		var jumped := last_mark == Vector2.INF or here.distance_to(last_mark) > SPACING * 4
		if jumped or here.distance_to(last_mark) >= SPACING:
			list.append({"at": here, "born": clock, "angle": randf() * TAU, "joined": not jumped})
			last_mark = here
	queue_redraw()

## 1 for a fresh mark, falling to 0 over its last FADE_TIME seconds.
func strength(mark: Dictionary) -> float:
	return clampf((LIFETIME - (clock - mark.born)) / FADE_TIME, 0.0, 1.0)

func _draw() -> void:
	var list: Array = marks.get(room_key, [])
	var points := PackedVector2Array()
	var wide := PackedColorArray()
	var core := PackedColorArray()
	for index in range(list.size() + 1):
		var mark: Dictionary = list[index] if index < list.size() else {}
		if mark.is_empty() or not mark.joined:
			# A soft wide scrape with a brighter groove down the middle.
			if points.size() > 1:
				draw_polyline_colors(points, wide, 8.0)
				draw_polyline_colors(points, core, 2.0)
			points.clear()
			wide.clear()
			core.clear()
		if mark.is_empty():
			break
		var life := strength(mark)
		points.append(mark.at)
		wide.append(Color(SCRAPE, 0.16 * life))
		core.append(Color(SCRAPE, 0.4 * life))
		var side := Vector2.from_angle(mark.angle) * 5.0
		draw_rect(Rect2((mark.at + side).floor(), Vector2(2, 2)), Color(GRAVEL, 0.85 * life))
		draw_rect(Rect2((mark.at - side * 0.6).floor(), Vector2(1, 1)), Color(GRAVEL, 0.7 * life))
