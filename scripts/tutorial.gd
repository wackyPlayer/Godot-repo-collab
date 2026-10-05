@tool
extends "res://scripts/room.gd"
## Prologue: teaches walking and running, then the mage at the far end of the
## antechamber turns the knight to stone. The sealed north door opens and leads
## into the dungeon (scenes/room.tscn), which is played in rock form.

const MAGE_IDLE: Texture2D = preload("res://assets/mage_idle.png")
const MAGE_CAST: Texture2D = preload("res://assets/mage_cast.png")
const DUNGEON := "res://scenes/room.tscn"
const CAST_FRAMES := 9
## Frame of the cast sheet where the spark leaves the staff.
const RELEASE_FRAME := 5
## Spark position relative to the mage's feet, for the unflipped art.
const STAFF_TIP := Vector2(5, -25)
const NOTICE_RANGE := 96.0
const LESSON_DISTANCE := 96.0
enum Step { WALK, RUN, APPROACH, CURSE, ESCAPE }

var step := Step.WALK
var walked := 0.0
var ran := 0.0
var last_position := Vector2.ZERO
var mage_time := 0.0
var casting := false
## Set once the knight walks out through the north door.
var left := false
var prompt: Label
var speech: Label

@onready var mage: StaticBody2D = $Mage
@onready var mage_sprite: Sprite2D = $Mage/Sprite

func begin() -> void:
	var hall := Generator.Room.new()
	hall.kind = "tutorial"
	hall.layout = "Antechamber"
	hall.tiled_floor = true
	hall.blocks.assign([Vector2i(2, 2), Vector2i(17, 2), Vector2i(2, Generator.ROWS - 3), Vector2i(17, Generator.ROWS - 3)])
	hall.ornaments.assign([Vector2i(6, 0), Vector2i(13, 0)])
	rooms = {Vector2i.ZERO: hall}
	var hud: CanvasLayer = $HUD
	prompt = make_label(hud, "", Vector2(0, 372), 15, Color("e1d6fb"))
	speech = make_label(hud, "", mage.position + Vector2(-160, -58), 12, Color("f0e5ff"))
	for label in [prompt, speech]:
		label.size = Vector2(768 if label == prompt else 320, 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_color_override("font_outline_color", Color("07050f"))
	minimap.visible = false
	item_slots.values()[0].get_parent().visible = false
	enter_room(Vector2i.ZERO, -1)
	knight.call("set_rock", false)
	last_position = knight.position

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(mage):
		return
	# Dialogue lives in the HUD, so project the mage through the moving camera.
	speech.position = mage.get_global_transform_with_canvas().origin + Vector2(-160, -58)
	if not casting:
		mage_time += delta * 2.0
		mage_sprite.frame = int(mage_time) % 2
		# The art faces left; turn to watch the knight.
		mage_sprite.flip_h = knight.position.x > mage.position.x + 4.0
	if step >= Step.CURSE:
		return
	var moved := knight.position.distance_to(last_position)
	last_position = knight.position
	if step == Step.WALK:
		walked += moved
		if walked > LESSON_DISTANCE:
			advance(Step.RUN)
	elif step == Step.RUN and Input.is_action_pressed("sprint"):
		ran += moved
		if ran > LESSON_DISTANCE:
			advance(Step.APPROACH)
	if knight.position.distance_to(mage.position) < NOTICE_RANGE:
		curse()

func advance(next: Step) -> void:
	step = next
	update_hud()

## The mage's scene: a few words, the spell, and a rock where a knight stood.
func curse() -> void:
	advance(Step.CURSE)
	transitioning = true
	knight.set_physics_process(false)
	knight.velocity = Vector2.ZERO
	knight.call("face", knight.position.x > mage.position.x)
	await say("Another knight, sneaking into my keep?", 1.8)
	await say("Then stand guard here... forever.", 1.5)
	speech.text = ""
	casting = true
	mage_sprite.texture = MAGE_CAST
	mage_sprite.vframes = CAST_FRAMES
	var bolt: Tween
	for frame in range(CAST_FRAMES):
		mage_sprite.frame = frame
		if frame == RELEASE_FRAME:
			bolt = launch_bolt()
		await wait(0.1)
	if bolt.is_running():
		await bolt.finished
	await petrify()
	mage_sprite.texture = MAGE_IDLE
	mage_sprite.vframes = 2
	casting = false
	await say("Good luck finding the way out like that.", 2.0)
	speech.text = ""
	await vanish()
	open_north_door()
	advance(Step.ESCAPE)
	knight.set_physics_process(true)
	transitioning = false

func say(line: String, seconds: float) -> void:
	speech.text = line
	await wait(seconds)

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func launch_bolt() -> Tween:
	var spark := Polygon2D.new()
	spark.polygon = PackedVector2Array([Vector2(0, -5), Vector2(2, -1), Vector2(6, 0), Vector2(2, 1), Vector2(0, 5), Vector2(-2, 1), Vector2(-6, 0), Vector2(-2, -1)])
	spark.color = Color("f0e5ff")
	spark.z_index = 2
	var tip := STAFF_TIP * Vector2(-1 if mage_sprite.flip_h else 1, 1)
	spark.position = mage.position + tip
	add_child(spark)
	var flight := spark.create_tween()
	flight.set_parallel()
	flight.tween_property(spark, "position", knight.position + Vector2(0, -14), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	flight.tween_property(spark, "rotation", TAU, 0.35)
	flight.chain().tween_callback(spark.queue_free)
	return flight

func petrify() -> void:
	var sprite: Sprite2D = knight.get_node("KnightSprite")
	var flash := knight.create_tween()
	flash.tween_property(knight, "modulate", Color(2.6, 2.4, 3.2), 0.08)
	await flash.finished
	knight.call("set_rock", true)
	burst(knight.position + Vector2(0, -10), Color("8f86a8"), 10)
	# Offsets are in texture pixels: the sprite is drawn at a quarter scale.
	var shake := knight.create_tween()
	for push in [10.0, -10.0, 7.0, -7.0, 3.0, 0.0]:
		shake.tween_property(sprite, "offset:x", push, 0.04)
	shake.parallel().tween_property(knight, "modulate", Color.WHITE, 0.4)
	await shake.finished
	await wait(0.6)

func vanish() -> void:
	burst(mage.position + Vector2(0, -14), Color("c5b2ff"), 12)
	var fade_out := mage.create_tween()
	fade_out.set_parallel()
	fade_out.tween_property(mage, "modulate:a", 0.0, 0.35)
	fade_out.tween_property(mage_sprite, "scale", Vector2(0.4, 1.6), 0.35)
	await fade_out.finished
	mage.queue_free()

## Little squares that fly out and fade, for dust and magic.
func burst(at: Vector2, color: Color, count: int) -> void:
	for index in range(count):
		var bit := ColorRect.new()
		bit.size = Vector2(2, 2)
		bit.color = color
		bit.position = at
		bit.z_index = 2
		add_child(bit)
		var angle := TAU * index / count
		var fly := bit.create_tween()
		fly.set_parallel()
		fly.tween_property(bit, "position", at + Vector2.from_angle(angle) * randf_range(10, 22), 0.45).set_ease(Tween.EASE_OUT)
		fly.tween_property(bit, "modulate:a", 0.0, 0.45)
		fly.chain().tween_callback(bit.queue_free)

func open_north_door() -> void:
	current.doors[Generator.NORTH] = true
	rebuild()
	queue_redraw()
	front_walls.queue_redraw()

func travel(_direction: int) -> void:
	knight.set_physics_process(false)
	await fade_to(1.0)
	left = true
	get_tree().change_scene_to_file(DUNGEON)

func update_hud() -> void:
	status_label.text = "PROLOGUE  /  THE ANTECHAMBER"
	progress_label.text = "CABALLERITO ENTERS THE VIOLET KEEP"
	caption_label.text = ""
	match step:
		Step.WALK:
			prompt.text = "Use WASD or the arrow keys to walk."
		Step.RUN:
			prompt.text = "Hold SHIFT while walking to run."
		Step.APPROACH:
			prompt.text = "Someone waits at the far end of the hall. Go and see."
		Step.CURSE:
			prompt.text = ""
		Step.ESCAPE:
			prompt.text = "You've been turned to stone! The north door is open."
			caption_label.text = "Find your way down through the keep and break the curse."

func _draw() -> void:
	super()
	# A runner leads from the entrance up to where the mage waits.
	var runner_height := INNER_END.y - 168
	draw_rect(Rect2(368, 168, 32, runner_height), Color("241536"))
	draw_rect(Rect2(368, 168, 2, runner_height), Color("6f459b"))
	draw_rect(Rect2(398, 168, 2, runner_height), Color("6f459b"))
	draw_rect(Rect2(360, 140, 48, 28), Color("241536"))
	draw_rect(Rect2(360, 140, 48, 28), Color("6f459b"), false, 2.0)
