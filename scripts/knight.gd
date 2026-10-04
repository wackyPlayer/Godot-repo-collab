extends CharacterBody2D
## The small foot collider lets the knight pass naturally behind tall blocks.

const IDLE: Texture2D = preload("res://assets/knight_idle.png")
const WALK: Texture2D = preload("res://assets/knight_walk.png")
const WALK_SPEED := 132.0
const RUN_SPEED := 210.0

@onready var sprite: Sprite2D = $KnightSprite
var animation_time := 0.0
var was_moving := false

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("knight")

func _physics_process(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var running := Input.is_action_pressed("sprint")
	velocity = direction * (RUN_SPEED if running else WALK_SPEED)
	move_and_slide()
	# Actual motion makes the knight idle when pushing directly into a wall.
	var moving := get_position_delta().length_squared() > 0.001
	if direction.x != 0.0:
		sprite.flip_h = direction.x < 0.0
	if moving != was_moving:
		animation_time = 0.0
		sprite.texture = WALK if moving else IDLE
		was_moving = moving
	animation_time += delta * ((12.0 if running else 8.0) if moving else 3.0)
	sprite.frame = int(animation_time) % 4

func reset_to(spawn: Vector2) -> void:
	position = spawn
	velocity = Vector2.ZERO
	animation_time = 0.0
	was_moving = false
	sprite.texture = IDLE
	sprite.frame = 0
	sprite.flip_h = false

func _draw() -> void:
	draw_rect(Rect2(-10, -3, 20, 5), Color(0.0, 0.0, 0.015, 0.5))
	draw_rect(Rect2(-7, -4, 14, 7), Color(0.0, 0.0, 0.015, 0.35))
