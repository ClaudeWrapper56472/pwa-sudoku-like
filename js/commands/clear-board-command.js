import * as Grid from "../puzzle/grid.js";
import { SudokuCommand } from "./command.js";

/**
 * Wipes every mark the player made, as a single undo step.
 *
 * Cells the game locked in red are left alone. Those are not the player's
 * working -- they are facts the game paid a life to establish, and clearing the
 * board should not quietly hand those lives back.
 *
 * One command rather than one per cell: throwing away twenty minutes of crossing
 * out is exactly the move somebody wants back in one press.
 */
export class ClearBoardCommand extends SudokuCommand {
	static TYPE = "clear";

	constructor() {
		super();
		this.indices = [];
		this.oldMarks = [];
	}

	static create(state) {
		const command = new ClearBoardCommand();
		for (let index = 0; index < state.marks.length; index += 1) {
			if (state.marks[index] === Grid.Mark.EMPTY || state.isLocked(index)) continue;
			command.indices.push(index);
			command.oldMarks.push(state.marks[index]);
		}
		return command;
	}

	isEmpty() {
		return this.indices.length === 0;
	}

	apply(state) {
		for (const index of this.indices) state.putIfEditable(index, Grid.Mark.EMPTY);
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
		return `clear ${this.indices.length} cells`;
	}

	toJSON() {
		return { t: ClearBoardCommand.TYPE, i: this.indices, o: this.oldMarks };
	}

	static fromJSON(data) {
		const command = new ClearBoardCommand();
		command.indices = Array.isArray(data.i) ? data.i.map(Number) : [];
		command.oldMarks = Array.isArray(data.o) ? data.o.map(Number) : [];
		// A truncated entry would restore cells it never recorded.
		if (command.oldMarks.length !== command.indices.length) return null;
		return command;
	}
}
