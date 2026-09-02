class_name PuzzleState
extends RefCounted
## The board the player is working on: the level, and what they have marked.
##
## Deliberately separate from the GameState autoload. Commands act on this, so
## the undo system has no dependency on the engine singleton and can be built and
## tested on its own. GameState owns one of these and relays its signal outward.

signal cells_changed(indices: PackedInt32Array)

var level: CatLevel = null
var marks := PackedByteArray() ## one CatGrid.Mark per cell


func setup(new_level: CatLevel) -> void:
	level = new_level
	marks = PackedByteArray()
	marks.resize(new_level.size * new_level.size)


func size() -> int:
	return level.size if level != null else 0


func mark_at(index: int) -> int:
	return marks[index]


func region_at(index: int) -> int:
	return level.regions[index]


## Silent write used by commands. They batch several of these and then call
## notify() once, so the board repaints a move rather than each cell of it.
func put(index: int, mark: int) -> void:
	marks[index] = mark


func notify(indices: PackedInt32Array) -> void:
	cells_changed.emit(indices)


## A cell whose answer is settled. Nothing about it can be edited, because there
## is nothing left to decide.
##
## Both kinds of settled cell get here. A red cross is one the game proved wrong.
## A cat is one the player got right -- and since a wrong cat is refused rather
## than placed, every cat on the board is correct by construction.
func is_locked(index: int) -> bool:
	return marks[index] == CatGrid.Mark.WRONG or marks[index] == CatGrid.Mark.CAT


## True when there is anything of the player's own to clear. Locked cells do not
## count -- they cannot be cleared, so a board holding only those has nothing to
## offer the Clear button.
func has_player_marks() -> bool:
	for index in marks.size():
		if marks[index] != CatGrid.Mark.EMPTY and not is_locked(index):
			return true
	return false


func cats_placed() -> int:
	var n := 0
	for mark in marks:
		if mark == CatGrid.Mark.CAT:
			n += 1
	return n


func cat_cells() -> PackedInt32Array:
	var out := PackedInt32Array()
	for index in marks.size():
		if marks[index] == CatGrid.Mark.CAT:
			out.append(index)
	return out


## A cat is wrong when it is not where the solution puts it.
##
## Because the level has exactly one solution, every other cell is one the player
## could have ruled out. There is no such thing as a cat that is "not wrong yet".
func is_wrong_cat(index: int) -> bool:
	return marks[index] == CatGrid.Mark.CAT and not level.is_solution_cell(index)


## Why a cat here would be wrong, in the player's terms. Asked before anything is
## placed, so it reads the board as it stands. A cell can be wrong without
## clashing with anything already down -- it is simply not in the answer -- so a
## specific rule is only quoted when one is actually broken.
func explain_wrong(index: int) -> String:
	var n := size()
	var row := CatGrid.row_of(n, index)
	var col := CatGrid.col_of(n, index)
	for other in cat_cells():
		if other == index:
			continue
		var other_row := CatGrid.row_of(n, other)
		var other_col := CatGrid.col_of(n, other)
		if CatGrid.touching(row, col, other_row, other_col):
			return "Cats cannot touch, not even corner to corner."
		if other_row == row:
			return "There is already a cat in that row."
		if other_col == col:
			return "There is already a cat in that column."
		if level.regions[other] == level.regions[index]:
			return "There is already a cat in that colour."
	return "No cat can go there."


## Solved when every cat in the solution is on the board and nothing else is.
func is_complete() -> bool:
	if level == null:
		return false
	var placed := 0
	for index in marks.size():
		if marks[index] != CatGrid.Mark.CAT:
			continue
		if not level.is_solution_cell(index):
			return false
		placed += 1
	return placed == size()


func marks_to_string() -> String:
	var out := ""
	for mark in marks:
		match mark:
			CatGrid.Mark.EXCLUDED:
				out += "x"
			CatGrid.Mark.CAT:
				out += "c"
			CatGrid.Mark.WRONG:
				out += "w"
			_:
				out += "."
	return out


func marks_from_string(text: String) -> void:
	marks.resize(size() * size())
	marks.fill(CatGrid.Mark.EMPTY)
	var i := 0
	for ch in text:
		if i >= marks.size():
			break
		match ch:
			"x":
				marks[i] = CatGrid.Mark.EXCLUDED
			"c":
				marks[i] = CatGrid.Mark.CAT
			"w":
				marks[i] = CatGrid.Mark.WRONG
			_:
				marks[i] = CatGrid.Mark.EMPTY
		i += 1


func to_dict() -> Dictionary:
	return {"level": level.to_dict(), "marks": marks_to_string()}


func from_dict(data: Dictionary) -> bool:
	var restored := CatLevel.from_dict(data.get("level", {}))
	if restored == null or not restored.is_valid():
		return false
	setup(restored)
	marks_from_string(String(data.get("marks", "")))
	return true
