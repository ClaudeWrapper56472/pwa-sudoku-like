class_name CatGenerator
extends RefCounted
## Builds levels for a requested difficulty tier.
##
## Sudoku generation starts from a filled board and removes clues. This puzzle
## has no clues to remove -- the *regions are the puzzle*. So generation runs the
## other way round: pick where the cats go first, then carve regions around them
## so that placement is the only one that works.
##
## 1. Draw a random legal placement: one cat per row and column, none touching.
## 2. Seed one region on each cat and grow all N regions outward until they
##      partition the board. Every region then contains exactly one cat by
##      construction, so the placement is guaranteed to be *a* solution.
## 3. Check it is the *only* solution. Region growth is random, so it usually is
##      not on the first try -- a fatter region gives the solver more room and lets
##      a second arrangement slip through.
## 4. Rate it, and reject if the rating misses the requested tier.
##
## Regrowing regions is much cheaper than redrawing the placement, so a failed
## attempt retries growth several times before giving up on the placement.

const DEFAULT_MAX_ATTEMPTS := 400
const GROWTH_RETRIES := 12

## Board sizes each tier draws from. Size and difficulty are related but not the
## same thing -- a 9x9 can fall to nothing but forced singles -- so the rater
## still decides, and this only sets the shape of the board.
const TIER_SIZES := {
	CatGrid.Tier.EASY: [5, 6],
	CatGrid.Tier.MEDIUM: [6, 7],
	CatGrid.Tier.HARD: [7, 8],
	CatGrid.Tier.EXPERT: [8, 9],
}


## Pass `fixed_size` to pin the board size; leave it 0 to draw from the tier's
## own range. The level ladder pins it, because the size a player sees needs to
## climb predictably rather than wander inside a tier.
## `seen` is a set of fingerprints to avoid, so the same board is not generated
## twice for the same player.
static func generate(tier: int, seed: int = 0, max_attempts: int = DEFAULT_MAX_ATTEMPTS,
		fixed_size: int = 0, seen: Dictionary = {}, min_region_cells: int = 1) -> CatLevel:
	CatGrid.ensure_tables()
	var rng := RandomNumberGenerator.new()
	var actual_seed := seed if seed != 0 else _random_seed()
	rng.seed = actual_seed

	var sizes: Array = TIER_SIZES.get(tier, [7])
	var best: CatLevel = null
	# A level that hits the tier but has been served before. Kept as a last
	# resort: repeating a board is a small annoyance, failing to produce one at
	# all is a broken game.
	var repeat: CatLevel = null
	for attempt in max_attempts:
		# Only draw when the size is free, so a pinned size does not shift the
		# random sequence and change which levels a seed produces.
		var size: int = fixed_size if fixed_size > 0 else sizes[rng.randi_range(0, sizes.size() - 1)]
		var level := _attempt(size, tier, rng, min_region_cells)
		if level == null:
			continue
		level.seed = actual_seed
		level.attempts = attempt + 1
		if level.tier == tier:
			if not seen.has(level.fingerprint()):
				return level
			if repeat == null:
				repeat = level
			continue
		if best == null or absi(level.tier - tier) < absi(best.tier - tier):
			best = level
	if repeat != null:
		repeat.attempts = max_attempts
		return repeat
	if best != null:
		best.attempts = max_attempts
	return best


static func _attempt(size: int, tier: int, rng: RandomNumberGenerator,
		min_region_cells: int = 1) -> CatLevel:
	var columns := random_placement(size, rng)
	if columns.is_empty():
		return null

	for retry in GROWTH_RETRIES:
		var regions := grow_regions(size, columns, rng, min_region_cells)
		if regions.is_empty():
			continue
		if not refine_regions(size, regions, columns, rng, 40, min_region_cells):
			continue
		if not CatGrid.regions_are_connected(size, regions):
			continue

		var level := CatLevel.new()
		level.size = size
		level.regions = regions
		level.columns = columns
		var rating := CatRater.rate(level)
		level.rating = rating
		# A level the logical solver cannot finish needs something outside our
		# technique set. We cannot honestly label it, so push it out of range.
		level.tier = rating.tier if rating.solved else -99
		return level
	return null


## A random legal placement: one cat per row and column, none touching.
static func random_placement(size: int, rng: RandomNumberGenerator) -> PackedByteArray:
	var columns := PackedByteArray()
	columns.resize(size)
	if _place_row(0, size, rng, 0, -2, columns):
		return columns
	return PackedByteArray()


static func _place_row(row: int, size: int, rng: RandomNumberGenerator, used_cols: int,
		previous_col: int, columns: PackedByteArray) -> bool:
	if row == size:
		return true
	var options := CatGrid.full_mask(size) & ~used_cols
	if previous_col >= 0:
		options &= ~CatGrid.adjacency_ban(size, previous_col)

	var choices: Array[int] = []
	while options != 0:
		var low := options & -options
		options &= options - 1
		choices.append(CatGrid.first_bit_index(low))
	_shuffle(choices, rng)

	for col in choices:
		columns[row] = col
		if _place_row(row + 1, size, rng, used_cols | (1 << col), col, columns):
			return true
	return false


## Grows N regions outward from the cats until they partition the board.
##
## Growth picks a random *frontier cell* and hands it to one of its neighbouring
## regions, which means a region with more edge grows faster. That unevenness is
## the point. An earlier version always extended the smallest region, which gave
## beautifully balanced blobs and terrible puzzles -- every board had six or more
## solutions. Uneven regions constrain far harder: a colour squeezed into two or
## three cells forces a placement almost immediately, and that cascades.
## `min_cells` forces every colour to cover at least that many squares. A colour
## of exactly one square is a free placement -- the cat can only go there -- so
## banning them removes the easiest foothold on the board.
static func grow_regions(size: int, columns: PackedByteArray, rng: RandomNumberGenerator,
		min_cells: int = 1) -> PackedByteArray:
	var cells := size * size
	var regions := PackedByteArray()
	regions.resize(cells)
	regions.fill(0xFF)
	var counts := PackedInt32Array()
	counts.resize(size)
	for row in size:
		regions[CatGrid.index_of(size, row, columns[row])] = row
		counts[row] = 1

	var remaining := cells - size

	# First bring every colour up to the minimum, smallest first. This is the
	# balanced growth that makes for weak puzzles, which is why it stops the
	# moment the minimum is met and hands over to the uneven growth below.
	while remaining > 0:
		var smallest := -1
		for region in size:
			if counts[region] >= min_cells:
				continue
			if smallest < 0 or counts[region] < counts[smallest]:
				smallest = region
		if smallest < 0:
			break
		var room := _free_neighbours_of(size, regions, smallest)
		if room.is_empty():
			return PackedByteArray() ## boxed in by its neighbours; the caller retries
		var claimed: int = room[rng.randi_range(0, room.size() - 1)]
		regions[claimed] = smallest
		counts[smallest] += 1
		remaining -= 1

	while remaining > 0:
		var frontier := _frontier_cells(size, regions)
		if frontier.is_empty():
			return PackedByteArray()
		var cell: int = frontier[rng.randi_range(0, frontier.size() - 1)]
		var owners: Array[int] = []
		for neighbour in CatGrid.orthogonal_neighbours(size, cell):
			if regions[neighbour] != 0xFF:
				owners.append(regions[neighbour])
		regions[cell] = owners[rng.randi_range(0, owners.size() - 1)]
		remaining -= 1
	return regions


## Unassigned cells orthogonally touching one particular region.
static func _free_neighbours_of(size: int, regions: PackedByteArray, region: int) -> Array[int]:
	var out: Array[int] = []
	for index in regions.size():
		if regions[index] != 0xFF:
			continue
		for neighbour in CatGrid.orthogonal_neighbours(size, index):
			if regions[neighbour] == region:
				out.append(index)
				break
	return out


## Unassigned cells touching at least one assigned cell.
static func _frontier_cells(size: int, regions: PackedByteArray) -> Array[int]:
	var out: Array[int] = []
	for index in regions.size():
		if regions[index] != 0xFF:
			continue
		for neighbour in CatGrid.orthogonal_neighbours(size, index):
			if regions[neighbour] != 0xFF:
				out.append(index)
				break
	return out


## Repairs a level that has more than one solution.
##
## Blind retries are wasteful, and there is a targeted move available. Take a
## rival placement and any row where it disagrees with ours. Its cat there sits in
## some colour; re-colour that one cell to any *neighbouring* colour and the rival
## instantly uses that colour twice, so it dies. Our own placement is untouched,
## because the cell we move is never one of our cats.
##
## Each pass therefore kills at least the rival it was shown. New rivals can
## appear, so it loops -- but it converges in a handful of passes where random
## regrowth would take hundreds of attempts.
static func refine_regions(size: int, regions: PackedByteArray, columns: PackedByteArray,
		rng: RandomNumberGenerator, max_passes: int = 40, min_cells: int = 1) -> bool:
	for pass_index in max_passes:
		var rival := CatSolver.find_rival(size, regions, columns)
		if rival.is_empty():
			return true

		var rows: Array[int] = []
		for row in size:
			if rival[row] != columns[row]:
				rows.append(row)
		_shuffle(rows, rng)

		var moved := false
		for row in rows:
			var cell := CatGrid.index_of(size, row, rival[row])
			if columns[CatGrid.row_of(size, cell)] == CatGrid.col_of(size, cell):
				continue ## never move one of our own cats
			var from_region := regions[cell]
			var options: Array[int] = []
			for neighbour in CatGrid.orthogonal_neighbours(size, cell):
				var candidate := regions[neighbour]
				if candidate != from_region and not options.has(candidate):
					options.append(candidate)
			_shuffle(options, rng)

			for to_region in options:
				regions[cell] = to_region
				# Moving a cell out must not break the donor apart, nor shrink it
				# below the minimum -- a repair that reintroduces a one-square
				# colour would undo the very thing the caller asked for.
				if CatGrid.region_is_connected(size, regions, from_region) \
						and _region_size(regions, from_region) >= min_cells:
					moved = true
					break
				regions[cell] = from_region
			if moved:
				break
		if not moved:
			return false
	return CatSolver.count_solutions(size, regions, CatSolver.open_constraints(size), 2) == 1


static func _region_size(regions: PackedByteArray, region: int) -> int:
	var n := 0
	for value in regions:
		if value == region:
			n += 1
	return n


## Fisher-Yates against our own RNG. Array.shuffle() draws from the global
## generator, which would break seed reproducibility.
static func _shuffle(items: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := items[i]
		items[i] = items[j]
		items[j] = swap


static func _random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(rng.seed)
