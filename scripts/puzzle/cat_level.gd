class_name CatLevel
extends RefCounted
## One puzzle: the board size, the region each cell belongs to, and the solution.
##
## The solution is stored as `columns[row]`, which is the whole answer -- one cat
## per row means a permutation is all there is to record.

var size := 0
var regions := PackedByteArray() ## region id per cell, row-major
var columns := PackedByteArray() ## solution: column of the cat in each row
var tier: int = CatGrid.Tier.EASY
var seed := 0
var attempts := 0
var rating = null ## CatRater.Rating, or null when it came from the bank unrated


func region_at(row: int, col: int) -> int:
	return regions[CatGrid.index_of(size, row, col)]


func solution_index(row: int) -> int:
	return CatGrid.index_of(size, row, columns[row])


func is_solution_cell(index: int) -> bool:
	return columns[CatGrid.row_of(size, index)] == CatGrid.col_of(size, index)


## Stable identity, used to avoid serving a board the player has already had.
##
## Region letters are assigned by the row each region's cat sits in, so the same
## board always stringifies the same way. Hashed rather than stored whole: a few
## hundred 81-character strings would bloat the save for nothing, and a hash
## collision costs exactly one skipped puzzle.
func fingerprint() -> int:
	return fingerprint_of(size, CatGrid.regions_to_string(regions))


static func fingerprint_of(board_size: int, regions_text: String) -> int:
	return ("%d:%s" % [board_size, regions_text]).hash()


## Squares in the smallest colour. One means the board has a free placement in it,
## which the later levels forbid.
func smallest_region() -> int:
	var counts := PackedInt32Array()
	counts.resize(size)
	for region in regions:
		counts[region] += 1
	var smallest := counts[0]
	for count in counts:
		smallest = mini(smallest, count)
	return smallest


func is_valid() -> bool:
	return CatGrid.is_valid_solution(size, regions, columns) \
		and CatGrid.regions_are_connected(size, regions)


func describe() -> String:
	return "%s %dx%d, seed %d" % [CatGrid.tier_name(tier), size, size, seed]


func to_dict() -> Dictionary:
	return {
		"size": size,
		"regions": CatGrid.regions_to_string(regions),
		"columns": CatGrid.columns_to_string(columns),
		"tier": tier,
		"seed": seed,
	}


static func from_dict(data: Dictionary) -> CatLevel:
	var level := CatLevel.new()
	level.size = int(data.get("size", 0))
	level.regions = CatGrid.regions_from_string(String(data.get("regions", "")))
	level.columns = CatGrid.columns_from_string(String(data.get("columns", "")))
	level.tier = int(data.get("tier", CatGrid.Tier.EASY))
	level.seed = int(data.get("seed", 0))
	if level.size < CatGrid.MIN_SIZE or level.regions.size() != level.size * level.size:
		return null
	return level
