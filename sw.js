/**
 * Offline play.
 *
 * Everything the game needs is static and small -- the level bank is the largest
 * file at about 48 KB -- so the whole app is precached on install and served from
 * the cache first. A puzzle you can already play should not stop working because
 * the train went into a tunnel.
 *
 * Bump CACHE when anything in ASSETS changes. The old cache is deleted on
 * activate, so a stale mix of files can never be served together.
 */
const CACHE = "nine-lives-v1";

const ASSETS = [
	"./",
	"index.html",
	"manifest.webmanifest",
	"css/style.css",
	"art/cat.png",
	"art/mascot.png",
	"icons/icon-192.png",
	"icons/icon-512.png",
	"icons/icon-1024.png",
	"content/level_bank.json",
	"js/builder.js",
	"js/game-state.js",
	"js/puzzle-state.js",
	"js/save-manager.js",
	"js/save-migration.js",
	"js/settings.js",
	"js/worker.js",
	"js/commands/clear-board-command.js",
	"js/commands/command.js",
	"js/commands/cross-run-command.js",
	"js/commands/set-mark-command.js",
	"js/commands/undo-stack.js",
	"js/puzzle/bank.js",
	"js/puzzle/generator.js",
	"js/puzzle/grid.js",
	"js/puzzle/ladder.js",
	"js/puzzle/level.js",
	"js/puzzle/rater.js",
	"js/puzzle/solver.js",
	"js/ui/board.js",
	"js/ui/game-screen.js",
	"js/ui/lives.js",
	"js/ui/main.js",
	"js/ui/menu-screen.js",
	"js/ui/palette.js",
	"js/util/emitter.js",
	"js/util/rng.js",
];

self.addEventListener("install", (event) => {
	event.waitUntil(
		caches.open(CACHE)
			.then((cache) => cache.addAll(ASSETS))
			.then(() => self.skipWaiting()),
	);
});

self.addEventListener("activate", (event) => {
	event.waitUntil(
		caches.keys()
			.then((names) => Promise.all(
				names.filter((name) => name !== CACHE).map((name) => caches.delete(name)),
			))
			.then(() => self.clients.claim()),
	);
});

self.addEventListener("fetch", (event) => {
	const request = event.request;
	if (request.method !== "GET") return;

	// A navigation to any URL in scope is the app itself: serve the shell rather
	// than 404ing, so a deep link or a refresh from the home screen still opens.
	if (request.mode === "navigate") {
		event.respondWith(
			caches.match("index.html").then((cached) => cached ?? fetch(request)),
		);
		return;
	}

	event.respondWith(
		caches.match(request).then((cached) => cached ?? fetch(request).then((response) => {
			// Cache anything else we end up fetching from our own origin, so a file
			// added after install is available the next time offline.
			if (response.ok && new URL(request.url).origin === self.location.origin) {
				const copy = response.clone();
				caches.open(CACHE).then((cache) => cache.put(request, copy));
			}
			return response;
		})),
	);
});
