/**
 * Offline play.
 *
 * Everything the game needs is static and small -- the level bank is the largest
 * file at about 48 KB -- so the whole app is precached on install. A puzzle you
 * can already play should not stop working because the train went into a tunnel.
 *
 * Two strategies, split by what goes wrong when a file is stale.
 *
 * Code -- the shell, the modules, the stylesheet -- is fetched from the network
 * first and falls back to the cache. They are a few kilobytes each, so the cost
 * of asking is small, and the cost of not asking is a browser pinned to an old
 * build forever: a cache-first worker with a hand-written version string serves
 * whatever it captured until someone remembers to bump the string, and a stale
 * mix of modules fails in ways that look like the app is simply broken.
 *
 * Content -- the art, the icons, the level bank -- is served cache-first. It is
 * the bulk of the bytes and it only changes when its filename does.
 */
const CACHE = "nine-lives-v2";

/** Files whose freshness matters more than the round trip to check it. */
const CODE = /\.(?:html|js|css|webmanifest)$/;

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
	if (new URL(request.url).origin !== self.location.origin) return;
	// A no-store request wants the network's own answer, redirect and all. The
	// menu sends one to find out whether the session has lapsed.
	if (request.cache === "no-store") return;

	if (request.mode === "navigate") {
		// The sign-in is left to the browser itself, as on the first visit.
		if (new URL(request.url).searchParams.has("signin")) return;
		event.respondWith(navigate(request));
		return;
	}

	if (CODE.test(new URL(request.url).pathname)) {
		event.respondWith(freshest(request));
		return;
	}

	event.respondWith(
		caches.match(request).then((cached) => cached ?? store(request)),
	);
});

/**
 * Opening the app. Any URL in scope is the app, so a deep link or a refresh from
 * the home screen gets the shell rather than a 404.
 *
 * Behind access control, a lapsed session answers with a redirect to the sign-in
 * and a failed sign-in with a 401 page. Neither is the app, so while a copy of
 * the shell is cached that opens instead, and the sign-in waits until the menu
 * asks for it with ?signin. With nothing cached, the first visit, the redirect
 * goes through because there is nothing else to show.
 */
async function navigate(request) {
	const shell = async () => await caches.match(request) ?? await caches.match("index.html");
	let response;
	try {
		response = await store(request);
	} catch (error) {
		const cached = await shell();
		if (cached !== undefined) return cached;
		throw error;
	}
	if (response.ok) return response;
	return await shell() ?? response;
}

/** Network first, with the cache as the answer when the network has no good one. */
async function freshest(request) {
	let response;
	try {
		response = await store(request);
	} catch (error) {
		const cached = await caches.match(request);
		if (cached !== undefined) return cached;
		throw error;
	}
	if (response.ok) return response;
	return await caches.match(request) ?? response;
}

/**
 * Fetches and files the result, so the next load has it offline.
 *
 * Redirects are not followed where the request allows it: behind access control
 * they lead to the sign-in three hops away, and a module's URL must never file
 * what comes back. A no-cors request cannot opt out, so a stylesheet or image
 * still follows, comes back opaque, and fails the ok check instead.
 */
async function store(request) {
	const manual = request.mode === "cors" || request.mode === "same-origin";
	const response = await fetch(request, manual ? { redirect: "manual" } : undefined);
	if (response.ok) {
		const copy = response.clone();
		const cache = await caches.open(CACHE);
		await cache.put(request, copy);
	}
	return response;
}
