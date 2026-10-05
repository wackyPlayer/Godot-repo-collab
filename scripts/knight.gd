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
## After a hit: a shove away from the danger, then a moment of blinking safety.
const KNOCKBACK := 260.0
const KNOCKBACK_DECAY := 900.0
const INVULNERABLE_TIME := 1.2
## Where enemies can hurt the player: the lower body, a little narrower than
## the sprite. Enemies test their own body against this every frame.
const HURT_RECT := Rect2(-7, -18, 14, 18)
## The player's own physics layer: walls and blocks stop the player, but
## enemies walk right up to (and onto) them instead of being held off.
const LAYER := 8

@onready var sprite: Sprite2D = $KnightSprite
## Stone chips kicked up behind a moving rock: the floor being carved.
var carving: CPUParticles2D
@onready var camera: Camera2D = $Camera2D
var animation_time := 0.0
var was_moving := false
var rock := false
var knockback := Vector2.ZERO
var invulnerable := 0.0
## The last direction moved in; the sword swings this way.
var aim := Vector2.RIGHT
## The potion's speed boost: a multiplier and how long it lasts.
var speed_boost := 1.0
var boost_left := 0.0

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("knight")
	carving = make_carving()
	add_child(carving)
	# Drawn first, so the chips spray out from under the rock.
	move_child(carving, 0)

func make_carving() -> CPUParticles2D:
	var chips := CPUParticles2D.new()
	chips.name = "Carving"
	chips.position = Vector2(0, -2)
	chips.emitting = false
	chips.local_coords = false
	chips.amount = 28
	chips.lifetime = 0.5
	chips.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	chips.emission_rect_extents = Vector2(6, 2)
	chips.spread = 55.0
	chips.gravity = Vector2(0, 60)
	chips.initial_velocity_min = 20.0
	chips.initial_velocity_max = 55.0
	chips.damping_min = 40.0
	chips.damping_max = 80.0
	chips.scale_amount_min = 1.0
	chips.scale_amount_max = 2.5
	var stone := Gradient.new()
	stone.colors = PackedColorArray([Color(0.62, 0.56, 0.74), Color(0.86, 0.8, 0.95)])
	chips.color_initial_ramp = stone
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	chips.color_ramp = fade
	return chips

func _physics_process(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var running := Input.is_action_pressed("sprint")
	velocity = direction * (RUN_SPEED if running else WALK_SPEED) * speed_boost + knockback
	if direction != Vector2.ZERO:
		aim = direction.normalized()
	knockback = knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	move_and_slide()
	if invulnerable > 0.0:
		invulnerable -= delta
		sprite.modulate.a = 0.35 if fmod(invulnerable, 0.16) < 0.07 else 1.0
	else:
		sprite.modulate.a = 1.0
	if boost_left > 0.0:
		boost_left -= delta
		# A cool shimmer while the potion lasts.
		var shimmer := 0.5 + 0.5 * sin(boost_left * 12.0)
		sprite.self_modulate = Color(1.0, 1.0, 1.0).lerp(Color(0.7, 1.15, 1.35), shimmer)
		if boost_left <= 0.0:
			speed_boost = 1.0
			sprite.self_modulate = Color.WHITE
	# Actual motion makes the knight idle when pushing directly into a wall.
	var moving := get_position_delta().length_squared() > 0.001
	if direction.x != 0.0:
		face(direction.x < 0.0)
	if moving != was_moving:
		animation_time = 0.0
		sprite.texture = sheet(moving)
		was_moving = moving
	animation_time += delta * ((12.0 if running else 8.0) if moving else 3.0)
	# Chips fly back from the direction of travel while a rock moves.
	carving.emitting = rock and moving and is_physics_processing()
	if carving.emitting:
		carving.direction = -velocity.normalized() if velocity != Vector2.ZERO else Vector2.UP
		carving.speed_scale = 1.4 if running else 1.0
	# A rock sits still until it moves; the knight breathes while idle.
	sprite.frame = 0 if rock and not moving else int(animation_time) % 4

func _process(_delta: float) -> void:
	# Cutscenes and doors pause movement; no chips while frozen.
	if not is_physics_processing() and carving.emitting:
		carving.emitting = false

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

func boost(seconds: float, factor: float) -> void:
	speed_boost = factor
	boost_left = seconds

## Ends a potion's speed boost early, e.g. when the floor starts over.
func end_boost() -> void:
	speed_boost = 1.0
	boost_left = 0.0
	sprite.self_modulate = Color.WHITE

func hurt(from: Vector2) -> void:
	knockback = from.direction_to(position) * KNOCKBACK
	invulnerable = INVULNERABLE_TIME

func hurt_rect() -> Rect2:
	return Rect2(position + HURT_RECT.position, HURT_RECT.size)

func is_invulnerable() -> bool:
	return invulnerable > 0.0

## `keep_safety` keeps the blinking safe time after a hit (R mid-blink must
## not end it early).
func reset_to(spawn: Vector2, face_left := false, keep_safety := false) -> void:
	position = spawn
	velocity = Vector2.ZERO
	knockback = Vector2.ZERO
	if not keep_safety:
		invulnerable = 0.0
		sprite.modulate.a = 1.0
	if carving:
		carving.emitting = false
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
