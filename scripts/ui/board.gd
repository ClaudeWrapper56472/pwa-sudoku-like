class_name SudokuBoard
extends Control
## The grid of cells.
##
## Board owns the cell instances and nothing else. It listens to GameState and
## pushes what it hears down into cells; it sends taps back up as signals rather
## than calling GameState itself, so the same board scene could be reused for a
## replay viewer or a tutorial with a different controller behind it.
##
## The board is rebuilt whenever a level loads, because the size changes between
## levels -- a 5x5 Easy and a 9x9 Expert are the same scene with a different
## number of children.

signal cell_tapped(index: int)
signal cell_double_tapped(index: int)
signal drag_started(index: int)
signal drag_reached(index: int)
signal drag_ended()

## A second tap inside this window means "place a cat" rather than "cross out".
## Touchscreens send no double-click event of their own, so the timing is done
## here and mouse and touch behave identically.
const DOUBLE_TAP_MSEC := 350

const CELL_SCENE := preload("res://scenes/Cell.tscn")

@onready var _cells_root: GridContainer = $Cells

var _cells: Array[SudokuCell] = []
var _hinted_cell := -1

## Pointer state. `_origin` is where the press landed, `_current` is the cell the
## pointer is over now; they differ the moment a press becomes a drag.
var _origin := -1
var _current := -1
var _dragging := false
var _last_tap_cell := -1
var _last_tap_msec := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_cells_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameState.level_loaded.connect(_on_level_loaded)
	GameState.cells_changed.connect(_on_cells_changed)
	GameState.selection_changed.connect(_on_selection_changed)
	GameState.hint_offered.connect(_on_hint_offered)
	GameState.level_failed.connect(_on_level_failed)
	_on_level_loaded()


func _on_level_loaded() -> void:
	_hinted_cell = -1
	_rebuild()


func _rebuild() -> void:
	for cell in _cells:
		cell.queue_free()
	_cells.clear()

	var state := GameState.board
	if state.level == null:
		return
	var n := state.size()
	_cells_root.columns = n
	# The gap between cells is exactly how far a cat may spill over the edge.
	var overhang := float(_cells_root.get_theme_constant("h_separation"))
	for index in n * n:
		var cell: SudokuCell = CELL_SCENE.instantiate()
		cell.setup(index, state.region_at(index))
		cell.set_overhang(overhang)
		_cells_root.add_child(cell)
		_cells.append(cell)
	refresh_all()


func refresh_all() -> void:
	if _cells.is_empty():
		return
	var state := GameState.board
	for index in _cells.size():
		_cells[index].set_mark(state.marks[index])
	_refresh_highlights()


## The whole board is refreshed rather than just the cells a move named. At most
## eighty-one cells, and the reveal at the end of a level touches all of them
## anyway; the simplicity is worth more than the saved comparisons.
func _on_cells_changed(_indices: PackedInt32Array) -> void:
	refresh_all()


func _on_selection_changed(_index: int) -> void:
	_refresh_highlights()


func _on_hint_offered(index: int, _message: String, success: bool) -> void:
	_hinted_cell = index if success else -1
	for i in _cells.size():
		_cells[i].set_hinted(i == _hinted_cell)


func _on_level_failed() -> void:
	refresh_all()


func _refresh_highlights() -> void:
	var selected := GameState.selected
	for index in _cells.size():
		_cells[index].set_selected(index == selected)


# --- Pointer input ----------------------------------------------------------
#
# All of it lives here rather than in the cells. Once a press lands on a Control,
# Godot routes every following motion and the release to that same Control, so a
# cell would only ever hear about itself -- which is no use to a gesture whose
# whole job is to cross a run of other cells.
#
# A press does not commit to being a tap or a drag. It becomes a drag the moment
# the pointer enters a *different* cell, and stays a tap otherwise. That needs no
# pixel threshold and matches what a finger expects: a small wobble inside one
# cell is still a tap.


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click is the mouse shorthand for the double-tap.
			if click.pressed:
				var index := _cell_at(click.position)
				if index >= 0:
					cell_double_tapped.emit(index)
				accept_event()
			return
		if click.button_index != MOUSE_BUTTON_LEFT:
			return
		if click.pressed:
			_press(_cell_at(click.position))
		else:
			_release(_cell_at(click.position))
		accept_event()
	elif event is InputEventMouseMotion:
		if _origin >= 0:
			_move(_cell_at((event as InputEventMouseMotion).position))
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press(_cell_at(touch.position))
		else:
			_release(_cell_at(touch.position))
		accept_event()
	elif event is InputEventScreenDrag:
		if _origin >= 0:
			_move(_cell_at((event as InputEventScreenDrag).position))


func _press(index: int) -> void:
	_origin = index
	_current = index
	_dragging = false


func _move(index: int) -> void:
	if index < 0 or index == _current or _origin < 0:
		return
	if not _dragging:
		_dragging = true
		drag_started.emit(_origin)
	_current = index
	drag_reached.emit(index)


func _release(index: int) -> void:
	if _dragging:
		drag_ended.emit()
	elif _origin >= 0 and index == _origin:
		var now := Time.get_ticks_msec()
		if _last_tap_cell == index and now - _last_tap_msec <= DOUBLE_TAP_MSEC:
			_last_tap_cell = -1
			cell_double_tapped.emit(index)
		else:
			_last_tap_cell = index
			_last_tap_msec = now
			cell_tapped.emit(index)
	_origin = -1
	_current = -1
	_dragging = false


## Which cell sits under a point given in this control's coordinates, or -1.
## A linear scan over at most eighty-one rectangles, which is cheaper than it
## sounds and far less fragile than reconstructing the grid's geometry.
func _cell_at(local_position: Vector2) -> int:
	var global_position := get_global_transform() * local_position
	for index in _cells.size():
		if _cells[index].get_global_rect().has_point(global_position):
			return index
	return -1
