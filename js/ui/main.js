import { Settings } from "../settings.js";
import { SaveManager } from "../save-manager.js";
import { GameState } from "../game-state.js";
import { MenuScreen } from "./menu-screen.js";
import { GameScreen } from "./game-screen.js";

/**
 * Boot and screen router.
 *
 * Both screens exist from the start and are shown or hidden, rather than being
 * built and thrown away. There are only two of them and they are cheap, and
 * keeping them alive means the board does not rebuild its hundred cells every
 * time the player glances at the menu.
 */

const settings = new Settings();
settings.load();

const save = new SaveManager(settings);
save.load();
save.installSuspendHooks();

const game = new GameState(save);

const menuRoot = document.querySelector("#menu-screen");
const gameRoot = document.querySelector("#game-screen");
const menu = new MenuScreen(menuRoot, save);
const screen = new GameScreen(gameRoot, game);

function showMenu() {
	menuRoot.hidden = false;
	gameRoot.hidden = true;
	menu.refresh();
	// Build the next board while the player is looking at the menu, so pressing
	// Play is instant even on the big boards where generating takes seconds.
	game.prefetchUpcoming();
}

function showGame() {
	menuRoot.hidden = true;
	gameRoot.hidden = false;
}

/**
 * Resuming is just what "play" means when there is something to resume. Keeping
 * that decision here rather than in the menu means the menu never has to ask the
 * save anything except what to write on the button.
 */
menu.on("playRequested", () => {
	showGame();
	if (!game.resumeSavedGame()) game.startLevel();
});

screen.on("exitRequested", showMenu);
// The result panel is already up; the menu just needs to forget the session.
game.on("levelFailed", () => menu.refresh());

showMenu();

if ("serviceWorker" in navigator) {
	window.addEventListener("load", () => {
		navigator.serviceWorker.register("sw.js").catch((error) => {
			// Offline play is the only casualty, and it is not worth a visible error.
			console.warn("Service worker registration failed.", error);
		});
	});
}
