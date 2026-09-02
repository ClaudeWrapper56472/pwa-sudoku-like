extends TestCase
## The level ladder: what board each level number asks for.


func test_the_first_level_is_the_gentlest_one() -> void:
	assert_eq(LevelLadder.tier_for(LevelLadder.FIRST_LEVEL), CatGrid.Tier.EASY, "level 1 is Easy")
	assert_eq(LevelLadder.size_for(LevelLadder.FIRST_LEVEL), LevelLadder.FIRST_SIZE,
		"on the smallest board")


func test_the_board_grows_at_the_advertised_levels() -> void:
	var expected := {1: 5, 11: 6, 26: 7, 46: 8, 70: 9, 100: 10}
	for level in expected:
		assert_eq(LevelLadder.size_for(level), expected[level],
			"level %d is a %dx%d" % [level, expected[level], expected[level]])
		assert_eq(LevelLadder.size_for(level - 1), expected[level] - 1 if level > 1 else 5,
			"and level %d is still the size below" % (level - 1))


func test_each_size_lasts_longer_than_the_one_before() -> void:
	var previous := 0
	for step in LevelLadder.LEVELS_PER_SIZE.size() - 1:
		var span: int = LevelLadder.LEVELS_PER_SIZE[step]
		assert_true(span >= previous, "size %d lasts at least as long as the one before"
			% (LevelLadder.FIRST_SIZE + step))
		previous = span


func test_the_board_never_shrinks() -> void:
	var last_size := 0
	for level in range(1, 400):
		var size := LevelLadder.size_for(level)
		assert_true(size >= last_size, "level %d is not smaller than level %d" % [level, level - 1])
		assert_true(size >= CatGrid.MIN_SIZE and size <= CatGrid.MAX_SIZE,
			"level %d has a board the generator can build" % level)
		last_size = size


func test_every_size_ramps_from_easy_to_expert() -> void:
	var start := LevelLadder.FIRST_LEVEL
	for step in LevelLadder.LEVELS_PER_SIZE.size():
		var span: int = LevelLadder.LEVELS_PER_SIZE[step]
		assert_eq(LevelLadder.tier_for(start), CatGrid.Tier.EASY,
			"the first level of a %dx%d is Easy" % [LevelLadder.FIRST_SIZE + step,
				LevelLadder.FIRST_SIZE + step])
		assert_eq(LevelLadder.tier_for(start + span - 1), CatGrid.Tier.EXPERT,
			"and the last is Expert")
		var last_tier := -1
		for level in range(start, start + span):
			var tier := LevelLadder.tier_for(level)
			assert_true(tier >= last_tier, "level %d is not easier than the one before" % level)
			last_tier = tier
		start += span


func test_the_ladder_stops_growing_but_the_levels_do_not() -> void:
	var final_level := LevelLadder.final_size_level()
	assert_eq(final_level, 100, "the largest board starts at level 100")
	assert_eq(LevelLadder.size_for(final_level), LevelLadder.LAST_SIZE, "and it is the largest")
	for level in [final_level + 200, final_level + 5000]:
		assert_eq(LevelLadder.size_for(level), LevelLadder.LAST_SIZE,
			"level %d stays on the largest board" % level)
		assert_eq(LevelLadder.tier_for(level), CatGrid.Tier.EXPERT, "at the hardest tier")


func test_step_ups_are_flagged_once_per_size() -> void:
	assert_false(LevelLadder.is_step_up(LevelLadder.FIRST_LEVEL), "the first level is not a step up")
	var steps := 0
	for level in range(1, LevelLadder.final_size_level() + 1):
		if LevelLadder.is_step_up(level):
			steps += 1
	assert_eq(steps, LevelLadder.LEVELS_PER_SIZE.size() - 1, "one step up per size after the first")


func test_next_step_up_points_at_the_next_bigger_board() -> void:
	assert_eq(LevelLadder.next_step_up(1), 11, "from level 1 the next bigger board is level 11")
	assert_eq(LevelLadder.next_step_up(10), 11, "and from the last 5x5 it is the very next level")
	assert_eq(LevelLadder.next_step_up(70), 100, "from the first 9x9 it is level 100")
	assert_eq(LevelLadder.next_step_up(100), 0, "on the largest board there is nothing left to reach")
	assert_eq(LevelLadder.next_step_up(9999), 0, "and that stays true forever")


func test_levels_below_one_are_clamped() -> void:
	# Nothing should produce these, but a corrupt save might.
	for level in [0, -1, -999]:
		assert_eq(LevelLadder.size_for(level), LevelLadder.FIRST_SIZE,
			"level %d falls back to the first board" % level)
		assert_eq(LevelLadder.tier_for(level), CatGrid.Tier.EASY, "and the first tier")


func test_combinations_cover_what_the_ladder_asks_for() -> void:
	# Every board a player can be served has to be in the content build list,
	# otherwise the bank has a hole that shows up as a stutter on their device.
	var specs := LevelLadder.combinations()
	assert_true(specs.size() > 0, "there are combinations to build")
	for level in range(1, LevelLadder.NO_SINGLE_CELL_REGIONS_FROM + 20):
		var wanted := Vector3i(LevelLadder.tier_for(level), LevelLadder.size_for(level),
			LevelLadder.min_region_cells(level))
		assert_true(specs.has(wanted), "the board for level %d is in the build list" % level)



func test_the_description_names_the_level_and_the_board() -> void:
	var text := LevelLadder.describe(100)
	assert_true(text.contains("Level 100"), "the level number is in there")
	assert_true(text.contains("10"), "and the board size")


func test_single_square_colours_are_banned_late_on() -> void:
	var boundary := LevelLadder.NO_SINGLE_CELL_REGIONS_FROM
	assert_eq(LevelLadder.min_region_cells(boundary - 1), 1,
		"a one-square colour is allowed right up to the boundary")
	assert_eq(LevelLadder.min_region_cells(boundary), 2, "and banned from it onward")
	assert_eq(LevelLadder.min_region_cells(boundary + 5000), 2, "for good")
	assert_eq(LevelLadder.min_region_cells(1), 1, "early levels are unaffected")


func test_combinations_include_the_late_game_rule() -> void:
	var specs := LevelLadder.combinations()
	var boundary := LevelLadder.NO_SINGLE_CELL_REGIONS_FROM
	var wanted := Vector3i(LevelLadder.tier_for(boundary), LevelLadder.size_for(boundary), 2)
	assert_true(specs.has(wanted),
		"the content build knows to produce boards with no single squares")
	for spec in specs:
		assert_true(spec.z >= 1 and spec.z <= 2, "every spec asks for a sane minimum")
