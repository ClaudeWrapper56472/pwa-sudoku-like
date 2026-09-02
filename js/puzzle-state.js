import * as Grid from "./puzzle/grid.js";
import { CatLevel } from "./puzzle/level.js";
import { Emitter } from "./util/emitter.js";

/**
 * The board the player is working on: the level, and what they have marked.
 *
 * Deliberately separate from GameState. Commands act on this, so the undo system
 * has no dependency on the running game and can be built and tested on its own.
 * GameState owns one of these and relays its event outward.
 *
 * Emits: cellsChanged(indices)
 */
export class PuzzleState extends Emitter {
	constructor() {
		super();
		this.level = null;
		this.marks = new Uint8Array(0); // one Grid.Mark per cell
	}

	setup(newLevel) {
		this.level = newLevel;
		this.marks = new Uint8Array(newLevel.size * newLevel.size);
	}

	size() {
		return this.level !== null ? this.level.size : 0;
	}

	markAt(index) {
		return this.marks[index];
	}

	regionAt(index) {
		return this.level.regions[index];
	}

	/**
	 * Silent write used by commands. They batch several of these and then call
	 * notify() once, so the board repaints a move rather than each cell of it.
	 */
	put(index, mark) {
		this.marks[index] = mark;
	}

	/**
	 * Silent write that refuses to disturb a settled cell.
	 *
	 * Commands use this rather than put(). No command ever *targets* a locked cell
	 * -- every entry point checks first -- but a command already on the undo stack
	 * can name a cell that has since been settled: cross a cell, clear the board,
	 * then lose a life on that same cell, and the clear command still holds its old
	 * cross. Reverting it blindly would repaint over the red the game paid a life
	 * to establish, which is exactly what a spent life is not allowed to do.
	 */
	putIfEditable(index, mark) {
		if (this.isLocked(index)) return;
		this.marks[index] = mark;
	}

	notify(indices) {
		this.emit("cellsChanged", indices);
	}

	/**
	 * A cell whose answer is settled. Nothing about it can be edited, because
	 * there is nothing left to decide.
	 *
	 * Both kinds of settled cell get here. A red cross is one the game proved
	 * wrong. A cat is one the player got right -- and since a wrong cat is refused
	 * rather than placed, every cat on the board is correct by construction.
	 */
	isLocked(index) {
		return this.marks[index] === Grid.Mark.WRONG || this.marks[index] === Grid.Mark.CAT;
	}

	/**
	 * True when there is anything of the player's own to clear. Locked cells do
	 * not count -- they cannot be cleared, so a board holding only those has
	 * nothing to offer the Clear button.
	 */
	hasPlayerMarks() {
		for (let index = 0; index < this.marks.length; index += 1) {
			if (this.marks[index] !== Grid.Mark.EMPTY && !this.isLocked(index)) return true;
		}
		return false;
	}

	catsPlaced() {
		let n = 0;
		for (const mark of this.marks) {
			if (mark === Grid.Mark.CAT) n += 1;
		}
		return n;
	}

	catCells() {
		const out = [];
		for (let index = 0; index < this.marks.length; index += 1) {
			if (this.marks[index] === Grid.Mark.CAT) out.push(index);
		}
		return out;
	}

	/**
	 * A cat is wrong when it is not where the solution puts it.
	 *
	 * Because the level has exactly one solution, every other cell is one the
	 * player could have ruled out. There is no such thing as a cat that is "not
	 * wrong yet".
	 */
	isWrongCat(index) {
		return this.marks[index] === Grid.Mark.CAT && !this.level.isSolutionCell(index);
	}

	/**
	 * Why a cat here would be wrong, in the player's terms. Asked before anything
	 * is placed, so it reads the board as it stands. A cell can be wrong without
	 * clashing with anything already down -- it is simply not in the answer -- so
	 * a specific rule is only quoted when one is actually broken.
	 */
	explainWrong(index) {
		const n = this.size();
		const row = Grid.rowOf(n, index);
		const col = Grid.colOf(n, index);
		for (const other of this.catCells()) {
			if (other === index) continue;
			const otherRow = Grid.rowOf(n, other);
			const otherCol = Grid.colOf(n, other);
			if (Grid.touching(row, col, otherRow, otherCol)) {
				return "Cats cannot touch, not even corner to corner.";
			}
			if (otherRow === row) return "There is already a cat in that row.";
			if (otherCol === col) return "There is already a cat in that column.";
			if (this.level.regions[other] === this.level.regions[index]) {
				return "There is already a cat in that colour.";
			}
		}
		return "No cat can go there.";
	}

	/** Solved when every cat in the solution is on the board and nothing else is. */
	isComplete() {
		if (this.level === null) return false;
		let placed = 0;
		for (let index = 0; index < this.marks.length; index += 1) {
			if (this.marks[index] !== Grid.Mark.CAT) continue;
			if (!this.level.isSolutionCell(index)) return false;
			placed += 1;
		}
		return placed === this.size();
	}

	marksToString() {
		let out = "";
		for (const mark of this.marks) {
			if (mark === Grid.Mark.EXCLUDED) out += "x";
			else if (mark === Grid.Mark.CAT) out += "c";
			else if (mark === Grid.Mark.WRONG) out += "w";
			else out += ".";
		}
		return out;
	}

	marksFromString(text) {
		this.marks = new Uint8Array(this.size() * this.size());
		for (let i = 0; i < text.length && i < this.marks.length; i += 1) {
			const ch = text[i];
			if (ch === "x") this.marks[i] = Grid.Mark.EXCLUDED;
			else if (ch === "c") this.marks[i] = Grid.Mark.CAT;
			else if (ch === "w") this.marks[i] = Grid.Mark.WRONG;
			else this.marks[i] = Grid.Mark.EMPTY;
		}
	}

	toJSON() {
		return { level: this.level.toJSON(), marks: this.marksToString() };
	}

	fromJSON(data) {
		const restored = CatLevel.fromJSON(data?.level ?? {});
		if (restored === null || !restored.isValid()) return false;
		this.setup(restored);
		this.marksFromString(String(data?.marks ?? ""));
		return true;
	}
}
