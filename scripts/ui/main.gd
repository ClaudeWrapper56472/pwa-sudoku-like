extends Control
## Root scene and screen router.
##
## Both screens exist from the start and are shown or hidden, rather than being
## loaded and freed. There are only two of them and they are cheap, and keeping
## them alive means the board does not rebuild its 81 cells every time the player
## glances at the menu.

@onready var _menu: MenuScreen = $MenuScreen
@onready var _game: GameScreen = $GameScreen


func _ready() -> void:
	_menu.play_requested.connect(_on_play_requested)
	_game.exit_requested.connect(_show_menu)
	GameState.level_failed.connect(_on_game_over)
	_show_menu()


func _show_menu() -> void:
	_menu.visible = true
	_game.visible = false
	_menu.refresh()
	# Build the next board while the player is looking at the menu, so pressing
	# Play is instant even on the big boards where generating takes seconds.
	GameState.prefetch_upcoming()


func _show_game() -> void:
	_menu.visible = false
	_game.visible = true


## Resuming is just what "play" means when there is something to resume. Keeping
## that decision here rather than in the menu means the menu never has to ask the
## save file anything except what to write on the button.
func _on_play_requested() -> void:
	_show_game()
	if not GameState.resume_saved_game():
		GameState.start_level()


func _on_game_over() -> void:
	# The result panel is already up; the menu just needs to forget the session.
	_menu.refresh()
