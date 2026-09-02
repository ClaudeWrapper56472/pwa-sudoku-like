import * as Grid from "../puzzle/grid.js";
import * as Ladder from "../puzzle/ladder.js";
import { Emitter } from "../util/emitter.js";

/**
 * Title screen. One button: it carries on from a suspended level if there is one,
 * and otherwise starts the level the player is up to.
 *
 * The menu does not decide which of those it is -- it just reports the press and
 * lets the router work out whether there is a game to resume. All it asks the
 * save for is what to write on the button.
 *
 * Emits: playRequested()
 */
export class MenuScreen extends Emitter {
	constructor(root, save) {
		super();
		this.root = root;
		this.save = save;
		this._playButton = root.querySelector("#play-button");
		this._stats = root.querySelector("#menu-stats");

		this._playButton.addEventListener("click", () => this.emit("playRequested"));
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
