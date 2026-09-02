class_name TestCase
extends RefCounted
## Minimal assertion harness.
##
## GUT is the usual choice, but a reference project should run with nothing
## installed. This is small enough to read in one sitting and works under
## `godot --headless --script`, so the suite runs in CI without an editor.

var failures: PackedStringArray = []
var assertion_count := 0
var _current_test := ""


func begin_test(test_name: String) -> void:
	_current_test = test_name


func check(condition: bool, message: String) -> bool:
	assertion_count += 1
	if not condition:
		failures.append("%s -- %s" % [_current_test, message])
	return condition


func assert_true(condition: bool, message: String) -> bool:
	return check(condition, message)


func assert_false(condition: bool, message: String) -> bool:
	return check(not condition, message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> bool:
	return check(actual == expected, "%s (got %s, expected %s)" % [message, actual, expected])


func assert_ne(actual: Variant, unexpected: Variant, message: String) -> bool:
	return check(actual != unexpected, "%s (got %s)" % [message, actual])
