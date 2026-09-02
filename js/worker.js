/**
 * Level generation, off the main thread.
 *
 * Carving regions that admit exactly one solution is a rejection loop, and a
 * 10x10 Expert board can take seconds. Running it here keeps the main thread free
 * to draw the "finding a level" overlay and keeps the page responsive.
 *
 * The protocol is one request in, one reply out, tagged with the caller's id so
 * a reply that arrives after the player has moved on can be recognised and
 * dropped.
 */
import { buildLevel, levelToMessage } from "./builder.js";

self.addEventListener("message", async (event) => {
	const { id, level, seen } = event.data;
	try {
		const built = await buildLevel(level, seen ?? []);
		self.postMessage({ id, level: levelToMessage(built) });
	} catch (error) {
		self.postMessage({ id, level: null, error: String(error) });
	}
});
