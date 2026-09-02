import { Emitter } from "../util/emitter.js";
import { SetMarkCommand } from "./set-mark-command.js";
import { CrossRunCommand } from "./cross-run-command.js";
import { ClearBoardCommand } from "./clear-board-command.js";

/**
 * Two stacks of commands and the rules for moving between them.
 *
 * push() applies the command and drops the redo stack, which is the standard
 * rule: once you make a new move, the future you undid is gone. undo() reverts
 * the top of the undo stack and moves it to redo; redo() does the reverse.
 *
 * Commands write to the board silently; the stack fires the board's change event
 * once per move, after the command has finished. A move touching twenty cells
 * therefore repaints once, not twenty-one times.
 *
 * The whole stack serializes, so closing the app mid-game and coming back does
 * not cost you your undo history. Depth is capped because history is written to
 * storage on every suspend and an unbounded stack would grow the document
 * without limit.
 *
 * Emits: changed(canUndo, canRedo)
 */
export class UndoStack extends Emitter {
	static MAX_DEPTH = 200;

	constructor() {
		super();
		this._undo = [];
		this._redo = [];
	}

	/** Applies `command` and records it. Returns the cells it touched. */
	push(command, state) {
		command.apply(state);
		this._record(command);
		const touched = command.touched();
		state.notify(touched);
		this._emitChanged();
		return touched;
	}

	/**
	 * Records a command whose changes are already on the board.
	 *
	 * A drag applies each cell as the finger passes over it, so by the time the
	 * gesture ends there is nothing left to apply -- only to remember. Re-applying
	 * would be harmless here but dishonest, and it would fire a second change
	 * event for a move the board has already drawn.
	 */
	pushApplied(command, state) {
		this._record(command);
		const touched = command.touched();
		state.notify(touched);
		this._emitChanged();
		return touched;
	}

	undo(state) {
		if (this._undo.length === 0) return [];
		const command = this._undo.pop();
		command.revert(state);
		this._redo.push(command);
		const touched = command.touched();
		state.notify(touched);
		this._emitChanged();
		return touched;
	}

	redo(state) {
		if (this._redo.length === 0) return [];
		const command = this._redo.pop();
		command.apply(state);
		this._undo.push(command);
		const touched = command.touched();
		state.notify(touched);
		this._emitChanged();
		return touched;
	}

	canUndo() {
		return this._undo.length > 0;
	}

	canRedo() {
		return this._redo.length > 0;
	}

	depth() {
		return this._undo.length;
	}

	clear() {
		this._undo = [];
		this._redo = [];
		this._emitChanged();
	}

	toJSON() {
		return { undo: serialize(this._undo), redo: serialize(this._redo) };
	}

	fromJSON(data) {
		this._undo = deserialize(data?.undo);
		this._redo = deserialize(data?.redo);
		this._emitChanged();
	}

	_record(command) {
		this._undo.push(command);
		this._redo = [];
		if (this._undo.length > UndoStack.MAX_DEPTH) this._undo.shift();
	}

	_emitChanged() {
		this.emit("changed", this.canUndo(), this.canRedo());
	}
}

function serialize(stack) {
	return stack.map((command) => command.toJSON());
}

/**
 * Rebuilds commands from saved objects. Unknown entries are dropped rather than
 * faulted, so a document written by a newer build with extra command types still
 * loads -- just with a shorter history.
 */
function deserialize(raw) {
	const stack = [];
	if (!Array.isArray(raw)) return stack;
	for (const entry of raw) {
		if (!entry || typeof entry !== "object") continue;
		const command = build(entry);
		if (command !== null) stack.push(command);
	}
	return stack;
}

/**
 * Command factory. Lives here rather than on SudokuCommand so the base class does
 * not have to name its own subclasses.
 */
export function build(data) {
	switch (String(data.t ?? "")) {
		case SetMarkCommand.TYPE:
			return SetMarkCommand.fromJSON(data);
		case CrossRunCommand.TYPE:
			return CrossRunCommand.fromJSON(data);
		case ClearBoardCommand.TYPE:
			return ClearBoardCommand.fromJSON(data);
		default:
			return null;
	}
}
