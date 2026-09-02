class_name LevelBank
extends RefCounted
## Levels generated ahead of time and shipped with the game.
##
## Runtime generation is honest but uneven. Carving regions that admit exactly
## one solution is a rejection loop, and the harder tiers reject a lot -- a player
## should not wait on that.
##
## So tools/build_level_bank.gd generates levels on a build machine and ships them
## as data. A level is two short strings, so a thousand of them is a handful of
## kilobytes and several minutes of generation. That trade -- cheap to store,
## expensive to find -- is why puzzle apps ship large content archives next to
## small code.
##
## The bank is a convenience, never a requirement. With no bank file the game
## generates at runtime, and an explicit seed always generates.

const BANK_PATH := "res://content/level_bank.json"

static var _cache: Dictionary = {}
static var _loaded := false


static func entries_for(tier: int) -> Array:
	_ensure_loaded()
	var by_tier: Variant = _cache.get("tiers", {})
	if not by_tier is Dictionary:
		return []
	var entries: Variant = (by_tier as Dictionary).get(str(tier), [])
	return entries if entries is Array else []


static func count_for(tier: int) -> int:
	return entries_for(tier).size()


## Draws a level from the bank, or returns null when the tier has none.
## Verifies before handing it over: a corrupt or hand-edited bank should degrade
## to runtime generation, not to an unsolvable board.
## `size` of 0 accepts any board size for the tier. `seen` is a set of
## fingerprints to skip, so a player never gets a board twice.
##
## Returns null when everything matching has already been served, which is the
## signal for the caller to fall back to generating a fresh one. With twenty
## levels per tier that happens sooner than it sounds.
static func take(tier: int, rng: RandomNumberGenerator, size: int = 0,
		seen: Dictionary = {}, min_region_cells: int = 1) -> CatLevel:
	var entries: Array = []
	for entry in entries_for(tier):
		if not entry is Dictionary:
			continue
		var record: Dictionary = entry
		if size > 0 and int(record.get("size", 0)) != size:
			continue
		if seen.has(CatLevel.fingerprint_of(int(record.get("size", 0)),
				String(record.get("regions", "")))):
			continue
		if min_region_cells > 1 and _smallest_region(String(record.get("regions", ""))) < min_region_cells:
			continue
		entries.append(entry)
	if entries.is_empty():
		return null
	var entry: Variant = entries[rng.randi_range(0, entries.size() - 1)]
	if not entry is Dictionary:
		return null

	var level := CatLevel.from_dict(entry as Dictionary)
	if level == null or not level.is_valid():
		return null
	if not CatSolver.has_unique_solution(level.size, level.regions,
			CatSolver.open_constraints(level.size)):
		return null
	level.rating = CatRater.rate(level)
	if not level.rating.solved or level.rating.tier != tier:
		return null
	level.tier = tier
	return level


## Smallest colour in a stored region string, without building a whole CatLevel
## for every candidate.
static func _smallest_region(regions: String) -> int:
	var counts := {}
	for ch in regions:
		counts[ch] = int(counts.get(ch, 0)) + 1
	var smallest := regions.length()
	for key in counts:
		smallest = mini(smallest, int(counts[key]))
	return smallest


static func reload() -> void:
	_loaded = false
	_cache = {}
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(BANK_PATH):
		return
	var file := FileAccess.open(BANK_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_cache = parsed
