class_name Palette
extends RefCounted
## Every colour the game draws, in one place.
##
## Warm paper rather than the usual puzzle-app slate: the board should look like
## something a cat would sit on. Kept as constants rather than a Theme resource
## because most of it is painted procedurally -- cell fills change with selection
## state, cats and grid lines are drawn in _draw() -- and a Theme cannot express
## "this cell is a peer of the selected one". Widget chrome that a Theme *can*
## handle lives in resources/cat_theme.tres instead.

const PAPER := Color("f7efe3")
const PAPER_DEEP := Color("ece0cf") ## backdrop paw prints, barely there
const CREAM := Color("fff6ea")

const BOARD := Color("fffbf5")
## Alternating 3x3 tint. Kept very close to BOARD on purpose: anything stronger
## competes with CELL_PEER, and then a highlighted row is indistinguishable from
## a shaded box.
const BOARD_BOX := Color("fdf8f0")
const CELL_PEER := Color("f5e6d3")
const CELL_SAME_DIGIT := Color("ffe3c4")
const CELL_SELECTED := Color("ffc794")
const CELL_CONFLICT := Color("ffd6d2")
const CELL_HINT := Color("d3efe1")

const INK := Color("4c3b31") ## clue digits
const INK_ENTERED := Color("cf6f34") ## digits the player put in
const INK_WRONG := Color("c2504b")
const INK_NOTE := Color("a89584")
const INK_SOFT := Color("8b7767")

const LINE := Color("ead9c4")
const LINE_BOLD := Color("c9a982")
const FRAME := Color("b5885d")

const ACCENT := Color("ef8f5a")
const ACCENT_DEEP := Color("d4703c")
const MINT := Color("74bfa0")

## One colour per region, and a region count always equals the board size, so
## there are as many of these as LevelLadder.LAST_SIZE. Chosen to stay distinguishable when
## dimmed and when sitting next to each other.
const REGIONS: Array[Color] = [
	Color("52a8c0"), ## teal
	Color("efa062"), ## orange
	Color("c97a9b"), ## rose
	Color("97ce7f"), ## green
	Color("a394d1"), ## lilac
	Color("edcf63"), ## butter
	Color("7fb0e8"), ## sky
	Color("d98a6a"), ## clay
	Color("8bc3a6"), ## sage
	Color("a8a29a"), ## stone -- a neutral, because by the tenth region every
	                 ## other hue family is already taken and two similar colours
	                 ## would read as one region
]

## Crosses and cats sit on top of a region colour, so both need to read against
## every entry above.
const MARK := Color("fffaf2")
const CONFLICT := Color("d64545")

static func region_colour(region: int) -> Color:
	return REGIONS[posmod(region, REGIONS.size())]
