extends Node
## Screenshot helper. Not part of the suite; run it when you want to look at the
## thing rather than assert about it.
##
##     godot --path . res://tests/Shot.tscn

const OUT_DIR := "user://shots"


func _ready() -> void:
	_run()


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var main: Node = load("res://scenes/Main.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var menu: Control = main.get_node("MenuScreen")
	var game: Control = main.get_node("GameScreen")

	menu.refresh()
	await _settle(tree, 4)
	_capture("menu")

	# Straight to a chosen level, skipping the routing the menu would do.
	menu.visible = false
	game.visible = true

	for level in [1, 13]:
		GameState.start_level(level)
		await _await_generation(tree)
		await _settle(tree, 4)
		_populate()
		await _settle(tree, 4)
		_capture("board_level_%d" % level)

	# A lost board: three wrong cats, then the reveal.
	GameState.start_level(7)
	await _await_generation(tree)
	await _settle(tree, 4)
	_populate()
	var level: CatLevel = GameState.board.level
	var spent := 0
	for index in level.size * level.size:
		if spent >= GameState.LIVES:
			break
		if not level.is_solution_cell(index) and GameState.board.marks[index] == CatGrid.Mark.EMPTY:
			GameState.toggle_cat(index)
			spent += 1
	await _settle(tree, 4)
	_capture("board_lost")

	print("shots in %s" % ProjectSettings.globalize_path(OUT_DIR))
	tree.quit(0)


## Plays part of the level so a screenshot shows cats, crosses and the selection.
func _populate() -> void:
	var level: CatLevel = GameState.board.level
	for row in mini(3, level.size):
		GameState.toggle_cat(level.solution_index(row))
	for index in level.size * level.size:
		if CatGrid.row_of(level.size, index) < 3 and not level.is_solution_cell(index):
			GameState.toggle_cross(index)
	GameState.select(CatGrid.index_of(level.size, level.size - 2, 1))


func _await_generation(tree: SceneTree) -> void:
	var frames := 0
	while GameState.is_generating() and frames < 3000:
		await tree.process_frame
		frames += 1


func _settle(tree: SceneTree, frames: int) -> void:
	for i in frames:
		await tree.process_frame
	await RenderingServer.frame_post_draw


func _capture(name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, name])
