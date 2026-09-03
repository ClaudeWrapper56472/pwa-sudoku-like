import * as Grid from "../puzzle/grid.js";
import * as Ladder from "../puzzle/ladder.js";
import { Emitter } from "../util/emitter.js";

/**
 * Title screen. The play button carries on from a suspended level if there is
 * one, and otherwise starts the level the player is up to. Below it, Easy, Medium
 * and Hard start their part of the ladder, each at the furthest level the player
 * has reached there.
 *
 * The menu does not decide which of those it is -- it just reports the press and
 * lets the router work out whether there is a game to resume. All it asks the
 * save for is what to write on the buttons.
 *
 * Emits: playRequested(), difficultyChosen(level)
 */
export class MenuScreen extends Emitter {
	constructor(root, save) {
		super();
		this.root = root;
		this.save = save;
		this._playButton = root.querySelector("#play-button");
		this._startAt = root.querySelector("#start-at");
		this._stats = root.querySelector("#menu-stats");
		this._difficultyButtons = [];

		this._playButton.addEventListener("click", () => this.emit("playRequested"));
		this._buildDifficulties();
		save.on("statsChanged", () => this.refresh());
		save.on("sessionAvailable", () => this.refresh());
		this.refresh();
	}

	refresh() {
		if (this.save.hasSession()) {
			const session = this.save.session();
			const seconds = Math.floor(Number(session.elapsed ?? 0));
			const minutes = Math.floor(seconds / 60);
			const rest = String(seconds % 60).padStart(2, "0");
			this._playButton.textContent =
				`Continue level ${Number(session.level ?? 1)}  ·  ${minutes}:${rest}`;
		} else {
			this._playButton.textContent = `Play level ${this.save.currentLevel()}`;
		}
		this._renderStats();
		this._renderDifficulties();
	}

	/**
	 * The difficulty row, built once and relabelled from the save on every
	 * refresh. Each button reads the level it would start, so the row is also a
	 * statement of where the player has got to.
	 */
	_buildDifficulties() {
		const heading = document.createElement("h2");
		heading.textContent = "Start at";

		const row = document.createElement("div");
		row.className = "difficulty";
		row.setAttribute("role", "group");
		row.setAttribute("aria-label", "Start at a difficulty");

		for (const [index, entry] of Ladder.DIFFICULTIES.entries()) {
			const button = document.createElement("button");
			button.type = "button";
			const level = document.createElement("span");
			level.className = "level";
			const size = document.createElement("span");
			size.className = "size";
			button.append(document.createTextNode(entry.name), level, size);
			// Read at press time rather than captured: which level a difficulty
			// starts moves with the save.
			button.addEventListener("click", () => this.emit("difficultyChosen",
				Ladder.difficultyLevel(index, this.save.currentLevel())));
			this._difficultyButtons.push(button);
			row.append(button);
		}

		this._startAt.replaceChildren(heading, row);
	}

	/**
	 * Labels each difficulty with the level it starts and marks the one the player
	 * is up to. That button is their furthest level, so there is always a way back
	 * to it from the menu -- including while a suspended level is holding the play
	 * button, which is the only other way there.
	 */
	_renderDifficulties() {
		const current = this.save.currentLevel();
		const band = Ladder.difficultyIndexFor(current);
		this._difficultyButtons.forEach((button, index) => {
			const entry = Ladder.DIFFICULTIES[index];
			const level = Ladder.difficultyLevel(index, current);
			const size = Ladder.sizeFor(level);
			button.querySelector(".level").textContent = `Level ${level}`;
			button.querySelector(".size").textContent = `${size}×${size}`;
			// The × needs saying in words for a screen reader.
			button.setAttribute("aria-label",
				`${entry.name}: level ${level}, a ${size} by ${size} board`);
			if (index === band) button.setAttribute("aria-current", "true");
			else button.removeAttribute("aria-current");
		});
	}

	_renderStats() {
		const level = this.save.currentLevel();
		const size = Ladder.sizeFor(level);
		const completed = this.save.levelsCompleted();
		const streak = this.save.stats().streak ?? {};
		const run = Number(streak.current ?? 0);
		const bestRun = Number(streak.best ?? 0);

		const lines = [
			`On level ${level}  ·  ${Grid.tierName(Ladder.tierFor(level))} ${size}×${size}`,
			`${completed} level${completed === 1 ? "" : "s"} finished`,
		];
		if (run > 0) lines.push(`${run} in a row (best ${bestRun})`);
		else if (bestRun > 0) lines.push(`Best run ${bestRun} in a row`);
		const nextSize = Ladder.nextStepUp(level);
		if (nextSize > 0) lines.push(`Bigger board at level ${nextSize}`);

		this._stats.replaceChildren();
		const heading = document.createElement("h2");
		heading.textContent = "Progress";
		this._stats.append(heading);
		for (const line of lines) {
			const paragraph = document.createElement("p");
			paragraph.textContent = line;
			this._stats.append(paragraph);
		}
	}
}
