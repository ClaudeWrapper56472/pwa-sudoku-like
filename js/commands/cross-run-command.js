import * as Grid from "../puzzle/grid.js";
import { SudokuCommand } from "./command.js";

/**
 * One drag across a run of cells, crossing them out or clearing them.
 *
 * The whole run is a single undo step, because one gesture is one decision --
 * having to press undo nine times to take back one swipe would be absurd.
 *
 * The run is built as the finger moves so the player sees each cell change
 * immediately, which means the cells are already applied by the time the command
 * reaches the undo stack. That is what UndoStack.pushApplied() exists for.
 *
 * The target mark is fixed when the drag starts, from whatever the first cell
 * was: starting on an empty cell crosses out, starting on a crossed cell erases.
 * Fixing it up front is what stops a drag from flickering cells on and off as it
 * wanders back over its own path.
 */
export class CrossRunCommand extends SudokuCommand {
	static TYPE = "run";

	constructor() {
		super();
		this.newMark = Grid.Mark.EXCLUDED;
		this.indices = [];
		this.oldMarks = [];
	}

	static create(mark) {
		const command = new CrossRunCommand();
		command.newMark = mark;
		return command;
	}

	/**
	 * Adds one cell to the run and applies it immediately. Returns true when the
	 * cell was actually taken.
	 *
	 * Cells holding a cat are skipped: dragging past a cat you have already placed
	 * should never wipe it, and a drag is far too easy to aim carelessly. Cells
	 * the game has proved wrong are skipped for the same reason -- there is
	 * nothing left to decide about them.
	 */
	extend(state, index) {
		if (state.marks[index] === Grid.Mark.CAT || state.isLocked(index)) return false;
		if (state.marks[index] === this.newMark) return false;
		this.indices.push(index);
		this.oldMarks.push(state.marks[index]);
		state.put(index, this.newMark);
		return true;
	}

	isEmpty() {
		return this.indices.length === 0;
	}

	apply(state) {
		for (const index of this.indices) state.putIfEditable(index, this.newMark);
	}

	revert(state) {
		for (let i = 0; i < this.indices.length; i += 1) {
			state.putIfEditable(this.indices[i], this.oldMarks[i]);
		}
	}

	touched() {
		return this.indices;
	}

	describe() {
		const what = this.newMark === Grid.Mark.EXCLUDED ? "cross" : "clear";
		return `${what} run of ${this.indices.length}`;
	}

	toJSON() {
		return { t: CrossRunCommand.TYPE, m: this.newMark, i: this.indices, o: this.oldMarks };
	}

	static fromJSON(data) {
		const command = new CrossRunCommand();
		command.newMark = Number(data.m ?? Grid.Mark.EXCLUDED);
		command.indices = Array.isArray(data.i) ? data.i.map(Number) : [];
		command.oldMarks = Array.isArray(data.o) ? data.o.map(Number) : [];
		// A truncated or hand-edited entry would revert cells it never touched.
		if (command.oldMarks.length !== command.indices.length) return null;
		return command;
	}
}
