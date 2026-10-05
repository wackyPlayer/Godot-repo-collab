extends SceneTree
## Checks rendered sprite visibility in open doors and continuous corner trim.
## Run with a graphics backend; append -- --before to capture the original bug.

const Generator := preload("res://scripts/dungeon_generator.gd")
const NAMES := ["north", "east", "south", "west"]
var failures := 0

func _initialize() -> void:
	# Default keys, whatever the player has rebound.
	root.get_node("Settings").use_defaults()
	call_deferred("capture")

func capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/door_fix"))
	var room: Node2D = load("res://scenes/room.tscn").instantiate()
	room.dungeon_seed = 1234
	room.fade_time = 0.0
	root.add_child(room)
	root.size = Vector2i(768, 512)
	room.transitioning = true
	room.current.doors.fill(true)
	room.rebuild()
	room.queue_redraw()
	room.front_walls.queue_redraw()
	var knight: CharacterBody2D = room.get_node("Knight")
	knight.set_physics_process(false)
	var sprite: Sprite2D = knight.get_node("KnightSprite")
	var positions := [
		Vector2(room.CENTER.x, room.INTERIOR.y - 4),
		Vector2(room.INNER_END.x + 15, room.CENTER.y + 2),
		Vector2(room.CENTER.x, room.INNER_END.y + 14),
		Vector2(room.INTERIOR.x - 15, room.CENTER.y + 2),
	]
	var phase := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	for rock in [false, true]:
		knight.call("set_rock", rock)
		for direction in range(4):
			knight.call("reset_to", positions[direction], direction == Generator.WEST)
			var form := "rock" if rock else "knight"
			await check_sprite(knight, sprite, "%s visible in %s door" % [form, NAMES[direction]], "%s_%s_%s" % [phase, form, NAMES[direction]])
		# Feet can enter right below the upper jamb. Every animation frame
		# must remain visible there, even with its head above the opening.
		for direction in [Generator.EAST, Generator.WEST]:
			var gap: Rect2 = room.DOOR_GAPS[direction]
			for edge in ["upper", "lower"]:
				var at: Vector2 = positions[direction]
				at.y = gap.position.y + 6.25 if edge == "upper" else gap.end.y - 0.25
				knight.call("reset_to", at, direction == Generator.WEST)
				for frame in range(4):
					sprite.frame = frame
					var caption := "%s %s door %s edge frame %d" % ["rock" if rock else "knight", NAMES[direction], edge, frame]
					await check_sprite(knight, sprite, caption, "%s_%s_%s_%s_%d" % [phase, "rock" if rock else "knight", NAMES[direction], edge, frame])
			# Above the doorway the same tile is still a solid wall, and must
			# cover sprites behind it rather than drawing every wall behind us.
			var behind: Vector2 = positions[direction]
			behind.y = gap.position.y - 8
			knight.call("reset_to", behind, direction == Generator.WEST)
			await check_sprite(knight, sprite, "Solid %s wall still occludes %s above its door" % [NAMES[direction], "rock" if rock else "knight"], "", false)
	knight.call("set_rock", false)
	knight.call("reset_to", room.START_SPAWN)
	# A full-size canvas captures the entire tall room for corner inspection.
	# Gameplay above uses the player's Camera2D at 1x throughout.
	knight.get_node("Camera2D").enabled = false
	room.get_node("HUD").visible = false
	root.content_scale_size = Vector2i(768, int(room.ROOM_END.y) + 64)
	root.size = root.content_scale_size
	root.canvas_transform = Transform2D.IDENTITY
	var overview := await rendered_image()
	overview.save_png("res://artifacts/door_fix/%s_room.png" % phase)
	# The inner trim must turn continuously at the four room corners.
	for corner in [Vector2i(61, 93), Vector2i(704, 93), Vector2i(61, int(room.INNER_END.y)), Vector2i(704, int(room.INNER_END.y))]:
		var continuous := true
		for y in range(3):
			for x in range(3):
				var color := overview.get_pixelv(corner + Vector2i(x, y))
				continuous = continuous and color.is_equal_approx(Color("766187"))
		check(continuous, "Continuous inner corner at %s" % corner)
	# No trim should continue past the corner through the north wall face.
	for pixel in [Vector2i(62, 80), Vector2i(705, 80)]:
		check(not overview.get_pixelv(pixel).is_equal_approx(Color("766187")), "Corner trim follows the floor opening at %s" % pixel)
	# Texture pixels at the bottom of a top corner must match the next side
	# tile. The north wall's base shadow must not cut across a vertical wall.
	for corner in [Vector2i(room.ORIGIN), Vector2i(room.INNER_END.x, room.ORIGIN.y)]:
		var continuous := true
		for offset in [Vector2i(8, 24), Vector2i(16, 24), Vector2i(24, 24), Vector2i(8, 31), Vector2i(16, 31), Vector2i(24, 31)]:
			continuous = continuous and overview.get_pixelv(corner + offset) == overview.get_pixelv(corner + offset + Vector2i(0, room.TILE))
		check(continuous, "Side-wall texture and shading continue through the top corner at %s" % corner)
	room.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: Door visibility and all four rendered corners.")
	quit(0 if failures == 0 else 1)

func rendered_image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func check_sprite(knight: CharacterBody2D, sprite: Sprite2D, caption: String, filename: String, fully_visible := true) -> void:
	knight.visible = false
	var background := await rendered_image()
	knight.visible = true
	var foreground := await rendered_image()
	var source := sprite.texture.get_image()
	var top_left := Vector2i(sprite.get_global_transform_with_canvas().origin - Vector2(16, 16))
	var opaque := 0
	var visible := 0
	for y in range(32):
		for x in range(32):
			var source_x := 127 - (x * 4 + 2) if sprite.flip_h else x * 4 + 2
			if source.get_pixel(source_x, sprite.frame * 128 + y * 4 + 2).a < 0.99:
				continue
			opaque += 1
			var pixel := top_left + Vector2i(x, y)
			if foreground.get_pixelv(pixel) != background.get_pixelv(pixel):
				visible += 1
	check(visible == opaque if fully_visible else visible < opaque, "%s: %d/%d sprite pixels" % [caption, visible, opaque])
	if not filename.is_empty():
		foreground.save_png("res://artifacts/door_fix/%s.png" % filename)

func check(condition: bool, caption: String) -> void:
	if condition:
		print("PASS: ", caption)
	else:
		failures += 1
		push_error("FAIL: " + caption)
