@tool
extends StaticBody2D
## Block faces reuse the supplied non-humanoid stone sprite.

const STONE: Texture2D = preload("res://assets/stone.png")

func _draw() -> void:
	draw_rect(Rect2(-14, 4, 42, 12), Color(0, 0, 0.02, 0.35))
	draw_texture_rect(STONE, Rect2(-16, -16, 32, 24), false, Color(1.15, 1.0, 1.65))
	draw_texture_rect(STONE, Rect2(-16, -40, 32, 32), false, Color(2.0, 1.75, 2.55))
	draw_rect(Rect2(-16, -40, 32, 2), Color("88769e"))
	draw_rect(Rect2(-16, -40, 2, 32), Color("665b80"))
	draw_rect(Rect2(-16, -8, 32, 2), Color("141125"))
	draw_rect(Rect2(-16, 6, 32, 2), Color("100d20"))
