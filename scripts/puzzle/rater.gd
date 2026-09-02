class_name CatRater
extends RefCounted
## Rates a level by the deductions it actually requires.
##
## Board size is a bad difficulty measure on its own: a 9x9 can fall to nothing
## but "last cell standing", and a 6x6 can need real work. So this is a logical
## solver that never guesses. Each pass it applies the *cheapest* technique that
## fires and records the hardest it ever needed. Cheapest-first is the whole
## point -- a solver allowed to reach for the expensive techniques early would
## rate every level Expert.
##
## Candidates live as one column bitmask per row: bit c of `alive[row]` means a
## cat could still go at (row, c). One cat per row is what makes that enough.
##
## Rows, columns and colours are all just *groups of cells that must contain
## exactly one cat*. Almost every technique below is written once against that
## idea and then applied to each pair of group kinds, which is why the ladder is
## four rungs rather than a dozen near-duplicates.

enum Technique {
	FORCED_SINGLE, ## a row, column or colour with one candidate cell left
	CONFINEMENT, ## a group penned inside another clears the rest of that other
	ADJACENCY, ## a cell every candidate of some group would touch
	SUBSET, ## k groups penned into k groups lock each other out
}

const TECHNIQUE_NAMES: PackedStringArray = [
	"Last one standing",
	"Penned in",
	"Too close",
	"Locked group",
]

## The three kinds of group. Each must hold exactly one cat, which is the only
## property the techniques rely on.
enum Group { ROW, COLUMN, REGION }

const GROUP_KINDS: Array[int] = [Group.ROW, Group.COLUMN, Group.REGION]

## Hardest technique permitted at each tier. A level belongs to the lowest tier
## whose cap still solves it.
const TIER_CAP := {
	CatGrid.Tier.EASY: Technique.FORCED_SINGLE,
	CatGrid.Tier.MEDIUM: Technique.CONFINEMENT,
	CatGrid.Tier.HARD: Technique.ADJACENCY,
	CatGrid.Tier.EXPERT: Technique.SUBSET,
}

const _MAX_PASSES := 2048

## Group sizes the locked-group technique looks for. Typed so the loop variable
## is an int rather than a Variant.
const _SUBSET_SIZES: Array[int] = [2, 3]


class Rating extends RefCounted:
	var solved := false
	var hardest := -1
	var tier: int = CatGrid.Tier.EASY
	var steps := 0
	var counts := {}

	func technique_name() -> String:
		return "None" if hardest < 0 else CatRater.TECHNIQUE_NAMES[hardest]

	func describe() -> String:
		return "%s (hardest: %s, %d steps)" % [CatGrid.tier_name(tier), technique_name(), steps]


class Hint extends RefCounted:
	var ok := false
	var index := -1
	var technique := -1
	var message := ""


## Working state: candidates plus the board facts the techniques need.
class Board extends RefCounted:
	var size := 0
	var regions := PackedByteArray()
	var alive := PackedInt32Array() ## column bitmask per row
	var placed := PackedByteArray() ## column per row, 0xFF when undecided

	func _init(level: CatLevel) -> void:
		size = level.size
		regions = level.regions
		alive.resize(size)
		alive.fill(CatGrid.full_mask(size))
		placed.resize(size)
		placed.fill(0xFF)

	func region_of(row: int, col: int) -> int:
		return regions[row * size + col]

	func is_alive(row: int, col: int) -> bool:
		return alive[row] & (1 << col) != 0

	func clear(row: int, col: int) -> bool:
		var bit := 1 << col
		if alive[row] & bit == 0:
			return false
		alive[row] &= ~bit
		return true

	func broken() -> bool:
		for mask in alive:
			if mask == 0:
				return true
		return false

	func solved() -> bool:
		for col in placed:
			if col == 0xFF:
				return false
		return true

	## Which group of `kind` a cell belongs to.
	func group_of(kind: int, row: int, col: int) -> int:
		match kind:
			Group.ROW:
				return row
			Group.COLUMN:
				return col
			_:
				return region_of(row, col)

	## Candidate cells of one group, as (row, column) pairs.
	func group_cells(kind: int, id: int) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for row in size:
			var mask := alive[row]
			while mask != 0:
				var low := mask & -mask
				mask &= mask - 1
				var col := CatGrid.first_bit_index(low)
				if group_of(kind, row, col) == id:
					out.append(Vector2i(row, col))
		return out

	## True once the group already contains a placed cat.
	func group_satisfied(kind: int, id: int) -> bool:
		for row in size:
			var col := placed[row]
			if col != 0xFF and group_of(kind, row, col) == id:
				return true
		return false

	## Places a cat and applies every consequence at once: the row is decided, the
	## column and colour are used up, and the rows above and below lose the three
	## columns the cat now touches.
	func place(row: int, col: int) -> void:
		placed[row] = col
		alive[row] = 1 << col
		var region := region_of(row, col)
		for other in size:
			if other != row:
				clear(other, col)
				for other_col in size:
					if region_of(other, other_col) == region:
						clear(other, other_col)
		var ban := CatGrid.adjacency_ban(size, col)
		for neighbour_row in [row - 1, row + 1]:
			if neighbour_row >= 0 and neighbour_row < size:
				alive[neighbour_row] &= ~ban


static func rate(level: CatLevel, max_technique: int = Technique.SUBSET) -> Rating:
	CatGrid.ensure_tables()
	var rating := Rating.new()
	var board := Board.new(level)

	var passes := 0
	while passes < _MAX_PASSES:
		passes += 1
		if board.solved():
			rating.solved = true
			break
		if board.broken():
			break
		var applied := _apply_cheapest(board, max_technique)
		if applied.x < 0:
			break
		rating.steps += applied.y
		rating.counts[applied.x] = int(rating.counts.get(applied.x, 0)) + applied.y
		if applied.x > rating.hardest:
			rating.hardest = applied.x

	rating.tier = tier_for(rating.hardest)
	return rating


static func tier_for(hardest: int) -> int:
	match hardest:
		-1, Technique.FORCED_SINGLE:
			return CatGrid.Tier.EASY
		Technique.CONFINEMENT:
			return CatGrid.Tier.MEDIUM
		Technique.ADJACENCY:
			return CatGrid.Tier.HARD
		_:
			return CatGrid.Tier.EXPERT


static func cap_for_tier(tier: int) -> int:
	return int(TIER_CAP.get(tier, Technique.SUBSET))


## The next cell the player can legitimately fill, working from the marks they
## have made. Their crosses are taken as given, so a hint respects the reasoning
## they have already done -- but a wrong cross shows up as a contradiction rather
## than a confident wrong answer.
static func find_hint(level: CatLevel, marks: PackedByteArray) -> Hint:
	CatGrid.ensure_tables()
	var hint := Hint.new()
	var board := Board.new(level)

	for index in marks.size():
		var row := CatGrid.row_of(level.size, index)
		var col := CatGrid.col_of(level.size, index)
		match marks[index]:
			CatGrid.Mark.EXCLUDED, CatGrid.Mark.WRONG:
				board.clear(row, col)
			CatGrid.Mark.CAT:
				if not board.is_alive(row, col):
					hint.message = "Two of your cats break a rule."
					return hint
				board.place(row, col)

	var passes := 0
	while passes < _MAX_PASSES:
		passes += 1
		if board.broken():
			hint.message = "One of your marks makes the level unsolvable."
			return hint
		if board.solved():
			hint.message = "Every cat is already placed."
			return hint

		var found := _find_forced(board)
		if found.x >= 0:
			hint.ok = true
			hint.index = CatGrid.index_of(level.size, found.x, found.y)
			hint.technique = Technique.FORCED_SINGLE
			hint.message = _forced_message(board, found.x, found.y)
			return hint

		if _apply_cheapest(board, Technique.SUBSET).x < 0:
			hint.message = "No further step found from here."
			return hint

	hint.message = "No further step found from here."
	return hint


static func _forced_message(board: Board, row: int, col: int) -> String:
	if CatGrid.is_single(board.alive[row]):
		return "Only one cell left in this row."
	if board.group_cells(Group.COLUMN, col).size() == 1:
		return "Only one cell left in this column."
	return "Only one cell left in this colour."


## Tries techniques in difficulty order. Returns {technique, deductions}, or
## x = -1 when nothing applies.
static func _apply_cheapest(board: Board, cap: int) -> Vector2i:
	var forced := _find_forced(board)
	if forced.x >= 0:
		board.place(forced.x, forced.y)
		return Vector2i(Technique.FORCED_SINGLE, 1)
	if cap >= Technique.CONFINEMENT:
		var n := _confinement(board)
		if n > 0:
			return Vector2i(Technique.CONFINEMENT, n)
	if cap >= Technique.ADJACENCY:
		var n := _adjacency(board)
		if n > 0:
			return Vector2i(Technique.ADJACENCY, n)
	if cap >= Technique.SUBSET:
		var n := _subset(board)
		if n > 0:
			return Vector2i(Technique.SUBSET, n)
	return Vector2i(-1, 0)


## A row, column or colour with exactly one candidate cell left. Returns the
## (row, column) to place, or x = -1.
static func _find_forced(board: Board) -> Vector2i:
	for kind in GROUP_KINDS:
		for id in board.size:
			if board.group_satisfied(kind, id):
				continue
			var cells := board.group_cells(kind, id)
			if cells.size() == 1:
				return cells[0]
	return Vector2i(-1, -1)


## A group whose candidates all fall inside a single other group. That other
## group's cat therefore belongs to this one, so its cells elsewhere are out.
##
## This is one rule applied six ways: a colour penned into a row, a row penned
## into a colour, a colour penned into a column, and so on.
static func _confinement(board: Board) -> int:
	var cleared := 0
	for a_kind in GROUP_KINDS:
		for b_kind in GROUP_KINDS:
			if a_kind == b_kind:
				continue
			for a_id in board.size:
				if board.group_satisfied(a_kind, a_id):
					continue
				var cells := board.group_cells(a_kind, a_id)
				if cells.is_empty():
					continue
				var b_id := board.group_of(b_kind, cells[0].x, cells[0].y)
				var confined := true
				for cell in cells:
					if board.group_of(b_kind, cell.x, cell.y) != b_id:
						confined = false
						break
				if not confined:
					continue
				cleared += _clear_group_except(board, b_kind, b_id, a_kind, a_id)
	return cleared


## Removes every candidate of one group that does not also belong to another.
static func _clear_group_except(board: Board, kind: int, id: int, keep_kind: int, keep_id: int) -> int:
	var cleared := 0
	for cell in board.group_cells(kind, id):
		if board.group_of(keep_kind, cell.x, cell.y) == keep_id:
			continue
		if board.clear(cell.x, cell.y):
			cleared += 1
	return cleared


## A cell that every candidate of some group would touch. That group's cat has to
## go somewhere, and wherever it goes it would sit next to this cell, so the cell
## is out. This is the one technique that is really about the no-touching rule.
static func _adjacency(board: Board) -> int:
	var cleared := 0
	for kind in GROUP_KINDS:
		for id in board.size:
			if board.group_satisfied(kind, id):
				continue
			var cells := board.group_cells(kind, id)
			if cells.size() < 2:
				continue
			# Start from everything the first candidate touches, then keep only
			# what the rest touch too.
			var shared := _touched_by(board, cells[0])
			for i in range(1, cells.size()):
				shared = _intersect(shared, _touched_by(board, cells[i]))
				if shared.is_empty():
					break
			for cell in shared:
				if board.clear(cell.x, cell.y):
					cleared += 1
	return cleared


## Live cells a cat at `cell` would touch, excluding itself.
static func _touched_by(board: Board, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row in range(maxi(0, cell.x - 1), mini(board.size, cell.x + 2)):
		for col in range(maxi(0, cell.y - 1), mini(board.size, cell.y + 2)):
			if row == cell.x and col == cell.y:
				continue
			if board.is_alive(row, col):
				out.append(Vector2i(row, col))
	return out


static func _intersect(a: Array[Vector2i], b: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in a:
		if b.has(cell):
			out.append(cell)
	return out


## k groups whose candidates fall inside exactly k groups of another kind own
## those k groups between them, so nothing else can use any of them.
##
## The k = 1 case is confinement, already handled above; this picks up pairs and
## triples, which is where a hard level usually hides.
static func _subset(board: Board) -> int:
	for a_kind in GROUP_KINDS:
		for b_kind in GROUP_KINDS:
			if a_kind == b_kind:
				continue
			var open: Array[int] = []
			for id in board.size:
				if not board.group_satisfied(a_kind, id) and not board.group_cells(a_kind, id).is_empty():
					open.append(id)
			for group_size in _SUBSET_SIZES:
				if open.size() <= group_size:
					continue
				var cleared := _subset_pass(board, a_kind, b_kind, open, group_size)
				if cleared > 0:
					return cleared
	return 0


static func _subset_pass(board: Board, a_kind: int, b_kind: int, open: Array[int],
		group_size: int) -> int:
	var combo := PackedInt32Array()
	combo.resize(group_size)
	for k in group_size:
		combo[k] = k
	while true:
		var touched: Array[int] = []
		var members: Array[int] = []
		for k in group_size:
			var a_id: int = open[combo[k]]
			members.append(a_id)
			for cell in board.group_cells(a_kind, a_id):
				var b_id := board.group_of(b_kind, cell.x, cell.y)
				if not touched.has(b_id):
					touched.append(b_id)
		if touched.size() == group_size:
			var cleared := 0
			for b_id in touched:
				for cell in board.group_cells(b_kind, b_id):
					if members.has(board.group_of(a_kind, cell.x, cell.y)):
						continue
					if board.clear(cell.x, cell.y):
						cleared += 1
			if cleared > 0:
				return cleared

		var i := group_size - 1
		while i >= 0 and combo[i] == open.size() - group_size + i:
			i -= 1
		if i < 0:
			break
		combo[i] += 1
		for j in range(i + 1, group_size):
			combo[j] = combo[j - 1] + 1
	return 0
