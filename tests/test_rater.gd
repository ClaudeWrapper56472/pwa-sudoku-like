extends TestCase
## Rater: tier assignment and the guarantee that backs it.

const TIERS := [CatGrid.Tier.EASY, CatGrid.Tier.MEDIUM, CatGrid.Tier.HARD, CatGrid.Tier.EXPERT]
const SEEDS := {
	CatGrid.Tier.EASY: 100,
	CatGrid.Tier.MEDIUM: 237,
	CatGrid.Tier.HARD: 374,
	CatGrid.Tier.EXPERT: 511,
}

const TUTORIAL_REGIONS := "ABCBABBBAADBADDB"
const TUTORIAL_COLUMNS: Array[int] = [2, 0, 3, 1]


func _tutorial() -> CatLevel:
	var level := CatLevel.new()
	level.size = 4
	level.regions = CatGrid.regions_from_string(TUTORIAL_REGIONS)
	level.columns = PackedByteArray(TUTORIAL_COLUMNS)
	return level


func test_the_tutorial_board_falls_to_simple_deductions() -> void:
	# Its green region is a single cell, so the first placement is free and the
	# rest follows. That is exactly what a tutorial should be.
	var rating := CatRater.rate(_tutorial())
	assert_true(rating.solved, "logical solver finishes the tutorial board")
	assert_eq(rating.tier, CatGrid.Tier.EASY, "and it rates Easy")


func test_generator_hits_the_requested_tier() -> void:
	for tier in TIERS:
		var level := CatGenerator.generate(tier, SEEDS[tier])
		assert_eq(level.tier, tier,
			"requested %s and got %s" % [CatGrid.tier_name(tier), CatGrid.tier_name(level.tier)])
		assert_true(level.rating.solved,
			"%s rating is backed by a logical solve" % CatGrid.tier_name(tier))


func test_rated_levels_are_solvable_by_their_own_tier() -> void:
	# The core promise of the tier system: a level labelled Hard can be finished
	# using nothing harder than the techniques Hard allows.
	for tier in TIERS:
		var level := CatGenerator.generate(tier, SEEDS[tier])
		var cap := CatRater.cap_for_tier(level.tier)
		var capped := CatRater.rate(level, cap)
		assert_true(capped.solved,
			"%s level solves with techniques capped at %s"
				% [CatGrid.tier_name(level.tier), CatRater.TECHNIQUE_NAMES[cap]])
		assert_true(level.rating.hardest <= cap, "hardest technique used stays within the tier cap")


func test_tier_boundaries_are_tight() -> void:
	# The other half of the promise: a level labelled Hard genuinely needs more
	# than Medium's techniques, otherwise the tier is inflated.
	for tier in [CatGrid.Tier.MEDIUM, CatGrid.Tier.HARD, CatGrid.Tier.EXPERT]:
		var level := CatGenerator.generate(tier, SEEDS[tier])
		if level.tier != tier:
			continue
		var lower_cap := CatRater.cap_for_tier(tier - 1)
		var weaker := CatRater.rate(level, lower_cap)
		assert_false(weaker.solved,
			"%s level is not solvable with only %s and below"
				% [CatGrid.tier_name(tier), CatRater.TECHNIQUE_NAMES[lower_cap]])


func test_tier_mapping_covers_every_technique() -> void:
	for technique in CatRater.Technique.values():
		var tier := CatRater.tier_for(technique)
		assert_true(tier >= CatGrid.Tier.EASY and tier <= CatGrid.Tier.EXPERT,
			"%s maps to a real tier" % CatRater.TECHNIQUE_NAMES[technique])
		assert_true(technique <= CatRater.cap_for_tier(tier),
			"%s is inside the cap of the tier it maps to" % CatRater.TECHNIQUE_NAMES[technique])
	assert_eq(CatRater.tier_for(-1), CatGrid.Tier.EASY, "an already solved board rates Easy")


func test_hint_points_at_a_correct_cell() -> void:
	for tier in TIERS:
		var level := CatGenerator.generate(tier, SEEDS[tier])
		var marks := PackedByteArray()
		marks.resize(level.size * level.size)
		var hint := CatRater.find_hint(level, marks)
		assert_true(hint.ok, "hint found a step on a fresh %s level" % CatGrid.tier_name(tier))
		if hint.ok:
			assert_true(level.is_solution_cell(hint.index),
				"hint points at a cell that really holds a cat")


func test_hint_follows_the_players_own_crosses() -> void:
	var level := CatGenerator.generate(CatGrid.Tier.MEDIUM, SEEDS[CatGrid.Tier.MEDIUM])
	var marks := PackedByteArray()
	marks.resize(level.size * level.size)
	# Cross out every cell of row 0 except the one that holds the cat. The hint
	# should now be that cell, reached by the player's own reasoning.
	var answer := level.columns[0]
	for col in level.size:
		if col != answer:
			marks[CatGrid.index_of(level.size, 0, col)] = CatGrid.Mark.EXCLUDED
	var hint := CatRater.find_hint(level, marks)
	assert_true(hint.ok, "hint available")
	assert_eq(hint.index, CatGrid.index_of(level.size, 0, answer),
		"hint takes the player's crosses as given")


func test_hint_detects_a_broken_board() -> void:
	var level := CatGenerator.generate(CatGrid.Tier.EASY, SEEDS[CatGrid.Tier.EASY])
	var marks := PackedByteArray()
	marks.resize(level.size * level.size)
	# Cross out the whole of row 0, which no legal board can survive.
	for col in level.size:
		marks[CatGrid.index_of(level.size, 0, col)] = CatGrid.Mark.EXCLUDED
	var hint := CatRater.find_hint(level, marks)
	assert_false(hint.ok, "hint reports the board is broken rather than guessing")


func test_placing_a_cat_rules_out_what_it_should() -> void:
	var level := _tutorial()
	var board := CatRater.Board.new(level)
	board.place(0, 2)
	assert_false(board.is_alive(0, 0), "the rest of the row is out")
	assert_false(board.is_alive(3, 2), "the rest of the column is out")
	assert_false(board.is_alive(1, 1), "the diagonal neighbour is out")
	assert_false(board.is_alive(1, 3), "the other diagonal neighbour is out")
	assert_true(board.is_alive(1, 0), "a cell two columns away survives")
