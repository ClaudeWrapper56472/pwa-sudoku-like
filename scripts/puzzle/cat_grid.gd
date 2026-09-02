class_name CatGrid
extends RefCounted
## Board geometry and the rules of the game.
##
## The board is an N x N grid carved into N irregular colour regions. Exactly one
## cat goes in every row, every column and every region, and no two cats may
## touch -- not even diagonally.
##
## Two consequences shape every algorithm here. Because there is exactly one cat
## per row, a whole solution is just a list of columns indexed by row: a
## permutation. And because there is one cat per row, the no-touching rule can
## only ever bite between *consecutive* rows, which turns adjacency from an
## awkward 2D check into "the next row's column must differ by more than one".

const MIN_SIZE := 4
const MAX_SIZE := 10

enum Tier { EASY, MEDIUM, HARD, EXPERT }

const TIER_NAMES: PackedStringArray = ["Easy", "Medium", "Hard", "Expert"]

## What is in a cell. EXCLUDED is the player's own cross, a note to themselves
## that costs nothing and can be taken back. WRONG is one the game put there after
## a cat was refused: it is a fact, not a guess, so it stays for the rest of the
## level and cannot be edited away.
enum Mark { EMPTY, EXCLUDED, CAT, WRONG }

static var _bit_index := PackedByteArray()
static var _popcount := PackedByteArray()
static var _initialized := false


static func _static_init() -> void:
	ensure_tables()


static func ensure_tables() -> void:
	if _initialized:
		return
	_initialized = true
	var span := 1 << MAX_SIZE
	_bit_index.resize(span)
	for bit in MAX_SIZE:
		_bit_index[1 << bit] = bit
	_popcount.resize(span)
	for mask in span:
		var n := 0
		var x := mask
		while x != 0:
			x &= x - 1
			n += 1
		_popcount[mask] = n


static func count_bits(mask: int) -> int:
	return _popcount[mask]


static func first_bit_index(single_bit: int) -> int:
	return _bit_index[single_bit]


static func is_single(mask: int) -> bool:
	return mask != 0 and mask & (mask - 1) == 0


static func full_mask(size: int) -> int:
	return (1 << size) - 1


static func index_of(size: int, row: int, col: int) -> int:
	return row * size + col


@warning_ignore("integer_division")
static func row_of(size: int, index: int) -> int:
	return index / size


static func col_of(size: int, index: int) -> int:
	return index % size


## Columns a cat in `col` forbids in an adjacent row: itself and its neighbours.
static func adjacency_ban(size: int, col: int) -> int:
	var ban := 1 << col
	if col > 0:
		ban |= 1 << (col - 1)
	if col < size - 1:
		ban |= 1 << (col + 1)
	return ban


## True when two cats would be touching, orthogonally or diagonally.
static func touching(row_a: int, col_a: int, row_b: int, col_b: int) -> bool:
	return absi(row_a - row_b) <= 1 and absi(col_a - col_b) <= 1


## Checks a complete placement against all four rules. Used by the tests and as a
## guard on anything loaded from disk.
static func is_valid_solution(size: int, regions: PackedByteArray, columns: PackedByteArray) -> bool:
	if columns.size() != size or regions.size() != size * size:
		return false
	var seen_cols := 0
	var seen_regions := 0
	for row in size:
		var col := columns[row]
		if col < 0 or col >= size:
			return false
		var col_bit := 1 << col
		if seen_cols & col_bit != 0:
			return false
		seen_cols |= col_bit
		var region_bit := 1 << regions[index_of(size, row, col)]
		if seen_regions & region_bit != 0:
			return false
		seen_regions |= region_bit
		if row > 0 and touching(row, col, row - 1, columns[row - 1]):
			return false
	return true


## True when every region is a single connected blob. Disconnected regions are
## legal for the solver but look broken, so the generator rejects them.
static func regions_are_connected(size: int, regions: PackedByteArray) -> bool:
	var counts := PackedInt32Array()
	counts.resize(size)
	for region in regions:
		if region >= size:
			return false
		counts[region] += 1

	for region in size:
		var start := -1
		for i in regions.size():
			if regions[i] == region:
				start = i
				break
		if start < 0:
			return false
		var seen := {}
		var queue: Array[int] = [start]
		seen[start] = true
		while not queue.is_empty():
			var cell: int = queue.pop_back()
			for neighbour in orthogonal_neighbours(size, cell):
				if regions[neighbour] == region and not seen.has(neighbour):
					seen[neighbour] = true
					queue.append(neighbour)
		if seen.size() != counts[region]:
			return false
	return true


## Connectivity of one region, which is what the generator needs while it is
## moving individual cells between regions.
static func region_is_connected(size: int, regions: PackedByteArray, region: int) -> bool:
	var total := 0
	var start := -1
	for index in regions.size():
		if regions[index] == region:
			total += 1
			if start < 0:
				start = index
	if start < 0:
		return false
	var seen := {start: true}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var cell: int = queue.pop_back()
		for neighbour in orthogonal_neighbours(size, cell):
			if regions[neighbour] == region and not seen.has(neighbour):
				seen[neighbour] = true
				queue.append(neighbour)
	return seen.size() == total


static func orthogonal_neighbours(size: int, index: int) -> PackedInt32Array:
	var row := row_of(size, index)
	var col := col_of(size, index)
	var out := PackedInt32Array()
	if row > 0:
		out.append(index - size)
	if row < size - 1:
		out.append(index + size)
	if col > 0:
		out.append(index - 1)
	if col < size - 1:
		out.append(index + 1)
	return out


static func tier_name(tier: int) -> String:
	return TIER_NAMES[clampi(tier, 0, TIER_NAMES.size() - 1)]


static func regions_to_string(regions: PackedByteArray) -> String:
	var out := ""
	for region in regions:
		out += String.chr(65 + region)
	return out


static func regions_from_string(text: String) -> PackedByteArray:
	var out := PackedByteArray()
	for ch in text:
		out.append(ch.unicode_at(0) - 65)
	return out


static func columns_to_string(columns: PackedByteArray) -> String:
	var out := ""
	for col in columns:
		out += str(col)
	return out


static func columns_from_string(text: String) -> PackedByteArray:
	var out := PackedByteArray()
	for ch in text:
		out.append(ch.to_int())
	return out
