class_name LivesDisplay
extends Control
## The row of hearts in the top bar.
##
## Spent lives stay on screen as hollow outlines rather than disappearing. A row
## that shrinks tells you how many you have; a row that hollows out tells you how
## many you have *left of how many*, which is the number that matters when you
## are deciding whether to guess.

const HEART_SIZE := 24.0
const GAP := 5.0

var _remaining := 0
var _total := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_lives(remaining: int, total: int) -> void:
	if _remaining == remaining and _total == total:
		return
	_remaining = remaining
	_total = total
	custom_minimum_size = Vector2(total * HEART_SIZE + maxf(0.0, (total - 1) * GAP), HEART_SIZE)
	queue_redraw()


func _draw() -> void:
	for i in _total:
		var origin := Vector2(i * (HEART_SIZE + GAP), (size.y - HEART_SIZE) * 0.5)
		var box := Rect2(origin, Vector2(HEART_SIZE, HEART_SIZE))
		if i < _remaining:
			_draw_heart(box, Palette.INK_WRONG)
		else:
			_draw_heart(box, Palette.INK_WRONG * Color(1.0, 1.0, 1.0, 0.22))


## A heart, for the lives display. Two lobes and a point -- the same shape a paw
## pad almost is, which is why both live in this file.
func _draw_heart(rect: Rect2, colour: Color) -> void:
	var span := minf(rect.size.x, rect.size.y)
	if span <= 3.0:
		return
	var centre := rect.get_center()
	var lobe := span * 0.26
	draw_circle(centre + Vector2(-lobe * 0.86, -lobe * 0.46), lobe, colour)
	draw_circle(centre + Vector2(lobe * 0.86, -lobe * 0.46), lobe, colour)
	draw_colored_polygon(PackedVector2Array([
		centre + Vector2(-lobe * 1.72, -lobe * 0.22),
		centre + Vector2(lobe * 1.72, -lobe * 0.22),
		centre + Vector2(0.0, span * 0.44),
	]), colour)
