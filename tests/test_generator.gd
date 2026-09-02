extends TestCase
## Generator: legality, uniqueness, region shape and seed reproducibility.

const TIERS := [CatGrid.Tier.EASY, CatGrid.Tier.MEDIUM, CatGrid.Tier.HARD, CatGrid.Tier.EXPERT]
const SEEDS := [4242, 90210]


func test_every_generated_level_is_legal_and_unique() -> void:
	for tier in TIERS:
		for seed in SEEDS:
			var level := CatGenerator.generate(tier, seed)
			var label := CatGrid.tier_name(tier)
			if not assert_true(level != null, "generator returned a level for %s" % label):
				continue
			assert_true(CatGrid.is_valid_solution(level.size, level.regions, level.columns),
				"%s seed %d stores a legal placement" % [label, seed])
			assert_true(CatGrid.regions_are_connected(level.size, level.regions),
				"%s seed %d has connected regions" % [label, seed])
			assert_eq(CatSolver.count_solutions(level.size, level.regions,
					CatSolver.open_constraints(level.size), 2), 1,
				"%s seed %d has exactly one solution" % [label, seed])
			assert_eq(Array(CatSolver.solve(level.size, level.regions,
					CatSolver.open_constraints(level.size))), Array(level.columns),
				"%s seed %d solves back to the stored placement" % [label, seed])


func test_region_count_matches_board_size() -> void:
	for tier in TIERS:
		var level := CatGenerator.generate(tier, 1234 + tier)
		var seen := {}
		for region in level.regions:
			seen[region] = true
		assert_eq(seen.size(), level.size,
			"%s has one region per row" % CatGrid.tier_name(tier))
		for region in seen:
			assert_true(int(region) < level.size, "region ids stay inside the board size")


func test_every_region_holds_exactly_one_cat() -> void:
	var level := CatGenerator.generate(CatGrid.Tier.HARD, 555)
	var used := {}
	for row in level.size:
		var region := level.region_at(row, level.columns[row])
		assert_false(used.has(region), "region %d is used once" % region)
		used[region] = true
	assert_eq(used.size(), level.size, "every region is used")


func test_same_seed_reproduces_the_same_level() -> void:
	for tier in TIERS:
		var first := CatGenerator.generate(tier, 31337)
		var second := CatGenerator.generate(tier, 31337)
		var label := CatGrid.tier_name(tier)
		assert_eq(first.size, second.size, "%s seed 31337 reproduces the board size" % label)
		assert_eq(CatGrid.regions_to_string(first.regions), CatGrid.regions_to_string(second.regions),
			"%s seed 31337 reproduces the regions" % label)
		assert_eq(Array(first.columns), Array(second.columns),
			"%s seed 31337 reproduces the placement" % label)
		assert_eq(first.attempts, second.attempts, "%s attempt count is deterministic" % label)


func test_different_seeds_produce_different_levels() -> void:
	var a := CatGenerator.generate(CatGrid.Tier.MEDIUM, 11)
	var b := CatGenerator.generate(CatGrid.Tier.MEDIUM, 12)
	assert_ne(CatGrid.regions_to_string(a.regions), CatGrid.regions_to_string(b.regions),
		"seeds 11 and 12 carve different regions")


func test_random_placement_obeys_the_rules() -> void:
	var rng := RandomNumberGenerator.new()
	for seed in [1, 99, 12345]:
		rng.seed = seed
		for size in range(CatGrid.MIN_SIZE, CatGrid.MAX_SIZE + 1):
			var columns := CatGenerator.random_placement(size, rng)
			assert_eq(columns.size(), size, "placement covers every row at size %d" % size)
			var seen := {}
			for row in size:
				seen[columns[row]] = true
				if row > 0:
					assert_false(CatGrid.touching(row, columns[row], row - 1, columns[row - 1]),
						"no two cats touch at size %d" % size)
			assert_eq(seen.size(), size, "one cat per column at size %d" % size)


func test_regions_partition_the_board() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var size := 7
	var columns := CatGenerator.random_placement(size, rng)
	var regions := CatGenerator.grow_regions(size, columns, rng)
	assert_eq(regions.size(), size * size, "every cell got a region")
	var counts := PackedInt32Array()
	counts.resize(size)
	for region in regions:
		assert_true(region < size, "no stray region id")
		counts[region] += 1
	for region in size:
		assert_true(counts[region] >= 1, "region %d is not empty" % region)
	assert_true(CatGrid.regions_are_connected(size, regions), "regions are connected")


func test_a_fingerprint_identifies_a_board() -> void:
	var a := CatGenerator.generate(CatGrid.Tier.MEDIUM, 4242)
	var b := CatGenerator.generate(CatGrid.Tier.MEDIUM, 4242)
	assert_eq(a.fingerprint(), b.fingerprint(), "the same board fingerprints the same")
	var c := CatGenerator.generate(CatGrid.Tier.MEDIUM, 999)
	assert_ne(a.fingerprint(), c.fingerprint(), "a different board fingerprints differently")


func test_a_seen_board_is_not_served_again() -> void:
	# Same seed twice normally reproduces the same level. Telling the generator it
	# has already been served must push it to a different one.
	var first := CatGenerator.generate(CatGrid.Tier.MEDIUM, 4242)
	var seen := {first.fingerprint(): true}
	var second := CatGenerator.generate(CatGrid.Tier.MEDIUM, 4242, CatGenerator.DEFAULT_MAX_ATTEMPTS, 0, seen)
	assert_true(second != null, "a replacement was found")
	assert_ne(second.fingerprint(), first.fingerprint(), "and it is a different board")
	assert_eq(second.tier, CatGrid.Tier.MEDIUM, "still at the requested tier")
	assert_true(CatSolver.has_unique_solution(second.size, second.regions,
		CatSolver.open_constraints(second.size)), "and still a real puzzle")


func test_a_pinned_size_is_honoured() -> void:
	for size in [5, 7, 9]:
		var level := CatGenerator.generate(CatGrid.Tier.HARD, 777, 200, size)
		if level != null:
			assert_eq(level.size, size, "asked for %dx%d and got it" % [size, size])


func test_a_minimum_colour_size_is_respected() -> void:
	# A one-square colour is a free placement, so the later levels forbid them.
	for size in [7, 9]:
		var level := CatGenerator.generate(CatGrid.Tier.EXPERT, 8080 + size,
			CatGenerator.DEFAULT_MAX_ATTEMPTS, size, {}, 2)
		if not assert_true(level != null, "generated a %dx%d with no single squares" % [size, size]):
			continue
		assert_true(level.smallest_region() >= 2,
			"every colour covers at least two squares (smallest was %d)" % level.smallest_region())
		assert_true(level.is_valid(), "and the board is still legal and connected")
		assert_eq(CatSolver.count_solutions(level.size, level.regions,
				CatSolver.open_constraints(level.size), 2), 1,
			"and still has exactly one solution")


func test_without_the_rule_single_squares_are_allowed() -> void:
	# Not that they must appear -- only that nothing rejects them by default.
	var level := CatGenerator.generate(CatGrid.Tier.EASY, 100)
	assert_true(level.smallest_region() >= 1, "a colour always covers at least one square")
