extends SceneTree
## Renders one room of each kind with the real graphics backend.

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var room: Node2D = load("res://scenes/room.tscn").instantiate()
	room.dungeon_seed = 1234
	room.fade_time = 0.0
	root.add_child(room)
	root.size = Vector2i(768, 512)
	await process_frame
	var shots := {"start": Vector2i.ZERO}
	for cell: Vector2i in room.rooms:
		var kind: String = room.rooms[cell].kind
		if not shots.has(kind) or (kind == "normal" and room.rooms[cell].blocks.size() > 8):
			shots[kind] = cell
	var result := OK
	for kind: String in shots:
		room.enter_room(shots[kind], -1)
		for frame in range(6):
			await process_frame
		await RenderingServer.frame_post_draw
		result = root.get_texture().get_image().save_png("res://artifacts/room_%s.png" % kind)
		print("Saved %s room: %s" % [kind, result == OK])
	room.queue_free()
	await process_frame
	quit(result)
