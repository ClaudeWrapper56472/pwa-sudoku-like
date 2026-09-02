extends TestCase
## Save format: migration from v1 and defensive normalization.
##
## These are pure-function tests on SaveMigration rather than on the SaveManager
## autoload, so nothing here writes to user:// and clobbers a real save.

const REGIONS := "ABCBABBBAADBADDB"
const COLUMNS := "2031"
const SIZE := 4


func _v1_document() -> Dictionary:
	var marks: Array = []
	marks.resize(SIZE * SIZE)
	marks.fill(0)
	marks[0] = 1 ## a cross
	marks[2] = 2 ## a cat
	return {
		"version": 1,
		"size": SIZE,
		"regions": REGIONS,
		"solution": COLUMNS,
		"seed": 4242,
		"marks": marks,
		"elapsed": 128.5,
		"mistakes": 1,
		"difficulty": "Hard",
		"stats": {
			"easy": {"played": 5, "won": 4, "best": 90},
			"hard": {"played": 3, "won": 1, "best": 420},
		},
	}


func test_v1_migrates_to_the_current_version() -> void:
	var migrated := SaveMigration.migrate(_v1_document())
	assert_eq(int(migrated["version"]), SaveMigration.CURRENT_VERSION, "version was bumped")
	assert_true(migrated.has("session"), "document has a session")
	assert_true(migrated.has("stats"), "document has stats")
	assert_true(migrated["stats"].has("progress"), "and a progression to resume from")


func test_v1_marks_become_characters() -> void:
	var session: Dictionary = SaveMigration.migrate_v1_to_v2(_v1_document())["session"]
	var marks := String(session["board"]["marks"])
	assert_eq(marks.length(), SIZE * SIZE, "one character per cell")
	assert_eq(marks[0], "x", "a cross became x")
	assert_eq(marks[2], "c", "a cat became c")
	assert_eq(marks[1], ".", "an empty cell became a dot")


func test_a_migrated_session_loads_into_a_board() -> void:
	var session: Dictionary = SaveMigration.migrate_v1_to_v2(_v1_document())["session"]
	var state := PuzzleState.new()
	assert_true(state.from_dict(session["board"]), "migrated board loads")
	assert_eq(state.size(), SIZE, "board size survived")
	assert_eq(state.marks[2], CatGrid.Mark.CAT, "the player's cat survived")
	assert_true(state.level.is_valid(), "and the level it references is legal")


func test_v1_session_fields_survive_the_first_step() -> void:
	# Tested against the single step rather than the whole chain: a later step
	# drops the session entirely, which would hide whether this one worked.
	var session: Dictionary = SaveMigration.migrate_v1_to_v2(_v1_document())["session"]
	assert_eq(int(session["tier"]), CatGrid.Tier.HARD, "difficulty name became a tier value")
	assert_eq(float(session["elapsed"]), 128.5, "elapsed time carried over")
	assert_eq(int(session["mistakes"]), 1, "mistake count carried over")
	assert_eq(int(session["hints"]), 0, "hint count defaults to zero")
	assert_true((session["history"]["undo"] as Array).is_empty(), "v1 had no history, so it starts empty")


func test_v1_stats_are_rekeyed_by_tier() -> void:
	var stats: Dictionary = SaveMigration.migrate(_v1_document())["stats"]
	var tiers: Dictionary = stats["tiers"]
	assert_eq(int(tiers[str(CatGrid.Tier.EASY)]["started"]), 5, "easy plays carried over")
	assert_eq(int(tiers[str(CatGrid.Tier.EASY)]["won"]), 4, "easy wins carried over")
	assert_eq(int(tiers[str(CatGrid.Tier.HARD)]["best_time"]), 420, "hard best time carried over")
	assert_eq(int(tiers[str(CatGrid.Tier.MEDIUM)]["started"]), 0, "tiers absent from v1 default to zero")
	assert_true(tiers.has(str(CatGrid.Tier.EXPERT)), "every tier is present after migration")
	assert_eq(int(stats["streak"]["current"]), 0, "streak starts at zero")


## v2 was played under different rules, so its saved board and history cannot be
## trusted wholesale.
func test_v2_lifts_wrong_cats_and_drops_the_history() -> void:
	var level := CatGenerator.generate(CatGrid.Tier.EASY, 100)
	var marks := ""
	var wrong := -1
	for index in level.size * level.size:
		if level.is_solution_cell(index):
			marks += "c"
		elif wrong < 0 and CatGrid.row_of(level.size, index) == 0:
			marks += "c" ## a cat v2 tolerated and v3 does not
			wrong = index
		else:
			marks += "."

	var document := {
		"version": 2,
		"session": {
			"tier": level.tier,
			"seed": level.seed,
			"board": {"level": level.to_dict(), "marks": marks},
			"elapsed": 10.0,
			"mistakes": 1,
			"hints": 0,
			"selected": -1,
			"history": {"undo": [{"t": "mark", "i": 0, "m": 1, "o": 0, "a": [1, 2, 3]}], "redo": []},
		},
		"stats": SaveMigration.empty_stats(),
	}
	assert_true(wrong >= 0, "the fixture really has a wrong cat in it")

	var migrated := SaveMigration.migrate_v2_to_v3(document)
	var board: Dictionary = migrated["session"]["board"]
	var cleaned := String(board["marks"])
	assert_eq(cleaned[wrong], ".", "the wrong cat was lifted")
	for index in level.size * level.size:
		if level.is_solution_cell(index):
			assert_eq(cleaned[index], "c", "correct cats were kept")
	assert_true((migrated["session"]["history"]["undo"] as Array).is_empty(),
		"the history was dropped rather than replayed under new rules")


## v3 had no concept of a level, so the chain has to invent one. Total wins is
## the closest honest estimate.
func test_v3_derives_a_level_from_past_wins() -> void:
	var document := SaveMigration.normalize({"version": 3, "stats": SaveMigration.empty_stats()})
	document["version"] = 3
	document["stats"]["tiers"][str(CatGrid.Tier.EASY)]["won"] = 4
	document["stats"]["tiers"][str(CatGrid.Tier.HARD)]["won"] = 1
	document["session"] = {"tier": 2, "board": {}}

	var migrated := SaveMigration.migrate_v3_to_v4(document)
	assert_eq(int(migrated["stats"]["progress"]["level"]), LevelLadder.FIRST_LEVEL + 5,
		"five wins puts the player five levels in")
	assert_eq(int(migrated["stats"]["progress"]["completed"]), 5, "and credits five finished levels")
	assert_true((migrated["session"] as Dictionary).is_empty(),
		"the old one-off puzzle is dropped rather than mislabelled with a level")


func test_the_whole_chain_runs_from_v1() -> void:
	var migrated := SaveMigration.migrate(_v1_document())
	assert_eq(int(migrated["version"]), SaveMigration.CURRENT_VERSION, "reached the current version")
	var tiers: Dictionary = migrated["stats"]["tiers"]
	assert_eq(int(tiers[str(CatGrid.Tier.EASY)]["won"]), 4, "stats survived every step")
	# v1 recorded 4 easy wins and 1 hard win.
	assert_eq(int(migrated["stats"]["progress"]["level"]), LevelLadder.FIRST_LEVEL + 5,
		"and became a level to resume on")


func test_current_version_passes_through_unchanged() -> void:
	var document := SaveMigration.empty_document()
	document["session"] = {"tier": 1, "seed": 7}
	var migrated := SaveMigration.migrate(document)
	assert_eq(int(migrated["session"]["seed"]), 7, "a current document is left alone")


func test_unknown_and_future_versions_are_discarded() -> void:
	var future := SaveMigration.empty_document()
	future["version"] = SaveMigration.CURRENT_VERSION + 1
	future["session"] = {"tier": 3}
	var migrated := SaveMigration.migrate(future)
	assert_true((migrated["session"] as Dictionary).is_empty(), "a newer save is not guessed at")
	assert_eq(int(migrated["version"]), SaveMigration.CURRENT_VERSION, "and we fall back to a clean document")

	var junk := SaveMigration.migrate({"hello": "world"})
	assert_true((junk["session"] as Dictionary).is_empty(), "a document with no version is discarded")


func test_normalize_fills_missing_fields() -> void:
	var partial := {"version": SaveMigration.CURRENT_VERSION, "stats": {"tiers": {"0": {"won": 3}}}}
	var fixed := SaveMigration.normalize(partial)
	var entry: Dictionary = fixed["stats"]["tiers"]["0"]
	assert_eq(int(entry["won"]), 3, "existing fields are kept")
	assert_eq(int(entry["started"]), 0, "missing fields get defaults")
	assert_true(fixed["stats"].has("streak"), "streak block is added")
	assert_true(fixed.has("session"), "session block is added")


func test_a_live_session_survives_a_json_round_trip() -> void:
	# The shape GameState.to_dict() produces has to survive JSON, which turns
	# every number into a float and every dictionary key into a string.
	var level := CatGenerator.generate(CatGrid.Tier.EASY, 100)
	var state := PuzzleState.new()
	state.setup(level)
	var stack := UndoStack.new()
	stack.push(SetMarkCommand.create(state, 0, CatGrid.Mark.EXCLUDED), state)
	stack.push(SetMarkCommand.create(state, level.solution_index(0), CatGrid.Mark.CAT), state)
	var marked := state.marks_to_string()

	var session := {
		"tier": level.tier,
		"seed": level.seed,
		"board": state.to_dict(),
		"elapsed": 61.25,
		"mistakes": 0,
		"hints": 0,
		"selected": 0,
		"history": stack.to_dict(),
	}
	var parsed: Variant = JSON.parse_string(JSON.stringify(session))
	assert_true(parsed is Dictionary, "session serializes to JSON")
	var reloaded: Dictionary = parsed

	var restored := PuzzleState.new()
	assert_true(restored.from_dict(reloaded["board"]), "board reloads")
	assert_eq(restored.marks_to_string(), marked, "marks match")
	assert_eq(CatGrid.regions_to_string(restored.level.regions),
		CatGrid.regions_to_string(level.regions), "regions match")

	var restored_stack := UndoStack.new()
	restored_stack.from_dict(reloaded["history"])
	assert_eq(restored_stack.depth(), 2, "both moves came back")
	restored_stack.undo(restored)
	restored_stack.undo(restored)
	assert_eq(restored.marks_to_string(), ".".repeat(level.size * level.size),
		"unwinding the restored history returns to an empty board")


func test_a_dated_streak_is_started_over() -> void:
	# Saves written when the streak counted consecutive days carry last_win_day.
	# The number means levels now, so it cannot be carried across.
	var document := SaveMigration.empty_document()
	document["stats"]["streak"] = {"current": 7, "best": 9, "last_win_day": "2026-08-30"}
	var fixed := SaveMigration.normalize(document)
	var streak: Dictionary = fixed["stats"]["streak"]
	assert_false(streak.has("last_win_day"), "the date field is dropped")
	assert_eq(int(streak["current"]), 0, "and the run starts over")
	assert_eq(int(streak["best"]), 0, "including the best, which was earned in days")


func test_a_level_streak_is_left_alone() -> void:
	var document := SaveMigration.empty_document()
	document["stats"]["streak"] = {"current": 4, "best": 11}
	var streak: Dictionary = SaveMigration.normalize(document)["stats"]["streak"]
	assert_eq(int(streak["current"]), 4, "an undated streak is already levels")
	assert_eq(int(streak["best"]), 11, "and keeps its best run")
