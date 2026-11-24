## Thrusters, thrust allocation, vehicle configuration and whole-vehicle
## behaviour (speeds, stability, trim, seabed contact, surface, current).
## Vehicle runs use a headless SimulationEngine driven manually.
extends "res://tests/test_suite.gd"


func _engine(depth: float = 200.0) -> SimulationEngine:
	var engine := SimulationEngine.new()
	engine.auto_advance = false
	engine.clock.max_steps_per_frame = 1000000
	engine.environment.water_depth = depth
	engine.environment.current_speed = 0.0
	return engine


func _vehicle(engine: SimulationEngine, config: VehicleConfig, start: Vector3) -> RovVehicle:
	var vehicle := RovVehicle.new(config, start)
	engine.objects.register(vehicle)
	return vehicle


func _run(engine: SimulationEngine, seconds: float) -> void:
	engine.start()
	engine.advance(seconds)
	engine.pause()


func _neutral_config() -> VehicleConfig:
	var config := VehicleConfig.new()
	config.set_value("net_buoyancy", 0.0)
	return config


func test_dense_matrix() -> void:
	var a := DenseMatrix.new(3, 3)
	a.data = PackedFloat64Array([4, 7, 2, 3, 6, 1, 2, 5, 3])
	var product := a.multiply(a.inverse())
	var worst := 0.0
	for r in 3:
		for c in 3:
			worst = maxf(worst, absf(product.at(r, c) - (1.0 if r == c else 0.0)))
	check(worst < 1e-12, "A · A⁻¹ = I")
	var singular := DenseMatrix.new(2, 2)
	singular.data = PackedFloat64Array([1, 2, 2, 4])
	check(singular.inverse() == null, "singular matrix detected")
	check(a.transposed().at(0, 1) == 3.0, "transpose")


func test_thruster_response() -> void:
	var thruster := Thruster.new("T", Vector3.ZERO, Vector3.FORWARD, 100.0, 80.0, 0.2)
	thruster.set_thrust_demand(50.0)
	check_near(thruster.command, 0.5, 1e-9, "demand converted to a normalised command")
	for i in 20:
		thruster.update(0.01)
	check_near(thruster.thrust, 50.0 * (1.0 - exp(-1.0)), 0.01, "first-order response: 63 % after one time constant")
	thruster.set_thrust_demand(-500.0)
	for i in 300:
		thruster.update(0.01)
	check_near(thruster.thrust, -80.0, 0.01, "reverse thrust saturates at the reverse limit")
	thruster.time_constant = 0.0
	thruster.set_thrust_demand(30.0)
	thruster.update(0.01)
	check_near(thruster.thrust, 30.0, 1e-9, "zero time constant responds immediately")


func test_allocation_full_layout() -> void:
	var allocator := ThrustAllocator.new(VehicleConfig.new().build_thrusters())
	for axis in 6:
		check(allocator.is_actuated(axis), "8-thruster layout actuates %s" % ThrustAllocator.AXIS_NAMES[axis])
	for axis in 6:
		var demand := PackedFloat64Array([0, 0, 0, 0, 0, 0])
		demand[axis] = 0.5 * allocator.capability(axis, 1.0)
		var achieved := allocator.achieved_wrench(allocator.allocate(demand))
		var error := 0.0
		for k in 6:
			error = maxf(error, absf(achieved[k] - demand[k]))
		check(error < 1e-6 * maxf(1.0, demand[axis]), "feasible %s demand reproduced exactly (error %s)" % [ThrustAllocator.AXIS_NAMES[axis], str(error)])
	check_near(allocator.capability(2, -1.0), 4.0 * 90.0 * sqrt(0.5), 0.5, "forward surge capability = 4 · 90 N · cos 45°")
	check_near(allocator.capability(1, 1.0), 4.0 * 90.0, 0.5, "heave-up capability = 4 · 90 N")
	var big := PackedFloat64Array([1000.0, 0.0, -2000.0, 0.0, 500.0, 0.0])
	var thrusts := allocator.allocate(big)
	var worst := 0.0
	for i in thrusts.size():
		worst = maxf(worst, absf(thrusts[i]) / allocator.thrusters[i].limit_for(thrusts[i]))
	check_near(worst, 1.0, 1e-9, "infeasible demand scaled to the saturation limit")
	var achieved := allocator.achieved_wrench(thrusts)
	var dot := 0.0
	var na := 0.0
	var nb := 0.0
	for k in 6:
		dot += achieved[k] * big[k]
		na += achieved[k] * achieved[k]
		nb += big[k] * big[k]
	check(dot / sqrt(na * nb) > 0.9999, "saturation preserves the wrench direction")


func test_underactuated_layouts() -> void:
	var config := VehicleConfig.new()
	config.set_layout("vectored_4h_2v")
	var allocator := ThrustAllocator.new(config.build_thrusters())
	check(allocator.thrusters.size() == 6, "6-thruster layout")
	check(not allocator.is_actuated(5), "4H+2V: roll not actuated")
	check(allocator.is_actuated(0) and allocator.is_actuated(1) and allocator.is_actuated(2) and allocator.is_actuated(3) and allocator.is_actuated(4), "4H+2V: other axes actuated")
	config.set_layout("basic_2h_2v")
	allocator = ThrustAllocator.new(config.build_thrusters())
	check(allocator.thrusters.size() == 4, "4-thruster layout")
	check(not allocator.is_actuated(0) and not allocator.is_actuated(5), "2H+2V: no sway, no roll")
	check(allocator.is_actuated(1) and allocator.is_actuated(2) and allocator.is_actuated(3) and allocator.is_actuated(4), "2H+2V: heave, surge, pitch, yaw actuated")


func test_configuration() -> void:
	var config := VehicleConfig.new()
	check_near(config.displaced_volume(), (85.0 * 9.81 + 3.0) / (1025.0 * 9.81), 1e-12, "displaced volume from mass and net buoyancy")
	var vehicle := RovVehicle.new(config)
	var env := EnvironmentConfig.new()
	check_near(vehicle.net_buoyancy(env), 3.0, 1e-6, "net buoyancy in reference water")
	check_vec_near(vehicle.center_of_buoyancy, Vector3(0.0, 0.14, 0.0), 1e-6, "CB relative to CG")
	check(vehicle.contact.contact_points.size() == 26, "26 hull contact points (corners, edges, faces)")
	check(vehicle.thrusters.size() == 8, "default layout has eight thrusters")
	check(vehicle.has_own_hydrodynamics(), "vehicle uses its own 6-DOF damping, not the isotropic drag")
	config.set_value("dry_mass", 5000.0)
	check_near(config.get_value("dry_mass"), 400.0, 1e-9, "parameters clamped")
	var copy := config.duplicate_config()
	check(copy.equals(config), "duplicate equals original")
	copy.set_layout("basic_2h_2v")
	check(not copy.equals(config), "layout change detected")
	var path := "user://test_vehicle_config.json"
	check(copy.save_json(path) == OK, "vehicle config saved")
	var loaded := VehicleConfig.new()
	check(loaded.load_json(path) == OK and loaded.equals(copy), "vehicle config round trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_apply_config_rebuilds_vehicle() -> void:
	var vehicle := RovVehicle.new(VehicleConfig.new())
	var applied: Array = [0]
	vehicle.configuration_applied.connect(func() -> void: applied[0] += 1)
	var config := VehicleConfig.new()
	config.set_layout("basic_2h_2v")
	config.set_value("dry_mass", 120.0)
	vehicle.apply_config(config)
	check(applied[0] == 1, "configuration_applied emitted")
	check(vehicle.thrusters.size() == 4 and vehicle.mass == 120.0, "thrusters and mass rebuilt")
	check(vehicle.local_force_models.size() == 4, "damping, thrusters, contact and arm loads attached")


func test_top_surge_speed_matches_prediction() -> void:
	var engine := _engine()
	var vehicle := _vehicle(engine, _neutral_config(), Vector3(0.0, -100.0, 0.0))
	vehicle.set_pilot_command(RovVehicle.Axis.SURGE, 1.0)
	_run(engine, 30.0)
	var predicted: float = vehicle.characteristics(engine.environment)["speed_surge"]
	check(predicted > 0.8 and predicted < 2.0, "predicted top speed plausible for an inspection ROV (%.2f m/s)" % predicted)
	check_near(vehicle.body_velocity_components().x, predicted, predicted * 0.02, "steady surge speed matches the prediction")
	check(absf(wrapf(vehicle.heading_degrees(), -180.0, 180.0)) < 1.0, "straight-line run keeps its heading")
	check(absf(vehicle.pitch_degrees()) < 1.0 and absf(vehicle.roll_degrees()) < 1.0, "attitude stays level")
	check_near(vehicle.distance_travelled, -vehicle.position.z, 0.5, "trip distance recorded")
	engine.free()


func test_yaw_rate_matches_prediction() -> void:
	var engine := _engine()
	var vehicle := _vehicle(engine, _neutral_config(), Vector3(0.0, -100.0, 0.0))
	vehicle.set_pilot_command(RovVehicle.Axis.YAW, 1.0)
	_run(engine, 15.0)
	var predicted: float = vehicle.characteristics(engine.environment)["yaw_rate"]
	check_near(vehicle.yaw_rate_degrees(), predicted, predicted * 0.03, "steady yaw rate matches the prediction (clockwise positive)")
	check(Vector2(vehicle.position.x, vehicle.position.z).length() < 0.2, "pure yaw turns on the spot")
	engine.free()


func test_net_buoyancy_ascent() -> void:
	var engine := _engine()
	var vehicle := _vehicle(engine, VehicleConfig.new(), Vector3(0.0, -100.0, 0.0))
	_run(engine, 40.0)
	var damping := vehicle.damping
	var expected := RovVehicle.terminal_speed(3.0, damping.linear_translational.y, damping.quadratic_translational(1025.0).y)
	check_near(vehicle.body_velocity_components().z, expected, expected * 0.05, "3 N positive buoyancy: slow steady ascent")
	engine.free()


func test_passive_roll_stability() -> void:
	var engine := _engine()
	var vehicle := RovVehicle.new(_neutral_config(), Vector3(0.0, -100.0, 0.0))
	vehicle.orientation = Quaternion(Vector3.BACK, deg_to_rad(20.0))
	engine.objects.register(vehicle)
	check(absf(vehicle.roll_degrees()) > 19.0, "starts heeled 20°")
	_run(engine, 20.0)
	check(absf(vehicle.roll_degrees()) < 0.5, "CB above CG rights the vehicle (roll %.2f°)" % vehicle.roll_degrees())
	engine.free()


func test_static_pitch_trim() -> void:
	var engine := _engine()
	var config := _neutral_config()
	config.set_value("cg_forward", 0.02)
	var vehicle := _vehicle(engine, config, Vector3(0.0, -100.0, 0.0))
	var predicted: float = vehicle.characteristics(engine.environment)["static_pitch_trim"]
	check(predicted < -5.0, "CG forward of CB predicts nose-down trim (%.1f°)" % predicted)
	_run(engine, 30.0)
	check_near(vehicle.pitch_degrees(), predicted, 0.3, "vehicle settles at the predicted trim")
	engine.free()


func test_seabed_landing_and_lift_off() -> void:
	var engine := _engine(30.0)
	var config := VehicleConfig.new()
	config.set_value("net_buoyancy", -40.0)
	var vehicle := _vehicle(engine, config, engine.world.place_on_seabed(0.0, 0.0, 2.0))
	_run(engine, 15.0)
	check(vehicle.in_seabed_contact, "heavy vehicle lands on the seabed")
	check_near(vehicle.altitude(engine.world), 0.0, 0.01, "hull rests on the seabed without sinking in")
	check(absf(vehicle.velocity.y) < 0.01, "vehicle at rest on the seabed")
	check(vehicle.contact.points_in_contact == 9, "resting on its bottom face (9 hull points)")
	check(absf(vehicle.roll_degrees()) < 0.5 and absf(vehicle.pitch_degrees()) < 0.5, "lands level")
	vehicle.set_pilot_command(RovVehicle.Axis.HEAVE, 1.0)
	_run(engine, 4.0)
	check(not vehicle.in_seabed_contact and vehicle.altitude(engine.world) > 0.5, "vertical thrust lifts the vehicle off")
	engine.free()


func test_floats_at_the_surface() -> void:
	var engine := _engine(20.0)
	var config := VehicleConfig.new()
	config.set_value("net_buoyancy", 60.0)
	var vehicle := _vehicle(engine, config, Vector3(0.0, -5.0, 0.0))
	_run(engine, 60.0)
	var fraction := vehicle.mass * 9.81 / (1025.0 * 9.81 * vehicle.displaced_volume)
	var expected_y := config.height * 0.5 - fraction * config.height
	check_near(vehicle.position.y, expected_y, 0.03, "floats with the immersed fraction weight / buoyancy")
	check(absf(vehicle.velocity.y) < 0.01, "settled at the surface")
	engine.free()


func test_current_carries_neutral_vehicle() -> void:
	var engine := _engine()
	engine.environment.current_speed = 0.5
	engine.environment.current_heading = 90.0
	var vehicle := _vehicle(engine, _neutral_config(), Vector3(0.0, -100.0, 0.0))
	_run(engine, 60.0)
	check_vec_near(vehicle.velocity, Vector3(0.5, 0.0, 0.0), 0.02, "vehicle drifts with the current")
	check(vehicle.water_relative_velocity(engine.world).length() < 0.02, "no speed through the water once entrained")
	engine.free()


func test_boundary_layer_profile() -> void:
	var env := EnvironmentConfig.new()
	env.current_speed = 1.0
	env.current_heading = 90.0
	env.current_boundary_layer = 4.0
	var world := WorldModel.new(env)
	var bed := world.seabed_y_at(0.0, 0.0)
	check_near(world.current_velocity_at(Vector3(0.0, bed + 10.0, 0.0)).x, 1.0, 1e-6, "free stream above the layer")
	check_near(world.current_velocity_at(Vector3(0.0, bed + 2.0, 0.0)).x, pow(0.5, 1.0 / 7.0), 1e-6, "1/7 power law inside the layer")
	check_near(world.current_velocity_at(Vector3(0.0, bed - 0.1, 0.0)).x, 0.0, 1e-9, "no current below the seabed")
	env.current_boundary_layer = 0.0
	check_near(world.current_velocity_at(Vector3(0.0, bed + 0.5, 0.0)).x, 1.0, 1e-6, "layer thickness 0 = uniform")


func test_interpolation_and_depth_shift() -> void:
	var engine := _engine(30.0)
	var vehicle := _vehicle(engine, VehicleConfig.new(), engine.world.place_on_seabed(0.0, 0.0, 1.5))
	vehicle.set_pilot_command(RovVehicle.Axis.SURGE, 1.0)
	engine.start()
	engine.advance(1.0)
	engine.advance(0.005)
	check_near(engine.interpolation_fraction(), 0.5, 0.01, "interpolation fraction while running")
	var mid := vehicle.get_interpolated_transform(0.5).origin
	check_vec_near(mid, (vehicle.previous_position + vehicle.position) * 0.5, 1e-6, "pose interpolated between steps")
	engine.pause()
	check_near(engine.interpolation_fraction(), 1.0, 1e-9, "paused: show the exact current pose")
	var y_before := vehicle.position.y
	engine.environment.water_depth = 40.0
	check_near(vehicle.position.y, y_before - 10.0, 1e-4, "objects move with the seabed when depth changes")
	engine.reset()
	check_near(vehicle.position.y, engine.world.seabed_reference_y() + 1.5, 1e-4, "reset pose moved with the seabed too")
	engine.free()
