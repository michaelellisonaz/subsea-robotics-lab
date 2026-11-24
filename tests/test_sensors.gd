## Sensors: seabed ray casting, timing (rate, latency), noise statistics
## against the configured values, biases, repeatability, and the geometry of
## every sensor checked against ground truth.
## The vehicle is held still (is_dynamic = false) unless a test needs motion;
## its sensors still update every step.
extends "res://tests/test_suite.gd"


func _engine(depth: float = 30.0) -> SimulationEngine:
	var engine := SimulationEngine.new()
	engine.auto_advance = false
	engine.clock.max_steps_per_frame = 1000000
	engine.environment.water_depth = depth
	engine.environment.current_speed = 0.0
	return engine


func _static_vehicle(engine: SimulationEngine, position: Vector3) -> RovVehicle:
	var vehicle := RovVehicle.new(VehicleConfig.new(), position)
	vehicle.is_dynamic = false
	engine.objects.register(vehicle)
	return vehicle


func _run(engine: SimulationEngine, seconds: float) -> void:
	engine.start()
	engine.advance(seconds)
	engine.pause()


## Runs the engine and returns every new reading the sensor delivered.
func _collect(engine: SimulationEngine, sensor: Sensor, seconds: float) -> Array:
	var readings: Array = []
	var last: Array = [engine.get_sim_time()]  # only readings measured during this run
	var on_step := func(_t: float, _dt: float) -> void:
		if sensor.latest != null and sensor.latest.time > last[0]:
			last[0] = sensor.latest.time
			readings.append(sensor.latest)
	engine.step_completed.connect(on_step)
	_run(engine, seconds)
	engine.step_completed.disconnect(on_step)
	return readings


func _error_stats(readings: Array, key: String, wrap_degrees: bool = false) -> Vector2:
	var errors: Array[float] = []
	for reading in readings:
		if reading.valid:
			var e: float = reading.values[key] - reading.truth[key]
			errors.append(wrapf(e, -180.0, 180.0) if wrap_degrees else e)
	var mean := 0.0
	for e in errors:
		mean += e
	mean /= maxf(errors.size(), 1)
	var variance := 0.0
	for e in errors:
		variance += (e - mean) * (e - mean)
	return Vector2(mean, sqrt(variance / maxf(errors.size() - 1, 1)))


func test_raycast_seabed() -> void:
	var env := EnvironmentConfig.new()
	var world := WorldModel.new(env)
	var origin := Vector3(0.0, -28.0, 0.0)
	check_near(world.raycast_seabed(origin, Vector3.DOWN, 50.0), 2.0, 1e-3, "straight down onto the level test area")
	check_near(world.raycast_seabed(origin, Vector3(1.0, -1.0, 0.0), 50.0), 2.0 * sqrt(2.0), 1e-3, "45° ray")
	check(world.raycast_seabed(origin, Vector3.UP, 50.0) == INF, "upward ray never hits")
	check(world.raycast_seabed(origin, Vector3.DOWN, 1.0) == INF, "seabed beyond max distance")
	var far := Vector3(200.0, world.seabed_y_at(200.0, 100.0) + 5.0, 100.0)
	var direction := Vector3(0.3, -1.0, 0.2).normalized()
	var r := world.raycast_seabed(far, direction, 100.0)
	var hit := far + direction * r
	check(r < INF and absf(hit.y - world.seabed_y_at(hit.x, hit.z)) < 0.005, "hit lies on the undulating seabed (%.4f m off)" % absf(hit.y - world.seabed_y_at(hit.x, hit.z)))


func test_rate_latency_and_repeatability() -> void:
	var engine := _engine()
	var vehicle := _static_vehicle(engine, Vector3(0.0, -20.0, 0.0))
	var depth: Sensor = vehicle.sensors.get_sensor("Depth")
	depth.set_param("rate_hz", 10.0)
	depth.set_param("latency", 0.25)
	_run(engine, 0.2)
	check(depth.latest == null, "nothing delivered before the latency has elapsed")
	_run(engine, 4.8)
	check(absi(depth.samples_taken - 50) <= 1, "10 Hz for 5 s -> 50 samples (got %d)" % depth.samples_taken)
	check_near(engine.get_sim_time() - depth.latest.time, 0.25, 0.1 + 1e-6, "latest reading is about one latency old")
	check(depth.latest.available_time - depth.latest.time == 0.25, "delivery = measurement time + latency")
	var first_run: Array = []
	engine.reset()
	for reading in _collect(engine, depth, 2.0):
		first_run.append(reading.values["depth"])
	engine.reset()
	var second_run: Array = []
	for reading in _collect(engine, depth, 2.0):
		second_run.append(reading.values["depth"])
	check(first_run.size() > 10 and first_run == second_run, "seeded noise: identical readings after reset")
	engine.free()


func test_depth_sensor() -> void:
	var engine := _engine()
	var vehicle := _static_vehicle(engine, Vector3(0.0, -20.0, 0.0))
	var depth: Sensor = vehicle.sensors.get_sensor("Depth")
	depth.set_param("rate_hz", 100.0)
	depth.set_param("latency", 0.0)
	var stats := _error_stats(_collect(engine, depth, 20.0), "depth")
	var expected_sigma := 50.0 / (1025.0 * 9.81)
	check(absf(stats.x) < 0.0005, "unbiased depth (mean error %.5f m)" % stats.x)
	check_near(stats.y, expected_sigma, expected_sigma * 0.1, "depth noise = pressure noise / (rho g)")
	depth.set_param("pressure_noise", 0.0)
	engine.environment.water_density = 1000.0
	_run(engine, 0.5)
	var truth: float = depth.latest.truth["depth"]
	check_near(depth.latest.values["depth"], truth * 1000.0 / 1025.0, 1e-4, "wrong conversion density gives a proportional depth error")
	engine.free()


func test_imu() -> void:
	var engine := _engine()
	var vehicle := _static_vehicle(engine, Vector3(0.0, -20.0, 0.0))
	var imu: Sensor = vehicle.sensors.get_sensor("IMU")
	imu.set_param("gyro_bias_walk", 0.0)
	var readings := _collect(engine, imu, 5.0)
	check(readings.size() > 200, "IMU at 50 Hz")
	check_near(_mean(readings, "accel_up"), 9.81, 0.01, "at rest the accelerometer reads +g (specific force)")
	check_near(_mean(readings, "accel_forward"), 0.0, 0.01, "no forward acceleration at rest")
	check_near(_error_stats(readings, "yaw_rate").y, 0.05, 0.01, "gyro noise matches its setting")
	vehicle.angular_velocity = Vector3(0.0, 0.5, 0.0)
	readings = _collect(engine, imu, 2.0)
	check_near(_mean(readings, "yaw_rate"), -rad_to_deg(0.5), 0.02, "turning left at 0.5 rad/s reads -28.6 °/s (clockwise positive)")
	imu.set_param("gyro_noise", 0.0)
	imu.set_param("gyro_bias_walk", 0.05)
	_run(engine, 100.0)
	var bias: Vector3 = imu.gyro_bias
	check(bias.length() > 0.05 and bias.length() < 5.0, "gyro bias wanders (|bias| %.3f °/s after 100 s)" % bias.length())
	check_near(imu.latest.values["yaw_rate"] - imu.latest.truth["yaw_rate"], bias.z, 0.01, "reading error equals the bias when noise is off")
	engine.free()


func test_compass() -> void:
	var engine := _engine()
	var vehicle := _static_vehicle(engine, Vector3(0.0, -20.0, 0.0))
	var compass: Sensor = vehicle.sensors.get_sensor("Compass")
	compass.set_param("deviation", 5.0)
	compass.set_param("rate_hz", 50.0)
	var stats := _error_stats(_collect(engine, compass, 20.0), "heading", true)
	check_near(stats.x, 5.0, 0.05, "deviation appears as a fixed heading offset")
	check_near(stats.y, 0.5, 0.05, "heading noise matches its setting")
	engine.free()


func test_dvl() -> void:
	var engine := _engine()
	var vehicle := _static_vehicle(engine, engine.world.place_on_seabed(0.0, 0.0, 1.5))
	vehicle.velocity = Vector3(0.5, 0.0, -0.3)  # 0.5 m/s east, 0.3 m/s north
	var dvl: Sensor = vehicle.sensors.get_sensor("DVL")
	dvl.set_param("rate_hz", 20.0)
	var readings := _collect(engine, dvl, 10.0)
	check(readings.size() > 150 and readings[-1].valid and readings[-1].values["beams_locked"] == 4, "four beams in bottom lock")
	check_near(_mean(readings, "forward"), 0.3, 0.002, "forward velocity (north, heading 000)")
	check_near(_mean(readings, "starboard"), 0.5, 0.002, "starboard velocity (east)")
	check_near(_mean(readings, "up"), 0.0, 0.002, "no vertical velocity")
	var true_altitude: float = readings[-1].truth["altitude"]
	check_near(readings[-1].values["altitude"], true_altitude, 1e-3, "altitude from the beam ranges")
	var sigma := 0.002 + 0.003 * 0.583
	check(_error_stats(readings, "forward").y < sigma * 1.5, "velocity noise of the order of the beam noise")
	vehicle.orientation = Quaternion(Vector3.RIGHT, deg_to_rad(10.0))
	readings = _collect(engine, dvl, 5.0)
	check_near(_mean(readings, "forward"), readings[-1].truth["forward"], 0.003, "pitched vehicle: velocity in the vehicle frame")
	dvl.set_param("max_altitude", 1.0)
	_run(engine, 0.5)
	check(not dvl.latest.valid and dvl.latest.values["beams_locked"] == 0, "no bottom lock above the maximum altitude")
	engine.free()


func test_altimeter() -> void:
	var engine := _engine()
	var vehicle := _static_vehicle(engine, engine.world.place_on_seabed(0.0, 0.0, 3.0))
	var altimeter: Sensor = vehicle.sensors.get_sensor("Altimeter")
	altimeter.set_param("rate_hz", 50.0)
	var readings := _collect(engine, altimeter, 10.0)
	var stats := _error_stats(readings, "range")
	var mount_height := altimeter.mount_world_position(vehicle).y - engine.world.seabed_y_at(0.0, 0.0)
	check_near(readings[-1].truth["range"], mount_height, 1e-3, "range = height of the transducer above the seabed")
	check(absf(stats.x) < 0.002, "unbiased range")
	check_near(stats.y, 0.01 + 0.001 * mount_height, 0.003, "range noise matches its setting")
	altimeter.set_param("max_range", 1.0)
	_run(engine, 0.5)
	check(not altimeter.latest.valid, "no echo beyond the maximum range")
	engine.free()


func test_usbl() -> void:
	var engine := _engine(200.0)
	var vehicle := _static_vehicle(engine, Vector3(0.0, -60.0, 0.0))
	var usbl: Sensor = vehicle.sensors.get_sensor("USBL")
	usbl.set_param("rate_hz", 10.0)
	var near := _collect(engine, usbl, 60.0)
	var slant: float = near[-1].truth["slant_range"]
	check_near(near[-1].available_time - near[-1].time, 2.0 * slant / 1500.0 + 0.2, 1e-6, "delay = two-way travel time + processing")
	var rms_near := _horizontal_rms(near)
	var expected := sqrt(2.0) * slant * deg_to_rad(0.25)
	check(rms_near > 0.5 * expected and rms_near < 2.0 * expected, "horizontal error ~ range x angle error (RMS %.2f m, expected ~%.2f m)" % [rms_near, expected])
	vehicle.shift(Vector3(300.0, 0.0, 0.0))
	vehicle.capture_initial_state()
	var far := _collect(engine, usbl, 60.0)
	check(_horizontal_rms(far) > 3.0 * rms_near, "error grows with distance from the vessel")
	engine.free()


func test_imaging_sonar() -> void:
	var engine := _engine()
	var vehicle := _static_vehicle(engine, engine.world.place_on_seabed(0.0, 0.0, 1.5))
	var sonar: ImagingSonar = vehicle.sensors.get_sensor("Imaging sonar")
	sonar.set_param("speckle", 0.0)
	sonar.set_param("noise_floor", 0.0)
	_run(engine, 1.0)
	var image: PackedFloat32Array = sonar.latest.values["image"]
	check(image.size() == ImagingSonar.BEAMS * ImagingSonar.BINS, "image is beams x bins")
	var energy := 0.0
	for v in image:
		energy += v
	check(energy > 10.0, "seabed echoes present")
	var height := sonar.mount_world_position(vehicle).y - engine.world.seabed_y_at(0.0, 0.0)
	var lowest := deg_to_rad(-15.0 + 20.0 * (0.5 / ImagingSonar.VERTICAL_RAYS - 0.5))
	var expected := height / sin(-lowest)
	var centre := ImagingSonar.BEAMS / 2
	var first_bin := -1
	for bin in ImagingSonar.BINS:
		if image[bin * ImagingSonar.BEAMS + centre] > 0.05:
			first_bin = bin
			break
	var bin_size: float = sonar.get_param("max_range") / ImagingSonar.BINS
	check(first_bin >= 0 and absf((first_bin + 0.5) * bin_size - expected) < 2.0 * bin_size,
		"first echo at the range where the lowest ray meets the seabed (%.2f m vs %.2f m)" % [(first_bin + 0.5) * bin_size, expected])
	engine.free()


func test_multibeam() -> void:
	var engine := _engine()
	var vehicle := _static_vehicle(engine, engine.world.place_on_seabed(0.0, 0.0, 2.0))
	var multibeam: MultibeamSonar = vehicle.sensors.get_sensor("Multibeam")
	multibeam.set_param("range_noise_rel", 0.0)
	_run(engine, 1.0)
	var height := multibeam.mount_world_position(vehicle).y - engine.world.seabed_y_at(0.0, 0.0)
	var below: PackedFloat32Array = multibeam.latest.values["below"]
	var across: PackedFloat32Array = multibeam.latest.values["across"]
	check(multibeam.latest.values["hits"] == MultibeamSonar.BEAMS, "every beam hits the seabed")
	for i in [0, MultibeamSonar.BEAMS / 2, MultibeamSonar.BEAMS - 1]:
		check_near(below[i], height, 2e-3, "flat seabed: every beam reports the same depth below (beam %d)" % i)
	check_near(absf(across[0]), height * tan(deg_to_rad(60.0)), 5e-3, "outer beam reaches h · tan(60°) across track")
	engine.free()


func test_parameters_and_persistence() -> void:
	var suite := SensorSuite.create_default()
	var dvl := suite.get_sensor("DVL")
	check_near(dvl.set_param("max_altitude", 1000.0), 200.0, 1e-9, "parameters clamped to their range")
	check(not suite.get_sensor("Stereo camera").enabled, "stereo camera off by default")
	dvl.enabled = false
	var path := "user://test_sensor_config.json"
	check(suite.save_json(path) == OK, "sensor settings saved")
	var other := SensorSuite.create_default()
	check(other.load_json(path) == OK, "sensor settings loaded")
	check(not other.get_sensor("DVL").enabled and other.get_sensor("DVL").get_param("max_altitude") == 200.0, "round trip keeps enable state and parameters")
	other.reset_parameters()
	check(other.get_sensor("DVL").enabled and other.get_sensor("DVL").get_param("max_altitude") == 50.0, "defaults restore settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var camera := suite.get_sensor("Camera")
	check(camera.get_param("fov") == 70.0 and not camera.has_param("rate_hz"), "camera has optics settings and no sampling")
	var stereo: StereoCameraSensor = suite.get_sensor("Stereo camera")
	var f := stereo.focal_length_pixels()
	check_near(stereo.depth_resolution(2.0), 4.0 / (f * 0.12), 1e-9, "stereo depth resolution Z² / (f B)")
	check_near(stereo.depth_from_disparity(f * 0.12 / 3.0), 3.0, 1e-9, "depth from disparity Z = f B / d")


func _mean(readings: Array, key: String) -> float:
	var total := 0.0
	var count := 0
	for reading in readings:
		if reading.valid:
			total += reading.values[key]
			count += 1
	return total / maxf(count, 1)


func _horizontal_rms(readings: Array) -> float:
	var total := 0.0
	for reading in readings:
		var de: float = reading.values["east"] - reading.truth["east"]
		var dn: float = reading.values["north"] - reading.truth["north"]
		total += de * de + dn * dn
	return sqrt(total / maxf(readings.size(), 1))
