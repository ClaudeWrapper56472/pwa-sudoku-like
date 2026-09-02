class_name CatMascot
extends Control
## The cat on the menu and the result card.
##
## Fits the art inside the node without distorting it. The node is far wider than
## it is tall, so handing the whole rect to draw_texture_rect would stretch the
## cat across the screen.

const MASCOT_TEXTURE: Texture2D = preload("res://art/mascot.png")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var aspect := MASCOT_TEXTURE.get_height() / float(MASCOT_TEXTURE.get_width())
	var width := minf(size.x, size.y / aspect)
	var height := width * aspect
	draw_texture_rect(MASCOT_TEXTURE,
		Rect2((size - Vector2(width, height)) * 0.5, Vector2(width, height)), false)
