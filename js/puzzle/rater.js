import * as Grid from "./grid.js";

/**
 * Rates a level by the deductions it actually requires.
 *
 * Board size is a bad difficulty measure on its own: a 9x9 can fall to nothing
 * but "last cell standing", and a 6x6 can need real work. So this is a logical
 * solver that never guesses. Each pass it applies the *cheapest* technique that
 * fires and records the hardest it ever needed. Cheapest-first is the whole
 * point -- a solver allowed to reach for the expensive techniques early would
 * rate every level Expert.
 *
 * Candidates live as one column bitmask per row: bit c of `alive[row]` means a
 * cat could still go at (row, c). One cat per row is what makes that enough.
 *
 * Rows, columns and colours are all just *groups of cells that must contain
 * exactly one cat*. Almost every technique below is written once against that
 * idea and then applied to each pair of group kinds, which is why the ladder is
 * four rungs rather than a dozen near-duplicates.
 *
 * Cells travel as packed row * size + col indices, so the set operations the
 * adjacency technique needs are plain Set lookups.
 */

export const Technique = {
	FORCED_SINGLE: 0, // a row, column or colour with one candidate cell left
	CONFINEMENT: 1, // a group penned inside another clears the rest of that other
	ADJACENCY: 2, // a cell every candidate of some group would touch
	SUBSET: 3, // k groups penned into k groups lock each other out
};

export const TECHNIQUE_NAMES = [
	"Last one standing",
	"Penned in",
	"Too close",
	"Locked group",
];

/**
 * The three kinds of group. Each must hold exactly one cat, which is the only
 * property the techniques rely on.
 */
export const Group = { ROW: 0, COLUMN: 1, REGION: 2 };
const GROUP_KINDS = [Group.ROW, Group.COLUMN, Group.REGION];

/**
 * Hardest technique permitted at each tier. A level belongs to the lowest tier
 * whose cap still solves it.
 */
const TIER_CAP = {
	[Grid.Tier.EASY]: Technique.FORCED_SINGLE,
	[Grid.Tier.MEDIUM]: Technique.CONFINEMENT,
	[Grid.Tier.HARD]: Technique.ADJACENCY,
	[Grid.Tier.EXPERT]: Technique.SUBSET,
};

const MAX_PASSES = 2048;

/** Group sizes the locked-group technique looks for. */
const SUBSET_SIZES = [2, 3];

export class Rating {
	constructor() {
		this.solved = false;
		this.hardest = -1;
		this.tier = Grid.Tier.EASY;
		this.steps = 0;
		this.counts = {};
	}

	techniqueName() {
		return this.hardest < 0 ? "None" : TECHNIQUE_NAMES[this.hardest];
	}

	describe() {
		return `${Grid.tierName(this.tier)} (hardest: ${this.techniqueName()}, ${this.steps} steps)`;
	}
}

export class Hint {
	constructor() {
		this.ok = false;
		this.index = -1;
		this.technique = -1;
		this.message = "";
	}
}

/** Working state: candidates plus the board facts the techniques need. */
class Board {
	constructor(level) {
		this.size = level.size;
		this.regions = level.regions;
		this.alive = new Int32Array(this.size).fill(Grid.fullMask(this.size));
		this.placed = new Uint8Array(this.size).fill(0xff);
	}

	regionOf(row, col) {
		return this.regions[row * this.size + col];
	}

	isAlive(row, col) {
		return (this.alive[row] & (1 << col)) !== 0;
	}

	clear(row, col) {
		const bit = 1 << col;
		if ((this.alive[row] & bit) === 0) return false;
		this.alive[row] &= ~bit;
		return true;
	}

	broken() {
		for (const mask of this.alive) {
			if (mask === 0) return true;
		}
		return false;
	}

	solved() {
		for (const col of this.placed) {
			if (col === 0xff) return false;
		}
		return true;
	}

	/** Which group of `kind` a cell belongs to. */
	groupOf(kind, row, col) {
		if (kind === Group.ROW) return row;
		if (kind === Group.COLUMN) return col;
		return this.regionOf(row, col);
	}

	/** Candidate cells of one group, as packed indices. */
	groupCells(kind, id) {
		const out = [];
		for (let row = 0; row < this.size; row += 1) {
			let mask = this.alive[row];
			while (mask !== 0) {
				const low = mask & -mask;
				mask &= mask - 1;
				const col = Grid.firstBitIndex(low);
				if (this.groupOf(kind, row, col) === id) out.push(row * this.size + col);
			}
		}
		return out;
	}

	/** True once the group already contains a placed cat. */
	groupSatisfied(kind, id) {
		for (let row = 0; row < this.size; row += 1) {
			const col = this.placed[row];
			if (col !== 0xff && this.groupOf(kind, row, col) === id) return true;
		}
		return false;
	}

	/**
	 * Places a cat and applies every consequence at once: the row is decided, the
	 * column and colour are used up, and the rows above and below lose the three
	 * columns the cat now touches.
	 */
	place(row, col) {
		this.placed[row] = col;
		this.alive[row] = 1 << col;
		const region = this.regionOf(row, col);
		for (let other = 0; other < this.size; other += 1) {
			if (other === row) continue;
			this.clear(other, col);
			for (let otherCol = 0; otherCol < this.size; otherCol += 1) {
				if (this.regionOf(other, otherCol) === region) this.clear(other, otherCol);
			}
		}
		const ban = Grid.adjacencyBan(this.size, col);
		for (const neighbourRow of [row - 1, row + 1]) {
			if (neighbourRow >= 0 && neighbourRow < this.size) this.alive[neighbourRow] &= ~ban;
		}
	}
}

export function rate(level, maxTechnique = Technique.SUBSET) {
	const rating = new Rating();
	const board = new Board(level);

	let passes = 0;
	while (passes < MAX_PASSES) {
		passes += 1;
		if (board.solved()) {
			rating.solved = true;
			break;
		}
		if (board.broken()) break;
		const applied = applyCheapest(board, maxTechnique);
		if (applied.technique < 0) break;
		rating.steps += applied.deductions;
		rating.counts[applied.technique] = (rating.counts[applied.technique] ?? 0) + applied.deductions;
		if (applied.technique > rating.hardest) rating.hardest = applied.technique;
	}

	rating.tier = tierFor(rating.hardest);
	return rating;
}

export function tierFor(hardest) {
	switch (hardest) {
		case -1:
		case Technique.FORCED_SINGLE:
			return Grid.Tier.EASY;
		case Technique.CONFINEMENT:
			return Grid.Tier.MEDIUM;
		case Technique.ADJACENCY:
			return Grid.Tier.HARD;
		default:
			return Grid.Tier.EXPERT;
	}
}

export function capForTier(tier) {
	return TIER_CAP[tier] ?? Technique.SUBSET;
}

/**
 * The next cell the player can legitimately fill, working from the marks they
 * have made. Their crosses are taken as given, so a hint respects the reasoning
 * they have already done -- but a wrong cross shows up as a contradiction rather
 * than a confident wrong answer.
 */
export function findHint(level, marks) {
	const hint = new Hint();
	const board = new Board(level);

	for (let index = 0; index < marks.length; index += 1) {
		const row = Grid.rowOf(level.size, index);
		const col = Grid.colOf(level.size, index);
		if (marks[index] === Grid.Mark.EXCLUDED || marks[index] === Grid.Mark.WRONG) {
			board.clear(row, col);
		} else if (marks[index] === Grid.Mark.CAT) {
			if (!board.isAlive(row, col)) {
				hint.message = "Two of your cats break a rule.";
				return hint;
			}
			board.place(row, col);
		}
	}

	let passes = 0;
	while (passes < MAX_PASSES) {
		passes += 1;
		if (board.broken()) {
			hint.message = "One of your marks makes the level unsolvable.";
			return hint;
		}
		if (board.solved()) {
			hint.message = "Every cat is already placed.";
			return hint;
		}

		const found = findForced(board);
		if (found >= 0) {
			hint.ok = true;
			hint.index = found;
			hint.technique = Technique.FORCED_SINGLE;
			hint.message = forcedMessage(board, Grid.rowOf(board.size, found),
				Grid.colOf(board.size, found));
			return hint;
		}

		if (applyCheapest(board, Technique.SUBSET).technique < 0) {
			hint.message = "No further step found from here.";
			return hint;
		}
	}

	hint.message = "No further step found from here.";
	return hint;
}

function forcedMessage(board, row, col) {
	if (Grid.isSingle(board.alive[row])) return "Only one cell left in this row.";
	if (board.groupCells(Group.COLUMN, col).length === 1) return "Only one cell left in this column.";
	return "Only one cell left in this colour.";
}

/**
 * Tries techniques in difficulty order. Returns the technique that fired and how
 * many deductions it made, or technique -1 when nothing applies.
 */
function applyCheapest(board, cap) {
	const forced = findForced(board);
	if (forced >= 0) {
		board.place(Grid.rowOf(board.size, forced), Grid.colOf(board.size, forced));
		return { technique: Technique.FORCED_SINGLE, deductions: 1 };
	}
	if (cap >= Technique.CONFINEMENT) {
		const n = confinement(board);
		if (n > 0) return { technique: Technique.CONFINEMENT, deductions: n };
	}
	if (cap >= Technique.ADJACENCY) {
		const n = adjacency(board);
		if (n > 0) return { technique: Technique.ADJACENCY, deductions: n };
	}
	if (cap >= Technique.SUBSET) {
		const n = subset(board);
		if (n > 0) return { technique: Technique.SUBSET, deductions: n };
	}
	return { technique: -1, deductions: 0 };
}

/**
 * A row, column or colour with exactly one candidate cell left. Returns the cell
 * to place, or -1.
 */
function findForced(board) {
	for (const kind of GROUP_KINDS) {
		for (let id = 0; id < board.size; id += 1) {
			if (board.groupSatisfied(kind, id)) continue;
			const cells = board.groupCells(kind, id);
			if (cells.length === 1) return cells[0];
		}
	}
	return -1;
}

/**
 * A group whose candidates all fall inside a single other group. That other
 * group's cat therefore belongs to this one, so its cells elsewhere are out.
 *
 * This is one rule applied six ways: a colour penned into a row, a row penned
 * into a colour, a colour penned into a column, and so on.
 */
function confinement(board) {
	let cleared = 0;
	for (const aKind of GROUP_KINDS) {
		for (const bKind of GROUP_KINDS) {
			if (aKind === bKind) continue;
			for (let aId = 0; aId < board.size; aId += 1) {
				if (board.groupSatisfied(aKind, aId)) continue;
				const cells = board.groupCells(aKind, aId);
				if (cells.length === 0) continue;
				const bId = board.groupOf(bKind, Grid.rowOf(board.size, cells[0]),
					Grid.colOf(board.size, cells[0]));
				let confined = true;
				for (const cell of cells) {
					if (board.groupOf(bKind, Grid.rowOf(board.size, cell),
						Grid.colOf(board.size, cell)) !== bId) {
						confined = false;
						break;
					}
				}
				if (!confined) continue;
				cleared += clearGroupExcept(board, bKind, bId, aKind, aId);
			}
		}
	}
	return cleared;
}

/** Removes every candidate of one group that does not also belong to another. */
function clearGroupExcept(board, kind, id, keepKind, keepId) {
	let cleared = 0;
	for (const cell of board.groupCells(kind, id)) {
		const row = Grid.rowOf(board.size, cell);
		const col = Grid.colOf(board.size, cell);
		if (board.groupOf(keepKind, row, col) === keepId) continue;
		if (board.clear(row, col)) cleared += 1;
	}
	return cleared;
}

/**
 * A cell that every candidate of some group would touch. That group's cat has to
 * go somewhere, and wherever it goes it would sit next to this cell, so the cell
 * is out. This is the one technique that is really about the no-touching rule.
 */
function adjacency(board) {
	let cleared = 0;
	for (const kind of GROUP_KINDS) {
		for (let id = 0; id < board.size; id += 1) {
			if (board.groupSatisfied(kind, id)) continue;
			const cells = board.groupCells(kind, id);
			if (cells.length < 2) continue;
			// Start from everything the first candidate touches, then keep only
			// what the rest touch too.
			let shared = touchedBy(board, cells[0]);
			for (let i = 1; i < cells.length; i += 1) {
				const next = touchedBy(board, cells[i]);
				shared = shared.filter((cell) => next.includes(cell));
				if (shared.length === 0) break;
			}
			for (const cell of shared) {
				if (board.clear(Grid.rowOf(board.size, cell), Grid.colOf(board.size, cell))) {
					cleared += 1;
				}
			}
		}
	}
	return cleared;
}

/** Live cells a cat at `cell` would touch, excluding itself. */
function touchedBy(board, cell) {
	const cellRow = Grid.rowOf(board.size, cell);
	const cellCol = Grid.colOf(board.size, cell);
	const out = [];
	for (let row = Math.max(0, cellRow - 1); row < Math.min(board.size, cellRow + 2); row += 1) {
		for (let col = Math.max(0, cellCol - 1); col < Math.min(board.size, cellCol + 2); col += 1) {
			if (row === cellRow && col === cellCol) continue;
			if (board.isAlive(row, col)) out.push(row * board.size + col);
		}
	}
	return out;
}

/**
 * k groups whose candidates fall inside exactly k groups of another kind own
 * those k groups between them, so nothing else can use any of them.
 *
 * The k = 1 case is confinement, already handled above; this picks up pairs and
 * triples, which is where a hard level usually hides.
 */
function subset(board) {
	for (const aKind of GROUP_KINDS) {
		for (const bKind of GROUP_KINDS) {
			if (aKind === bKind) continue;
			const open = [];
			for (let id = 0; id < board.size; id += 1) {
				if (!board.groupSatisfied(aKind, id) && board.groupCells(aKind, id).length > 0) {
					open.push(id);
				}
			}
			for (const groupSize of SUBSET_SIZES) {
				if (open.length <= groupSize) continue;
				const cleared = subsetPass(board, aKind, bKind, open, groupSize);
				if (cleared > 0) return cleared;
			}
		}
	}
	return 0;
}

function subsetPass(board, aKind, bKind, open, groupSize) {
	const combo = new Int32Array(groupSize);
	for (let k = 0; k < groupSize; k += 1) combo[k] = k;
	for (;;) {
		const touched = [];
		const members = [];
		for (let k = 0; k < groupSize; k += 1) {
			const aId = open[combo[k]];
			members.push(aId);
			for (const cell of board.groupCells(aKind, aId)) {
				const bId = board.groupOf(bKind, Grid.rowOf(board.size, cell),
					Grid.colOf(board.size, cell));
				if (!touched.includes(bId)) touched.push(bId);
			}
		}
		if (touched.length === groupSize) {
			let cleared = 0;
			for (const bId of touched) {
				for (const cell of board.groupCells(bKind, bId)) {
					const row = Grid.rowOf(board.size, cell);
					const col = Grid.colOf(board.size, cell);
					if (members.includes(board.groupOf(aKind, row, col))) continue;
					if (board.clear(row, col)) cleared += 1;
				}
			}
			if (cleared > 0) return cleared;
		}

		let i = groupSize - 1;
		while (i >= 0 && combo[i] === open.length - groupSize + i) i -= 1;
		if (i < 0) break;
		combo[i] += 1;
		for (let j = i + 1; j < groupSize; j += 1) combo[j] = combo[j - 1] + 1;
	}
	return 0;
}
