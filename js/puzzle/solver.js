import * as Grid from "./grid.js";

/**
 * Counts solutions, with a limit so uniqueness checks stop at two.
 *
 * The search walks one row at a time, which is the whole trick. One cat per row
 * means row order is a free choice and every row must be filled exactly once, so
 * there is no cell-selection heuristic to get right. Used columns and used
 * regions ride along as bitmasks, and the no-touching rule reduces to "not within
 * one column of the row above" -- two cats more than one row apart can never
 * touch, so nothing else needs remembering.
 *
 * `allowed[row]` is a bitmask of columns still permitted in that row. That single
 * input covers every caller: the generator passes wide-open rows, uniqueness
 * checks after a player's move pass rows narrowed by their cats and crosses, and
 * the hint system passes the same thing.
 */

/** Every column permitted in every row. */
export function openConstraints(size) {
	return new Int32Array(size).fill(Grid.fullMask(size));
}

/** Number of solutions, capped at `limit`. */
export function countSolutions(size, regions, allowed, limit = 2) {
	return search(0, size, regions, allowed, 0, 0, -2, limit);
}

export function hasUniqueSolution(size, regions, allowed) {
	return countSolutions(size, regions, allowed, 2) === 1;
}

/** First solution as columns[row], or an empty array when there is none. */
export function solve(size, regions, allowed) {
	const columns = new Uint8Array(size);
	if (findFirst(0, size, regions, allowed, 0, 0, -2, columns)) return columns;
	return new Uint8Array(0);
}

/**
 * Finds a solution that differs from `known`, or an empty array when `known` is
 * the only one. The generator uses this to repair a level: knowing *which* rival
 * placement slips through tells it exactly which cell to re-colour, where a bare
 * "there are two answers" would leave it guessing.
 */
export function findRival(size, regions, known) {
	const allowed = openConstraints(size);
	const columns = new Uint8Array(size);
	if (searchRival(0, size, regions, allowed, 0, 0, -2, columns, known)) return columns;
	return new Uint8Array(0);
}

function searchRival(row, size, regions, allowed, usedCols, usedRegions, previousCol, columns, known) {
	if (row === size) {
		for (let i = 0; i < size; i += 1) {
			if (columns[i] !== known[i]) return true;
		}
		return false;
	}
	let options = allowed[row] & ~usedCols;
	if (previousCol >= 0) options &= ~Grid.adjacencyBan(size, previousCol);

	while (options !== 0) {
		const low = options & -options;
		options &= options - 1;
		const col = Grid.firstBitIndex(low);
		const regionBit = 1 << regions[row * size + col];
		if ((usedRegions & regionBit) !== 0) continue;
		columns[row] = col;
		if (searchRival(row + 1, size, regions, allowed, usedCols | low,
			usedRegions | regionBit, col, columns, known)) {
			return true;
		}
	}
	return false;
}

function search(row, size, regions, allowed, usedCols, usedRegions, previousCol, limit) {
	if (row === size) return 1;
	let options = allowed[row] & ~usedCols;
	if (previousCol >= 0) options &= ~Grid.adjacencyBan(size, previousCol);

	let total = 0;
	while (options !== 0) {
		const low = options & -options;
		options &= options - 1;
		const col = Grid.firstBitIndex(low);
		const regionBit = 1 << regions[row * size + col];
		if ((usedRegions & regionBit) !== 0) continue;
		total += search(row + 1, size, regions, allowed, usedCols | low,
			usedRegions | regionBit, col, limit - total);
		if (total >= limit) return total;
	}
	return total;
}

function findFirst(row, size, regions, allowed, usedCols, usedRegions, previousCol, columns) {
	if (row === size) return true;
	let options = allowed[row] & ~usedCols;
	if (previousCol >= 0) options &= ~Grid.adjacencyBan(size, previousCol);

	while (options !== 0) {
		const low = options & -options;
		options &= options - 1;
		const col = Grid.firstBitIndex(low);
		const regionBit = 1 << regions[row * size + col];
		if ((usedRegions & regionBit) !== 0) continue;
		columns[row] = col;
		if (findFirst(row + 1, size, regions, allowed, usedCols | low,
			usedRegions | regionBit, col, columns)) {
			return true;
		}
	}
	return false;
}
