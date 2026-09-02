import * as Grid from "../puzzle/grid.js";
import { SudokuCommand } from "./command.js";

/**
 * Changes what is in one cell.
 *
 * Every edit in this game is one cell changing between empty, crossed and cat,
 * so this is the only single-cell command there is.
 *
 * The command pattern earns its place: the move serializes to four integers so
 * undo history survives a restart, redo is free, and the board is told which
 * cell to repaint rather than repainting all eighty-one.
 */
export class SetMarkCommand extends SudokuCommand {
	static TYPE = "mark";

	constructor() {
		super();
		this.index = -1;
		this.newMark = Grid.Mark.EMPTY;
		this.oldMark = Grid.Mark.EMPTY;
	}

	/**
	 * Builds the command against the board as it currently stands, capturing the
	 * old state. Call this before pushing to the undo stack.
	 */
	static create(state, cell, mark) {
		const command = new SetMarkCommand();
		command.index = cell;
		command.newMark = mark;
		command.oldMark = state.marks[cell];
		return command;
	}

	apply(state) {
		state.putIfEditable(this.index, this.newMark);
	}

	revert(state) {
		state.putIfEditable(this.index, this.oldMark);
	}

	touched() {
		return [this.index];
	}

	describe() {
		const what = this.newMark === Grid.Mark.EXCLUDED ? "cross"
			: (this.newMark === Grid.Mark.CAT ? "cat" : "clear");
		return `${what} at ${this.index}`;
	}

	toJSON() {
		return { t: SetMarkCommand.TYPE, i: this.index, m: this.newMark, o: this.oldMark };
	}

	static fromJSON(data) {
		const command = new SetMarkCommand();
		command.index = Number(data.i ?? -1);
		command.newMark = Number(data.m ?? Grid.Mark.EMPTY);
		command.oldMark = Number(data.o ?? Grid.Mark.EMPTY);
		return command;
	}
}
