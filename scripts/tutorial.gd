@tool
extends "res://scripts/room.gd"
## Floor 1, the round chamber: teaches walking and running, then the mage
## turns the knight to stone. The sealed north door opens and leads into the
## generated floors (scenes/room.tscn), which are played in rock form.

const MAGE_IDLE: Texture2D = preload("res://assets/mage_idle.png")
const MAGE_CAST: Texture2D = preload("res://assets/mage_cast.png")
const DUNGEON := "res://scenes/room.tscn"
const CAST_FRAMES := 9
## Frame of the cast sheet where the spark leaves the staff.
const RELEASE_FRAME := 5
## Spark position relative to the mage's feet, for the unflipped art at 1x.
## The mage is drawn at 3x (its Sprite scale), so offsets are scaled by that.
const STAFF_TIP := Vector2(5, -25)
const MAGE_HEIGHT := 28.0
const NOTICE_RANGE := 120.0
const LESSON_DISTANCE := 96.0
## The chamber is a ring of brick around a round floor.
const RING_INNER := 304.0
const RING_OUTER := 336.0
const RING_MID := (RING_INNER + RING_OUTER) / 2.0
const NORTH_ANGLE := -PI / 2.0
## Half the door's width, and the angle it opens in the ring.
const DOOR_HALF := 32.0
const DOOR_ANGLE := asin(DOOR_HALF / RING_INNER)
const PASSAGE := Rect2(CENTER.x - DOOR_HALF, CENTER.y - RING_OUTER, DOOR_HALF * 2, RING_OUTER - RING_INNER + 2)
const ROUND_TRIGGER := Rect2(CENTER.x - DOOR_HALF, CENTER.y - RING_OUTER, DOOR_HALF * 2, 14)
const ROUND_STOP := Rect2(CENTER.x - DOOR_HALF, CENTER.y - RING_OUTER - 16, DOOR_HALF * 2, 16)
const SPAWN := Vector2(CENTER.x, CENTER.y + RING_INNER - 52)
## Far enough below the wall for the tall mage to stand clear of it.
const MAGE_POS := Vector2(CENTER.x, CENTER.y - RING_INNER + 100)
const TORCH_ANGLES: Array[float] = [-150.0, -120.0, -60.0, -30.0]
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
	hall.layout = "The Round Chamber"
	hall.tiled_floor = true
	hall.blocks.assign([Vector2i(4, 7), Vector2i(15, 7), Vector2i(4, 14), Vector2i(15, 14)])
	rooms = {Vector2i.ZERO: hall}
	floor_number = 1
	mage.position = MAGE_POS
	var hud: CanvasLayer = $HUD
	prompt = make_label(hud, "", Vector2(0, 372), 15, Color("e1d6fb"))
	speech = make_label(hud, "", Vector2.ZERO, 12, Color("f0e5ff"))
	for label in [prompt, speech]:
		label.size = Vector2(768 if label == prompt else 320, 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_color_override("font_outline_color", Color("07050f"))
	minimap.visible = false
	item_slots.values()[0].get_parent().visible = false
	play_music("keep")
	enter_room(Vector2i.ZERO, -1)
	entry_point = SPAWN
	knight.call("set_rock", false)
	knight.call("reset_to", SPAWN)
	last_position = knight.position

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(mage):
		return
	# Dialogue lives in the HUD, so project the mage through the moving camera.
	speech.position = mage.get_global_transform_with_canvas().origin + Vector2(-160, -MAGE_HEIGHT * mage_sprite.scale.y - 26)
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
			advance(Step.RUN if can_run() else Step.APPROACH)
	elif step == Step.RUN and Input.is_action_pressed("sprint"):
		ran += moved
		if ran > LESSON_DISTANCE:
			advance(Step.APPROACH)
	if knight.position.distance_to(mage.position) < NOTICE_RANGE:
		curse()

func advance(next: Step) -> void:
	step = next
	update_hud()

## False when playing by headset and no signal is set to run, so the running
## lesson can't be done (the Unicorn detector sends blink, shake and nod).
func can_run() -> bool:
	var settings := get_node_or_null("/root/Settings")
	return not (settings and settings.brain_enabled) or brain_signal_for("run") != ""

func refresh_controls_hint() -> void:
	super()
	if step == Step.RUN and not can_run():
		advance(Step.APPROACH)
	elif prompt:
		update_hud()

## The mage's scene: a few words, the spell, and a rock where a knight stood.
func curse() -> void:
	advance(Step.CURSE)
	transitioning = true
	knight.set_physics_process(false)
	knight.velocity = Vector2.ZERO
	knight.call("face", knight.position.x > mage.position.x)
	# The mage is tall: frame the shot between the two of them.
	await pan_camera((mage.position - knight.position) / 2.0 + Vector2(0, -30))
	await say("Another knight, sneaking into my tower?", 1.8)
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
	await say("Come find me four floors down, if you can. Good luck, little rock.", 2.4)
	speech.text = ""
	await vanish()
	open_north_door()
	await pan_camera(Vector2.ZERO)
	advance(Step.ESCAPE)
	knight.set_physics_process(true)
	transitioning = false

func say(line: String, seconds: float) -> void:
	speech.text = line
	await wait(seconds)

func launch_bolt() -> Tween:
	var spark := Polygon2D.new()
	spark.polygon = PackedVector2Array([Vector2(0, -5), Vector2(2, -1), Vector2(6, 0), Vector2(2, 1), Vector2(0, 5), Vector2(-2, 1), Vector2(-6, 0), Vector2(-2, -1)])
	spark.color = Color("f0e5ff")
	spark.z_index = 2
	var tip := STAFF_TIP * mage_sprite.scale * Vector2(-1 if mage_sprite.flip_h else 1, 1)
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
	refresh_hearts()
	burst(knight.position + Vector2(0, -10), Color("8f86a8"), 10)
	# Offsets are in texture pixels: the sprite is drawn at a quarter scale.
	var shake := knight.create_tween()
	for push in [10.0, -10.0, 7.0, -7.0, 3.0, 0.0]:
		shake.tween_property(sprite, "offset:x", push, 0.04)
	shake.parallel().tween_property(knight, "modulate", Color.WHITE, 0.4)
	await shake.finished
	await wait(0.6)

func vanish() -> void:
	burst(mage.position + Vector2(0, -14 * mage_sprite.scale.y), Color("c5b2ff"), 18)
	var fade_out := mage.create_tween()
	fade_out.set_parallel()
	fade_out.tween_property(mage, "modulate:a", 0.0, 0.35)
	fade_out.tween_property(mage_sprite, "scale", mage_sprite.scale * Vector2(0.4, 1.6), 0.35)
	await fade_out.finished
	mage.queue_free()

func open_north_door() -> void:
	current.doors[Generator.NORTH] = true
	rebuild()
	queue_redraw()
	front_walls.queue_redraw()

# --- The round chamber --------------------------------------------------------

## The wall is one ring of segments, left open where the door stands.
func build_walls() -> void:
	var body := StaticBody2D.new()
	var shape := ConcavePolygonShape2D.new()
	var outline := arc_points(RING_INNER, NORTH_ANGLE + door_gap(), NORTH_ANGLE + TAU - door_gap())
	var segments := PackedVector2Array()
	for index in range(outline.size() - 1):
		segments.append_array([outline[index], outline[index + 1]])
	if has_door(Generator.NORTH):
		for x in [PASSAGE.position.x, PASSAGE.end.x]:
			segments.append_array([Vector2(x, ROUND_STOP.position.y), Vector2(x, PASSAGE.end.y)])
	shape.segments = segments
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	boundaries.add_child(body)
	if has_door(Generator.NORTH):
		make_wall(ROUND_STOP)
		make_area(ROUND_TRIGGER, boundaries).body_entered.connect(_on_round_door_entered)

func place_torches() -> void:
	for degrees in TORCH_ANGLES:
		make_torch(CENTER + Vector2.from_angle(deg_to_rad(degrees)) * (RING_INNER + 4))

func door_gap() -> float:
	return DOOR_ANGLE if has_door(Generator.NORTH) else 0.0

static func arc_points(radius: float, from: float, to: float) -> PackedVector2Array:
	var steps := maxi(2, ceili((to - from) * radius / 12.0))
	var points := PackedVector2Array()
	for index in range(steps + 1):
		points.append(CENTER + Vector2.from_angle(lerpf(from, to, float(index) / steps)) * radius)
	return points

func _on_round_door_entered(body: Node2D) -> void:
	if body == knight and has_door(Generator.NORTH) and PASSAGE.grow(8).has_point(knight.position) and not transitioning:
		transitioning = true
		travel.call_deferred(Generator.NORTH)

func travel(_direction: int) -> void:
	knight.set_physics_process(false)
	await fade_to(1.0)
	left = true
	get_tree().change_scene_to_file(DUNGEON)

func update_hud() -> void:
	status_label.text = "FLOOR 1 OF %d  /  THE ROUND CHAMBER" % FINAL_FLOOR
	progress_label.text = "CABALLERITO ENTERS THE ROCKY TOWER"
	caption_label.text = ""
	match step:
		Step.WALK:
			if brain_signal_for("go") != "":
				prompt.text = "%s to start or stop walking." % brain_signal_for("go")
				if brain_signal_for("turn") != "":
					prompt.text += " %s to turn." % brain_signal_for("turn")
			else:
				prompt.text = "Use %s to walk." % move_keys_text()
		Step.RUN:
			if brain_signal_for("run") != "":
				prompt.text = "%s to start running." % brain_signal_for("run")
			else:
				prompt.text = "Hold %s while walking to run." % key_hint("sprint", "Shift")
		Step.APPROACH:
			prompt.text = "Someone waits at the far end of the chamber. Go and see."
		Step.CURSE:
			prompt.text = ""
		Step.ESCAPE:
			prompt.text = "You've been turned to stone! The north door is open."
			caption_label.text = "Four floors lie below. Find the mage and make them undo this."

func _draw() -> void:
	draw_rect(Rect2(ORIGIN, ROOM_SIZE), Color("05040b"))
	for row in range(1, ROWS - 1):
		for column in range(1, COLUMNS - 1):
			var rect := Rect2(ORIGIN + Vector2(column, row) * TILE, Vector2(TILE, TILE))
			# The ring covers the ragged tile edge, so only nearby tiles draw.
			if rect.get_center().distance_to(CENTER) > RING_INNER + 14:
				continue
			var brightness := 1.05 + float((column * 7 + row * 3) % 5) * 0.025
			draw_texture_rect(FLOOR_TILES, rect, false, Color(brightness, brightness, brightness * 1.13))
			draw_rect(rect, Color(0.18, 0.14, 0.3, 0.15), false, 1.0)
	draw_arc(CENTER, RING_INNER - 5, 0, TAU, 128, Color(0, 0, 0.03, 0.3), 10.0)
	# A runner leads from the entrance up to the dais where the mage waits.
	var dais := Rect2(MAGE_POS.x - 44, MAGE_POS.y - 26, 88, 44)
	var runner := Rect2(CENTER.x - 16, dais.end.y, 32, SPAWN.y - dais.end.y + 24)
	draw_rect(runner, Color("241536"))
	draw_rect(Rect2(runner.position, Vector2(2, runner.size.y)), Color("6f459b"))
	draw_rect(Rect2(runner.end.x - 2, runner.position.y, 2, runner.size.y), Color("6f459b"))
	draw_rect(dais, Color("241536"))
	draw_rect(dais, Color("6f459b"), false, 2.0)
	draw_ring(self, PI, TAU)
	if has_door(Generator.NORTH):
		for x in [PASSAGE.position.x, CENTER.x]:
			draw_doorway(Rect2(x, PASSAGE.position.y, TILE, TILE), Generator.NORTH)
		draw_rect(Rect2(PASSAGE.position.x, PASSAGE.end.y - 4, PASSAGE.size.x, 3), Color("8870b1"))
	else:
		draw_sealed_door()
	draw_door_posts()

func draw_front_walls() -> void:
	draw_ring(front_walls, 0, PI)

## Draws the brick ring between two angles, one brick tile per quad so the
## texture keeps its scale, with trim on both edges and a dark rim outside.
func draw_ring(canvas: CanvasItem, from: float, to: float) -> void:
	var spans: Array[Vector2] = [Vector2(from, to)]
	var gap := door_gap()
	if gap > 0.0 and from <= NORTH_ANGLE + TAU and to >= NORTH_ANGLE + TAU:
		var door := NORTH_ANGLE + TAU
		spans = [Vector2(from, door - gap), Vector2(door + gap, to)]
	var tint := Color(1.25, 1.1, 1.4)
	for span in spans:
		var quads := maxi(1, ceili((span.y - span.x) * RING_MID / TILE))
		for index in range(quads):
			var a := lerpf(span.x, span.y, float(index) / quads)
			var b := lerpf(span.x, span.y, float(index + 1) / quads)
			var points := PackedVector2Array([
				CENTER + Vector2.from_angle(a) * RING_INNER, CENTER + Vector2.from_angle(b) * RING_INNER,
				CENTER + Vector2.from_angle(b) * RING_OUTER, CENTER + Vector2.from_angle(a) * RING_OUTER])
			var uvs := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
			canvas.draw_polygon(points, PackedColorArray([tint, tint, tint, tint]), uvs, WALL)
		var steps := maxi(4, ceili((span.y - span.x) * 24))
		canvas.draw_arc(CENTER, RING_INNER + 1.5, span.x, span.y, steps, Color("766187"), 3.0)
		canvas.draw_arc(CENTER, RING_OUTER - 1.0, span.x, span.y, steps, Color("766187"), 2.0)
	canvas.draw_arc(CENTER, RING_OUTER + 6.0, from, to, maxi(4, ceili((to - from) * 24)), Color("05040b"), 12.0)

func draw_sealed_door() -> void:
	var door := Rect2(PASSAGE.position, Vector2(PASSAGE.size.x, PASSAGE.size.y - 2))
	draw_rect(door, Color("2a1d40"))
	for x in [door.position.x + 21, door.position.x + 42]:
		draw_rect(Rect2(x, door.position.y + 2, 1, door.size.y - 4), Color("140d22"))
	draw_rect(door, Color("6f459b"), false, 2.0)
	draw_circle(door.get_center(), 4, ACCENT)

func draw_door_posts() -> void:
	var post := Color("8f7bb0")
	for x in [PASSAGE.position.x - 4, PASSAGE.end.x]:
		draw_rect(Rect2(x, PASSAGE.position.y - 2, 4, PASSAGE.size.y + 2), post)
