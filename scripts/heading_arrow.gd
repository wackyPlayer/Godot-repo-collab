extends Node2D
## A small arrow at the player's feet showing which way the brain controls
## will walk (BrainLink's heading). Faint while standing, bright while
## walking, doubled while running. Hidden when the brain interface is off.

const COLOR := Color("af9be9")
## Centre of the player's body, relative to the feet.
const BODY := Vector2(0, -12)
const DISTANCE := 24.0

func _process(_delta: float) -> void:
	var brain := get_node_or_null("/root/BrainLink")
	visible = brain != null and brain.enabled()
	if visible:
		queue_redraw()

func _draw() -> void:
	var brain := get_node("/root/BrainLink")
	var forward: Vector2 = brain.heading_vector()
	var side := Vector2(-forward.y, forward.x)
	var alpha := 0.95 if brain.moving else 0.45
	var count := 2 if brain.running else 1
	for index in range(count):
		var tip := BODY + forward * (DISTANCE + index * 6.0)
		var points := PackedVector2Array([tip, tip - forward * 6.0 + side * 5.0, tip - forward * 6.0 - side * 5.0])
		draw_colored_polygon(points, Color(COLOR, alpha))
