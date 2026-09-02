class_name CatSolver
extends RefCounted
## Counts solutions, with a limit so uniqueness checks stop at two.
##
## The search walks one row at a time, which is the whole trick. One cat per row
## means row order is a free choice and every row must be filled exactly once, so
## there is no cell-selection heuristic to get right. Used columns and used
## regions ride along as bitmasks, and the no-touching rule reduces to "not within
## one column of the row above" -- two cats more than one row apart can never
## touch, so nothing else needs remembering.
##
## `allowed[row]` is a bitmask of columns still permitted in that row. That single
## input covers every caller: the generator passes wide-open rows, uniqueness
## checks after a player's move pass rows narrowed by their cats and crosses, and
## the hint system passes the same thing.


## Every column permitted in every row.
static func open_constraints(size: int) -> PackedInt32Array:
	var allowed := PackedInt32Array()
	allowed.resize(size)
	allowed.fill(CatGrid.full_mask(size))
	return allowed


## Number of solutions, capped at `limit`.
static func count_solutions(size: int, regions: PackedByteArray, allowed: PackedInt32Array,
		limit: int = 2) -> int:
	CatGrid.ensure_tables()
	return _search(0, size, regions, allowed, 0, 0, -2, limit)


static func has_unique_solution(size: int, regions: PackedByteArray, allowed: PackedInt32Array) -> bool:
	return count_solutions(size, regions, allowed, 2) == 1


## First solution as columns[row], or an empty array when there is none.
static func solve(size: int, regions: PackedByteArray, allowed: PackedInt32Array) -> PackedByteArray:
	CatGrid.ensure_tables()
	var columns := PackedByteArray()
	columns.resize(size)
	if _find_first(0, size, regions, allowed, 0, 0, -2, columns):
		return columns
	return PackedByteArray()


## Finds a solution that differs from `known`, or an empty array when `known` is
## the only one. The generator uses this to repair a level: knowing *which* rival
## placement slips through tells it exactly which cell to re-colour, where a bare
## "there are two answers" would leave it guessing.
static func find_rival(size: int, regions: PackedByteArray, known: PackedByteArray) -> PackedByteArray:
	CatGrid.ensure_tables()
	var allowed := open_constraints(size)
	var columns := PackedByteArray()
	columns.resize(size)
	if _find_rival(0, size, regions, allowed, 0, 0, -2, columns, known):
		return columns
	return PackedByteArray()


static func _find_rival(row: int, size: int, regions: PackedByteArray, allowed: PackedInt32Array,
		used_cols: int, used_regions: int, previous_col: int, columns: PackedByteArray,
		known: PackedByteArray) -> bool:
	if row == size:
		for i in size:
			if columns[i] != known[i]:
				return true
		return false
	var options := allowed[row] & ~used_cols
	if previous_col >= 0:
		options &= ~CatGrid.adjacency_ban(size, previous_col)

	while options != 0:
		var low := options & -options
		options &= options - 1
		var col := CatGrid.first_bit_index(low)
		var region_bit := 1 << regions[row * size + col]
		if used_regions & region_bit != 0:
			continue
		columns[row] = col
		if _find_rival(row + 1, size, regions, allowed, used_cols | low,
				used_regions | region_bit, col, columns, known):
			return true
	return false


static func _search(row: int, size: int, regions: PackedByteArray, allowed: PackedInt32Array,
		used_cols: int, used_regions: int, previous_col: int, limit: int) -> int:
	if row == size:
		return 1
	var options := allowed[row] & ~used_cols
	if previous_col >= 0:
		options &= ~CatGrid.adjacency_ban(size, previous_col)

	var total := 0
	while options != 0:
		var low := options & -options
		options &= options - 1
		var col := CatGrid.first_bit_index(low)
		var region_bit := 1 << regions[row * size + col]
		if used_regions & region_bit != 0:
			continue
		total += _search(row + 1, size, regions, allowed, used_cols | low,
			used_regions | region_bit, col, limit - total)
		if total >= limit:
			return total
	return total


static func _find_first(row: int, size: int, regions: PackedByteArray, allowed: PackedInt32Array,
		used_cols: int, used_regions: int, previous_col: int, columns: PackedByteArray) -> bool:
	if row == size:
		return true
	var options := allowed[row] & ~used_cols
	if previous_col >= 0:
		options &= ~CatGrid.adjacency_ban(size, previous_col)

	while options != 0:
		var low := options & -options
		options &= options - 1
		var col := CatGrid.first_bit_index(low)
		var region_bit := 1 << regions[row * size + col]
		if used_regions & region_bit != 0:
			continue
		columns[row] = col
		if _find_first(row + 1, size, regions, allowed, used_cols | low,
				used_regions | region_bit, col, columns):
			return true
	return false
