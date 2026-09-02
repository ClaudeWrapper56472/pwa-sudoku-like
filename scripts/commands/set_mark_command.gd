class_name SetMarkCommand
extends SudokuCommand
## Changes what is in one cell.
##
## Every edit in this game is one cell changing between empty, crossed and cat,
## so this is the only command there is. An earlier version also carried the
## cells a cat automatically crossed out; that feature is gone, and with it the
## reason for a command to touch more than one cell.
##
## The command pattern still earns its place without it: the move serializes to
## four integers so undo history survives a restart, redo is free, and the board
## is told which cell to repaint rather than repainting all eighty-one.

const TYPE := "mark"

var index := -1
var new_mark := CatGrid.Mark.EMPTY
var old_mark := CatGrid.Mark.EMPTY


## Builds the command against the board as it currently stands, capturing the old
## state. Call this before pushing to the undo stack.
static func create(state: PuzzleState, cell: int, mark: int) -> SetMarkCommand:
	var command := SetMarkCommand.new()
	command.index = cell
	command.new_mark = mark
	command.old_mark = state.marks[cell]
	return command


func apply(state: PuzzleState) -> void:
	state.put(index, new_mark)


func revert(state: PuzzleState) -> void:
	state.put(index, old_mark)


func touched() -> PackedInt32Array:
	return PackedInt32Array([index])


func describe() -> String:
	var what := "cross" if new_mark == CatGrid.Mark.EXCLUDED else \
		("cat" if new_mark == CatGrid.Mark.CAT else "clear")
	return "%s at %d" % [what, index]


func to_dict() -> Dictionary:
	return {"t": TYPE, "i": index, "m": new_mark, "o": old_mark}


static func from_dict(data: Dictionary) -> SetMarkCommand:
	var command := SetMarkCommand.new()
	command.index = int(data.get("i", -1))
	command.new_mark = int(data.get("m", CatGrid.Mark.EMPTY))
	command.old_mark = int(data.get("o", CatGrid.Mark.EMPTY))
	return command
