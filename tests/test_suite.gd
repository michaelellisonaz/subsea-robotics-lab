## Minimal assertion helper shared by the test suites (no external framework).
##
## Synchronous suites define test_* methods; the default run() calls them all.
## Asynchronous suites override run(), await what they need, then call done().
extends RefCounted

signal finished

var tree: SceneTree
var checks: int = 0
var failures: PackedStringArray = []
var is_done: bool = false


func run() -> void:
	for method in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_"):
			call(method_name)
	done()


func done() -> void:
	is_done = true
	finished.emit()


func check(condition: bool, message: String) -> void:
	checks += 1
	if OS.has_environment("TEST_VERBOSE"):
		print("  %s %s" % ["ok  " if condition else "FAIL", message])
	if not condition:
		failures.append(message)


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual - expected) <= tolerance,
		"%s (expected %s ± %s, got %s)" % [message, expected, tolerance, actual])


func check_vec_near(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	check(actual.distance_to(expected) <= tolerance,
		"%s (expected %s ± %s, got %s)" % [message, expected, tolerance, actual])
