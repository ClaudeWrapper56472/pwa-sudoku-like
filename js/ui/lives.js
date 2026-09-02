/**
 * The row of hearts in the top bar.
 *
 * Spent lives stay on screen as hollow outlines rather than disappearing. A row
 * that shrinks tells you how many you have; a row that hollows out tells you how
 * many you have *left of how many*, which is the number that matters when you
 * are deciding whether to guess.
 */
export class LivesView {
	constructor(root) {
		this.root = root;
		this._remaining = -1;
		this._total = -1;
	}

	set(remaining, total) {
		if (this._remaining === remaining && this._total === total) return;
		if (this._total !== total) {
			this.root.replaceChildren();
			for (let i = 0; i < total; i += 1) {
				const heart = document.createElementNS("http://www.w3.org/2000/svg", "svg");
				heart.setAttribute("class", "heart");
				heart.setAttribute("viewBox", "0 0 24 22");
				heart.setAttribute("aria-hidden", "true");
				heart.innerHTML = '<path d="M12 21C12 21 1.5 14.4 1.5 7.9 1.5 4.3 4.2 1.5 '
					+ '7.6 1.5 9.7 1.5 11.2 2.6 12 3.9 12.8 2.6 14.3 1.5 16.4 1.5 19.8 1.5 '
					+ '22.5 4.3 22.5 7.9 22.5 14.4 12 21 12 21Z" />';
				this.root.append(heart);
			}
		}
		this._remaining = remaining;
		this._total = total;
		const hearts = this.root.children;
		for (let i = 0; i < hearts.length; i += 1) {
			hearts[i].classList.toggle("is-spent", i >= remaining);
		}
		this.root.setAttribute("aria-label", `${remaining} of ${total} lives left`);
	}
}
