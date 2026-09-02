class_name CrossRunCommand
extends SudokuCommand
## One drag across a run of cells, crossing them out or clearing them.
##
## The whole run is a single undo step, because one gesture is one decision --
## having to press undo nine times to take back one swipe would be absurd.
##
## The run is built as the finger moves so the player sees each cell change
## immediately, which means the cells are already applied by the time the command
## reaches the undo stack. That is what UndoStack.push_applied() exists for.
##
## The target mark is fixed when the drag starts, from whatever the first cell
## was: starting on an empty cell crosses out, starting on a crossed cell erases.
## Fixing it up front is what stops a drag from flickering cells on and off as it
## wanders back over its own path.

const TYPE := "run"

var new_mark := CatGrid.Mark.EXCLUDED
var indices := PackedInt32Array()
var old_marks := PackedByteArray()


static func create(mark: int) -> CrossRunCommand:
	var command := CrossRunCommand.new()
	command.new_mark = mark
	return command


## Adds one cell to the run and applies it immediately. Returns true when the
## cell was actually taken.
##
## Cells holding a cat are skipped: dragging past a cat you have already placed
## should never wipe it, and a drag is far too easy to aim carelessly. Cells the
## game has proved wrong are skipped for the same reason -- there is nothing left
## to decide about them.
func extend(state: PuzzleState, index: int) -> bool:
	if state.marks[index] == CatGrid.Mark.CAT or state.is_locked(index):
		return false
	if state.marks[index] == new_mark:
		return false
	indices.append(index)
	old_marks.append(state.marks[index])
	state.put(index, new_mark)
	return true


func is_empty() -> bool:
	return indices.is_empty()


func apply(state: PuzzleState) -> void:
	for index in indices:
		state.put(index, new_mark)


func revert(state: PuzzleState) -> void:
	for i in indices.size():
		state.put(indices[i], old_marks[i])


func touched() -> PackedInt32Array:
	return indices


func describe() -> String:
	var what := "cross" if new_mark == CatGrid.Mark.EXCLUDED else "clear"
	return "%s run of %d" % [what, indices.size()]


func to_dict() -> Dictionary:
	return {"t": TYPE, "m": new_mark, "i": Array(indices), "o": Array(old_marks)}


static func from_dict(data: Dictionary) -> CrossRunCommand:
	var command := CrossRunCommand.new()
	command.new_mark = int(data.get("m", CatGrid.Mark.EXCLUDED))
	command.indices = PackedInt32Array(data.get("i", []))
	command.old_marks = PackedByteArray(data.get("o", []))
	# A truncated or hand-edited entry would revert cells it never touched.
	if command.old_marks.size() != command.indices.size():
		return null
	return command
