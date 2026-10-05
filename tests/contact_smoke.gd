extends SceneTree
## Enemy contact damage: an enemy that reaches the player hurts them from
## every side, and one that is merely nearby does not.

const SEED := 1234
const SIDES := {"north": Vector2(0, -60), "south": Vector2(0, 60), "east": Vector2(60, 0), "west": Vector2(-60, 0)}

var failures := 0
var room: Node2D
var knight: CharacterBody2D

func _initialize() -> void:
	root.get_node("Settings").use_defaults()
	call_deferred("run_checks")

func run_checks() -> void:
	Engine.time_scale = 4.0
	room = load("res://scenes/room.tscn").instantiate()
	room.dungeon_seed = SEED
	room.fade_time = 0.0
	room.enemies = false
	root.add_child(room)
	knight = room.get_node("Knight")
	await ticks(3)
	for kind in ["slime", "skeleton"]:
		for side: String in SIDES:
			var hurt := await approach(kind, SIDES[side])
			check(hurt, "A %s chasing in from the %s hurts the player" % [kind, side])
		var stacked := await approach(kind, Vector2.ZERO)
		check(stacked, "A %s right on top of the player hurts them" % kind)
	# Fairness: close, but not touching, is safe.
	for kind in ["slime", "skeleton"]:
		for offset in [Vector2(30, 0), Vector2(-30, 0), Vector2(0, -26), Vector2(0, 30)]:
			var hurt := await approach(kind, offset, true)
			check(not hurt, "A %s standing %s away (not touching) does no harm" % [kind, offset])
	room.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: All contact checks.")
	quit(0 if failures == 0 else 1)

## Places a still player and one enemy; returns whether a heart was lost.
## A frozen enemy stays exactly where it was put.
func approach(kind: String, offset: Vector2, frozen := false) -> bool:
	room.restore_health()
	knight.call("reset_to", room.CENTER)
	knight.velocity = Vector2.ZERO
	var enemy: Node = room.spawn_enemy(kind, room.CENTER + offset)
	enemy.asleep = 0.0
	if frozen:
		enemy.chase_speed = 0.0
		enemy.wander_speed = 0.0
	var hurt := false
	for attempt in range(45):
		await ticks(1)
		knight.position = room.CENTER
		if room.health < room.MAX_HEALTH:
			hurt = true
			break
	enemy.queue_free()
	await ticks(1)
	return hurt

func ticks(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
