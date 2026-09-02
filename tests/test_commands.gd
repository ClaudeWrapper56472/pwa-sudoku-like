extends TestCase
## Undo/redo and the rules a placement is judged against.

const REGIONS := "ABCBABBBAADBADDB"
const COLUMNS: Array[int] = [2, 0, 3, 1]
const SIZE := 4


func _fresh_board() -> PuzzleState:
	var level := CatLevel.new()
	level.size = SIZE
	level.regions = CatGrid.regions_from_string(REGIONS)
	level.columns = PackedByteArray(COLUMNS)
	var state := PuzzleState.new()
	state.setup(level)
	return state


func test_marking_a_cross_round_trips() -> void:
	var state := _fresh_board()
	var stack := UndoStack.new()
	stack.push(SetMarkCommand.create(state, 5, CatGrid.Mark.EXCLUDED), state)
	assert_eq(state.marks[5], CatGrid.Mark.EXCLUDED, "cell is crossed")
	assert_true(stack.can_undo(), "there is something to undo")

	stack.undo(state)
	assert_eq(state.marks[5], CatGrid.Mark.EMPTY, "undo clears it")
	assert_true(stack.can_redo(), "the move moved to the redo stack")
	stack.redo(state)
	assert_eq(state.marks[5], CatGrid.Mark.EXCLUDED, "redo puts it back")


func test_placing_a_cat_changes_only_that_cell() -> void:
	var state := _fresh_board()
	var stack := UndoStack.new()
	var cell := CatGrid.index_of(SIZE, 0, 2)
	stack.push(SetMarkCommand.create(state, cell, CatGrid.Mark.CAT), state)

	assert_eq(state.marks[cell], CatGrid.Mark.CAT, "the cat is placed")
	var others := 0
	for index in state.marks.size():
		if index != cell and state.marks[index] != CatGrid.Mark.EMPTY:
			others += 1
	assert_eq(others, 0, "nothing else is touched -- working out what a cat rules out is the game")

	stack.undo(state)
	assert_eq(state.marks[cell], CatGrid.Mark.EMPTY, "undo restores an untouched board")


func test_a_cat_off_the_solution_is_wrong() -> void:
	var state := _fresh_board()
	var right := CatGrid.index_of(SIZE, 0, COLUMNS[0])
	var wrong := CatGrid.index_of(SIZE, 0, 0)
	state.put(right, CatGrid.Mark.CAT)
	assert_false(state.is_wrong_cat(right), "a cat on a solution cell is right")
	state.put(right, CatGrid.Mark.EMPTY)
	state.put(wrong, CatGrid.Mark.CAT)
	assert_true(state.is_wrong_cat(wrong), "a cat anywhere else is wrong")


func test_a_wrong_cat_is_explained() -> void:
	var state := _fresh_board()
	state.put(CatGrid.index_of(SIZE, 0, COLUMNS[0]), CatGrid.Mark.CAT)
	var same_row := CatGrid.index_of(SIZE, 0, 0)
	state.put(same_row, CatGrid.Mark.CAT)
	assert_true(state.explain_wrong(same_row).contains("row"), "a row clash is named")

	# A wrong cell need not clash with anything already down -- it can simply not
	# be in the answer -- and that case still has to say something useful.
	state.put(same_row, CatGrid.Mark.EMPTY)
	var lonely := CatGrid.index_of(SIZE, 2, 1)
	state.put(lonely, CatGrid.Mark.CAT)
	assert_true(state.is_wrong_cat(lonely), "the fixture cell really is off the solution")
	assert_true(state.explain_wrong(lonely).length() > 0, "and it still gets an explanation")


func test_a_new_move_discards_the_redo_stack() -> void:
	var state := _fresh_board()
	var stack := UndoStack.new()
	stack.push(SetMarkCommand.create(state, 5, CatGrid.Mark.EXCLUDED), state)
	stack.undo(state)
	assert_true(stack.can_redo(), "redo available after an undo")
	stack.push(SetMarkCommand.create(state, 6, CatGrid.Mark.EXCLUDED), state)
	assert_false(stack.can_redo(), "a new move drops the redo stack")


func test_history_round_trips_through_serialization() -> void:
	var state := _fresh_board()
	var stack := UndoStack.new()
	for row in SIZE:
		stack.push(SetMarkCommand.create(state, CatGrid.index_of(SIZE, row, row),
			CatGrid.Mark.EXCLUDED), state)
	stack.push(SetMarkCommand.create(state, CatGrid.index_of(SIZE, 0, 2),
		CatGrid.Mark.CAT), state)
	var marked := state.marks_to_string()

	var parsed: Variant = JSON.parse_string(JSON.stringify(stack.to_dict()))
	assert_true(parsed is Dictionary, "history survives a JSON round trip")
	var restored := UndoStack.new()
	restored.from_dict(parsed as Dictionary)
	assert_eq(restored.depth(), stack.depth(), "same number of moves came back")

	while restored.can_undo():
		restored.undo(state)
	assert_eq(state.marks_to_string(), ".".repeat(SIZE * SIZE),
		"unwinding the deserialized history returns to an empty board")
	while restored.can_redo():
		restored.redo(state)
	assert_eq(state.marks_to_string(), marked, "replaying it returns to where we were")


func test_history_depth_is_capped() -> void:
	var state := _fresh_board()
	var stack := UndoStack.new()
	for n in UndoStack.MAX_DEPTH + 40:
		var mark := CatGrid.Mark.EXCLUDED if n % 2 == 0 else CatGrid.Mark.EMPTY
		stack.push(SetMarkCommand.create(state, 5, mark), state)
	assert_eq(stack.depth(), UndoStack.MAX_DEPTH, "stack stops growing at the cap")


func test_board_signals_once_per_move() -> void:
	var state := _fresh_board()
	var stack := UndoStack.new()
	var emissions: Array = []
	state.cells_changed.connect(func(indices: PackedInt32Array) -> void: emissions.append(indices))
	stack.push(SetMarkCommand.create(state, CatGrid.index_of(SIZE, 0, 2),
		CatGrid.Mark.CAT), state)
	assert_eq(emissions.size(), 1, "one signal per move")
	assert_eq(emissions[0].size(), 1, "naming the cell that changed")


func test_completion_needs_every_cat_and_no_wrong_ones() -> void:
	var state := _fresh_board()
	assert_false(state.is_complete(), "an empty board is not complete")
	for row in SIZE:
		state.put(CatGrid.index_of(SIZE, row, COLUMNS[row]), CatGrid.Mark.CAT)
	assert_true(state.is_complete(), "the intended placement completes the level")

	state.put(CatGrid.index_of(SIZE, 0, COLUMNS[0]), CatGrid.Mark.EMPTY)
	state.put(CatGrid.index_of(SIZE, 0, 0), CatGrid.Mark.CAT)
	assert_false(state.is_complete(), "a board with a wrong cat is not complete")

	# Crosses are just notes to yourself and never block completion.
	state.put(CatGrid.index_of(SIZE, 0, 0), CatGrid.Mark.EMPTY)
	state.put(CatGrid.index_of(SIZE, 0, COLUMNS[0]), CatGrid.Mark.CAT)
	state.put(CatGrid.index_of(SIZE, 1, 1), CatGrid.Mark.EXCLUDED)
	assert_true(state.is_complete(), "a stray cross does not stop the level completing")


func test_a_proved_wrong_cell_survives_serialisation() -> void:
	var state := _fresh_board()
	var cell := CatGrid.index_of(SIZE, 0, 0)
	state.put(cell, CatGrid.Mark.WRONG)
	state.put(CatGrid.index_of(SIZE, 1, 1), CatGrid.Mark.EXCLUDED)
	assert_true(state.is_locked(cell), "the cell is locked")

	var text := state.marks_to_string()
	assert_eq(text[cell], "w", "it has its own character, distinct from a cross")

	var restored := PuzzleState.new()
	restored.setup(state.level)
	restored.marks_from_string(text)
	assert_eq(restored.marks[cell], CatGrid.Mark.WRONG, "and comes back as itself")
	assert_true(restored.is_locked(cell), "still locked after a reload")
	assert_eq(restored.marks[CatGrid.index_of(SIZE, 1, 1)], CatGrid.Mark.EXCLUDED,
		"an ordinary cross is unaffected")


func test_a_proved_wrong_cell_does_not_block_completion() -> void:
	var state := _fresh_board()
	# Every wrong cell is off the solution by definition, so one can never sit
	# where a cat belongs.
	state.put(CatGrid.index_of(SIZE, 0, 0), CatGrid.Mark.WRONG)
	for row in SIZE:
		state.put(CatGrid.index_of(SIZE, row, COLUMNS[row]), CatGrid.Mark.CAT)
	assert_true(state.is_complete(), "the level still completes around it")


func test_clearing_the_board_is_one_undo_step() -> void:
	var state := _fresh_board()
	var stack := UndoStack.new()
	stack.push(SetMarkCommand.create(state, 1, CatGrid.Mark.EXCLUDED), state)
	stack.push(SetMarkCommand.create(state, 2, CatGrid.Mark.EXCLUDED), state)
	stack.push(SetMarkCommand.create(state, 3, CatGrid.Mark.EXCLUDED), state)
	var before := state.marks_to_string()

	assert_true(state.has_player_marks(), "there is something to clear")
	stack.push(ClearBoardCommand.create(state), state)
	assert_eq(state.marks_to_string(), ".".repeat(SIZE * SIZE), "every cross is wiped")
	assert_false(state.has_player_marks(), "and nothing is left to clear")

	stack.undo(state)
	assert_eq(state.marks_to_string(), before, "one undo brings all of it back")



func test_clearing_leaves_settled_cells_alone() -> void:
	var state := _fresh_board()
	var locked := CatGrid.index_of(SIZE, 3, 3)
	var cat := CatGrid.index_of(SIZE, 0, COLUMNS[0])
	state.put(locked, CatGrid.Mark.WRONG)
	state.put(cat, CatGrid.Mark.CAT)
	state.put(1, CatGrid.Mark.EXCLUDED)

	var command := ClearBoardCommand.create(state)
	command.apply(state)
	assert_eq(state.marks[locked], CatGrid.Mark.WRONG,
		"a cell the game proved wrong survives -- it cost a life to establish")
	assert_eq(state.marks[cat], CatGrid.Mark.CAT,
		"and so does a cat, which cannot have been wrong")
	assert_eq(state.marks[1], CatGrid.Mark.EMPTY, "only the player's own crosses go")



func test_clearing_an_empty_board_records_nothing() -> void:
	var state := _fresh_board()
	assert_false(state.has_player_marks(), "nothing on the board")
	assert_true(ClearBoardCommand.create(state).is_empty(), "so the command is empty")

	# A board holding only settled cells has nothing the player can clear either.
	state.put(4, CatGrid.Mark.WRONG)
	state.put(CatGrid.index_of(SIZE, 0, COLUMNS[0]), CatGrid.Mark.CAT)
	assert_false(state.has_player_marks(), "a settled cell is not the player's to clear")
	assert_true(ClearBoardCommand.create(state).is_empty(), "and still nothing to record")


func test_a_clear_survives_serialisation() -> void:
	var state := _fresh_board()
	var stack := UndoStack.new()
	stack.push(SetMarkCommand.create(state, 1, CatGrid.Mark.EXCLUDED), state)
	var before := state.marks_to_string()
	stack.push(ClearBoardCommand.create(state), state)

	var parsed: Variant = JSON.parse_string(JSON.stringify(stack.to_dict()))
	var restored := UndoStack.new()
	restored.from_dict(parsed as Dictionary)
	assert_eq(restored.depth(), 2, "both moves came back")
	restored.undo(state)
	assert_eq(state.marks_to_string(), before, "and the clear still reverts")


func test_a_cat_settles_its_cell() -> void:
	var state := _fresh_board()
	var cat := CatGrid.index_of(SIZE, 0, COLUMNS[0])
	assert_false(state.is_locked(cat), "an empty cell is open")
	state.put(cat, CatGrid.Mark.EXCLUDED)
	assert_false(state.is_locked(cat), "so is a cross -- the player may change their mind")
	state.put(cat, CatGrid.Mark.CAT)
	assert_true(state.is_locked(cat),
		"but a cat settles it: a wrong one is refused, so every cat on the board is right")
