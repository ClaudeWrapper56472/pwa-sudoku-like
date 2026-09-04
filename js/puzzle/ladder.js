import * as Grid from "./grid.js";

/**
 * Turns a level number into a board to generate.
 *
 * Level 1 is a gentle 5x5 and every level after it is a little harder, so the
 * player meets each new idea once they have had some practice with the last one.
 * The menu's Easy, Medium and Hard are three entry points onto this one ladder
 * (see DIFFICULTIES), not three separate settings.
 *
 * Difficulty climbs on two axes. The board grows, and within each size the
 * techniques required ramp from Easy to Expert -- so the curve rises steadily and
 * dips slightly whenever the board grows, which is the breather that pays for the
 * extra rows and columns.
 *
 * Each size lasts longer than the one before it. A 5x5 is understood in a few
 * goes; a 9x9 deserves twenty. It also means the sizes, which run out, take much
 * longer to do so than a player does.
 */

export const FIRST_LEVEL = 1;
export const FIRST_SIZE = 5;
export const LAST_SIZE = 10;

/**
 * How many levels are spent on each board size, from FIRST_SIZE upward. The last
 * entry is how long the final size takes to ramp from Easy to Expert; after that
 * the level number keeps climbing but the board and the tier stay put.
 *
 * These total 99, so the 10x10 boards begin at level 100.
 */
export const LEVELS_PER_SIZE = [10, 15, 20, 24, 30, 30];

/**
 * Why the ladder stops growing at 10x10, when the level count does not:
 *
 *   Generating a unique board costs roughly five times more per extra row --
 *   8 ms at 9x9, 34 ms at 10x10, 1.7 s at 12x12, where almost nothing succeeds.
 *   Cells shrink below a comfortable touch target: 41 pt at 9x9, 37 pt at 10x10,
 *   30 pt at 12x12, against Apple's 44 pt guidance.
 *   And every region needs its own colour. Past a dozen flat colours nobody can
 *   tell them apart at cell size, which is a limit of eyes rather than code.
 */
const FINAL_RAMP = 30;

/**
 * From this level on, no colour may be a single square.
 *
 * A one-square colour is a free placement -- the cat can only go there -- so it
 * is the easiest foothold on any board. Removing it means the player has to open
 * the puzzle with real reasoning rather than a gift. By this point they are deep
 * into 10x10 Expert boards and have earned it.
 */
export const NO_SINGLE_CELL_REGIONS_FROM = 150;

export function sizeFor(level) {
	let remaining = Math.max(level, FIRST_LEVEL) - FIRST_LEVEL;
	for (let step = 0; step < LEVELS_PER_SIZE.length; step += 1) {
		if (remaining < LEVELS_PER_SIZE[step]) return FIRST_SIZE + step;
		remaining -= LEVELS_PER_SIZE[step];
	}
	return LAST_SIZE;
}

export function tierFor(level) {
	let remaining = Math.max(level, FIRST_LEVEL) - FIRST_LEVEL;
	for (let step = 0; step < LEVELS_PER_SIZE.length; step += 1) {
		if (remaining < LEVELS_PER_SIZE[step]) {
			return Math.min(Math.floor(Grid.TIER_VALUES.length * remaining / LEVELS_PER_SIZE[step]),
				Grid.Tier.EXPERT);
		}
		remaining -= LEVELS_PER_SIZE[step];
	}
	return Grid.Tier.EXPERT;
}

export function minRegionCells(level) {
	return level >= NO_SINGLE_CELL_REGIONS_FROM ? 2 : 1;
}

/**
 * The entry points the menu offers, in order, as the board size each opens on.
 *
 * Each one opens on the first level of its size, where the technique ramp begins
 * again at Easy: somebody picking Hard wants a bigger board, not to be dropped
 * into Expert deductions on a board they have never seen. Picking one is starting
 * that stretch of the ladder over, whatever the player has done since -- the way
 * back to where they were is the menu's own button.
 */
export const DIFFICULTIES = [
	{ name: "Easy", size: FIRST_SIZE },
	{ name: "Medium", size: 7 },
	{ name: "Hard", size: 9 },
];

/** The first level played on a board of this size. */
export function firstLevelAtSize(size) {
	const wanted = Math.min(Math.max(size, FIRST_SIZE), LAST_SIZE);
	let level = FIRST_LEVEL;
	for (let step = 0; step < LEVELS_PER_SIZE.length; step += 1) {
		if (FIRST_SIZE + step >= wanted) break;
		level += LEVELS_PER_SIZE[step];
	}
	return level;
}

/** Short caption for the top bar: "Level 7  ·  Medium 6x6". */
export function describe(level) {
	const size = sizeFor(level);
	return `Level ${level}  ·  ${Grid.tierName(tierFor(level))} ${size}×${size}`;
}

/** True when this level is the first on a bigger board, so the UI can warn. */
export function isStepUp(level) {
	return level > FIRST_LEVEL && sizeFor(level) !== sizeFor(level - 1);
}

/** First level on the largest board. Past it the boards stop growing. */
export function finalSizeLevel() {
	let total = FIRST_LEVEL;
	for (let step = 0; step < LEVELS_PER_SIZE.length - 1; step += 1) total += LEVELS_PER_SIZE[step];
	return total;
}

/**
 * The next level that puts the player on a bigger board, or 0 when there are no
 * bigger boards left.
 */
export function nextStepUp(level) {
	let next = Math.max(level, FIRST_LEVEL) + 1;
	const limit = finalSizeLevel();
	while (next <= limit) {
		if (isStepUp(next)) return next;
		next += 1;
	}
	return 0;
}

/**
 * Every board the ladder can ask for, as {tier, size, minimum colour size}. The
 * shipped bank covers exactly what players will actually be served.
 */
export function combinations() {
	const out = [];
	const seen = new Set();
	const last = Math.max(finalSizeLevel() + FINAL_RAMP, NO_SINGLE_CELL_REGIONS_FROM);
	for (let level = FIRST_LEVEL; level <= last; level += 1) {
		const spec = { tier: tierFor(level), size: sizeFor(level), minRegion: minRegionCells(level) };
		const key = `${spec.tier}:${spec.size}:${spec.minRegion}`;
		if (seen.has(key)) continue;
		seen.add(key);
		out.push(spec);
	}
	return out;
}
