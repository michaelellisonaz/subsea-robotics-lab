## Pilot aids: depth hold and heading hold running on sensor readings, with
## the full vehicle dynamics.
extends "res://tests/test_suite.gd"


func _engine() -> SimulationEngine:
	var engine := SimulationEngine.new()
	engine.auto_advance = false
	engine.clock.max_steps_per_frame = 1000000
	engine.environment.water_depth = 30.0
	engine.environment.current_speed = 0.0
	return engine


func _run(engine: SimulationEngine, seconds: float) -> void:
	engine.start()
	engine.advance(seconds)
	engine.pause()


func test_aids_need_sensor_data() -> void:
	var engine := _engine()
	var vehicle := RovVehicle.new(VehicleConfig.new(), Vector3(0.0, -20.0, 0.0))
	engine.objects.register(vehicle)
	check(not vehicle.toggle_depth_hold() and vehicle.aids.status != "", "depth hold refuses to engage before any reading")
	_run(engine, 1.0)
	vehicle.sensors.get_sensor("Compass").enabled = false
	check(not vehicle.toggle_heading_hold(), "heading hold refuses to engage with the compass off")
	check(vehicle.toggle_depth_hold() and vehicle.aids.depth_hold, "depth hold engages once readings arrive")
	vehicle.sensors.get_sensor("Depth").enabled = false
	_run(engine, 1.5)
	check(not vehicle.aids.depth_hold and vehicle.aids.status.contains("released"), "depth hold releases when its sensor stops")
	engine.free()


func test_depth_hold() -> void:
	var engine := _engine()
	var free_vehicle := RovVehicle.new(VehicleConfig.new(), Vector3(-20.0, -20.0, 0.0))
	var held := RovVehicle.new(VehicleConfig.new(), Vector3(20.0, -20.0, 0.0))
	engine.objects.register(free_vehicle)
	engine.objects.register(held)
	_run(engine, 1.0)
	check(held.toggle_depth_hold(), "depth hold engaged")
	var setpoint := held.aids.depth_setpoint
	_run(engine, 60.0)
	check(free_vehicle.depth() < 20.0 - 2.0, "without the aid the +3 N buoyant vehicle rises (%.2f m)" % free_vehicle.depth())
	# The aid holds the depth at the sensor (8 cm above the CG), so compare with that.
	var sensor := held.sensors.get_sensor("Depth")
	var sensor_depth: float = sensor.latest.truth["depth"]
	check(absf(sensor_depth - setpoint) < 0.03, "depth hold keeps the setpoint within 3 cm (error %.3f m)" % (sensor_depth - setpoint))
	check(held.applied_command[RovVehicle.Axis.HEAVE] < 0.0, "the aid pushes down against the positive buoyancy")
	held.set_pilot_command(RovVehicle.Axis.HEAVE, 1.0)
	_run(engine, 2.0)
	held.set_pilot_command(RovVehicle.Axis.HEAVE, 0.0)
	_run(engine, 1.0)
	var new_setpoint := held.aids.depth_setpoint
	check(new_setpoint < setpoint - 0.5, "pilot heave input overrides and re-captures a shallower setpoint")
	_run(engine, 20.0)
	sensor_depth = sensor.latest.truth["depth"]
	check(absf(sensor_depth - new_setpoint) < 0.1, "new depth held after the override (error %.3f m)" % (sensor_depth - new_setpoint))
	engine.free()


func test_depth_hold_follows_water_depth_change() -> void:
	var engine := _engine()
	var vehicle := RovVehicle.new(VehicleConfig.new(), engine.world.place_on_seabed(0.0, 0.0, 3.0))
	engine.objects.register(vehicle)
	_run(engine, 1.0)
	check(vehicle.toggle_depth_hold(), "depth hold engaged")
	var setpoint := vehicle.aids.depth_setpoint
	engine.environment.water_depth = 80.0
	check_near(vehicle.aids.depth_setpoint, setpoint + 50.0, 1e-4, "setpoint moves with the seabed (site shifted 50 m down)")
	_run(engine, 10.0)
	var altitude := vehicle.altitude(engine.world)
	check(absf(vehicle.sensors.get_sensor("Depth").latest.truth["depth"] - vehicle.aids.depth_setpoint) < 0.05 and altitude > 2.0,
		"vehicle keeps its height above the moved seabed (altitude %.2f m)" % altitude)
	engine.free()


func test_heading_hold() -> void:
	var engine := _engine()
	var vehicle := RovVehicle.new(VehicleConfig.new(), Vector3(0.0, -20.0, 0.0))
	engine.objects.register(vehicle)
	_run(engine, 1.0)
	check(vehicle.toggle_heading_hold(), "heading hold engaged")
	var setpoint := vehicle.aids.heading_setpoint
	vehicle.angular_velocity = Vector3(0.0, -0.8, 0.0)  # sudden clockwise yaw disturbance
	_run(engine, 10.0)
	check(absf(wrapf(vehicle.heading_degrees() - setpoint, -180.0, 180.0)) < 1.5, "heading recovers after a disturbance (error %.2f°)" % wrapf(vehicle.heading_degrees() - setpoint, -180.0, 180.0))
	engine.environment.current_speed = 0.5
	engine.environment.current_heading = 90.0
	vehicle.set_pilot_command(RovVehicle.Axis.SURGE, 0.6)
	_run(engine, 30.0)
	check(absf(wrapf(vehicle.heading_degrees() - setpoint, -180.0, 180.0)) < 2.0, "heading held while driving across a 0.5 m/s current")
	vehicle.set_pilot_command(RovVehicle.Axis.YAW, 0.8)
	_run(engine, 2.0)
	vehicle.set_pilot_command(RovVehicle.Axis.YAW, 0.0)
	_run(engine, 0.5)
	check(absf(wrapf(vehicle.aids.heading_setpoint - setpoint, -180.0, 180.0)) > 20.0, "yaw input overrides and re-captures the setpoint")
	engine.free()


func test_position_hold() -> void:
	var engine := _engine()
	engine.environment.current_speed = 0.25
	var free_vehicle := RovVehicle.new(VehicleConfig.new(), engine.world.place_on_seabed(-10.0, 0.0, 2.0))
	var held := RovVehicle.new(VehicleConfig.new(), engine.world.place_on_seabed(10.0, 0.0, 2.0))
	engine.objects.register(free_vehicle)
	engine.objects.register(held)
	_run(engine, 1.0)
	check(held.toggle_depth_hold() and held.toggle_heading_hold() and held.toggle_position_hold(), "all three holds engaged")
	var start := held.position
	var free_start := free_vehicle.position
	_run(engine, 60.0)
	var drift := Vector2(held.position.x - start.x, held.position.z - start.z).length()
	var free_drift := Vector2(free_vehicle.position.x - free_start.x, free_vehicle.position.z - free_start.z).length()
	check(free_drift > 5.0, "without station keeping the current carries the vehicle away (%.1f m)" % free_drift)
	check(drift < 0.3, "DVL station keeping holds within 0.3 m for 60 s against a 0.25 m/s current (%.2f m)" % drift)
	held.set_pilot_command(RovVehicle.Axis.SURGE, 0.6)
	_run(engine, 3.0)
	held.set_pilot_command(RovVehicle.Axis.SURGE, 0.0)
	_run(engine, 1.0)
	check(held.aids.position_hold and held.aids.position_offset.length() < 0.5, "surge input overrides and the hold re-captures at the new spot")
	held.sensors.get_sensor("DVL").set_param("max_altitude", 0.5)
	_run(engine, 2.0)
	check(not held.aids.position_hold and held.aids.status.contains("released"), "losing DVL bottom lock releases position hold")
	engine.free()


func test_attitude_hold_counters_arm_moment() -> void:
	var engine := _engine()
	var free_vehicle := RovVehicle.new(VehicleConfig.new(), Vector3(-10.0, -20.0, 0.0))
	var held := RovVehicle.new(VehicleConfig.new(), Vector3(10.0, -20.0, 0.0))
	engine.objects.register(free_vehicle)
	engine.objects.register(held)
	_run(engine, 1.0)
	check(held.toggle_attitude_hold(), "attitude hold engaged")
	for vehicle in [free_vehicle, held]:
		vehicle.manipulator.command_tool(vehicle.manipulator.mount_position + Vector3(0.0, 0.0, -1.0), 0.0, 0.0, true)
	_run(engine, 25.0)
	check(free_vehicle.pitch_degrees() < -3.0, "without the aid the outstretched arm trims the vehicle nose-down (%.1f°)" % free_vehicle.pitch_degrees())
	check(absf(held.pitch_degrees()) < 0.5 and absf(held.roll_degrees()) < 0.5, "attitude hold keeps it level (pitch %.2f°, roll %.2f°)" % [held.pitch_degrees(), held.roll_degrees()])
	engine.free()
