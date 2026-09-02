class_name SquareSlot
extends AspectRatioContainer
## Holds the board and keeps it square, claiming exactly as much height as it is
## wide.
##
## AspectRatioContainer cannot do this alone. A VBoxContainer asks each child for
## a minimum size *before* it knows how wide that child will end up, so the
## container reports no height and the board gets none -- or, if it is told to
## expand, it swallows all the leftover space and the labels meant to sit tight
## above and below it drift to the far edges of the screen.
##
## Reporting width as the minimum height fixes both. The VBox then allocates a
## square, and everything else in the stack packs against it. Width in a VBox does
## not depend on height, so this settles in one pass rather than oscillating.

func _ready() -> void:
	resized.connect(_match_height_to_width)
	_match_height_to_width()


func _match_height_to_width() -> void:
	if not is_equal_approx(custom_minimum_size.y, size.x):
		custom_minimum_size.y = size.x
