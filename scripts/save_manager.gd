extends Node
## Autoload: reads and writes user://sudoku_save.json.
##
## Two jobs, kept in one file because they share a document: the in-progress
## game, and lifetime statistics.
##
## Saving is driven by a signal rather than a node path. SaveManager announces
## "I am about to write", whoever owns live state hands it over, and the write
## happens. That keeps this file free of any knowledge of GameState, and it means
## a second system with state to persist only has to connect.
##
## The write itself goes to a temp file and is then renamed. Renaming within a
## filesystem is atomic, so a process killed mid-save leaves either the old file
## or the new one, never a half-written one -- which matters here because the
## most likely moment to be killed is exactly when we are saving, during app
## suspend.

signal save_requested()
signal stats_changed()
signal session_available(available: bool)

const SAVE_PATH := "user://sudoku_save.json"
const TEMP_PATH := "user://sudoku_save.tmp"
## How many past boards to remember at the current size. Only the largest board
## ever accumulates enough to reach this.
const SEEN_LIMIT := 400

var _document: Dictionary = SaveMigration.empty_document()
var _loaded := false


func _ready() -> void:
	# Autoloads keep processing while the tree is paused, so a save triggered by
	# a pause notification still runs.
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_document()


## Mobile platforms give no warning before the process is killed, so every hook
## that might be the last one we get writes the file.
##
##   APPLICATION_PAUSED   iOS/Android moved us to the background
##   APPLICATION_FOCUS_OUT  a phone call or notification took the foreground
##   WM_CLOSE_REQUEST     desktop window closing
##   WM_GO_BACK_REQUEST   Android back gesture out of the app
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, \
		NOTIFICATION_APPLICATION_FOCUS_OUT, \
		NOTIFICATION_WM_CLOSE_REQUEST, \
		NOTIFICATION_WM_GO_BACK_REQUEST, \
		NOTIFICATION_EXIT_TREE:
			flush()


## Collects live state from whoever is listening, then writes.
func flush() -> void:
	if not _loaded:
		return
	save_requested.emit()
	Settings.save_settings()
	_write_document()


## Called from a save_requested handler.
func submit_session(session: Dictionary) -> void:
	_document["session"] = session


func clear_session() -> void:
	_document["session"] = {}
	_write_document()
	session_available.emit(false)


func has_session() -> bool:
	var session: Variant = _document.get("session", {})
	return session is Dictionary and not (session as Dictionary).is_empty()


func session() -> Dictionary:
	return _document.get("session", {})


func stats() -> Dictionary:
	return _document.get("stats", SaveMigration.empty_stats())


func tier_stats(tier: int) -> Dictionary:
	return stats().get("tiers", {}).get(str(tier), SaveMigration.empty_tier_stats())


## Fingerprints of boards already served at `size`, as a set for quick lookup.
##
## Only the current board size is ever tracked. LevelLadder never sends a player
## back to a smaller board, so the moment the size goes up every fingerprint
## below it is unreachable and gets dropped -- which is why the cap below rarely
## comes into play until a player settles on the largest board for good.
##
## Rebuilt from the stored array on each read because JSON turns every number
## into a float on the way back in; comparing an int against those floats would
## silently never match and the whole mechanism would quietly do nothing.
func seen_fingerprints(size: int) -> Dictionary:
	var known := {}
	var seen: Dictionary = stats().get("seen", SaveMigration.empty_seen())
	if int(seen.get("size", 0)) != size:
		return known
	for value in seen.get("prints", []):
		known[int(value)] = true
	return known


func has_seen(size: int, fingerprint: int) -> bool:
	return seen_fingerprints(size).has(fingerprint)


## Records a board as served. Moving up a size throws the previous size's list
## away wholesale, since none of it can come round again.
func record_seen(size: int, fingerprint: int) -> void:
	var seen: Dictionary = stats().get("seen", SaveMigration.empty_seen())
	var prints: Array = []
	if int(seen.get("size", 0)) == size:
		for value in seen.get("prints", []):
			prints.append(int(value))
		if prints.has(fingerprint):
			return
	prints.append(fingerprint)
	if prints.size() > SEEN_LIMIT:
		prints = prints.slice(prints.size() - SEEN_LIMIT)

	var all_stats := stats()
	all_stats["seen"] = {"size": size, "prints": prints}
	_document["stats"] = all_stats
	_write_document()


func progress() -> Dictionary:
	return stats().get("progress", SaveMigration.empty_progress())


## The level the player is on now. Levels are one-based and only ever go up.
func current_level() -> int:
	return maxi(int(progress().get("level", LevelLadder.FIRST_LEVEL)), LevelLadder.FIRST_LEVEL)


func levels_completed() -> int:
	return int(progress().get("completed", 0))


func load_document() -> void:
	_loaded = true
	if not FileAccess.file_exists(SAVE_PATH):
		_document = SaveMigration.empty_document()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Save file could not be opened: %s" % error_string(FileAccess.get_open_error()))
		_document = SaveMigration.empty_document()
		return
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("Save file is not valid JSON; starting fresh.")
		_document = SaveMigration.empty_document()
		return
	_document = SaveMigration.migrate(parsed as Dictionary)
	session_available.emit(has_session())
	stats_changed.emit()


func record_started(tier: int) -> void:
	var entry := _tier_entry(tier)
	entry["started"] = int(entry.get("started", 0)) + 1
	_write_document()
	stats_changed.emit()


## Records a finished level and moves the player up one.
##
## The level number advances here rather than in GameState so that it cannot get
## out of step with the file: the same write that records the win is the one that
## says which level comes next.
func record_win(level: int, tier: int, seconds: int, mistakes: int, hints: int) -> void:
	var all_progress := progress()
	all_progress["level"] = maxi(int(all_progress.get("level", level)), level + 1)
	all_progress["completed"] = int(all_progress.get("completed", 0)) + 1
	var stats_block := stats()
	stats_block["progress"] = all_progress
	_document["stats"] = stats_block

	var entry := _tier_entry(tier)
	entry["won"] = int(entry.get("won", 0)) + 1
	entry["total_time"] = int(entry.get("total_time", 0)) + seconds
	entry["mistakes"] = int(entry.get("mistakes", 0)) + mistakes
	var best := int(entry.get("best_time", 0))
	if best == 0 or seconds < best:
		entry["best_time"] = seconds

	var all_stats := stats()
	all_stats["hints_used"] = int(all_stats.get("hints_used", 0)) + hints
	_extend_streak(all_stats)

	_document["session"] = {}
	_write_document()
	stats_changed.emit()
	session_available.emit(false)


## A run of levels cleared without running out of lives.
##
## It used to count consecutive days played, which measured how often somebody
## opened the app rather than how they were doing at it. This version is reset by
## a loss, which is a thing the player can feel while playing, and it needs no
## date handling at all -- no timezone edge cases, no clock to trust.
func _extend_streak(all_stats: Dictionary) -> void:
	var streak: Dictionary = all_stats.get("streak", SaveMigration.empty_streak())
	streak["current"] = int(streak.get("current", 0)) + 1
	streak["best"] = maxi(int(streak.get("best", 0)), int(streak["current"]))
	all_stats["streak"] = streak


## Called when the last life goes. The best run is kept -- that is the point of
## recording it.
func record_loss() -> void:
	var all_stats := stats()
	var streak: Dictionary = all_stats.get("streak", SaveMigration.empty_streak())
	streak["current"] = 0
	all_stats["streak"] = streak
	_document["stats"] = all_stats
	_write_document()
	stats_changed.emit()


func _tier_entry(tier: int) -> Dictionary:
	var all_stats := stats()
	var tiers: Dictionary = all_stats.get("tiers", {})
	var key := str(tier)
	if not tiers.get(key) is Dictionary:
		tiers[key] = SaveMigration.empty_tier_stats()
	all_stats["tiers"] = tiers
	_document["stats"] = all_stats
	return tiers[key]


## Write to a temp file, then rename over the real one. See the note at the top
## about why the rename matters.
func _write_document() -> void:
	_document["version"] = SaveMigration.CURRENT_VERSION
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write save file: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(_document))
	file.close()

	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("Cannot open user:// to finalise the save.")
		return
	var error := dir.rename(TEMP_PATH.get_file(), SAVE_PATH.get_file())
	if error != OK:
		push_error("Cannot finalise save file: %s" % error_string(error))
