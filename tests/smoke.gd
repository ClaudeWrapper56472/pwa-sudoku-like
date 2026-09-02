extends Node
## End-to-end check of the running game.
##
##     ./run_smoke.sh
##
## The unit suites test the puzzle layer in isolation; this one boots the real
## scene tree, plays levels through the same signals the UI uses, and checks the
## progression, the lives and the save/resume path. It needs frames to run, so it
## lives outside run_tests.gd rather than pretending to be a synchronous suite.

var failures: PackedStringArray = []
var checks := 0
## GDScript lambdas capture locals by value, so signal results have to come back
## through a reference type.
var events := {"generated": false, "completed": -1, "failed": false, "wrong": 0, "hinted": false}


func _ready() -> void:
	_run()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("  FAIL  %s" % message)
	else:
		print("  ok    %s" % message)


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame

	var menu: Control = main.get_node("MenuScreen")
	var game: Control = main.get_node("GameScreen")
	check(menu.visible and not game.visible, "starts on the menu")

	# Sitting on the menu should already be building the level Play would start,
	# so the wait is spent before the player asks rather than after.
	var idle_waited := 0
	while GameState._prefetched == null and idle_waited < 3000:
		await tree.process_frame
		idle_waited += 1
	check(GameState._prefetched != null, "the menu builds the upcoming level while idle")
	check(GameState._prefetched_for == LevelLadder.FIRST_LEVEL, "which is level 1")
	check(SaveManager.current_level() == LevelLadder.FIRST_LEVEL, "a fresh save starts on level 1")

	GameState.generation_finished.connect(func(ok: bool) -> void: events["generated"] = ok)
	GameState.level_completed.connect(func(level: int, _s: int, _h: int) -> void: events["completed"] = level)
	GameState.level_failed.connect(func() -> void: events["failed"] = true)
	GameState.wrong_cat.connect(func(_i: int, _m: String) -> void: events["wrong"] += 1)
	GameState.hint_offered.connect(func(_i: int, _m: String, ok: bool) -> void: events["hinted"] = ok)

	# --- level 1 ------------------------------------------------------------
	menu.play_requested.emit()
	await tree.process_frame
	check(game.visible, "starting switches to the game screen")
	await _await_generation(tree)
	check(events["generated"], "generation completed")
	check(GameState.level_number == 1, "it is level 1")
	check(GameState.size() == LevelLadder.size_for(1), "on the board size the ladder asks for")
	check(GameState.tier == LevelLadder.tier_for(1), "at the tier the ladder asks for")
	check(GameState.lives_left == GameState.LIVES, "with a full set of lives")

	var level: CatLevel = GameState.board.level
	check(level != null and level.is_valid(), "the live level is legal")
	var board: SudokuBoard = game.get_node("%Board")
	check(board.get_node("Cells").get_child_count() == level.size * level.size, "board built")

	# --- dragging a run of crosses -----------------------------------------
	var row := level.size - 1
	var run: Array[int] = []
	for col in level.size:
		run.append(CatGrid.index_of(level.size, row, col))
	board.drag_started.emit(run[0])
	for index in run:
		board.drag_reached.emit(index)
	board.drag_ended.emit()
	await tree.process_frame

	var crossed := 0
	for index in run:
		if GameState.board.marks[index] == CatGrid.Mark.EXCLUDED:
			crossed += 1
	check(crossed == run.size(), "a drag crossed out the whole row")
	check(GameState.history.depth() == 1, "and it is one undo step, not %d" % run.size())

	GameState.undo()
	await tree.process_frame
	var still_crossed := 0
	for index in run:
		if GameState.board.marks[index] != CatGrid.Mark.EMPTY:
			still_crossed += 1
	check(still_crossed == 0, "one undo took the whole run back")
	GameState.redo()
	await tree.process_frame

	# A drag starting on a crossed cell erases instead.
	board.drag_started.emit(run[0])
	for index in run:
		board.drag_reached.emit(index)
	board.drag_ended.emit()
	await tree.process_frame
	var cleared := 0
	for index in run:
		if GameState.board.marks[index] == CatGrid.Mark.EMPTY:
			cleared += 1
	check(cleared == run.size(), "dragging back over a crossed run erases it")

	# A drag stays in the row it began in, so a wandering finger cannot wipe a
	# diagonal through the player's working.
	var stray := CatGrid.index_of(level.size, row - 1, 0)
	var stray_before: int = GameState.board.marks[stray]
	board.drag_started.emit(run[0])
	board.drag_reached.emit(stray)
	board.drag_ended.emit()
	await tree.process_frame
	check(GameState.board.marks[stray] == stray_before,
		"a drag cannot reach a cell outside the row it started in")
	check(GameState.board.marks[run[0]] == CatGrid.Mark.EXCLUDED,
		"while the cell it started on is still crossed")
	GameState.toggle_cross(run[0]) ## leave the board empty for the next section
	await tree.process_frame

	# --- clearing the board -------------------------------------------------
	# The drag above ended by erasing its own run, so put something back first.
	var clear_button: Button = game.get_node("%ClearButton")
	check(clear_button.disabled, "Clear is disabled while the board is empty")
	board.drag_started.emit(run[0])
	for index in run:
		board.drag_reached.emit(index)
	board.drag_ended.emit()
	await tree.process_frame
	check(not clear_button.disabled, "and available once there are marks")
	clear_button.pressed.emit()
	await tree.process_frame
	check(GameState.board.marks_to_string() == ".".repeat(level.size * level.size),
		"Clear wipes the board")
	check(clear_button.disabled, "and then disables itself")
	GameState.undo()
	await tree.process_frame
	check(GameState.board.marks_to_string() != ".".repeat(level.size * level.size),
		"one undo brings the whole board back")
	check(not clear_button.disabled, "and Clear is available again")
	clear_button.pressed.emit()
	await tree.process_frame

	# --- a wrong cat costs a life and is refused ---------------------------
	var wrong_cells: Array[int] = []
	for index in level.size * level.size:
		if not level.is_solution_cell(index):
			wrong_cells.append(index)
	board.cell_double_tapped.emit(wrong_cells[0])
	await tree.process_frame
	check(events["wrong"] == 1, "a wrong cat is reported")
	check(GameState.lives_left == GameState.LIVES - 1, "and costs a life")
	check(GameState.board.marks[wrong_cells[0]] == CatGrid.Mark.WRONG,
		"the cell is crossed out in red instead of taking the cat")
	check(GameState.board.is_locked(wrong_cells[0]), "and locked")

	# A locked cell ignores every kind of edit.
	GameState.toggle_cross(wrong_cells[0])
	GameState.clear_cell(wrong_cells[0])
	GameState.toggle_cat(wrong_cells[0])
	await tree.process_frame
	check(GameState.board.marks[wrong_cells[0]] == CatGrid.Mark.WRONG,
		"taps, clears and cats all leave it alone")
	check(GameState.lives_left == GameState.LIVES - 1,
		"and retrying a locked cell does not cost another life")

	# A drag passes over it without disturbing it.
	board.drag_started.emit(wrong_cells[0])
	board.drag_reached.emit(wrong_cells[0])
	board.drag_ended.emit()
	await tree.process_frame
	check(GameState.board.marks[wrong_cells[0]] == CatGrid.Mark.WRONG,
		"and a drag cannot wipe it either")
	check(GameState.history.depth() > 0 and not GameState.finished, "play continues")

	# --- a correct cat is permanent ----------------------------------------
	var first_cat := level.solution_index(0)
	board.cell_double_tapped.emit(first_cat)
	await tree.process_frame
	check(GameState.board.marks[first_cat] == CatGrid.Mark.CAT, "a correct cat is placed")
	check(GameState.board.is_locked(first_cat), "and the cell is settled")

	# A cat cannot turn out to be wrong, so there is nothing to take back.
	board.cell_double_tapped.emit(first_cat)
	board.cell_tapped.emit(first_cat)
	GameState.clear_cell(first_cat)
	GameState.undo()
	GameState.undo()
	await tree.process_frame
	check(GameState.board.marks[first_cat] == CatGrid.Mark.CAT,
		"taps, clears and undo all leave it in place")

	# --- hint ---------------------------------------------------------------
	var hint_button: Button = game.get_node("%HintButton")
	check(not hint_button.disabled, "Hint is available at the start of a level")
	GameState.use_hint()
	await tree.process_frame
	check(events["hinted"], "the hint system found a step")
	check(hint_button.disabled, "and there is only one per level")

	# A second attempt changes nothing, whether by button or keyboard.
	var cats_before: int = GameState.board.cats_placed()
	events["hinted"] = false
	GameState.use_hint()
	await tree.process_frame
	check(not events["hinted"], "a second hint is refused")
	check(GameState.hints_used == 1, "and is not counted against the player")
	check(GameState.board.cats_placed() == cats_before, "no extra cat appeared")

	# --- save and resume ----------------------------------------------------
	GameState.suspend()
	check(SaveManager.has_session(), "suspending writes the session")
	var saved_marks: String = GameState.board.marks_to_string()
	SaveManager.load_document()
	# Play and Continue are one button, so pressing it with a session on disk has to
	# resume rather than start the level over.
	menu.play_requested.emit()
	await tree.process_frame
	check(GameState.board.marks_to_string() == saved_marks, "pressing Play resumed the suspended board")
	check(GameState.level_number == 1, "on the same level")
	check(GameState.lives_left == GameState.LIVES - 1, "with the lives already spent")

	# --- finishing level 1 --------------------------------------------------
	for index in level.size * level.size:
		if level.is_solution_cell(index) and GameState.board.marks[index] != CatGrid.Mark.CAT:
			GameState.toggle_cat(index)
	await tree.process_frame
	var level_one_print: int = level.fingerprint()
	check(events["completed"] == 1, "placing the last cat completes level 1")
	# The next level is built in the background while the current one is played,
	# so by now it should already be waiting.
	var prefetch_waited := 0
	while GameState._prefetched == null and prefetch_waited < 3000:
		await tree.process_frame
		prefetch_waited += 1
	check(GameState._prefetched != null, "level 2 was built in the background")
	check(GameState._prefetched_for == 2, "and it is the level that comes next")
	check(SaveManager.has_seen(GameState.board.level.size, level_one_print), "the board just played is remembered")
	check(SaveManager.current_level() == 2, "and the player moves up to level 2")
	check(int(SaveManager.stats()["streak"]["current"]) == 1, "the run counter reads one")
	check(SaveManager.levels_completed() == 1, "one level is on the board")
	check(not SaveManager.has_session(), "a finished level clears the saved session")
	var result_panel: Control = game.get_node("%ResultPanel")
	check(result_panel.visible, "the result panel is shown")

	# --- level 2, lost ------------------------------------------------------
	events["generated"] = false
	GameState.start_level()
	await _await_generation(tree)
	check(GameState.level_number == 2, "level 2 started")
	check(not GameState.is_generating(), "with no wait, because it was already built")
	level = GameState.board.level
	check(level.fingerprint() != level_one_print, "and it is not the board we just solved")

	wrong_cells.clear()
	for index in level.size * level.size:
		if not level.is_solution_cell(index):
			wrong_cells.append(index)
	for attempt in GameState.LIVES:
		GameState.toggle_cat(wrong_cells[attempt])
		await tree.process_frame
	check(GameState.lives_left == 0, "three wrong cats spend every life")
	check(events["failed"], "and the level is lost")
	check(GameState.finished, "the board is closed")
	check(not SaveManager.has_session(), "a lost level clears the saved session")
	check(SaveManager.current_level() == 2, "losing does not advance the level")
	check(int(SaveManager.stats()["streak"]["current"]) == 0, "and it breaks the run")
	check(int(SaveManager.stats()["streak"]["best"]) == 1, "while keeping the best one")

	GameState.toggle_cat(level.solution_index(0))
	await tree.process_frame
	check(GameState.board.marks[level.solution_index(0)] != CatGrid.Mark.CAT,
		"the board is locked once the lives are gone")

	# --- retry the same level ----------------------------------------------
	var lost_regions := CatGrid.regions_to_string(level.regions)
	GameState.restart_level()
	await tree.process_frame
	check(GameState.level_number == 2, "retry stays on level 2")
	check(CatGrid.regions_to_string(GameState.board.level.regions) == lost_regions,
		"and gives back the same puzzle rather than rerolling it")
	check(GameState.lives_left == GameState.LIVES, "with the lives restored")
	check(GameState.hints_left() == GameState.HINTS_PER_LEVEL, "and the hint back")
	check(GameState.board.marks_to_string() == ".".repeat(level.size * level.size),
		"on a cleared board")
	check(not GameState.finished, "play resumes")

	# --- growing the board forgets the smaller ones -------------------------
	events["generated"] = false
	GameState.start_level(13)
	await _await_generation(tree)
	check(GameState.size() == LevelLadder.size_for(13), "level 13 uses the ladder's board size")
	check(not SaveManager.has_seen(LevelLadder.size_for(1), level_one_print),
		"moving up a size forgets the fingerprints of smaller boards")
	check(SaveManager.has_seen(GameState.board.level.size, GameState.board.level.fingerprint()),
		"while remembering the board just served")

	print("")
	if failures.is_empty():
		print("SMOKE PASSED  %d checks" % checks)
		tree.quit(0)
	else:
		print("SMOKE FAILED  %d of %d checks" % [failures.size(), checks])
		tree.quit(1)


## Generation is threaded, but a level served from the bank can finish inside the
## same frame -- so poll rather than awaiting a signal that may already have fired.
func _await_generation(tree: SceneTree) -> void:
	var frames := 0
	while not events["generated"] and frames < 3000:
		await tree.process_frame
		frames += 1
