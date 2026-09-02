class_name LevelLadder
extends RefCounted
## Turns a level number into a board to generate.
##
## There is no difficulty menu. Level 1 is a gentle 5x5 and every level after it
## is a little harder, so the player meets each new idea once they have had some
## practice with the last one.
##
## Difficulty climbs on two axes. The board grows, and within each size the
## techniques required ramp from Easy to Expert -- so the curve rises steadily and
## dips slightly whenever the board grows, which is the breather that pays for the
## extra rows and columns.
##
## Each size lasts longer than the one before it. A 5x5 is understood in a few
## goes; a 9x9 deserves twenty. It also means the sizes, which run out, take much
## longer to do so than a player does.

const FIRST_LEVEL := 1
const FIRST_SIZE := 5
const LAST_SIZE := 10

## How many levels are spent on each board size, from FIRST_SIZE upward. The last
## entry is how long the final size takes to ramp from Easy to Expert; after that
## the level number keeps climbing but the board and the tier stay put.
##
## These total 99, so the 10x10 boards begin at level 100.
const LEVELS_PER_SIZE: Array[int] = [10, 15, 20, 24, 30, 30]

## Why the ladder stops growing at 10x10, when the level count does not:
##
##   Generating a unique board costs roughly five times more per extra row --
##   8 ms at 9x9, 34 ms at 10x10, 1.7 s at 12x12, where almost nothing succeeds.
##   Cells shrink below a comfortable touch target: 41 pt at 9x9, 37 pt at 10x10,
##   30 pt at 12x12, against Apple's 44 pt guidance.
##   And every region needs its own colour. Past a dozen flat colours nobody can
##   tell them apart at cell size, which is a limit of eyes rather than code.
const _FINAL_RAMP := 30

## From this level on, no colour may be a single square.
##
## A one-square colour is a free placement -- the cat can only go there -- so it
## is the easiest foothold on any board. Removing it means the player has to open
## the puzzle with real reasoning rather than a gift. By this point they are deep
## into 10x10 Expert boards and have earned it.
const NO_SINGLE_CELL_REGIONS_FROM := 150


static func size_for(level: int) -> int:
	var remaining := maxi(level, FIRST_LEVEL) - FIRST_LEVEL
	for step in LEVELS_PER_SIZE.size():
		if remaining < LEVELS_PER_SIZE[step]:
			return FIRST_SIZE + step
		remaining -= LEVELS_PER_SIZE[step]
	return LAST_SIZE


@warning_ignore("integer_division")
static func tier_for(level: int) -> int:
	var remaining := maxi(level, FIRST_LEVEL) - FIRST_LEVEL
	for step in LEVELS_PER_SIZE.size():
		if remaining < LEVELS_PER_SIZE[step]:
			return mini(CatGrid.Tier.size() * remaining / LEVELS_PER_SIZE[step],
				CatGrid.Tier.EXPERT)
		remaining -= LEVELS_PER_SIZE[step]
	return CatGrid.Tier.EXPERT


static func min_region_cells(level: int) -> int:
	return 2 if level >= NO_SINGLE_CELL_REGIONS_FROM else 1


## Short caption for the top bar: "Level 7  ·  Medium 6x6".
static func describe(level: int) -> String:
	var size := size_for(level)
	return "Level %d  ·  %s %d×%d" % [level, CatGrid.tier_name(tier_for(level)), size, size]


## True when this level is the first on a bigger board, so the UI can warn.
static func is_step_up(level: int) -> bool:
	return level > FIRST_LEVEL and size_for(level) != size_for(level - 1)


## First level on the largest board. Past it the boards stop growing.
static func final_size_level() -> int:
	var total := FIRST_LEVEL
	for step in LEVELS_PER_SIZE.size() - 1:
		total += LEVELS_PER_SIZE[step]
	return total


## The next level that puts the player on a bigger board, or 0 when there are no
## bigger boards left.
static func next_step_up(level: int) -> int:
	var next := maxi(level, FIRST_LEVEL) + 1
	var limit := final_size_level()
	while next <= limit:
		if is_step_up(next):
			return next
		next += 1
	return 0


## Every board the ladder can ask for, as {tier, size, minimum colour size}. The
## content build uses this so the shipped bank covers exactly what players will
## actually be served.
static func combinations() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var last := maxi(final_size_level() + _FINAL_RAMP, NO_SINGLE_CELL_REGIONS_FROM)
	for level in range(FIRST_LEVEL, last + 1):
		var spec := Vector3i(tier_for(level), size_for(level), min_region_cells(level))
		if not out.has(spec):
			out.append(spec)
	return out
