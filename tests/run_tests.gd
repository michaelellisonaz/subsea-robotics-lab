## Headless test runner.
##
##   godot --headless --path . -s res://tests/run_tests.gd
##
## Exit code 0 = all checks passed, 1 = at least one failure.
extends SceneTree

const SUITES := [
	"res://tests/test_environment.gd",
	"res://tests/test_world.gd",
	"res://tests/test_simulation.gd",
	"res://tests/test_objects.gd",
	"res://tests/test_physics.gd",
	"res://tests/test_rigid_body.gd",
	"res://tests/test_vehicle.gd",
	"res://tests/test_sensors.gd",
	"res://tests/test_pilot_aids.gd",
	"res://tests/test_structures.gd",
	"res://tests/test_manipulator.gd",
	"res://tests/test_tools.gd",
	"res://tests/test_autonomy.gd",
	"res://tests/test_main_scene.gd",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var total_checks := 0
	var total_failures := 0
	for path in SUITES:
		var suite = load(path).new()
		suite.tree = self
		suite.run()
		if not suite.is_done:
			await suite.finished
		total_checks += suite.checks
		total_failures += suite.failures.size()
		var status := "PASS" if suite.failures.is_empty() else "FAIL"
		print("[%s] %s  (%d checks, %d failed)" % [status, path.get_file(), suite.checks, suite.failures.size()])
		for failure in suite.failures:
			print("       - " + failure)
	print("TOTAL: %d checks, %d failed" % [total_checks, total_failures])
	quit(0 if total_failures == 0 else 1)
