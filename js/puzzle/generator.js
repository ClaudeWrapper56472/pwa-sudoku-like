import * as Grid from "./grid.js";
import * as Solver from "./solver.js";
import * as Rater from "./rater.js";
import { CatLevel } from "./level.js";
import { Rng } from "../util/rng.js";

/**
 * Builds levels for a requested difficulty tier.
 *
 * Sudoku generation starts from a filled board and removes clues. This puzzle
 * has no clues to remove -- the *regions are the puzzle*. So generation runs the
 * other way round: pick where the cats go first, then carve regions around them
 * so that placement is the only one that works.
 *
 * 1. Draw a random legal placement: one cat per row and column, none touching.
 * 2. Seed one region on each cat and grow all N regions outward until they
 *    partition the board. Every region then contains exactly one cat by
 *    construction, so the placement is guaranteed to be *a* solution.
 * 3. Check it is the *only* solution. Region growth is random, so it usually is
 *    not on the first try -- a fatter region gives the solver more room and lets
 *    a second arrangement slip through.
 * 4. Rate it, and reject if the rating misses the requested tier.
 *
 * Regrowing regions is much cheaper than redrawing the placement, so a failed
 * attempt retries growth several times before giving up on the placement.
 */

export const DEFAULT_MAX_ATTEMPTS = 400;
const GROWTH_RETRIES = 12;

/**
 * Board sizes each tier draws from. Size and difficulty are related but not the
 * same thing -- a 9x9 can fall to nothing but forced singles -- so the rater
 * still decides, and this only sets the shape of the board.
 */
export const TIER_SIZES = {
	[Grid.Tier.EASY]: [5, 6],
	[Grid.Tier.MEDIUM]: [6, 7],
	[Grid.Tier.HARD]: [7, 8],
	[Grid.Tier.EXPERT]: [8, 9],
};

const UNASSIGNED = 0xff;

/**
 * Pass `fixedSize` to pin the board size; leave it 0 to draw from the tier's own
 * range. The level ladder pins it, because the size a player sees needs to climb
 * predictably rather than wander inside a tier.
 * `seen` is a set of fingerprints to avoid, so the same board is not generated
 * twice for the same player.
 */
export function generate(tier, seed = 0, maxAttempts = DEFAULT_MAX_ATTEMPTS,
	fixedSize = 0, seen = new Set(), minRegionCells = 1) {
	const actualSeed = seed !== 0 ? seed : Rng.randomSeed();
	const rng = new Rng(actualSeed);

	const sizes = TIER_SIZES[tier] ?? [7];
	let best = null;
	// A level that hits the tier but has been served before. Kept as a last
	// resort: repeating a board is a small annoyance, failing to produce one at
	// all is a broken game.
	let repeat = null;
	for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
		// Only draw when the size is free, so a pinned size does not shift the
		// random sequence and change which levels a seed produces.
		const size = fixedSize > 0 ? fixedSize : sizes[rng.randiRange(0, sizes.length - 1)];
		const level = attemptOne(size, rng, minRegionCells);
		if (level === null) continue;
		level.seed = actualSeed;
		level.attempts = attempt + 1;
		if (level.tier === tier) {
			if (!seen.has(level.fingerprint())) return level;
			if (repeat === null) repeat = level;
			continue;
		}
		if (best === null || Math.abs(level.tier - tier) < Math.abs(best.tier - tier)) {
			best = level;
		}
	}
	if (repeat !== null) {
		repeat.attempts = maxAttempts;
		return repeat;
	}
	if (best !== null) best.attempts = maxAttempts;
	return best;
}

function attemptOne(size, rng, minRegionCells) {
	const columns = randomPlacement(size, rng);
	if (columns.length === 0) return null;

	for (let retry = 0; retry < GROWTH_RETRIES; retry += 1) {
		const regions = growRegions(size, columns, rng, minRegionCells);
		if (regions.length === 0) continue;
		if (!refineRegions(size, regions, columns, rng, 40, minRegionCells)) continue;
		if (!Grid.regionsAreConnected(size, regions)) continue;

		const level = new CatLevel();
		level.size = size;
		level.regions = regions;
		level.columns = columns;
		const rating = Rater.rate(level);
		level.rating = rating;
		// A level the logical solver cannot finish needs something outside our
		// technique set. We cannot honestly label it, so push it out of range.
		level.tier = rating.solved ? rating.tier : -99;
		return level;
	}
	return null;
}

/** A random legal placement: one cat per row and column, none touching. */
export function randomPlacement(size, rng) {
	const columns = new Uint8Array(size);
	if (placeRow(0, size, rng, 0, -2, columns)) return columns;
	return new Uint8Array(0);
}

function placeRow(row, size, rng, usedCols, previousCol, columns) {
	if (row === size) return true;
	let options = Grid.fullMask(size) & ~usedCols;
	if (previousCol >= 0) options &= ~Grid.adjacencyBan(size, previousCol);

	const choices = [];
	while (options !== 0) {
		const low = options & -options;
		options &= options - 1;
		choices.push(Grid.firstBitIndex(low));
	}
	rng.shuffle(choices);

	for (const col of choices) {
		columns[row] = col;
		if (placeRow(row + 1, size, rng, usedCols | (1 << col), col, columns)) return true;
	}
	return false;
}

/**
 * Grows N regions outward from the cats until they partition the board.
 *
 * Growth picks a random *frontier cell* and hands it to one of its neighbouring
 * regions, which means a region with more edge grows faster. That unevenness is
 * the point. An earlier version always extended the smallest region, which gave
 * beautifully balanced blobs and terrible puzzles -- every board had six or more
 * solutions. Uneven regions constrain far harder: a colour squeezed into two or
 * three cells forces a placement almost immediately, and that cascades.
 * `minCells` forces every colour to cover at least that many squares. A colour
 * of exactly one square is a free placement -- the cat can only go there -- so
 * banning them removes the easiest foothold on the board.
 */
export function growRegions(size, columns, rng, minCells = 1) {
	const cells = size * size;
	const regions = new Uint8Array(cells).fill(UNASSIGNED);
	const counts = new Int32Array(size);
	for (let row = 0; row < size; row += 1) {
		regions[Grid.indexOf(size, row, columns[row])] = row;
		counts[row] = 1;
	}

	let remaining = cells - size;

	// First bring every colour up to the minimum, smallest first. This is the
	// balanced growth that makes for weak puzzles, which is why it stops the
	// moment the minimum is met and hands over to the uneven growth below.
	while (remaining > 0) {
		let smallest = -1;
		for (let region = 0; region < size; region += 1) {
			if (counts[region] >= minCells) continue;
			if (smallest < 0 || counts[region] < counts[smallest]) smallest = region;
		}
		if (smallest < 0) break;
		const room = freeNeighboursOf(size, regions, smallest);
		if (room.length === 0) return new Uint8Array(0); // boxed in; the caller retries
		regions[rng.pick(room)] = smallest;
		counts[smallest] += 1;
		remaining -= 1;
	}

	while (remaining > 0) {
		const frontier = frontierCells(size, regions);
		if (frontier.length === 0) return new Uint8Array(0);
		const cell = rng.pick(frontier);
		const owners = [];
		for (const neighbour of Grid.orthogonalNeighbours(size, cell)) {
			if (regions[neighbour] !== UNASSIGNED) owners.push(regions[neighbour]);
		}
		regions[cell] = rng.pick(owners);
		remaining -= 1;
	}
	return regions;
}

/** Unassigned cells orthogonally touching one particular region. */
function freeNeighboursOf(size, regions, region) {
	const out = [];
	for (let index = 0; index < regions.length; index += 1) {
		if (regions[index] !== UNASSIGNED) continue;
		for (const neighbour of Grid.orthogonalNeighbours(size, index)) {
			if (regions[neighbour] === region) {
				out.push(index);
				break;
			}
		}
	}
	return out;
}

/** Unassigned cells touching at least one assigned cell. */
function frontierCells(size, regions) {
	const out = [];
	for (let index = 0; index < regions.length; index += 1) {
		if (regions[index] !== UNASSIGNED) continue;
		for (const neighbour of Grid.orthogonalNeighbours(size, index)) {
			if (regions[neighbour] !== UNASSIGNED) {
				out.push(index);
				break;
			}
		}
	}
	return out;
}

/**
 * Repairs a level that has more than one solution.
 *
 * Blind retries are wasteful, and there is a targeted move available. Take a
 * rival placement and any row where it disagrees with ours. Its cat there sits in
 * some colour; re-colour that one cell to any *neighbouring* colour and the rival
 * instantly uses that colour twice, so it dies. Our own placement is untouched,
 * because the cell we move is never one of our cats.
 *
 * Each pass therefore kills at least the rival it was shown. New rivals can
 * appear, so it loops -- but it converges in a handful of passes where random
 * regrowth would take hundreds of attempts.
 */
export function refineRegions(size, regions, columns, rng, maxPasses = 40, minCells = 1) {
	for (let passIndex = 0; passIndex < maxPasses; passIndex += 1) {
		const rival = Solver.findRival(size, regions, columns);
		if (rival.length === 0) return true;

		const rows = [];
		for (let row = 0; row < size; row += 1) {
			if (rival[row] !== columns[row]) rows.push(row);
		}
		rng.shuffle(rows);

		let moved = false;
		for (const row of rows) {
			const cell = Grid.indexOf(size, row, rival[row]);
			if (columns[Grid.rowOf(size, cell)] === Grid.colOf(size, cell)) {
				continue; // never move one of our own cats
			}
			const fromRegion = regions[cell];
			const options = [];
			for (const neighbour of Grid.orthogonalNeighbours(size, cell)) {
				const candidate = regions[neighbour];
				if (candidate !== fromRegion && !options.includes(candidate)) options.push(candidate);
			}
			rng.shuffle(options);

			for (const toRegion of options) {
				regions[cell] = toRegion;
				// Moving a cell out must not break the donor apart, nor shrink it
				// below the minimum -- a repair that reintroduces a one-square
				// colour would undo the very thing the caller asked for.
				if (Grid.regionIsConnected(size, regions, fromRegion)
					&& regionSize(regions, fromRegion) >= minCells) {
					moved = true;
					break;
				}
				regions[cell] = fromRegion;
			}
			if (moved) break;
		}
		if (!moved) return false;
	}
	return Solver.countSolutions(size, regions, Solver.openConstraints(size), 2) === 1;
}

function regionSize(regions, region) {
	let n = 0;
	for (const value of regions) {
		if (value === region) n += 1;
	}
	return n;
}
