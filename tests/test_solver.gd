extends TestCase
## Solver: solving, solution counting, and the rules that make a level unique.
##
## The fixture is the four-by-four tutorial board: teal, orange, green and rose
## regions, with the green region a single cell.
##
##       A B C B        A teal      solution: row 0 -> col 2
##       A B B B        B orange            row 1 -> col 0
##       A A D B        C green                row 2 -> col 3
##       A D D B        D rose                row 3 -> col 1

const TUTORIAL_REGIONS := "ABCBABBBAADBADDB"
const TUTORIAL_COLUMNS: Array[int] = [2, 0, 3, 1]
const SIZE := 4


func _regions() -> PackedByteArray:
	return CatGrid.regions_from_string(TUTORIAL_REGIONS)


func test_tutorial_board_parses() -> void:
	var regions := _regions()
	assert_eq(regions.size(), SIZE * SIZE, "sixteen cells")
	assert_eq(CatGrid.regions_to_string(regions), TUTORIAL_REGIONS, "region string round trips")
	assert_true(CatGrid.regions_are_connected(SIZE, regions), "every region is one connected blob")


func test_the_intended_placement_is_legal() -> void:
	assert_true(CatGrid.is_valid_solution(SIZE, _regions(), PackedByteArray(TUTORIAL_COLUMNS)),
		"one cat per row, column and colour, none touching")


func test_solver_finds_the_intended_placement() -> void:
	var found := CatSolver.solve(SIZE, _regions(), CatSolver.open_constraints(SIZE))
	assert_eq(Array(found), TUTORIAL_COLUMNS, "solver reproduces the tutorial answer")


func test_the_board_has_exactly_one_solution() -> void:
	var count := CatSolver.count_solutions(SIZE, _regions(), CatSolver.open_constraints(SIZE), 3)
	assert_eq(count, 1, "exactly one placement satisfies every rule")


func test_the_no_touching_rule_is_load_bearing() -> void:
	# [2, 3, 0, 1] satisfies one-per-row, one-per-column and one-per-colour. It is
	# only excluded because the cats in rows 0 and 1 would touch diagonally. Drop
	# the adjacency rule and this board would have two answers, which is how we
	# know the rule is really there.
	var rival := PackedByteArray([2, 3, 0, 1])
	var seen_cols := {}
	var seen_regions := {}
	var regions := _regions()
	for row in SIZE:
		seen_cols[rival[row]] = true
		seen_regions[regions[CatGrid.index_of(SIZE, row, rival[row])]] = true
	assert_eq(seen_cols.size(), SIZE, "the rival uses every column once")
	assert_eq(seen_regions.size(), SIZE, "the rival uses every colour once")
	assert_true(CatGrid.touching(0, rival[0], 1, rival[1]), "but its first two cats touch")
	assert_false(CatGrid.is_valid_solution(SIZE, regions, rival), "so it is not a legal placement")


func test_counting_stops_at_the_limit() -> void:
	# An unconstrained board with every cell its own colour has many placements.
	var regions := PackedByteArray()
	for row in SIZE:
		for col in SIZE:
			regions.append(row)
	assert_eq(CatSolver.count_solutions(SIZE, regions, CatSolver.open_constraints(SIZE), 2), 2,
		"the count short-circuits rather than enumerating everything")


func test_constraints_narrow_the_search() -> void:
	var regions := _regions()
	var allowed := CatSolver.open_constraints(SIZE)
	# Pin row 0 to the green cell, which is where it has to go anyway.
	allowed[0] = 1 << 2
	assert_eq(CatSolver.count_solutions(SIZE, regions, allowed, 3), 1, "still exactly one answer")

	# Now forbid it. Nothing can satisfy the green region, so there is no answer.
	allowed[0] = CatGrid.full_mask(SIZE) & ~(1 << 2)
	assert_eq(CatSolver.count_solutions(SIZE, regions, allowed, 3), 0,
		"excluding the only green cell makes the board unsolvable")


func test_adjacency_ban_covers_three_columns() -> void:
	CatGrid.ensure_tables()
	assert_eq(CatGrid.adjacency_ban(9, 4), (1 << 3) | (1 << 4) | (1 << 5), "middle column bans three")
	assert_eq(CatGrid.adjacency_ban(9, 0), (1 << 0) | (1 << 1), "the left edge bans two")
	assert_eq(CatGrid.adjacency_ban(9, 8), (1 << 7) | (1 << 8), "the right edge bans two")
