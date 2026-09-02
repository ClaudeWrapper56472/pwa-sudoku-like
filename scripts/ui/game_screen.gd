class_name GameScreen
extends Control
## The playing screen: board, toolbar and the panels that cover them.
##
## This is the only script that knows all the pieces exist, and its whole job is
## translating between them: a tap on the board becomes a GameState call, a
## GameState signal becomes a label update. Nothing here holds game state of its
## own, so the screen can be closed and reopened mid-level without losing
## anything.

signal exit_requested()

@onready var _board: SudokuBoard = %Board
@onready var _tier_label: Label = %TierLabel
@onready var _time_label: Label = %TimeLabel
@onready var _lives: LivesDisplay = %Lives
@onready var _progress_label: Label = %ProgressLabel
@onready var _status_label: Label = %StatusLabel
@onready var _undo_button: Button = %UndoButton
@onready var _redo_button: Button = %RedoButton
@onready var _clear_button: Button = %ClearButton
@onready var _hint_button: Button = %HintButton
@onready var _back_button: Button = %BackButton
@onready var _loading_panel: Control = %LoadingPanel
@onready var _loading_label: Label = %LoadingLabel
@onready var _result_panel: Control = %ResultPanel
@onready var _result_cat: CatMascot = %ResultCat
@onready var _result_title: Label = %ResultTitle
@onready var _result_detail: Label = %ResultDetail
@onready var _again_button: Button = %AgainButton
@onready var _result_menu_button: Button = %ResultMenuButton

var _status_timer := 0.0
## Which button the result card is offering: the next level, or this one again.
var _retry_mode := false


func _ready() -> void:
	_board.cell_tapped.connect(_on_cell_tapped)
	_board.cell_double_tapped.connect(_on_cell_double_tapped)
	_board.drag_started.connect(GameState.begin_cross_run)
	_board.drag_reached.connect(GameState.extend_cross_run)
	_board.drag_ended.connect(GameState.end_cross_run)

	_back_button.pressed.connect(_on_back_pressed)
	_undo_button.pressed.connect(GameState.undo)
	_redo_button.pressed.connect(GameState.redo)
	_clear_button.pressed.connect(GameState.clear_board)
	_hint_button.pressed.connect(GameState.use_hint)
	_again_button.pressed.connect(_on_play_again_pressed)
	_result_menu_button.pressed.connect(_on_back_pressed)

	GameState.generation_started.connect(_on_generation_started)
	GameState.generation_finished.connect(_on_generation_finished)
	GameState.level_loaded.connect(_on_level_loaded)
	GameState.time_changed.connect(_on_time_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.wrong_cat.connect(_on_wrong_cat)
	GameState.cats_changed.connect(_on_cats_changed)
	GameState.cells_changed.connect(_on_cells_changed)
	GameState.history_changed.connect(_on_history_changed)
	GameState.hint_offered.connect(_on_hint_offered)
	GameState.hints_changed.connect(_on_hints_changed)
	GameState.level_completed.connect(_on_level_completed)
	GameState.level_failed.connect(_on_level_failed)

	_loading_panel.visible = false
	_result_panel.visible = false
	_status_label.text = ""
	_clear_button.disabled = true


func _process(delta: float) -> void:
	if _status_timer <= 0.0:
		return
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status_label.text = ""


## Keyboard play, which mostly matters while developing: the board is quicker to
## drive from the keyboard than from the mouse.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or _result_panel.visible or _loading_panel.visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	if key.keycode == KEY_SPACE or key.keycode == KEY_X:
		GameState.toggle_cross(GameState.selected)
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_C:
		GameState.toggle_cat(GameState.selected)
	elif key.keycode == KEY_BACKSPACE or key.keycode == KEY_DELETE:
		GameState.clear_cell(GameState.selected)
	elif key.keycode == KEY_H:
		GameState.use_hint()
	elif key.keycode == KEY_Z and (key.ctrl_pressed or key.meta_pressed):
		if key.shift_pressed:
			GameState.redo()
		else:
			GameState.undo()
	elif key.keycode == KEY_Y and key.ctrl_pressed:
		GameState.redo()
	elif key.keycode == KEY_LEFT:
		GameState.move_selection(0, -1)
	elif key.keycode == KEY_RIGHT:
		GameState.move_selection(0, 1)
	elif key.keycode == KEY_UP:
		GameState.move_selection(-1, 0)
	elif key.keycode == KEY_DOWN:
		GameState.move_selection(1, 0)
	elif key.keycode == KEY_ESCAPE:
		_on_back_pressed()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_cell_tapped(index: int) -> void:
	GameState.select(index)
	GameState.toggle_cross(index)


func _on_cell_double_tapped(index: int) -> void:
	GameState.select(index)
	GameState.toggle_cat(index)


## Disabled when there is nothing of the player's to wipe, so it never again
## looks like a button that does nothing.
func _on_cells_changed(_indices: PackedInt32Array) -> void:
	_clear_button.disabled = not GameState.board.has_player_marks()


func _on_generation_started(level: int) -> void:
	_result_panel.visible = false
	_loading_panel.visible = true
	_loading_label.text = "Setting up level %d..." % level


func _on_generation_finished(success: bool) -> void:
	_loading_panel.visible = false
	if not success:
		_show_status("Could not build a level. Try again.")


func _on_level_loaded() -> void:
	_result_panel.visible = false
	_tier_label.text = LevelLadder.describe(GameState.level_number)
	if LevelLadder.is_step_up(GameState.level_number):
		_show_status("Bigger board from here on \u2014 take your time.")
	else:
		_show_status("Tap or drag along a row to cross out. Double-tap to place a cat.")


func _on_time_changed(seconds: int) -> void:
	_time_label.text = "%d:%02d" % [seconds / 60, seconds % 60]


func _on_lives_changed(remaining: int, total: int) -> void:
	_lives.set_lives(remaining, total)


func _on_wrong_cat(_index: int, message: String) -> void:
	_show_status(message)


func _on_cats_changed(placed: int, total: int) -> void:
	_progress_label.text = "%d / %d cats" % [placed, total]


func _on_history_changed(can_undo: bool, can_redo: bool) -> void:
	_undo_button.disabled = not can_undo
	_redo_button.disabled = not can_redo


func _on_hint_offered(_index: int, message: String, _success: bool) -> void:
	_show_status(message)


func _on_hints_changed(remaining: int) -> void:
	_hint_button.disabled = remaining <= 0


func _on_level_completed(level: int, seconds: int, hints: int) -> void:
	_retry_mode = false
	_result_title.text = "Level %d done" % level
	var parts := PackedStringArray(["%d:%02d" % [seconds / 60, seconds % 60]])
	var lost := GameState.mistakes()
	if lost > 0:
		parts.append("%d wrong cat%s" % [lost, "" if lost == 1 else "s"])
	if hints > 0:
		parts.append("%d hint%s" % [hints, "" if hints == 1 else "s"])
	_result_detail.text = "   ".join(parts)
	_again_button.text = "Level %d" % (level + 1)
	_result_panel.visible = true


func _on_level_failed() -> void:
	_retry_mode = true
	_result_title.text = "Out of lives"
	_result_detail.text = "Three cats in the wrong spot. Try again."
	_again_button.text = "Try again"
	_result_panel.visible = true


func _on_play_again_pressed() -> void:
	_result_panel.visible = false
	if _retry_mode:
		GameState.restart_level()
	else:
		GameState.start_level()


func _on_back_pressed() -> void:
	if not GameState.finished:
		GameState.suspend()
	exit_requested.emit()


func _show_status(message: String) -> void:
	_status_label.text = message
	_status_timer = 3.5
