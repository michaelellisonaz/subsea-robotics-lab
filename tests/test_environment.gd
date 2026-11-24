## EnvironmentConfig: defaults, clamping, signals, derived values, save/load.
extends "res://tests/test_suite.gd"

const TEST_FILE := "user://test_environment_config.json"


func test_defaults() -> void:
	var env := EnvironmentConfig.new()
	check_near(env.water_depth, 30.0, 1e-9, "default depth")
	check_near(env.water_density, 1025.0, 1e-9, "default density")
	check_near(env.dynamic_viscosity, 0.00108, 1e-12, "default viscosity")
	check_near(env.gravity, 9.81, 1e-9, "default gravity")
	for key in EnvironmentConfig.PARAMETER_ORDER:
		var spec := EnvironmentConfig.get_spec(key)
		check(spec.has("label") and spec.has("unit") and spec.has("description"), "spec complete for " + key)
		check(spec["min"] <= spec["default"] and spec["default"] <= spec["max"], "default in range for " + key)


func test_clamping_and_wrapping() -> void:
	var env := EnvironmentConfig.new()
	check_near(env.set_value("water_depth", 5000.0), 1000.0, 1e-9, "depth clamped to max")
	check_near(env.set_value("water_depth", -3.0), 5.0, 1e-9, "depth clamped to min")
	env.visibility = 0.1
	check_near(env.visibility, 1.0, 1e-9, "visibility clamped via property")
	env.current_heading = 370.0
	check_near(env.current_heading, 10.0, 1e-9, "heading wraps above 360")
	env.current_heading = -90.0
	check_near(env.current_heading, 270.0, 1e-9, "heading wraps below 0")
	check_near(env.set_value("water_density", NAN), env.water_density, 1e-9, "NaN ignored")


func test_change_signal() -> void:
	var env := EnvironmentConfig.new()
	var log: Array = []
	env.parameter_changed.connect(func(key: String, value: float) -> void: log.append([key, value]))
	env.water_depth = 55.0
	check(log.size() == 1 and log[0][0] == "water_depth" and is_equal_approx(log[0][1], 55.0), "signal carries key and value")
	env.water_depth = 55.0
	check(log.size() == 1, "no signal when value unchanged")
	env.reset_to_defaults()
	check(log.size() == 2 and log[1][0] == "water_depth", "reset emits only for changed parameters")


func test_derived_quantities() -> void:
	var env := EnvironmentConfig.new()
	check_near(env.gauge_pressure_at_depth(30.0), 1025.0 * 9.81 * 30.0, 1e-6, "gauge pressure rho*g*h")
	check_near(env.absolute_pressure_at_depth(30.0), 101325.0 + 1025.0 * 9.81 * 30.0, 1e-6, "absolute pressure")
	check_near(env.gauge_pressure_at_depth(-5.0), 0.0, 1e-9, "no negative pressure above surface")
	check_near(env.kinematic_viscosity(), 0.00108 / 1025.0, 1e-15, "kinematic viscosity")
	check_near(env.optical_extinction_coefficient(), 3.912 / 30.0, 1e-9, "extinction from default visibility (30 m)")
	check_near(env.light_fraction_at_depth(0.0), 1.0, 1e-12, "full light at surface")
	check(env.light_fraction_at_depth(100.0) < env.light_fraction_at_depth(10.0), "light decreases with depth")
	env.current_speed = 0.5
	env.current_heading = 90.0
	check_vec_near(env.current_velocity(), Vector3(0.5, 0.0, 0.0), 1e-9, "eastward current is +X")
	env.current_heading = 0.0
	check_vec_near(env.current_velocity(), Vector3(0.0, 0.0, -0.5), 1e-9, "northward current is -Z")
	check_near(env.reynolds_number(1.0, 0.5), 0.5 / env.kinematic_viscosity(), 1e-3, "Reynolds number")


func test_save_and_load() -> void:
	var env := EnvironmentConfig.new()
	env.water_depth = 123.5
	env.visibility = 7.5
	env.current_heading = 200.0
	check(env.save_json(TEST_FILE) == OK, "save succeeds")
	var other := EnvironmentConfig.new()
	check(other.load_json(TEST_FILE) == OK, "load succeeds")
	for key in EnvironmentConfig.PARAMETER_ORDER:
		check_near(other.get_value(key), env.get_value(key), 1e-9, "round trip " + key)
	var file := FileAccess.open(TEST_FILE, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	check(other.load_json(TEST_FILE) == ERR_PARSE_ERROR, "invalid file rejected")
	check_near(other.water_depth, 123.5, 1e-9, "invalid file leaves values untouched")
	check(other.load_json("user://does_not_exist.json") == ERR_FILE_NOT_FOUND, "missing file reported")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE))
