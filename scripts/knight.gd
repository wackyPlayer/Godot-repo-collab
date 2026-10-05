extends CharacterBody2D
## The origin sits at the bottom of the feet so Y-sorting and the small foot
## collider both match where the knight visibly stands.

const IDLE: Texture2D = preload("res://assets/knight_idle.png")
const WALK: Texture2D = preload("res://assets/knight_walk.png")
## After the mage's curse the knight is a rock (with the plume still on).
const ROCK: Texture2D = preload("res://assets/knight_rock.png")
const WALK_SPEED := 132.0
const RUN_SPEED := 210.0
## The art's feet sit 5px right of the frame centre, so the sprite is shifted
## to keep them over the collider whichever way the knight faces.
const SPRITE_SHIFT := 5.0
const ROCK_SHIFT := 3.0

@onready var sprite: Sprite2D = $KnightSprite
@onready var camera: Camera2D = $Camera2D
var animation_time := 0.0
var was_moving := false
var rock := false

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
		face(direction.x < 0.0)
	if moving != was_moving:
		animation_time = 0.0
		sprite.texture = sheet(moving)
		was_moving = moving
	animation_time += delta * ((12.0 if running else 8.0) if moving else 3.0)
	# A rock sits still until it moves; the knight breathes while idle.
	sprite.frame = 0 if rock and not moving else int(animation_time) % 4

func face(left: bool) -> void:
	var shift := ROCK_SHIFT if rock else SPRITE_SHIFT
	sprite.flip_h = left
	sprite.position.x = shift if left else -shift

func sheet(moving: bool) -> Texture2D:
	if rock:
		return ROCK
	return WALK if moving else IDLE

func set_rock(value: bool) -> void:
	rock = value
	sprite.texture = sheet(was_moving)
	face(sprite.flip_h)

func reset_to(spawn: Vector2, face_left := false) -> void:
	position = spawn
	velocity = Vector2.ZERO
	animation_time = 0.0
	was_moving = false
	sprite.texture = sheet(false)
	sprite.frame = 0
	face(face_left)
	# Door transitions and R move the camera immediately with the player.
	if is_instance_valid(camera):
		camera.force_update_scroll()

func _draw() -> void:
	draw_rect(Rect2(-10, -4, 20, 5), Color(0.0, 0.0, 0.015, 0.5))
	draw_rect(Rect2(-7, -5, 14, 7), Color(0.0, 0.0, 0.015, 0.35))
