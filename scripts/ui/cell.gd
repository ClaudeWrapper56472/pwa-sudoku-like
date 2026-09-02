class_name SudokuCell
extends Control
## One square of the board.
##
## A cell knows its colour and what is marked on it, and draws that. It reads no
## game state, handles no input and decides nothing -- Board tells it everything. So a cell can be dropped into a test scene, handed a region and a
## mark, and it renders correctly with no autoloads present.
##
## The fill is the region colour and nothing shifts it. An earlier version dimmed
## the selected cell's row, column and colour, which is standard in a Sudoku --
## but here colour *is* the region, so two shades of the same blue read as two
## different regions. Selection is an outline instead.
##
## Everything is drawn rather than assembled from child nodes: the fill needs
## rounded corners, the cross and the cat are procedural anyway, and one _draw()
## beats four nodes per cell on a board of up to eighty-one of them.

const CAT_TEXTURE: Texture2D = preload("res://art/cat.png")

var index := -1

var _region := 0
var _mark := CatGrid.Mark.EMPTY
var _selected := false
var _hinted := false
## How far the cat may spill past the cell edge, in pixels. Board sets it from
## the grid's own separation so the art fills the gap between cells exactly and no
## further: cells draw in order, so anything past the gap would be painted over by
## the neighbour below and to the right and the overlap would look lopsided.
var _overhang := 0.0
var _box := StyleBoxFlat.new()


func _ready() -> void:
	# Pointer input belongs to Board: a drag has to know which cell it is over,
	# and Godot sends every motion event after a press to the control that was
	# pressed -- so a cell could only ever hear about itself.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func setup(cell_index: int, region: int) -> void:
	index = cell_index
	_region = region
	queue_redraw()


func set_mark(mark: int) -> void:
	if _mark == mark:
		return
	_mark = mark
	queue_redraw()


func set_selected(selected: bool) -> void:
	if _selected == selected:
		return
	_selected = selected
	queue_redraw()


func set_overhang(pixels: float) -> void:
	if is_equal_approx(_overhang, pixels):
		return
	_overhang = pixels
	queue_redraw()


func set_hinted(hinted: bool) -> void:
	if _hinted == hinted:
		return
	_hinted = hinted
	queue_redraw()


func _draw() -> void:
	var span := minf(size.x, size.y)
	_box.bg_color = _fill_colour()
	_box.set_corner_radius_all(int(span * 0.16))
	if _selected or _hinted:
		_box.set_border_width_all(maxi(2, int(span * 0.06)))
		_box.border_color = _border_colour()
	else:
		_box.set_border_width_all(0)
	draw_style_box(_box, Rect2(Vector2.ZERO, size))

	match _mark:
		CatGrid.Mark.CAT:
			_draw_game_cat(span, Color.WHITE)
		CatGrid.Mark.EXCLUDED:
			_draw_cross(span, Palette.MARK)
		CatGrid.Mark.WRONG:
			# Red, and permanent. The player's own crosses are cream and can be
			# taken back; this one is the game stating a fact.
			_draw_cross(span, Palette.CONFLICT)


## Sized to fill the cell's width plus the gap on either side, with the height
## following the art's own proportions.
##
## The cat is wider than it is tall -- whiskers -- so filling the width is what
## makes it look like it fills the cell. Filling the height instead would push the
## whiskers well past the gap, where the neighbouring cell, drawn later, would
## clip them.
func _draw_game_cat(span: float, tint: Color) -> void:
	var width := span + _overhang * 2.0
	var height := width * CAT_TEXTURE.get_height() / float(CAT_TEXTURE.get_width())
	var box := Rect2((size - Vector2(width, height)) * 0.5, Vector2(width, height))
	draw_texture_rect(CAT_TEXTURE, box, false, tint)


func _draw_cross(span: float, colour: Color) -> void:
	var centre := size * 0.5
	var reach := span * 0.24
	var width := maxf(3.0, span * 0.11)
	draw_line(centre - Vector2(reach, reach), centre + Vector2(reach, reach), colour, width, true)
	draw_line(centre - Vector2(reach, -reach), centre + Vector2(reach, -reach), colour, width, true)


func _fill_colour() -> Color:
	var colour: Color = Palette.region_colour(_region)
	return colour.lightened(0.25) if _hinted else colour


func _border_colour() -> Color:
	if _hinted:
		return Palette.MINT
	return Palette.INK
