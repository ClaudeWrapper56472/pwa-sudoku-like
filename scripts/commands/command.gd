class_name SudokuCommand
extends RefCounted
## Base class for one undoable move.
##
## A command carries everything needed to put the board back exactly as it was,
## which means it records the old state as well as the new one. That is what lets
## undo work without keeping a copy of the whole board per move -- and it is why
## the undo history is small enough to write into the save file.
##
## Subclasses implement apply/revert as exact mirrors of each other, and
## to_dict/from_dict so history survives a restart.


func apply(_state: PuzzleState) -> void:
	pass


func revert(_state: PuzzleState) -> void:
	pass


## Cells this command touches. The board repaints these and nothing else.
func touched() -> PackedInt32Array:
	return PackedInt32Array()


## Short label for a move list or debug overlay.
func describe() -> String:
	return "command"


func to_dict() -> Dictionary:
	return {}
