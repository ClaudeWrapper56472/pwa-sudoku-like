class_name SaveMigration
extends RefCounted
## Save-format versioning.
##
## Pure functions, no file access, so migration can be unit tested without
## touching user:// -- which matters, because a migration bug corrupts real
## players' progress and is the one thing you cannot hotfix after the fact.
##
## The rule: every save carries a version, migration only ever moves forward one
## step at a time, and an unrecognised or newer version is discarded rather than
## guessed at.
##
## Each step is a public function so it can be tested on its own. The chain is
## only as trustworthy as its weakest link, and testing only the whole chain
## hides which link broke.
##
## Version history
##     1    Flat document. Marks as an array of small integers, difficulty as a
##        display name, stats keyed by difficulty name, no undo history.
##     2    Session and stats separated. Marks as one character per cell, difficulty
##        as a tier value, plus undo history, hint counts and the daily streak.

const CURRENT_VERSION := 4

const _V1_TIER_NAMES := {
	"easy": CatGrid.Tier.EASY,
	"medium": CatGrid.Tier.MEDIUM,
	"hard": CatGrid.Tier.HARD,
	"expert": CatGrid.Tier.EXPERT,
}
const _V1_MARKS := [".", "x", "c"]


static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	if version <= 0 or version > CURRENT_VERSION:
		# Either not one of ours, or written by a build newer than this one. A
		# newer save may use fields we would silently drop, so start clean rather
		# than corrupt it.
		return empty_document()

	var document := data.duplicate(true)
	while version < CURRENT_VERSION:
		match version:
			1:
				document = migrate_v1_to_v2(document)
			2:
				document = migrate_v2_to_v3(document)
			3:
				document = migrate_v3_to_v4(document)
			_:
				return empty_document()
		version = int(document.get("version", CURRENT_VERSION))
	return normalize(document)


static func empty_document() -> Dictionary:
	return {"version": CURRENT_VERSION, "session": {}, "stats": empty_stats()}


static func empty_stats() -> Dictionary:
	var tiers := {}
	for tier in CatGrid.Tier.values():
		tiers[str(tier)] = empty_tier_stats()
	return {
		"tiers": tiers,
		"streak": empty_streak(),
		"hints_used": 0,
		"progress": empty_progress(),
		"seen": empty_seen(),
	}


## Fingerprints of boards already served, and the size they belong to.
##
## Only one size is ever tracked. LevelLadder's sizes never decrease, so the
## moment the board grows every smaller board becomes unreachable and its
## fingerprints are dead weight.
## Levels cleared in a row without running out of lives.
static func empty_streak() -> Dictionary:
	return {"current": 0, "best": 0}


static func empty_seen() -> Dictionary:
	return {"size": 0, "prints": []}


static func empty_progress() -> Dictionary:
	return {"level": LevelLadder.FIRST_LEVEL, "completed": 0}


static func empty_tier_stats() -> Dictionary:
	return {"started": 0, "won": 0, "best_time": 0, "total_time": 0, "mistakes": 0}


## Fills in anything a partially written or hand-edited save is missing, so the
## rest of the game can read fields without guarding every one.
static func normalize(document: Dictionary) -> Dictionary:
	document["version"] = CURRENT_VERSION
	if not document.get("session") is Dictionary:
		document["session"] = {}
	if not document.get("stats") is Dictionary:
		document["stats"] = empty_stats()

	var stats: Dictionary = document["stats"]
	if not stats.get("tiers") is Dictionary:
		stats["tiers"] = {}
	for tier in CatGrid.Tier.values():
		var key := str(tier)
		if not stats["tiers"].get(key) is Dictionary:
			stats["tiers"][key] = empty_tier_stats()
		else:
			var defaults := empty_tier_stats()
			for field in defaults:
				if not stats["tiers"][key].has(field):
					stats["tiers"][key][field] = defaults[field]
	if not stats.get("streak") is Dictionary:
		stats["streak"] = empty_streak()
	else:
		var streak: Dictionary = stats["streak"]
		# last_win_day marks a save from when the streak counted consecutive days
		# rather than consecutive levels. The number means something different
		# now, so start it over rather than show a figure that reads as levels but
		# was earned in days.
		if streak.has("last_win_day"):
			streak.erase("last_win_day")
			streak["current"] = 0
			streak["best"] = 0
		for field in ["current", "best"]:
			if not streak.has(field):
				streak[field] = 0
	if not stats.has("hints_used"):
		stats["hints_used"] = 0
	# `seen` is purely a de-duplication convenience, so it needs no version bump:
	# normalize() exists for exactly this, and the worst case of throwing an
	# unrecognised shape away is that one board could repeat.
	if not stats.get("seen") is Dictionary:
		stats["seen"] = empty_seen()
	else:
		if not stats["seen"].get("prints") is Array:
			stats["seen"]["prints"] = []
		if not stats["seen"].has("size"):
			stats["seen"]["size"] = 0
	if not stats.get("progress") is Dictionary:
		stats["progress"] = empty_progress()
	else:
		var defaults := empty_progress()
		for field in defaults:
			if not stats["progress"].has(field):
				stats["progress"][field] = defaults[field]
	stats["progress"]["level"] = maxi(int(stats["progress"]["level"]), LevelLadder.FIRST_LEVEL)
	return document


static func migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	var session := {}
	var size := int(data.get("size", 0))
	var regions := String(data.get("regions", ""))
	if size > 0 and regions.length() == size * size:
		session = {
			"tier": _tier_from_name(String(data.get("difficulty", "Easy"))),
			"seed": int(data.get("seed", 0)),
			"board": {
				"level": {
					"size": size,
					"regions": regions,
					"columns": String(data.get("solution", "")),
					"tier": _tier_from_name(String(data.get("difficulty", "Easy"))),
					"seed": int(data.get("seed", 0)),
				},
				"marks": _marks_to_string(data.get("marks", []), size * size),
			},
			"elapsed": float(data.get("elapsed", 0.0)),
			"mistakes": int(data.get("mistakes", 0)),
			# v1 tracked neither hints nor undo history. Zero and empty are the
			# honest values -- a resumed v1 game simply starts with nothing to undo.
			"hints": 0,
			"selected": -1,
			"history": {"undo": [], "redo": []},
		}

	var stats := empty_stats()
	var old_stats: Dictionary = data.get("stats", {})
	for name in old_stats:
		var tier: int = _V1_TIER_NAMES.get(String(name).to_lower(), -1)
		if tier < 0 or not old_stats[name] is Dictionary:
			continue
		var entry: Dictionary = old_stats[name]
		var won := int(entry.get("won", 0))
		var best := int(entry.get("best", 0))
		stats["tiers"][str(tier)] = {
			"started": int(entry.get("played", 0)),
			"won": won,
			"best_time": best,
			# v1 never recorded cumulative time, so best_time per win is the only
			# estimate available. Noted here so the average is not mistaken for
			# exact history.
			"total_time": best * won,
			"mistakes": 0,
		}

	return {"version": 2, "session": session, "stats": stats}


## v2 was played under different rules: a cat could sit on a wrong cell without
## ending the level, and placing one crossed out its row, column and colour.
##
## The crosses are kept -- they are still the player's own reasoning. Wrong cats
## are lifted, because under the current rules that board could not exist. And
## the undo history is dropped rather than migrated: those commands were recorded
## against the old rules and reverting one could reconstruct a board the new rules
## would never produce. A shorter history is a much smaller cost than a save that
## can undo into an impossible state.
static func migrate_v2_to_v3(data: Dictionary) -> Dictionary:
	var document := data.duplicate(true)
	document["version"] = 3
	var session: Variant = document.get("session")
	if not session is Dictionary or (session as Dictionary).is_empty():
		return document

	var board: Variant = (session as Dictionary).get("board")
	if board is Dictionary:
		var level := CatLevel.from_dict((board as Dictionary).get("level", {}))
		var marks := String((board as Dictionary).get("marks", ""))
		if level != null and marks.length() == level.size * level.size:
			var cleaned := ""
			for index in marks.length():
				var mark := marks[index]
				if mark == "c" and not level.is_solution_cell(index):
					mark = "."
				cleaned += mark
			(board as Dictionary)["marks"] = cleaned
	(session as Dictionary)["history"] = {"undo": [], "redo": []}
	return document


## v3 let the player pick a difficulty; v4 has one climbing progression instead.
##
## There is no record of which level anyone was on, because the concept did not
## exist. Total wins is the closest honest estimate: someone who finished twelve
## puzzles has done roughly twelve levels of work, so that is where they resume.
## It can only ever be generous, never punishing, which is the right direction to
## be wrong in.
static func migrate_v3_to_v4(data: Dictionary) -> Dictionary:
	var document := data.duplicate(true)
	document["version"] = 4

	var stats: Variant = document.get("stats")
	if not stats is Dictionary:
		return document
	var won := 0
	var tiers: Variant = (stats as Dictionary).get("tiers", {})
	if tiers is Dictionary:
		for key in tiers as Dictionary:
			if (tiers as Dictionary)[key] is Dictionary:
				won += int(((tiers as Dictionary)[key] as Dictionary).get("won", 0))
	(stats as Dictionary)["progress"] = {
		"level": LevelLadder.FIRST_LEVEL + won,
		"completed": won,
	}

	# A v3 session was a one-off puzzle at a chosen difficulty. It has no level
	# number and cannot be given one honestly, so it is dropped -- losing one
	# unfinished puzzle is a smaller cost than resuming into a level that lies
	# about where the player is.
	document["session"] = {}
	return document


static func _tier_from_name(name: String) -> int:
	return _V1_TIER_NAMES.get(name.to_lower(), CatGrid.Tier.EASY)


## v1 stored one small integer per cell; v2 stores one character per cell.
static func _marks_to_string(raw: Variant, cells: int) -> String:
	var out := ""
	var values: Array = raw if raw is Array else []
	for i in cells:
		var mark := int(values[i]) if i < values.size() else 0
		out += _V1_MARKS[clampi(mark, 0, _V1_MARKS.size() - 1)]
	return out
