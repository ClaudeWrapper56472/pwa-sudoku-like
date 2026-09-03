import * as Ladder from "../puzzle/ladder.js";
import { BoardView } from "./board.js";
import { LivesView } from "./lives.js";
import { Emitter } from "../util/emitter.js";

/**
 * The playing screen: board, toolbar and the panels that cover them.
 *
 * This is the only view that knows all the pieces exist, and its whole job is
 * translating between them: a tap on the board becomes a GameState call, a
 * GameState event becomes a label update. Nothing here holds game state of its
 * own, so the screen can be closed and reopened mid-level without losing
 * anything.
 *
 * Emits: exitRequested()
 */
export class GameScreen extends Emitter {
	/** How long a status message stays up. */
	static STATUS_MS = 3500;

	constructor(root, game) {
		super();
		this.root = root;
		this.game = game;

		this._tierLabel = root.querySelector("#tier-label");
		this._timeLabel = root.querySelector("#time-label");
		this._progressLabel = root.querySelector("#progress-label");
		this._statusLabel = root.querySelector("#status-label");
		this._undoButton = root.querySelector("#undo-button");
		this._redoButton = root.querySelector("#redo-button");
		this._clearButton = root.querySelector("#clear-button");
		this._hintButton = root.querySelector("#hint-button");
		this._backButton = root.querySelector("#back-button");
		this._loadingPanel = root.querySelector("#loading-panel");
		this._loadingLabel = root.querySelector("#loading-label");
		this._resultPanel = root.querySelector("#result-panel");
		this._resultTitle = root.querySelector("#result-title");
		this._resultDetail = root.querySelector("#result-detail");
		this._againButton = root.querySelector("#again-button");
		this._resultMenuButton = root.querySelector("#result-menu-button");

		this._playArea = root.querySelector(".play-area");
		this._headerRow = root.querySelector(".header-row");
		this._bottomBar = root.querySelector(".bottom-bar");

		this._lives = new LivesView(root.querySelector("#lives"));
		this._board = new BoardView(root.querySelector("#board"), game);

		this._statusTimer = null;
		/** Which button the result card is offering: the next level, or this one again. */
		this._retryMode = false;

		this._wireBoard();
		this._wireButtons();
		this._wireGame();
		this._installKeyboard();

		this._loadingPanel.hidden = true;
		this._resultPanel.hidden = true;
		this._statusLabel.textContent = "";
		this._clearButton.disabled = true;

		// The screen for the viewport changing, the bottom bar for a status message
		// that wraps onto another line. Neither depends on how big the board is, so
		// publishing a new limit cannot start a loop.
		const fit = new ResizeObserver(() => this._publishBoardLimit());
		fit.observe(this.root);
		fit.observe(this._bottomBar);
	}

	/**
	 * How much height is left for the board: the screen, less its padding, less
	 * everything stacked around it.
	 *
	 * The board is square and takes the width it is given, so on a screen too
	 * short for a full-width one it is the height that has to do the deciding. The
	 * stylesheet caps the board's width with this.
	 */
	_publishBoardLimit() {
		const height = this.root.clientHeight;
		// Hidden, so there is nothing to measure and the last limit still holds.
		if (height === 0) return;
		const styles = getComputedStyle(this.root);
		const gap = parseFloat(getComputedStyle(this._playArea).rowGap) || 0;
		const around = this._headerRow.offsetHeight + this._progressLabel.offsetHeight
			+ this._bottomBar.offsetHeight + gap * 2;
		const limit = height - parseFloat(styles.paddingTop)
			- parseFloat(styles.paddingBottom) - around;
		this.root.style.setProperty("--board-limit", `${Math.max(limit, 0)}px`);
	}

	_wireBoard() {
		this._board.on("cellTapped", (index) => {
			this.game.select(index);
			this.game.toggleCross(index);
		});
		// Two ways to commit a cat, one meaning. The board reports the gesture; what
		// it amounts to is decided here.
		for (const gesture of ["cellLongPressed", "cellRightClicked"]) {
			this._board.on(gesture, (index) => {
				this.game.select(index);
				this.game.toggleCat(index);
			});
		}
		this._board.on("dragStarted", (index) => this.game.beginCrossRun(index));
		this._board.on("dragReached", (index) => this.game.extendCrossRun(index));
		this._board.on("dragEnded", () => this.game.endCrossRun());
	}

	_wireButtons() {
		this._backButton.addEventListener("click", () => this._onBackPressed());
		this._undoButton.addEventListener("click", () => this.game.undo());
		this._redoButton.addEventListener("click", () => this.game.redo());
		this._clearButton.addEventListener("click", () => this.game.clearBoard());
		this._hintButton.addEventListener("click", () => this.game.useHint());
		this._againButton.addEventListener("click", () => this._onPlayAgainPressed());
		this._resultMenuButton.addEventListener("click", () => this._onBackPressed());
	}

	_wireGame() {
		const game = this.game;
		game.on("generationStarted", (level) => {
			this._resultPanel.hidden = true;
			this._loadingPanel.hidden = false;
			this._loadingLabel.textContent = `Setting up level ${level}…`;
		});
		game.on("generationFinished", (success) => {
			this._loadingPanel.hidden = true;
			if (!success) this._showStatus("Could not build a level. Try again.");
		});
		game.on("levelLoaded", () => {
			this._resultPanel.hidden = true;
			this._tierLabel.textContent = Ladder.describe(game.levelNumber);
			if (Ladder.isStepUp(game.levelNumber)) {
				this._showStatus("Bigger board from here on — take your time.");
			} else {
				this._showStatus("Tap or drag to cross out. Hold a cell to place a cat.");
			}
		});
		game.on("timeChanged", (seconds) => {
			this._timeLabel.textContent = formatTime(seconds);
		});
		game.on("livesChanged", (remaining, total) => this._lives.set(remaining, total));
		game.on("wrongCat", (_index, message) => this._showStatus(message));
		game.on("catsChanged", (placed, total) => {
			this._progressLabel.textContent = `${placed} / ${total} cats`;
		});
		// Disabled when there is nothing of the player's to wipe, so it never looks
		// like a button that does nothing.
		game.on("cellsChanged", () => {
			this._clearButton.disabled = !game.board.hasPlayerMarks();
		});
		game.on("historyChanged", (canUndo, canRedo) => {
			this._undoButton.disabled = !canUndo;
			this._redoButton.disabled = !canRedo;
		});
		game.on("hintOffered", (_index, message) => this._showStatus(message));
		game.on("hintsChanged", (remaining) => {
			this._hintButton.disabled = remaining <= 0;
		});
		game.on("levelCompleted", (level, seconds, hints) => {
			this._retryMode = false;
			this._resultTitle.textContent = `Level ${level} done`;
			const parts = [formatTime(seconds)];
			const lost = game.mistakes();
			if (lost > 0) parts.push(`${lost} wrong cat${lost === 1 ? "" : "s"}`);
			if (hints > 0) parts.push(`${hints} hint${hints === 1 ? "" : "s"}`);
			this._resultDetail.textContent = parts.join("   ");
			this._againButton.textContent = `Level ${level + 1}`;
			this._resultPanel.hidden = false;
			this._againButton.focus();
		});
		game.on("levelFailed", () => {
			this._retryMode = true;
			this._resultTitle.textContent = "Out of lives";
			this._resultDetail.textContent = "Three cats in the wrong spot. Try again.";
			this._againButton.textContent = "Try again";
			this._resultPanel.hidden = false;
			this._againButton.focus();
		});
	}

	/**
	 * Keyboard play. The board is quicker to drive from the keyboard than from the
	 * pointer, which matters while developing and is the only way in for anyone who
	 * cannot use a pointer at all.
	 */
	_installKeyboard() {
		window.addEventListener("keydown", (event) => {
			if (this.root.hidden || !this._resultPanel.hidden || !this._loadingPanel.hidden) return;
			// A focused button owns Space and Enter; stealing them would break the
			// toolbar for keyboard users.
			if (event.target instanceof HTMLButtonElement && (event.key === " " || event.key === "Enter")) {
				return;
			}
			const game = this.game;
			const key = event.key;
			if (key === " " || key === "x" || key === "X") game.toggleCross(game.selected);
			else if (key === "Enter" || key === "c" || key === "C") game.toggleCat(game.selected);
			else if (key === "Backspace" || key === "Delete") game.clearCell(game.selected);
			else if (key === "h" || key === "H") game.useHint();
			else if ((key === "z" || key === "Z") && (event.ctrlKey || event.metaKey)) {
				if (event.shiftKey) game.redo();
				else game.undo();
			} else if ((key === "y" || key === "Y") && event.ctrlKey) game.redo();
			else if (key === "ArrowLeft") game.moveSelection(0, -1);
			else if (key === "ArrowRight") game.moveSelection(0, 1);
			else if (key === "ArrowUp") game.moveSelection(-1, 0);
			else if (key === "ArrowDown") game.moveSelection(1, 0);
			else if (key === "Escape") this._onBackPressed();
			else return;
			event.preventDefault();
		});
	}

	_onPlayAgainPressed() {
		this._resultPanel.hidden = true;
		if (this._retryMode) this.game.restartLevel();
		// The level after the one just finished, which is what the button says.
		// A player who dropped back to an easier board carries on from there.
		else this.game.startLevel(this.game.levelNumber + 1);
	}

	_onBackPressed() {
		if (!this.game.finished) this.game.suspend();
		this.emit("exitRequested");
	}

	_showStatus(message) {
		this._statusLabel.textContent = message;
		if (this._statusTimer !== null) clearTimeout(this._statusTimer);
		this._statusTimer = setTimeout(() => {
			this._statusLabel.textContent = "";
			this._statusTimer = null;
		}, GameScreen.STATUS_MS);
	}
}

function formatTime(seconds) {
	return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}
