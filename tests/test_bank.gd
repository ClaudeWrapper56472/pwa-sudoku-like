extends TestCase
## The shipped level bank.
##
## The bank is content, and content can rot: a bad build script, a merge, a hand
## edit. Every entry is verified here so a broken bank fails the build rather
## than reaching a player as an unsolvable board.
##
## Skips cleanly when there is no bank file, since the game does not require one.


func _bank_exists() -> bool:
	return FileAccess.file_exists(LevelBank.BANK_PATH)


func test_bank_covers_every_tier() -> void:
	if not _bank_exists():
		return
	for tier in CatGrid.Tier.values():
		assert_true(LevelBank.count_for(tier) > 0, "bank has %s levels" % CatGrid.tier_name(tier))


func test_every_bank_entry_is_legal_unique_and_correctly_rated() -> void:
	if not _bank_exists():
		return
	for tier in CatGrid.Tier.values():
		var label := CatGrid.tier_name(tier)
		for entry in LevelBank.entries_for(tier):
			var level := CatLevel.from_dict(entry as Dictionary)
			if not assert_true(level != null, "%s entry parses" % label):
				continue
			assert_true(level.is_valid(), "%s seed %d is legal and connected" % [label, level.seed])
			assert_eq(CatSolver.count_solutions(level.size, level.regions,
					CatSolver.open_constraints(level.size), 2), 1,
				"%s seed %d has exactly one solution" % [label, level.seed])
			var rating := CatRater.rate(level)
			assert_true(rating.solved, "%s seed %d is solvable by the technique set" % [label, level.seed])
			assert_eq(rating.tier, tier, "%s seed %d rates as its stored tier" % [label, level.seed])


func test_take_returns_a_usable_level() -> void:
	if not _bank_exists():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for tier in CatGrid.Tier.values():
		var level := LevelBank.take(tier, rng)
		if not assert_true(level != null, "take() served a %s level" % CatGrid.tier_name(tier)):
			continue
		assert_eq(level.tier, tier, "served level carries the requested tier")
		assert_true(level.is_valid(), "served level is legal")


func test_the_bank_skips_levels_already_served() -> void:
	if not _bank_exists():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for tier in CatGrid.Tier.values():
		var entries := LevelBank.entries_for(tier)
		if entries.is_empty():
			continue
		# Mark every entry of this tier as seen; the bank should then decline
		# rather than repeat, so the caller falls back to generating.
		var seen := {}
		for entry in entries:
			var record: Dictionary = entry
			seen[CatLevel.fingerprint_of(int(record.get("size", 0)),
				String(record.get("regions", "")))] = true
		assert_true(LevelBank.take(tier, rng, 0, seen) == null,
			"%s bank declines when everything is seen" % CatGrid.tier_name(tier))

		# With only one marked, it should still find something else.
		var one := {}
		var first: Dictionary = entries[0]
		one[CatLevel.fingerprint_of(int(first.get("size", 0)), String(first.get("regions", "")))] = true
		var served := LevelBank.take(tier, rng, 0, one)
		if entries.size() > 1:
			assert_true(served != null, "%s bank still serves the rest" % CatGrid.tier_name(tier))
			if served != null:
				assert_false(one.has(served.fingerprint()), "and never the one already seen")
