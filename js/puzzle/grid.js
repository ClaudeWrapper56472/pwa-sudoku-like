/**
 * Board geometry and the rules of the game.
 *
 * The board is an N x N grid carved into N irregular colour regions. Exactly one
 * cat goes in every row, every column and every region, and no two cats may
 * touch -- not even diagonally.
 *
 * Two consequences shape every algorithm here. Because there is exactly one cat
 * per row, a whole solution is just a list of columns indexed by row: a
 * permutation. And because there is one cat per row, the no-touching rule can
 * only ever bite between *consecutive* rows, which turns adjacency from an
 * awkward 2D check into "the next row's column must differ by more than one".
 */

export const MIN_SIZE = 4;
export const MAX_SIZE = 10;

export const Tier = { EASY: 0, MEDIUM: 1, HARD: 2, EXPERT: 3 };
export const TIER_VALUES = [Tier.EASY, Tier.MEDIUM, Tier.HARD, Tier.EXPERT];
export const TIER_NAMES = ["Easy", "Medium", "Hard", "Expert"];

/**
 * What is in a cell. EXCLUDED is the player's own cross, a note to themselves
 * that costs nothing and can be taken back. WRONG is one the game put there after
 * a cat was refused: it is a fact, not a guess, so it stays for the rest of the
 * level and cannot be edited away.
 */
export const Mark = { EMPTY: 0, EXCLUDED: 1, CAT: 2, WRONG: 3 };

const SPAN = 1 << MAX_SIZE;

const BIT_INDEX = new Uint8Array(SPAN);
for (let bit = 0; bit < MAX_SIZE; bit += 1) BIT_INDEX[1 << bit] = bit;

const POPCOUNT = new Uint8Array(SPAN);
for (let mask = 0; mask < SPAN; mask += 1) {
	let n = 0;
	for (let x = mask; x !== 0; x &= x - 1) n += 1;
	POPCOUNT[mask] = n;
}

export function countBits(mask) {
	return POPCOUNT[mask];
}

export function firstBitIndex(singleBit) {
	return BIT_INDEX[singleBit];
}

export function isSingle(mask) {
	return mask !== 0 && (mask & (mask - 1)) === 0;
}

export function fullMask(size) {
	return (1 << size) - 1;
}

export function indexOf(size, row, col) {
	return row * size + col;
}

export function rowOf(size, index) {
	return Math.floor(index / size);
}

export function colOf(size, index) {
	return index % size;
}

/** Columns a cat in `col` forbids in an adjacent row: itself and its neighbours. */
export function adjacencyBan(size, col) {
	let ban = 1 << col;
	if (col > 0) ban |= 1 << (col - 1);
	if (col < size - 1) ban |= 1 << (col + 1);
	return ban;
}

/** True when two cats would be touching, orthogonally or diagonally. */
export function touching(rowA, colA, rowB, colB) {
	return Math.abs(rowA - rowB) <= 1 && Math.abs(colA - colB) <= 1;
}

/**
 * Checks a complete placement against all four rules. Used by the self-check and
 * as a guard on anything loaded from storage.
 */
export function isValidSolution(size, regions, columns) {
	if (columns.length !== size || regions.length !== size * size) return false;
	let seenCols = 0;
	let seenRegions = 0;
	for (let row = 0; row < size; row += 1) {
		const col = columns[row];
		if (col < 0 || col >= size) return false;
		const colBit = 1 << col;
		if ((seenCols & colBit) !== 0) return false;
		seenCols |= colBit;
		const regionBit = 1 << regions[indexOf(size, row, col)];
		if ((seenRegions & regionBit) !== 0) return false;
		seenRegions |= regionBit;
		if (row > 0 && touching(row, col, row - 1, columns[row - 1])) return false;
	}
	return true;
}

export function orthogonalNeighbours(size, index) {
	const row = rowOf(size, index);
	const col = colOf(size, index);
	const out = [];
	if (row > 0) out.push(index - size);
	if (row < size - 1) out.push(index + size);
	if (col > 0) out.push(index - 1);
	if (col < size - 1) out.push(index + 1);
	return out;
}

/**
 * True when every region is a single connected blob. Disconnected regions are
 * legal for the solver but look broken, so the generator rejects them.
 */
export function regionsAreConnected(size, regions) {
	const counts = new Int32Array(size);
	for (const region of regions) {
		if (region >= size) return false;
		counts[region] += 1;
	}

	for (let region = 0; region < size; region += 1) {
		let start = -1;
		for (let i = 0; i < regions.length; i += 1) {
			if (regions[i] === region) {
				start = i;
				break;
			}
		}
		if (start < 0) return false;
		const seen = new Set([start]);
		const queue = [start];
		while (queue.length > 0) {
			const cell = queue.pop();
			for (const neighbour of orthogonalNeighbours(size, cell)) {
				if (regions[neighbour] === region && !seen.has(neighbour)) {
					seen.add(neighbour);
					queue.push(neighbour);
				}
			}
		}
		if (seen.size !== counts[region]) return false;
	}
	return true;
}

/**
 * Connectivity of one region, which is what the generator needs while it is
 * moving individual cells between regions.
 */
export function regionIsConnected(size, regions, region) {
	let total = 0;
	let start = -1;
	for (let index = 0; index < regions.length; index += 1) {
		if (regions[index] === region) {
			total += 1;
			if (start < 0) start = index;
		}
	}
	if (start < 0) return false;
	const seen = new Set([start]);
	const queue = [start];
	while (queue.length > 0) {
		const cell = queue.pop();
		for (const neighbour of orthogonalNeighbours(size, cell)) {
			if (regions[neighbour] === region && !seen.has(neighbour)) {
				seen.add(neighbour);
				queue.push(neighbour);
			}
		}
	}
	return seen.size === total;
}

export function tierName(tier) {
	return TIER_NAMES[Math.min(Math.max(tier, 0), TIER_NAMES.length - 1)];
}

export function regionsToString(regions) {
	let out = "";
	for (const region of regions) out += String.fromCharCode(65 + region);
	return out;
}

export function regionsFromString(text) {
	const out = new Uint8Array(text.length);
	for (let i = 0; i < text.length; i += 1) out[i] = text.charCodeAt(i) - 65;
	return out;
}

export function columnsToString(columns) {
	let out = "";
	for (const col of columns) out += String(col);
	return out;
}

export function columnsFromString(text) {
	const out = new Uint8Array(text.length);
	for (let i = 0; i < text.length; i += 1) out[i] = text.charCodeAt(i) - 48;
	return out;
}

/**
 * djb2 over a string, as an unsigned 32-bit value. Used only for level
 * fingerprints, where all that is asked of it is that the same board always
 * hashes the same way and different boards usually do not.
 */
export function hashString(text) {
	let hash = 5381;
	for (let i = 0; i < text.length; i += 1) {
		hash = (Math.imul(hash, 33) + text.charCodeAt(i)) | 0;
	}
	return hash >>> 0;
}
