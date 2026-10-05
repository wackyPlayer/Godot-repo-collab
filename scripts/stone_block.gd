@tool
extends StaticBody2D
## One floor tile of solid stone. The art fills exactly the tile its collider
## covers, and edges shared with neighbouring blocks are left open so a run of
## blocks reads as one continuous wall.

const STONE: Texture2D = preload("res://assets/stone.png")
const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8
const FACE_HEIGHT := 10.0

## Bitmask of adjacent blocks (NORTH | EAST | SOUTH | WEST).
@export var neighbours := 0:
	set(value):
		neighbours = value
		queue_redraw()

func _draw() -> void:
	var open_below := neighbours & SOUTH == 0
	var top_bottom := 16.0 - (FACE_HEIGHT if open_below else 0.0)
	# Regions keep the texture at one scale, so neighbouring tiles line up.
	var top_height := top_bottom + 16.0
	var texel := STONE.get_width() / 32.0
	draw_texture_rect_region(STONE, Rect2(-16, -16, 32, top_height), Rect2(0, 0, STONE.get_width(), top_height * texel), Color(2.0, 1.75, 2.55))
	if open_below:
		# The front face only shows where nothing stands in front of it.
		draw_texture_rect_region(STONE, Rect2(-16, top_bottom, 32, FACE_HEIGHT), Rect2(0, top_height * texel, STONE.get_width(), FACE_HEIGHT * texel), Color(1.0, 0.88, 1.45))
		draw_rect(Rect2(-16, top_bottom, 32, 1), Color("141125"))
		draw_rect(Rect2(-16, 15, 32, 1), Color("100d20"))
		draw_rect(Rect2(-16, 16, 32, 4), Color(0, 0, 0.02, 0.35))
	if neighbours & NORTH == 0:
		draw_rect(Rect2(-16, -16, 32, 2), Color("88769e"))
	if neighbours & WEST == 0:
		draw_rect(Rect2(-16, -16, 2, 32), Color("665b80"))
	if neighbours & EAST == 0:
		draw_rect(Rect2(15, -16, 1, 32), Color("1b1530"))
