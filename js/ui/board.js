import * as Grid from "../puzzle/grid.js";
import { regionColour } from "./palette.js";
import { Emitter } from "../util/emitter.js";

/**
 * The grid of cells.
 *
 * Board owns the cell elements and nothing else. It listens to GameState and
 * pushes what it hears down into cells; it sends taps back up as events rather
 * than calling GameState itself, so the same board could be reused for a replay
 * viewer or a tutorial with a different controller behind it.
 *
 * The board is rebuilt whenever a level loads, because the size changes between
 * levels -- a 5x5 Easy and a 9x9 Expert are the same grid with a different number
 * of children.
 *
 * A cell is a div with the region colour on it and a class per mark. The cross is
 * an inline SVG so its geometry scales with the cell rather than being redrawn,
 * and the cat is an img so one file serves every board size.
 *
 * Emits: cellTapped(index), cellDoubleTapped(index), cellRightClicked(index),
 *        dragStarted(index), dragReached(index), dragEnded()
 */
export class BoardView extends Emitter {
	/**
	 * Two taps on the same cell this close together place a cat.
	 *
	 * The first of them has already crossed the cell out by the time the second
	 * lands, so a cat placed this way shows a cross for a moment first. That is the
	 * price of the gesture: crossing out is the bulk of play and it answers
	 * immediately, rather than every cross waiting to find out whether a second tap
	 * is coming.
	 */
	static DOUBLE_TAP_MS = 300;

	/**
	 * Gap between cells, as a fraction of the board. It is also exactly how far a
	 * cat may spill over a cell edge, which is what makes the art look like it
	 * fills the cell rather than floating inside it.
	 */
	static GAP_RATIO = 0.0072;

	constructor(root, game) {
		super();
		this.root = root;
		this.game = game;
		this._cells = [];
		this._hintedCell = -1;

		/**
		 * Pointer state. `_origin` is where the press landed, `_current` is the cell
		 * the pointer is over now; they differ the moment a press becomes a drag.
		 */
		this._origin = -1;
		this._current = -1;
		this._dragging = false;
		this._pointerId = null;
		/** The last tap, for spotting the second half of a double one. */
		this._lastTapIndex = -1;
		this._lastTapAt = 0;
		/** What kind of pointer is pressing, so a hold cannot pass for a right-click. */
		this._pointerType = "";

		this._installPointerHandlers();
		new ResizeObserver(() => this._measure()).observe(this.root);

		game.on("levelLoaded", () => {
			this._hintedCell = -1;
			this._rebuild();
		});
		game.on("cellsChanged", () => this.refreshAll());
		game.on("selectionChanged", () => this._refreshHighlights());
		game.on("hintOffered", (index, _message, success) => {
			this._hintedCell = success ? index : -1;
			for (let i = 0; i < this._cells.length; i += 1) {
				this._cells[i].classList.toggle("is-hinted", i === this._hintedCell);
			}
		});
		game.on("levelFailed", () => this.refreshAll());
	}

	_rebuild() {
		// A level can load mid-gesture, and the cell the finger was on is about to
		// stop existing. Drop the gesture rather than let it report cells from a
		// board that has gone, and forget the last tap so it cannot pair with one
		// on the new board.
		this._endGesture?.();
		this._release(-1);
		this._lastTapIndex = -1;
		this.root.replaceChildren();
		this._cells = [];

		const state = this.game.board;
		if (state.level === null) return;
		const n = state.size();
		this.root.style.setProperty("--columns", String(n));

		const fragment = document.createDocumentFragment();
		for (let index = 0; index < n * n; index += 1) {
			const cell = document.createElement("div");
			cell.className = "cell";
			cell.dataset.index = String(index);
			cell.style.setProperty("--region", regionColour(state.regionAt(index)));

			const cross = document.createElementNS("http://www.w3.org/2000/svg", "svg");
			cross.setAttribute("class", "cross");
			cross.setAttribute("viewBox", "0 0 100 100");
			cross.setAttribute("aria-hidden", "true");
			// reach 24 of a 100-unit cell, stroke 11 -- the proportions the original
			// drew, so a cross reads the same at every board size.
			cross.innerHTML = '<path d="M26 26 74 74 M74 26 26 74" />';
			cell.append(cross);

			const cat = document.createElement("img");
			cat.className = "cat";
			cat.src = "art/cat.png";
			cat.alt = "";
			cat.draggable = false;
			cell.append(cat);

			fragment.append(cell);
			this._cells.push(cell);
		}
		this.root.append(fragment);
		this._measure();
		this.refreshAll();
	}

	/**
	 * Publishes the cell size and gap as custom properties, so every cell metric --
	 * corner radius, selection border, how far the cat overhangs -- is a calc()
	 * off one measured number rather than a value recomputed per cell.
	 */
	_measure() {
		const n = this.game.board.size();
		if (n === 0) return;
		const width = this.root.clientWidth;
		if (width === 0) return;
		const gap = Math.max(2, Math.round(width * BoardView.GAP_RATIO));
		const cell = (width - (n - 1) * gap) / n;
		this.root.style.setProperty("--gap", `${gap}px`);
		this.root.style.setProperty("--cell", `${cell}px`);
	}

	/**
	 * The whole board is refreshed rather than just the cells a move named. At most
	 * a hundred cells, and the reveal at the end of a level touches all of them
	 * anyway; the simplicity is worth more than the saved comparisons.
	 */
	refreshAll() {
		if (this._cells.length === 0) return;
		const state = this.game.board;
		for (let index = 0; index < this._cells.length; index += 1) {
			const cell = this._cells[index];
			const mark = state.marks[index];
			cell.classList.toggle("is-cat", mark === Grid.Mark.CAT);
			cell.classList.toggle("is-cross", mark === Grid.Mark.EXCLUDED);
			cell.classList.toggle("is-wrong", mark === Grid.Mark.WRONG);
		}
		this._refreshHighlights();
	}

	_refreshHighlights() {
		const selected = this.game.selected;
		for (let index = 0; index < this._cells.length; index += 1) {
			this._cells[index].classList.toggle("is-selected", index === selected);
		}
	}

	/**
	 * Whether to draw the selected cell's outline.
	 *
	 * It is the keyboard's cursor: with no pointer it is the only way to tell which
	 * cell the next key will change. A tap needs no cursor -- the finger is the
	 * cursor -- and outlining what it just changed reads as something being wrong
	 * with the cell, so pointer play turns it off again.
	 */
	showSelection(on) {
		this.root.classList.toggle("is-keyboard", on);
	}

	// --- Pointer input ------------------------------------------------------
	//
	// All of it lives on the board rather than the cells. Pointer capture routes
	// every move and the release to the element the press landed on, so a cell
	// would only ever hear about itself -- which is no use to a gesture whose whole
	// job is to cross a run of other cells.
	//
	// A press does not commit to being a tap or a drag. It becomes a drag the
	// moment the pointer enters a *different* cell, and stays a tap otherwise. That
	// needs no pixel threshold and matches what a finger expects: a small wobble
	// inside one cell is still a tap.

	_installPointerHandlers() {
		// Only the press is listened for on the board. Move and release are tracked
		// on the window for the length of the gesture.
		//
		// The obvious alternative, setPointerCapture on the board, is the flakiest
		// corner of Pointer Events across engines -- and it buys nothing here,
		// because _cellAt works from viewport coordinates and so does not care
		// which element the event was delivered to. Window listeners also mean a
		// finger that leaves the board still ends its run properly, rather than
		// leaving a gesture stuck open until the next press.
		const onMove = (event) => {
			if (event.pointerId !== this._pointerId || this._origin < 0) return;
			this._move(this._cellAt(event));
		};
		const onFinish = (event) => {
			if (event.pointerId !== this._pointerId) return;
			this._endGesture();
			this._release(this._cellAt(event));
		};

		this._beginGesture = (event) => {
			this._pointerId = event.pointerId;
			window.addEventListener("pointermove", onMove);
			window.addEventListener("pointerup", onFinish);
			window.addEventListener("pointercancel", onFinish);
		};
		this._endGesture = () => {
			this._pointerId = null;
			window.removeEventListener("pointermove", onMove);
			window.removeEventListener("pointerup", onFinish);
			window.removeEventListener("pointercancel", onFinish);
		};

		this.root.addEventListener("pointerdown", (event) => {
			// A second finger while a run is in progress is ignored rather than
			// hijacking it: a drag is one gesture by one pointer.
			if (!event.isPrimary || event.button !== 0 || this._pointerId !== null) return;
			event.preventDefault();
			this._pointerType = event.pointerType;
			this.showSelection(false);
			this._beginGesture(event);
			this._press(this._cellAt(event));
		});

		// Right-click is the mouse's one-press way to place a cat. The menu is
		// suppressed whatever raised it -- a finger held on an Android board raises
		// one too, and there the cat belongs to the second tap, not the hold.
		this.root.addEventListener("contextmenu", (event) => {
			event.preventDefault();
			if (this._pointerType !== "mouse") return;
			const index = this._cellAt(event);
			if (index >= 0) this.emit("cellRightClicked", index);
		});

		// iOS still zooms on a double tap here, touch-action or not. Cancelling
		// touchend stops it. Nothing on the board listens for click, so nothing
		// else is lost.
		this.root.addEventListener("touchend", (event) => {
			event.preventDefault();
		}, { passive: false });
	}

	_press(index) {
		this._origin = index;
		this._current = index;
		this._dragging = false;
	}

	_move(index) {
		if (index < 0 || index === this._current || this._origin < 0) return;
		if (!this._dragging) {
			this._dragging = true;
			// Leaving the cell makes this a drag rather than a tap. A wobble inside
			// one cell does not get here.
			this.emit("dragStarted", this._origin);
		}
		this._current = index;
		this.emit("dragReached", index);
	}

	_release(index) {
		if (this._dragging) {
			// A drag is never half of a double tap, so it clears what came before it.
			this._lastTapIndex = -1;
			this.emit("dragEnded");
		} else if (this._origin >= 0 && index === this._origin) {
			const now = performance.now();
			const second = index === this._lastTapIndex
				&& now - this._lastTapAt <= BoardView.DOUBLE_TAP_MS;
			// A pair is spent once it fires. Without this a third tap would pair with
			// the second and place a cat on a cell the player is trying to clear.
			this._lastTapIndex = second ? -1 : index;
			this._lastTapAt = now;
			this.emit(second ? "cellDoubleTapped" : "cellTapped", index);
		}
		this._origin = -1;
		this._current = -1;
		this._dragging = false;
	}

	/**
	 * Which cell sits under a pointer event, or -1.
	 *
	 * elementFromPoint rather than arithmetic on the grid: it costs one hit test,
	 * it is correct through any transform or scroll the page later grows, and the
	 * gap between cells genuinely belongs to no cell, which is the behaviour a
	 * drag wants anyway.
	 */
	_cellAt(event) {
		const target = document.elementFromPoint(event.clientX, event.clientY);
		const cell = target?.closest?.(".cell");
		if (!cell || cell.parentElement !== this.root) return -1;
		return Number(cell.dataset.index);
	}
}
