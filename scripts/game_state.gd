extends Node
## Autoload: the running game.
##
## Everything the UI needs to know lives here, and everything it needs to say
## comes back as a signal. No scene reaches into another scene's node tree -- the
## board, the toolbar and the top bar each connect to the signals they care about
## and know nothing about each other.
##
## There is no difficulty menu. The player is on a level, the level decides the
## board, and finishing one moves them up. LevelLadder owns that mapping;
## SaveManager owns the number.
##
## Generation runs on a worker thread. Carving regions that admit exactly one
## solution is a rejection loop, so the main thread stays free to draw the
## "finding a level" overlay.

signal generation_started(level: int)
signal generation_finished(success: bool)
signal level_loaded()
signal cells_changed(indices: PackedInt32Array)
signal selection_changed(index: int)
signal cats_changed(placed: int, total: int)
signal lives_changed(remaining: int, total: int)
signal wrong_cat(index: int, message: String)
signal time_changed(seconds: int)
signal history_changed(can_undo: bool, can_redo: bool)
signal hint_offered(index: int, message: String, success: bool)
signal hints_changed(remaining: int)
signal level_completed(level: int, seconds: int, hints: int)
signal level_failed()

## Wrong cats allowed before the level has to be started again.
const LIVES := 3

## Hints available per level. One: enough to unstick somebody who has genuinely
## run out of ideas, not enough to solve the board with.
const HINTS_PER_LEVEL := 1

var board := PuzzleState.new()
var history := UndoStack.new()

var level_number := LevelLadder.FIRST_LEVEL
var tier: int = CatGrid.Tier.EASY
var seed := 0
var selected := -1
var lives_left := LIVES
var hints_used := 0
var elapsed := 0.0
var playing := false
var finished := false

var _thread: Thread = null
var _last_whole_second := -1

## The next level, built while the player works on the current one.
##
## Carving a unique 10x10 Expert board takes seconds, and the shipped bank holds
## only so many -- past level 142 or so it runs dry and every level is generated
## live. Rather than make the player watch a spinner, the next board is built in
## the background the moment the current one loads. By the time they finish, it is
## already waiting.
var _prefetch_thread: Thread = null
var _prefetched: CatLevel = null
var _prefetched_for := 0
## Which level the prefetch *should* be building, if it drifted.
var _prefetch_wanted := 0
var _run: CrossRunCommand = null
## The row a drag began in. A drag never leaves it.
var _run_row := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	board.cells_changed.connect(_on_board_cells_changed)
	history.changed.connect(_on_history_changed)
	SaveManager.save_requested.connect(_on_save_requested)


func _process(delta: float) -> void:
	if not playing or finished:
		return
	elapsed += delta
	var whole := int(elapsed)
	if whole != _last_whole_second:
		_last_whole_second = whole
		time_changed.emit(whole)


func _exit_tree() -> void:
	_join_thread()
	_join_prefetch()


func size() -> int:
	return board.size()


func mistakes() -> int:
	return LIVES - lives_left


func hints_left() -> int:
	return maxi(HINTS_PER_LEVEL - hints_used, 0)


# --- Starting, retrying and resuming ----------------------------------------

func is_generating() -> bool:
	return _thread != null


## Generates the level the player is currently on.
func start_level(requested_level: int = 0) -> void:
	if is_generating():
		return
	level_number = requested_level if requested_level > 0 else SaveManager.current_level()

	# Built already, while the last level was being played.
	if _prefetched != null and _prefetched_for == level_number:
		var ready := _prefetched
		_prefetched = null
		_prefetched_for = 0
		generation_started.emit(level_number)
		_accept(ready)
		return

	playing = false
	generation_started.emit(level_number)
	# Snapshotted here, on the main thread. The worker must not reach into
	# SaveManager while the tree is running.
	var seen := SaveManager.seen_fingerprints(LevelLadder.size_for(level_number))
	_thread = Thread.new()
	_thread.start(_generate_worker.bind(level_number, seen))


## Puts the same board back the way it started. Losing means starting this level
## over, not being handed a different one -- the point is to solve *this* puzzle,
## and swapping it out would let a player reroll their way past anything awkward.
func restart_level() -> void:
	if board.level == null or is_generating():
		return
	_reset_for(board.level)


## Runs on the worker thread. Nothing here may touch the scene tree, so the result
## is handed back to the main thread before anything is done with it.
func _generate_worker(target_level: int, seen: Dictionary) -> void:
	_on_generated.call_deferred(_build(target_level, seen))


## Takes a precomputed level when the bank has one, and falls back to generating.
## Safe to call from any thread: it reads nothing but its arguments.
static func _build(target_level: int, seen: Dictionary) -> CatLevel:
	var tier := LevelLadder.tier_for(target_level)
	var size := LevelLadder.size_for(target_level)
	var min_region := LevelLadder.min_region_cells(target_level)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var level := LevelBank.take(tier, rng, size, seen, min_region)
	if level == null:
		level = CatGenerator.generate(tier, 0, CatGenerator.DEFAULT_MAX_ATTEMPTS,
			size, seen, min_region)
	return level


func _on_generated(level: CatLevel) -> void:
	_join_thread()
	if level == null:
		generation_finished.emit(false)
		return
	_accept(level)


func _accept(level: CatLevel) -> void:
	_reset_for(level)
	SaveManager.record_seen(level.size, level.fingerprint())
	SaveManager.record_started(level.tier)
	generation_finished.emit(true)
	_start_prefetch(level_number + 1)


## Starts building the level the player would get if they pressed Play right now,
## so sitting on the menu is not a dead moment. There is nothing to build when a
## suspended level is waiting to be resumed.
func prefetch_upcoming() -> void:
	if SaveManager.has_session():
		return
	_start_prefetch(SaveManager.current_level())


## Begins building the level after this one. Does nothing while a build is already
## in flight -- that one re-evaluates what is wanted when it lands.
func _start_prefetch(next_level: int) -> void:
	_prefetch_wanted = next_level
	if _prefetch_thread != null:
		return ## in flight; it checks again when it lands
	if _prefetched != null and _prefetched_for == next_level:
		return
	_prefetched = null
	_prefetched_for = 0
	var seen := SaveManager.seen_fingerprints(LevelLadder.size_for(next_level))
	_prefetch_thread = Thread.new()
	_prefetch_thread.start(_prefetch_worker.bind(next_level, seen))


func _prefetch_worker(next_level: int, seen: Dictionary) -> void:
	_on_prefetched.call_deferred(_build(next_level, seen), next_level)


func _on_prefetched(level: CatLevel, for_level: int) -> void:
	_join_prefetch()
	# The player may have gone somewhere else while this was building. Throw it
	# away and start on what is actually wanted now.
	if for_level != _prefetch_wanted:
		_prefetched = null
		_prefetched_for = 0
		_start_prefetch(_prefetch_wanted)
		return
	_prefetched = level
	_prefetched_for = for_level



func _reset_for(level: CatLevel) -> void:
	_run = null
	_run_row = -1
	board.setup(level)
	history.clear()
	tier = level.tier
	seed = level.seed
	selected = -1
	lives_left = LIVES
	hints_used = 0
	elapsed = 0.0
	_last_whole_second = -1
	finished = false
	playing = true
	_announce()


func resume_saved_game() -> bool:
	var session := SaveManager.session()
	if session.is_empty():
		return false
	var restored := PuzzleState.new()
	if not restored.from_dict(session.get("board", {})):
		return false

	_run = null
	_run_row = -1
	board.setup(restored.level)
	board.marks = restored.marks
	history.clear()
	history.from_dict(session.get("history", {}))

	level_number = maxi(int(session.get("level", LevelLadder.FIRST_LEVEL)), LevelLadder.FIRST_LEVEL)
	tier = int(session.get("tier", CatGrid.Tier.EASY))
	seed = int(session.get("seed", 0))
	lives_left = clampi(int(session.get("lives", LIVES)), 1, LIVES)
	hints_used = int(session.get("hints", 0))
	elapsed = float(session.get("elapsed", 0.0))
	selected = int(session.get("selected", -1))
	_last_whole_second = -1
	finished = false
	playing = true
	_announce()
	_start_prefetch(level_number + 1)
	return true


func _announce() -> void:
	level_loaded.emit()
	selection_changed.emit(selected)
	lives_changed.emit(lives_left, LIVES)
	hints_changed.emit(hints_left())
	cats_changed.emit(board.cats_placed(), size())
	time_changed.emit(int(elapsed))
	history_changed.emit(history.can_undo(), history.can_redo())


## Leaves the level running in the save file so the menu can offer Continue.
func suspend() -> void:
	playing = false
	SaveManager.flush()


func abandon() -> void:
	playing = false
	finished = true
	SaveManager.clear_session()


# --- Player input -----------------------------------------------------------

func select(index: int) -> void:
	if index == selected:
		return
	selected = index
	selection_changed.emit(selected)


func move_selection(delta_row: int, delta_column: int) -> void:
	var n := size()
	if n == 0:
		return
	if selected < 0:
		select(0)
		return
	var row := clampi(CatGrid.row_of(n, selected) + delta_row, 0, n - 1)
	var col := clampi(CatGrid.col_of(n, selected) + delta_column, 0, n - 1)
	select(CatGrid.index_of(n, row, col))


## A plain tap cycles empty and crossed. Crossing out is the bulk of play, so it
## gets the cheap gesture. It is purely a note to yourself -- crossing the wrong
## cell costs nothing and is never checked.
func toggle_cross(index: int) -> void:
	if not _can_edit() or board.is_locked(index):
		return
	var next := CatGrid.Mark.EMPTY if board.marks[index] != CatGrid.Mark.EMPTY \
		else CatGrid.Mark.EXCLUDED
	_push(SetMarkCommand.create(board, index, next))


## Placing a cat is the committing move, and the only one that can cost a life.
##
## A wrong cat is refused rather than placed: the cell flashes, a life goes, and
## the board stays clean. Leaving it there would block completion and mean the
## player had to tidy up after their own mistake, which is busywork on top of a
## penalty.
func toggle_cat(index: int) -> void:
	if not _can_edit() or board.is_locked(index):
		return
	if not board.level.is_solution_cell(index):
		_refuse_cat(index)
		return
	# Placed directly rather than through the undo stack. A correct cat is a fact,
	# not an opinion -- it cannot turn out to be wrong later, so there is nothing
	# to take back. The undo stack is left holding only crosses, which are exactly
	# the marks a player might change their mind about.
	board.put(index, CatGrid.Mark.CAT)
	board.notify(PackedInt32Array([index]))
	_check_completion()


## A drag across a run of cells. The target mark is decided from the cell the drag
## starts on -- from an empty cell it crosses out, from a crossed cell it erases --
## and every cell the drag reaches is set to that same mark. Fixing the target up
## front is what stops a drag flickering cells on and off as it wanders back over
## its own path.
##
## A drag stays in the row it started in. A finger crossing a 10x10 board wanders
## by a cell or two without meaning to, and a gesture that can wipe a diagonal
## through your working is one you have to aim carefully -- which defeats the
## point of it being the quick gesture.
##
## Settled cells are skipped entirely: a drag cannot disturb a cat or a red cross.
func begin_cross_run(index: int) -> void:
	if not _can_edit() or _run != null or board.is_locked(index):
		return
	var mark := board.marks[index]
	if mark == CatGrid.Mark.CAT:
		return
	select(index)
	_run_row = CatGrid.row_of(size(), index)
	_run = CrossRunCommand.create(
		CatGrid.Mark.EMPTY if mark == CatGrid.Mark.EXCLUDED else CatGrid.Mark.EXCLUDED)
	extend_cross_run(index)


func extend_cross_run(index: int) -> void:
	if _run == null or CatGrid.row_of(size(), index) != _run_row:
		return
	if _run.extend(board, index):
		board.notify(PackedInt32Array([index]))


## Ends the gesture and records it as one undo step. The cells are already on the
## board, so the command is filed rather than re-applied.
func end_cross_run() -> void:
	if _run == null:
		return
	var run := _run
	_run = null
	_run_row = -1
	if run.is_empty():
		return
	history.push_applied(run, board)


func clear_cell(index: int) -> void:
	if not _can_edit() or board.is_locked(index) or board.marks[index] == CatGrid.Mark.EMPTY:
		return
	_push(SetMarkCommand.create(board, index, CatGrid.Mark.EMPTY))


## Wipes the player's own marks in one step. Lives, the clock and the red cells
## are untouched: this is for starting your reasoning over, not the level.
func clear_board() -> void:
	if not _can_edit():
		return
	var command := ClearBoardCommand.create(board)
	if command.is_empty():
		return
	_push(command)


func undo() -> void:
	if finished:
		return
	history.undo(board)
	_check_completion()


func redo() -> void:
	if finished:
		return
	history.redo(board)
	_check_completion()


## Places the cat the logical solver says is next, once per level. Works from the board as it stands, so it also catches a board the
## player has already made unsolvable with their crosses.
func use_hint() -> void:
	if finished or not playing:
		return
	if hints_left() <= 0:
		hint_offered.emit(-1, "No hints left on this level.", false)
		return
	var hint := CatRater.find_hint(board.level, board.marks)
	if not hint.ok:
		hint_offered.emit(-1, hint.message, false)
		return
	hints_used += 1
	hints_changed.emit(hints_left())
	select(hint.index)
	board.put(hint.index, CatGrid.Mark.CAT)
	board.notify(PackedInt32Array([hint.index]))
	hint_offered.emit(hint.index, hint.message, true)
	_check_completion()


func _push(command: SudokuCommand) -> void:
	history.push(command, board)


func _can_edit() -> bool:
	return playing and not finished and board.level != null


## Every wrong cell is one the rules already ruled out, so there is no such thing
## as a placement that is only wrong in hindsight. That is what makes spending a
## life fair rather than arbitrary.
func _refuse_cat(index: int) -> void:
	lives_left = maxi(lives_left - 1, 0)
	# Marked directly rather than pushed as a command. The cross is not a move the
	# player made, and undoing their way out of it would make the lost life
	# meaningless -- the same reason a spent life never comes back.
	board.put(index, CatGrid.Mark.WRONG)
	board.notify(PackedInt32Array([index]))
	wrong_cat.emit(index, board.explain_wrong(index))
	lives_changed.emit(lives_left, LIVES)
	if lives_left > 0:
		return
	finished = true
	playing = false
	SaveManager.record_loss()
	SaveManager.clear_session()
	level_failed.emit()


func _check_completion() -> void:
	if finished or not board.is_complete():
		return
	finished = true
	playing = false
	var seconds := int(elapsed)
	SaveManager.record_win(level_number, tier, seconds, mistakes(), hints_used)
	level_completed.emit(level_number, seconds, hints_used)


# --- Plumbing ---------------------------------------------------------------

func _on_board_cells_changed(indices: PackedInt32Array) -> void:
	cells_changed.emit(indices)
	cats_changed.emit(board.cats_placed(), size())


func _on_history_changed(can_undo: bool, can_redo: bool) -> void:
	history_changed.emit(can_undo, can_redo)


## Deliberately not gated on `playing`. suspend() stops the clock before asking
## for a save, and a paused level is exactly the one worth writing.
func _on_save_requested() -> void:
	if finished or board.level == null:
		return
	SaveManager.submit_session(to_dict())


func to_dict() -> Dictionary:
	return {
		"level": level_number,
		"tier": tier,
		"seed": seed,
		"board": board.to_dict(),
		"elapsed": elapsed,
		"lives": lives_left,
		"hints": hints_used,
		"selected": selected,
		"history": history.to_dict(),
	}


func _join_prefetch() -> void:
	if _prefetch_thread == null:
		return
	if _prefetch_thread.is_started():
		_prefetch_thread.wait_to_finish()
	_prefetch_thread = null


func _join_thread() -> void:
	if _thread == null:
		return
	if _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
