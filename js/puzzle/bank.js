import * as Solver from "./solver.js";
import * as Rater from "./rater.js";
import { CatLevel } from "./level.js";

/**
 * Levels generated ahead of time and shipped with the game.
 *
 * Runtime generation is honest but uneven. Carving regions that admit exactly
 * one solution is a rejection loop, and the harder tiers reject a lot -- a player
 * should not wait on that.
 *
 * So the bank ships as data. A level is two short strings, so a few hundred of
 * them is a handful of kilobytes and several minutes of generation. That trade --
 * cheap to store, expensive to find -- is why puzzle apps ship large content
 * archives next to small code.
 *
 * The bank is a convenience, never a requirement. If the file is missing or
 * unreadable the game generates at runtime instead, and an explicit seed always
 * generates.
 */

const BANK_URL = new URL("../../content/level_bank.json", import.meta.url);

let cache = null;
let pending = null;

/** Loads the bank once. Resolves to an empty bank rather than throwing. */
export async function load() {
	if (cache !== null) return cache;
	if (pending === null) {
		pending = fetch(BANK_URL)
			.then((response) => (response.ok ? response.json() : {}))
			.catch(() => ({}))
			.then((parsed) => {
				cache = parsed && typeof parsed === "object" ? parsed : {};
				return cache;
			});
	}
	return pending;
}

export function entriesFor(tier) {
	const tiers = cache?.tiers;
	if (!tiers || typeof tiers !== "object") return [];
	const entries = tiers[String(tier)];
	return Array.isArray(entries) ? entries : [];
}

export function countFor(tier) {
	return entriesFor(tier).length;
}

/**
 * Draws a level from the bank, or returns null when the tier has none.
 * Verifies before handing it over: a corrupt or hand-edited bank should degrade
 * to runtime generation, not to an unsolvable board.
 * `size` of 0 accepts any board size for the tier. `seen` is a set of
 * fingerprints to skip, so a player never gets a board twice.
 *
 * Returns null when everything matching has already been served, which is the
 * signal for the caller to fall back to generating a fresh one.
 */
export function take(tier, rng, size = 0, seen = new Set(), minRegionCells = 1) {
	const candidates = [];
	for (const entry of entriesFor(tier)) {
		if (!entry || typeof entry !== "object") continue;
		const entrySize = Number(entry.size ?? 0);
		if (size > 0 && entrySize !== size) continue;
		const regions = String(entry.regions ?? "");
		if (seen.has(CatLevel.fingerprintOf(entrySize, regions))) continue;
		if (minRegionCells > 1 && smallestRegion(regions) < minRegionCells) continue;
		candidates.push(entry);
	}
	if (candidates.length === 0) return null;

	const level = CatLevel.fromJSON(rng.pick(candidates));
	if (level === null || !level.isValid()) return null;
	if (!Solver.hasUniqueSolution(level.size, level.regions,
		Solver.openConstraints(level.size))) {
		return null;
	}
	level.rating = Rater.rate(level);
	if (!level.rating.solved || level.rating.tier !== tier) return null;
	level.tier = tier;
	return level;
}

/**
 * Smallest colour in a stored region string, without building a whole CatLevel
 * for every candidate.
 */
function smallestRegion(regions) {
	const counts = new Map();
	for (const ch of regions) counts.set(ch, (counts.get(ch) ?? 0) + 1);
	let smallest = regions.length;
	for (const count of counts.values()) smallest = Math.min(smallest, count);
	return smallest;
}

/** Replaces the cached bank. Used by the self-check, which reads the file itself. */
export function seed(document) {
	cache = document ?? {};
	pending = Promise.resolve(cache);
}
