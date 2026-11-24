## Manipulator: kinematics, inverse kinematics, servos and backlash, payload
## capacity, grasping, loads on the vehicle and the accuracy test.
extends "res://tests/test_suite.gd"


func _engine(depth: float = 30.0) -> SimulationEngine:
	var engine := SimulationEngine.new()
	engine.auto_advance = false
	engine.clock.max_steps_per_frame = 1000000
	engine.environment.water_depth = depth
	engine.environment.current_speed = 0.0
	return engine


func _run(engine: SimulationEngine, seconds: float) -> void:
	engine.start()
	engine.advance(seconds)
	engine.pause()


func _arm(layout: String = "arm_5dof", backlash: float = 0.3) -> Manipulator:
	var config := VehicleConfig.new()
	config.set_arm_layout(layout)
	config.set_value("arm_backlash", backlash)
	return Manipulator.new(config)


func test_layouts_and_forward_kinematics() -> void:
	var counts := {"arm_3dof": 3, "arm_4dof": 4, "arm_5dof": 5, "arm_6dof": 6, "none": 0}
	for layout in counts:
		check(_arm(layout).joints.size() == counts[layout], "%s has %d joints" % [layout, counts[layout]])
	var arm := _arm()
	var zero := PackedFloat64Array([0, 0, 0, 0, 0])
	var tool := arm.tool_transform(zero)
	var straight := 0.06 + arm.upper_length + arm.forearm_length + 0.06 + 0.16
	check_vec_near(tool.origin, arm.mount_position + Vector3.FORWARD * straight, 1e-6, "all joints at zero: tool straight ahead of the base")
	check_near(arm.full_reach(), straight - 0.06, 1e-6, "full reach measured from the shoulder")
	var raised := arm.tool_transform(PackedFloat64Array([0, deg_to_rad(90.0), 0, 0, 0]))
	check(raised.origin.y > arm.mount_position.y + 0.9, "positive shoulder pitch raises the arm")
	var left := arm.tool_transform(PackedFloat64Array([deg_to_rad(90.0), 0, 0, 0, 0]))
	check(left.origin.x < arm.mount_position.x - 0.9, "positive yaw swings the arm to port")


func test_inverse_kinematics() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for layout in ["arm_5dof", "arm_6dof", "arm_4dof", "arm_3dof"]:
		var arm := _arm(layout)
		var solved := 0
		var worst := 0.0
		var limits_ok := true
		for trial in 20:
			var q := PackedFloat64Array()
			for joint in arm.joints:
				q.append(rng.randf_range(lerpf(joint.min_angle, joint.max_angle, 0.15), lerpf(joint.min_angle, joint.max_angle, 0.85)))
			var goal := arm.tool_transform(q)
			var direction := -goal.basis.z
			var result := arm.solve_ik(goal.origin, direction, arm.target_angles())
			if result["reachable"]:
				solved += 1
				worst = maxf(worst, result["position_error"])
			var angles: PackedFloat64Array = result["angles"]
			for i in arm.joints.size():
				if angles[i] < arm.joints[i].min_angle - 1e-9 or angles[i] > arm.joints[i].max_angle + 1e-9:
					limits_ok = false
		check(solved >= 18, "%s: IK reaches %d of 20 random reachable poses" % [layout, solved])
		check(worst < 0.005, "%s: residual error below 5 mm (worst %.2f mm)" % [layout, worst * 1000.0])
		check(limits_ok, "%s: IK respects joint limits" % layout)
	var arm := _arm()
	var before := arm.target_angles()
	check(not arm.command_tool(arm.mount_position + Vector3(0, 0, -3.0), 0.0, 0.0), "target 3 m away is rejected")
	check(arm.ik_status == "out of reach" and arm.target_angles() == before, "rejected command leaves the targets unchanged")
	check(arm.command_tool(arm.mount_position + Vector3(0.1, -0.3, -0.6), -45.0, 30.0), "reachable command accepted")
	var tool := arm.tool_transform(arm.target_angles())
	check_vec_near(tool.origin, arm.mount_position + Vector3(0.1, -0.3, -0.6), 0.001, "planned tool position")
	check_near(rad_to_deg(asin((-tool.basis.z).y)), -45.0, 1.0, "planned tool pitch")


func test_servo_speed_and_backlash() -> void:
	var joint := ManipulatorJoint.new("test", Vector3.RIGHT, Vector3.ZERO, -180.0, 180.0)
	joint.set_target(deg_to_rad(90.0))
	var time := 0.0
	while not joint.is_settled() and time < 20.0:
		joint.step(0.01, deg_to_rad(30.0))
		time += 0.01
	check(time > 3.0 and time < 4.0, "90° at 30 °/s takes ~3 s (%.2f s)" % time)
	joint.backlash = deg_to_rad(1.0)
	joint.place(0.0)
	joint.set_target(deg_to_rad(10.0))
	while not joint.is_settled():
		joint.step(0.01, deg_to_rad(30.0))
	var from_below := joint.angle()
	joint.set_target(deg_to_rad(20.0))
	while not joint.is_settled():
		joint.step(0.01, deg_to_rad(30.0))
	joint.set_target(deg_to_rad(10.0))
	while not joint.is_settled():
		joint.step(0.01, deg_to_rad(30.0))
	check_near(rad_to_deg(joint.angle() - from_below), 1.0, 1e-6, "approach direction changes the final angle by the backlash")


func test_payload_capacity() -> void:
	var arm := _arm()
	check_near(arm.payload_capacity_at(arm.full_reach()), 12.0, 0.01, "rated payload at full reach")
	check(arm.payload_capacity_at(arm.full_reach() * 0.5) > 20.0, "more capacity closer in")
	check(arm.sample_envelope(5).size() == 125, "reach envelope sampled")


func test_grasp_carry_and_release() -> void:
	var engine := _engine()
	var vehicle := RovVehicle.new(VehicleConfig.new(), engine.world.place_on_seabed(0.0, 0.0, 1.5))
	vehicle.is_dynamic = false
	engine.objects.register(vehicle)
	var arm := vehicle.manipulator
	var reach_point := arm.mount_position + Vector3(0.0, -0.45, -0.55)
	var item_position := vehicle.local_to_world_point(reach_point)
	var item := GraspableObject.new("Test block", "box", Vector3(0.08, 0.1, 0.12), 3.0, 2500.0, Color.WHITE, item_position)
	item.is_dynamic = false
	engine.objects.register(item)
	check(arm.command_tool(reach_point, -60.0, 0.0), "tool commanded to the item")
	_run(engine, 8.0)
	arm.set_gripper_closed(true)
	_run(engine, 2.0)
	check(arm.grasped == item and item.held_by == arm, "closing the gripper around the item grasps it")
	check_near(arm.gripper_opening, item.grasp_width, 1e-6, "jaws stop at the item width")
	arm.command_tool(reach_point + Vector3(0.0, 0.3, 0.0), -60.0, 0.0)
	_run(engine, 5.0)
	check(item.position.y > item_position.y + 0.25, "item is carried with the tool")
	arm.set_gripper_closed(false)
	item.is_dynamic = true
	_run(engine, 10.0)
	check(arm.grasped == null and item.held_by == null, "opening the gripper releases the item")
	check_near(item.position.y, engine.world.seabed_y_at(item.position.x, item.position.z) + 0.05, 0.01, "released item sinks to the seabed")
	engine.free()


func test_overload_drops_payload() -> void:
	var engine := _engine()
	var vehicle := RovVehicle.new(VehicleConfig.new(), engine.world.place_on_seabed(0.0, 0.0, 1.5))
	vehicle.is_dynamic = false
	engine.objects.register(vehicle)
	var arm := vehicle.manipulator
	var reach_point := arm.mount_position + Vector3(0.0, -0.2, -0.95)
	var anode := GraspableObject.new("Anode", "box", Vector3(0.12, 0.12, 0.6), 40.0, 2700.0, Color.WHITE, vehicle.local_to_world_point(reach_point))
	anode.is_dynamic = false
	engine.objects.register(anode)
	arm.command_tool(reach_point, 0.0, 0.0, true)
	_run(engine, 10.0)
	arm.set_gripper_closed(true)
	_run(engine, 3.0)
	check(arm.grasped == null and arm.status_message.begins_with("Dropped"), "25 kg (in water) at ~1 m reach exceeds the 12 kg rating: dropped (%s)" % arm.status_message)
	engine.free()


func test_arm_moment_trims_vehicle() -> void:
	var engine := _engine(200.0)
	var config := VehicleConfig.new()
	config.set_value("net_buoyancy", 0.0)
	var vehicle := RovVehicle.new(config, Vector3(0.0, -100.0, 0.0))
	engine.objects.register(vehicle)
	_run(engine, 10.0)
	check(absf(vehicle.pitch_degrees()) < 0.1, "stowed arm: vehicle level (pitch %.3f°)" % vehicle.pitch_degrees())
	vehicle.manipulator.command_tool(vehicle.manipulator.mount_position + Vector3(0.0, 0.0, -1.0), 0.0, 0.0, true)
	_run(engine, 20.0)
	check(vehicle.pitch_degrees() < -1.0, "arm stretched forward pitches the vehicle nose-down (%.2f°)" % vehicle.pitch_degrees())
	vehicle.manipulator.command_tool(vehicle.manipulator.mount_position + Vector3(0.75, 0.0, -0.3), 0.0, 0.0, true)
	_run(engine, 20.0)
	check(vehicle.roll_degrees() > 0.3, "arm swung out to starboard rolls the vehicle starboard-down (%.2f°)" % vehicle.roll_degrees())
	engine.free()


func test_accuracy_test() -> void:
	for backlash in [0.0, 0.5]:
		var engine := _engine(200.0)
		var config := VehicleConfig.new()
		config.set_value("arm_backlash", backlash)
		var vehicle := RovVehicle.new(config, Vector3(0.0, -100.0, 0.0))
		vehicle.is_dynamic = false
		engine.objects.register(vehicle)
		vehicle.manipulator.start_accuracy_test()
		_run(engine, 120.0)
		var summary := vehicle.manipulator.accuracy_summary()
		check(not vehicle.manipulator.accuracy_test_running and summary["reached"] == Manipulator.TEST_TARGETS.size(), "accuracy test completes all targets (backlash %.1f°)" % backlash)
		if backlash == 0.0:
			check(summary["max_error"] < 0.001, "no backlash: sub-millimetre positioning (max %.2f mm)" % (summary["max_error"] * 1000.0))
		else:
			check(summary["mean_error"] > 0.001 and summary["max_error"] < 0.03, "0.5° backlash: mm-level errors (mean %.1f mm, max %.1f mm)" % [summary["mean_error"] * 1000.0, summary["max_error"] * 1000.0])
		engine.free()


func test_operator_grasp_from_hovering_vehicle() -> void:
	# Realistic workflow: free-floating vehicle (current 0.25 m/s, +3 N buoyant),
	# station keeping on sensor-based holds, the operator re-aims the tool at the
	# item a few times (vehicle trim changes as the arm reaches), then grasps.
	var engine := SimulationEngine.new()
	engine.auto_advance = false
	engine.clock.max_steps_per_frame = 1000000
	var site := Site.populate(engine)
	var debris: GraspableObject = engine.objects.find_by_name("Debris block")
	var vehicle := RovVehicle.new(VehicleConfig.new(), Vector3.ZERO)
	var arm := vehicle.manipulator
	vehicle.position = debris.position - (arm.mount_position + Vector3(0.0, -0.45, -0.6))
	engine.objects.register(vehicle)
	_run(engine, 1.0)
	check(vehicle.aids.set_depth_hold(true, vehicle, vehicle.last_update_time)
		and vehicle.aids.set_heading_hold(true, vehicle, vehicle.last_update_time)
		and vehicle.aids.set_position_hold(true, vehicle, vehicle.last_update_time)
		and vehicle.aids.set_attitude_hold(true, vehicle, vehicle.last_update_time), "depth, heading, position and attitude hold engaged")
	for attempt in 4:
		var local := vehicle.orientation.inverse() * (debris.position - vehicle.position)
		arm.command_tool(local, -70.0, 0.0, true)
		_run(engine, 5.0)
	var tool_world := vehicle.local_to_world_point(arm.tool_transform().origin)
	check(tool_world.distance_to(debris.position) < Manipulator.GRASP_TOLERANCE, "operator corrections bring the tool onto the item (%.3f m)" % tool_world.distance_to(debris.position))
	arm.set_gripper_closed(true)
	_run(engine, 2.5)
	check(arm.grasped == debris, "item grasped from the hovering vehicle")
	arm.command_tool(arm.tool_target_position + Vector3(0.0, 0.3, 0.0), -40.0, 0.0, true)
	# The vehicle first sinks ~0.15 m under the new load until the depth-hold
	# integral catches up, so allow 10 s.
	_run(engine, 10.0)
	check(debris.position.y > engine.world.seabed_y_at(debris.position.x, debris.position.z) + 0.2, "item lifted off the seabed")
	check(vehicle.aids.position_offset.length() < 0.3, "station keeping held the vehicle within 0.3 m (estimate %.2f m)" % vehicle.aids.position_offset.length())
	check(absf(vehicle.pitch_degrees()) < 2.0 and absf(vehicle.roll_degrees()) < 2.0, "attitude hold keeps the vehicle level with the payload held (pitch %.1f°, roll %.1f°)" % [vehicle.pitch_degrees(), vehicle.roll_degrees()])
	engine.free()
