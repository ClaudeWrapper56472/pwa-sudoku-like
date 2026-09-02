class_name ClearBoardCommand
extends SudokuCommand
## Wipes every mark the player made, as a single undo step.
##
## Cells the game locked in red are left alone. Those are not the player's
## working -- they are facts the game paid a life to establish, and clearing the
## board should not quietly hand those lives back.
##
## One command rather than one per cell: throwing away twenty minutes of crossing
## out is exactly the move somebody wants back in one press.

const TYPE := "clear"

var indices := PackedInt32Array()
var old_marks := PackedByteArray()


static func create(state: PuzzleState) -> ClearBoardCommand:
	var command := ClearBoardCommand.new()
	for index in state.marks.size():
		if state.marks[index] == CatGrid.Mark.EMPTY or state.is_locked(index):
			continue
		command.indices.append(index)
		command.old_marks.append(state.marks[index])
	return command


func is_empty() -> bool:
	return indices.is_empty()


func apply(state: PuzzleState) -> void:
	for index in indices:
		state.put(index, CatGrid.Mark.EMPTY)


func revert(state: PuzzleState) -> void:
	for i in indices.size():
		state.put(indices[i], old_marks[i])


func touched() -> PackedInt32Array:
	return indices


func describe() -> String:
	return "clear %d cells" % indices.size()


func to_dict() -> Dictionary:
	return {"t": TYPE, "i": Array(indices), "o": Array(old_marks)}


static func from_dict(data: Dictionary) -> ClearBoardCommand:
	var command := ClearBoardCommand.new()
	command.indices = PackedInt32Array(data.get("i", []))
	command.old_marks = PackedByteArray(data.get("o", []))
	# A truncated entry would restore cells it never recorded.
	if command.old_marks.size() != command.indices.size():
		return null
	return command
