class_name UndoStack
extends RefCounted
## Two stacks of commands and the rules for moving between them.
##
## push() applies the command and drops the redo stack, which is the standard
## rule: once you make a new move, the future you undid is gone. undo() reverts
## the top of the undo stack and moves it to redo; redo() does the reverse.
##
## Commands write to the board silently; the stack fires the board's change
## signal once per move, after the command has finished. Placing a cat that
## crosses out twenty cells therefore repaints once, not twenty-one times.
##
## The whole stack serializes, so closing the app mid-game and coming back does
## not cost you your undo history. Depth is capped because history is written to
## disk on every suspend and an unbounded stack would grow the save file
## without limit.

signal changed(can_undo: bool, can_redo: bool)

const MAX_DEPTH := 200

var _undo: Array[SudokuCommand] = []
var _redo: Array[SudokuCommand] = []


## Applies `command` and records it. Returns the cells it touched.
func push(command: SudokuCommand, state: PuzzleState) -> PackedInt32Array:
	command.apply(state)
	_undo.append(command)
	_redo.clear()
	if _undo.size() > MAX_DEPTH:
		_undo.remove_at(0)
	var touched := command.touched()
	state.notify(touched)
	_emit()
	return touched


## Records a command whose changes are already on the board.
##
## A drag applies each cell as the finger passes over it, so by the time the
## gesture ends there is nothing left to apply -- only to remember. Re-applying
## would be harmless here but dishonest, and it would fire a second change signal
## for a move the board has already drawn.
func push_applied(command: SudokuCommand, state: PuzzleState) -> PackedInt32Array:
	_undo.append(command)
	_redo.clear()
	if _undo.size() > MAX_DEPTH:
		_undo.remove_at(0)
	var touched := command.touched()
	state.notify(touched)
	_emit()
	return touched


func undo(state: PuzzleState) -> PackedInt32Array:
	if _undo.is_empty():
		return PackedInt32Array()
	var command: SudokuCommand = _undo.pop_back()
	command.revert(state)
	_redo.append(command)
	var touched := command.touched()
	state.notify(touched)
	_emit()
	return touched


func redo(state: PuzzleState) -> PackedInt32Array:
	if _redo.is_empty():
		return PackedInt32Array()
	var command: SudokuCommand = _redo.pop_back()
	command.apply(state)
	_undo.append(command)
	var touched := command.touched()
	state.notify(touched)
	_emit()
	return touched


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func depth() -> int:
	return _undo.size()


func clear() -> void:
	_undo.clear()
	_redo.clear()
	_emit()


func to_dict() -> Dictionary:
	return {"undo": _serialize(_undo), "redo": _serialize(_redo)}


func from_dict(data: Dictionary) -> void:
	_undo = _deserialize(data.get("undo", []))
	_redo = _deserialize(data.get("redo", []))
	_emit()


func _emit() -> void:
	changed.emit(can_undo(), can_redo())


func _serialize(stack: Array[SudokuCommand]) -> Array:
	var out: Array = []
	for command in stack:
		out.append(command.to_dict())
	return out


## Rebuilds commands from saved dictionaries. Unknown entries are dropped rather
## than faulted, so a save written by a newer build with extra command types
## still loads -- just with a shorter history.
func _deserialize(raw: Variant) -> Array[SudokuCommand]:
	var stack: Array[SudokuCommand] = []
	if not raw is Array:
		return stack
	for entry in raw as Array:
		if not entry is Dictionary:
			continue
		var command := build(entry as Dictionary)
		if command != null:
			stack.append(command)
	return stack


## Command factory. Lives here rather than on SudokuCommand so the base class
## does not have to name its own subclasses.
static func build(data: Dictionary) -> SudokuCommand:
	match String(data.get("t", "")):
		SetMarkCommand.TYPE:
			return SetMarkCommand.from_dict(data)
		CrossRunCommand.TYPE:
			return CrossRunCommand.from_dict(data)
		ClearBoardCommand.TYPE:
			return ClearBoardCommand.from_dict(data)
	return null
