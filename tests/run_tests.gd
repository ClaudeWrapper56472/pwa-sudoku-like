extends Node
## Headless test runner.
##
##     godot --headless --path . res://tests/TestRunner.tscn
##     godot --headless --path . res://tests/TestRunner.tscn -- rater
##
## Anything after `--` filters suites by name. Exits non-zero on failure so CI
## can gate on it. Use ./run_tests.sh rather than typing either of those.
##
## This runs as a *scene* rather than with --script. Godot only registers
## autoload singletons when it boots a scene; under --script any script that
## mentions GameState or Settings fails to compile, which would rule out ever
## testing anything above the puzzle layer.


const TEST_DIR := "res://tests"


func _ready() -> void:
	var filter := ""
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		filter = user_args[0].to_lower()

	var suites := _discover_suites(filter)
	if suites.is_empty():
		print("No test suites matched %s" % filter)
		_finish(1)
		return

	var started := Time.get_ticks_msec()
	var total_assertions := 0
	var all_failures: PackedStringArray = []

	for path in suites:
		var script: GDScript = load(path)
		var suite: TestCase = script.new()
		var suite_name := path.get_file().get_basename()
		var suite_failures := 0
		var suite_assertions := 0

		for method in _test_methods(script):
			suite.begin_test("%s.%s" % [suite_name, method])
			var before := suite.failures.size()
			suite.call(method)
			if suite.failures.size() > before:
				suite_failures += 1

		suite_assertions = suite.assertion_count
		total_assertions += suite_assertions
		for failure in suite.failures:
			all_failures.append(failure)

		var status := "FAIL" if suite.failures.size() > 0 else "ok"
		print("  %-24s %-5s %4d assertions, %d failing test(s)"
			% [suite_name, status, suite_assertions, suite_failures])

	var elapsed := Time.get_ticks_msec() - started
	print("")
	if all_failures.is_empty():
		print("PASSED  %d assertions in %d suite(s), %.2fs"
			% [total_assertions, suites.size(), elapsed / 1000.0])
		_finish(0)
		return

	print("FAILED  %d assertion(s):" % all_failures.size())
	for failure in all_failures:
		print("  - %s" % failure)
	print("")
	print("%d assertions in %d suite(s), %.2fs" % [total_assertions, suites.size(), elapsed / 1000.0])
	_finish(1)


func _discover_suites(filter: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		push_error("Cannot open %s" % TEST_DIR)
		return found
	for file in dir.get_files():
		# Exported projects rename scripts to .gd.remap; strip that if present.
		var name := file.trim_suffix(".remap")
		if not name.begins_with("test_") or not name.ends_with(".gd"):
			continue
		if name == "test_case.gd":
			continue
		if filter != "" and not name.to_lower().contains(filter):
			continue
		found.append("%s/%s" % [TEST_DIR, name])
	found.sort()
	return found


func _test_methods(script: GDScript) -> PackedStringArray:
	var names: PackedStringArray = []
	for method in script.get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_"):
			names.append(method_name)
	names.sort()
	return names


func _finish(code: int) -> void:
	get_tree().quit(code)
