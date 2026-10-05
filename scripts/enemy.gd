extends CharacterBody2D
## A dungeon enemy. It shuffles around where it spawned and chases the player
## on sight; touching it costs a heart. The slime and skeleton scenes share
## this script with their own speeds and sheets. On floor 4 room.gd enrages
## every enemy: player-running speed, longer sight and red eyes.

signal touched(from: Vector2)

@export var wander_speed := 26.0
@export var chase_speed := 58.0
@export var sight := 150.0
@export var frames_per_second := 6.0
## The sheet's figure sits this far right of the frame centre.
@export var sprite_shift := 0.0
## The same sheet with red eyes, used when enraged.
@export var red_eyes: Texture2D

const LEASH := 96.0
## A beat after a room appears before enemies move, so nothing can hit the
## player in the same instant they walk through a door.
const WAKE_TIME := 0.6

var target: Node2D
var home := Vector2.ZERO
var wander := Vector2.ZERO
var wander_left := 0.0
var time := randf() * 4.0
var asleep := WAKE_TIME
## Set before the enemy enters the tree.
var enraged := false

@onready var sprite: Sprite2D = $Sprite
@onready var hitbox: Area2D = $Hitbox

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	home = position
	if enraged and red_eyes:
		sprite.texture = red_eyes
	face(false)

func enrage(speed: float, new_sight: float) -> void:
	enraged = true
	chase_speed = speed
	wander_speed = speed * 0.35
	sight = new_sight

func _physics_process(delta: float) -> void:
	time += delta
	sprite.frame = int(time * frames_per_second) % sprite.vframes
	if asleep > 0.0:
		asleep -= delta
		return
	if is_instance_valid(target) and position.distance_to(target.position) < sight:
		velocity = position.direction_to(target.position) * chase_speed
	else:
		wander_left -= delta
		if wander_left <= 0.0:
			wander_left = randf_range(1.0, 2.5)
			wander = Vector2.from_angle(randf() * TAU) * wander_speed if randf() < 0.7 else Vector2.ZERO
			if position.distance_to(home) > LEASH:
				wander = position.direction_to(home) * wander_speed
		velocity = wander
	if absf(velocity.x) > 1.0:
		face(velocity.x < 0.0)
	move_and_slide()
	for body in hitbox.get_overlapping_bodies():
		if body == target:
			touched.emit(position)

func face(left: bool) -> void:
	sprite.flip_h = left
	sprite.position.x = sprite_shift if left else -sprite_shift
