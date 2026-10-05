extends Node2D
## A wall torch: loops the six flame frames and flickers its warm glow.

const FRAMES_PER_SECOND := 10.0

@onready var flame: Sprite2D = $Flame
@onready var glow: Sprite2D = $Glow
## Random start so neighbouring torches do not flicker in step.
var time := randf() * 10.0

func _process(delta: float) -> void:
	time += delta
	flame.frame = int(time * FRAMES_PER_SECOND) % flame.vframes
	glow.scale = Vector2.ONE * (1.0 + 0.05 * sin(time * 11.0) + 0.03 * sin(time * 23.0))
