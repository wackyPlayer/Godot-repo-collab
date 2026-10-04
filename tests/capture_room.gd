extends SceneTree
## Render with Godot's real graphics backend to verify the delivered room.

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var room: Node2D = load("res://scenes/room.tscn").instantiate()
	root.add_child(room)
	root.size = Vector2i(768, 512)
	for frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://artifacts/room_preview.png")
	print("Room preview saved: ", result == OK)
	room.queue_free()
	await process_frame
	quit(result)
