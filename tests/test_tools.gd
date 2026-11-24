## Stage 5: tool change, tool-tip contact force, arm / held-item collision,
## cleaning, the CP probe and protection model, the retrofit anode and the
## repair clamp (direct and through the arm).
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


## Static vehicle, facing north, placed so that `point` is at `offset` from
## the arm base (body axes).
func _vehicle_at(engine: SimulationEngine, point: Vector3, offset: Vector3) -> RovVehicle:
	var vehicle := RovVehicle.new(VehicleConfig.new(), Vector3.ZERO)
	vehicle.position = point - (vehicle.manipulator.mount_position + offset)
	vehicle.is_dynamic = false
	engine.objects.register(vehicle)
	return vehicle


## Mounts a tool through the normal tool change; returns the time it took.
func _mount(engine: SimulationEngine, arm: Manipulator, tool: WorkTool) -> float:
	check(arm.request_tool(tool), "tool change to %s accepted" % (tool.display_name if tool != null else "gripper"))
	var time := 0.0
	while arm.tool_change_phase != "" and time < 40.0:
		_run(engine, 0.5)
		time += 0.5
	return time


## Commands the tool point to `world_point` (vehicle facing north, so body
## axes = world axes) with a pitch, partial reach allowed.
func _aim(vehicle: RovVehicle, world_point: Vector3, pitch: float) -> void:
	vehicle.manipulator.command_tool(vehicle.orientation.inverse() * (world_point - vehicle.position), pitch, 0.0, true)


func _tool_by_type(arm: Manipulator, type: Variant) -> WorkTool:
	for t in arm.tools:
		if is_instance_of(t, type):
			return t
	return null


func test_tool_change() -> void:
	var engine := _engine()
	var vehicle := RovVehicle.new(VehicleConfig.new(), Vector3(0.0, -15.0, 0.0))
	vehicle.is_dynamic = false
	engine.objects.register(vehicle)
	var arm := vehicle.manipulator
	check(arm.tools.size() == 2 and arm.tool == null, "brush and CP probe in the skid, gripper free")
	var reach := arm.full_reach()
	arm.ready_pose()
	_run(engine, 5.0)
	var brush := _tool_by_type(arm, CleaningBrush)
	arm.grasped = GraspableObject.new("Dummy")
	check(not arm.request_tool(brush), "no tool change while holding an item")
	arm.grasped = null
	check(arm.request_tool(brush) and arm.tool_change_phase == "stowing", "tool change starts by stowing the arm")
	check(not arm.command_tool(arm.mount_position + Vector3(0, -0.3, -0.6), -45.0, 0.0), "arm commands refused during the change")
	var time := 0.0
	while arm.tool_change_phase != "" and time < 40.0:
		_run(engine, 0.1)
		time += 0.1
	check(arm.tool == brush and time >= Manipulator.TOOL_CHANGE_TIME, "brush mounted after %.1f s (>= %.0f s in the skid)" % [time, Manipulator.TOOL_CHANGE_TIME])
	check_near(arm.full_reach(), reach + brush.length, 1e-6, "tool extends the reach by its length")
	check(arm.command_tool(arm.mount_position + Vector3(0, -0.3, -0.7), -60.0, 0.0), "IK uses the extended tool point")
	_run(engine, 6.0)
	var tip := arm.tool_transform().origin
	check(tip.distance_to(arm.mount_position + Vector3(0, -0.3, -0.7)) < 0.01, "brush tip placed at the commanded point (%.1f mm)" % (tip.distance_to(arm.mount_position + Vector3(0, -0.3, -0.7)) * 1000.0))
	arm.tool_action(0.0)
	check(brush.active and not arm.gripper_closing == false, "G spins the brush (gripper stays closed on the handle)")
	arm.set_gripper_closed(false)
	check(arm.gripper_closing, "the gripper cannot open while a tool is mounted")
	check(arm.next_tool() == _tool_by_type(arm, CpProbe), "next tool after the brush is the CP probe")
	_mount(engine, arm, null)
	check(arm.tool == null and not brush.active and arm.full_reach() == reach, "brush returned to the skid")
	engine.free()


func test_brush_contact_force_and_cleaning() -> void:
	var engine := _engine()
	var pipeline: Pipeline = Site.populate(engine)["pipeline"]
	var spot := Vector3(10.0, pipeline.axis_y() + pipeline.radius(), pipeline.axis_z())
	var vehicle := _vehicle_at(engine, spot, Vector3(0.0, -0.3, -0.6))
	var arm := vehicle.manipulator
	var brush := _tool_by_type(arm, CleaningBrush) as CleaningBrush
	_mount(engine, arm, brush)
	_aim(vehicle, spot + Vector3.UP * (brush.tip_radius + 0.08), -80.0)
	_run(engine, 8.0)
	check(brush.contact.is_empty() and brush.contact_force == 0.0, "no contact above the pipe")
	_aim(vehicle, spot + Vector3.UP * (brush.tip_radius - 0.03), -80.0)
	_run(engine, 4.0)
	check(brush.contact_force > 60.0 and brush.contact_force < 90.0, "3 cm into the compliant mount: ~75 N (%.1f N)" % brush.contact_force)
	check(WorkTool.surface_name(brush.contact) == "corrosion product", "brush touches the corrosion product")
	var load_sum := Vector3.ZERO
	for load in arm.contact_loads:
		load_sum += load[1]
	check_near(load_sum.y, brush.contact_force, 0.5, "contact force passed to the vehicle (upward reaction)")
	check_near(pipeline.deposit_at(spot), Pipeline.CORROSION_PRODUCT_MM, 1e-6, "brush off: nothing cleaned")
	arm.tool_action(0.0)
	_run(engine, 8.0)
	check(pipeline.surface_kind(spot, pipeline.primitives[0]) == "bare steel", "spinning brush cleans the corrosion product to bare steel")
	check_near(brush.reaction_torque.length(), CleaningBrush.FRICTION * brush.contact_force * CleaningBrush.EFFECTIVE_RADIUS, 1e-6, "brush friction torque reacts on the vehicle")
	check(pipeline.cleaned_area() > 0.005 and pipeline.cleaned_area() < 0.1, "cleaned patch about the brush footprint (%.3f m²)" % pipeline.cleaned_area())
	check_near(pipeline.deposit_at(Vector3(11.4, spot.y, spot.z)), Pipeline.CORROSION_PRODUCT_MM, 1e-6, "deposit away from the brush untouched")
	# Light touch elsewhere (lift off first): below the working force nothing is removed.
	var light := Vector3(8.8, spot.y, spot.z)
	_aim(vehicle, spot + Vector3.UP * 0.15, -80.0)
	_run(engine, 3.0)
	_aim(vehicle, light + Vector3.UP * 0.15, -80.0)
	_run(engine, 4.0)
	_aim(vehicle, light + Vector3.UP * (brush.tip_radius - 0.01), -80.0)
	_run(engine, 6.0)
	check(brush.status.begins_with("Contact force too low"), "25 N is below the working range (%s)" % brush.status)
	check_near(pipeline.deposit_at(light), Pipeline.CORROSION_PRODUCT_MM, 1e-6, "no cleaning below the working force")
	engine.free()


func test_tool_bottoming_out_blocks_the_arm() -> void:
	var engine := _engine()
	var pipeline: Pipeline = Site.populate(engine)["pipeline"]
	var spot := Vector3(4.0, pipeline.axis_y() + pipeline.radius(), pipeline.axis_z())
	var vehicle := _vehicle_at(engine, spot, Vector3(0.0, -0.3, -0.6))
	var arm := vehicle.manipulator
	var brush := _tool_by_type(arm, CleaningBrush)
	_mount(engine, arm, brush)
	_aim(vehicle, spot + Vector3.UP * (brush.tip_radius + 0.05), -80.0)
	_run(engine, 6.0)
	_aim(vehicle, spot - Vector3.UP * 0.15, -80.0)
	var deepest: Array = [0.0]
	engine.step_completed.connect(func(_t: float, _dt: float) -> void:
		deepest[0] = maxf(deepest[0], brush.contact.get("depth", 0.0)))
	_run(engine, 6.0)
	check(arm.blocked and arm.collision_info.contains("bottomed out"), "pushing past the tool travel blocks the arm (%s)" % arm.collision_info)
	check(deepest[0] < brush.travel + Manipulator.COLLISION_ALLOWANCE + 0.005, "tip never goes far past its travel (%.1f mm)" % (deepest[0] * 1000.0))
	_aim(vehicle, spot + Vector3.UP * 0.2, -80.0)
	_run(engine, 4.0)
	check(not arm.blocked and brush.contact.is_empty(), "moving away is allowed")
	engine.free()


func test_arm_cannot_pass_through_seabed() -> void:
	var engine := _engine()
	var vehicle := RovVehicle.new(VehicleConfig.new(), engine.world.place_on_seabed(0.0, 0.0, 1.0))
	vehicle.is_dynamic = false
	engine.objects.register(vehicle)
	var arm := vehicle.manipulator
	var seabed := engine.world.seabed_y_at(0.0, -1.0)
	var lowest: Array = [INF]
	engine.step_completed.connect(func(_t: float, _dt: float) -> void:
		lowest[0] = minf(lowest[0], vehicle.local_to_world_point(arm.tool_transform().origin).y))
	_aim(vehicle, vehicle.local_to_world_point(arm.mount_position + Vector3(0, 0, -0.6)) + Vector3.DOWN * 1.2, -60.0)
	_run(engine, 10.0)
	check(arm.blocked and arm.collision_info.contains("seabed"), "arm stops at the seabed (%s)" % arm.collision_info)
	check(lowest[0] > seabed - 0.01, "jaw tips never go into the seabed (lowest %.3f m above)" % (lowest[0] - seabed))
	check(arm.collision_depth <= Manipulator.COLLISION_ALLOWANCE + 0.002, "penetration within the allowance (%.1f mm)" % (arm.collision_depth * 1000.0))
	arm.ready_pose()
	_run(engine, 5.0)
	check(not arm.blocked and arm.collision_info == "", "arm moves freely again once lifted")
	engine.free()


func test_held_item_kept_out_of_seabed() -> void:
	var engine := _engine()
	var vehicle := RovVehicle.new(VehicleConfig.new(), engine.world.place_on_seabed(0.0, 0.0, 0.8))
	vehicle.is_dynamic = false
	engine.objects.register(vehicle)
	var arm := vehicle.manipulator
	var reach_point := arm.mount_position + Vector3(0.0, -0.3, -0.55)
	var item := GraspableObject.new("Test block", "box", Vector3(0.08, 0.16, 0.12), 3.0, 2500.0, Color.WHITE, vehicle.local_to_world_point(reach_point))
	item.is_dynamic = false
	engine.objects.register(item)
	arm.command_tool(reach_point, -60.0, 0.0)
	_run(engine, 8.0)
	arm.set_gripper_closed(true)
	_run(engine, 2.0)
	check(arm.grasped == item, "block grasped")
	var seabed := engine.world.seabed_y_at(item.position.x, item.position.z)
	arm.command_tool(reach_point + Vector3.DOWN * 0.5, -60.0, 0.0, true)
	_run(engine, 8.0)
	check(arm.blocked and arm.collision_info.begins_with("Test block"), "held block stops on the seabed (%s)" % arm.collision_info)
	check(item.position.y - item.bottom_clearance > seabed - 0.015, "block not pushed into the seabed (%.3f m)" % (item.position.y - item.bottom_clearance - seabed))
	engine.free()


func test_contact_reaction_moves_a_free_vehicle() -> void:
	var engine := _engine()
	var pipeline: Pipeline = Site.populate(engine)["pipeline"]
	var spot := Vector3(4.0, pipeline.axis_y() + pipeline.radius(), pipeline.axis_z())
	var vehicle := _vehicle_at(engine, spot, Vector3(0.0, -0.3, -0.6))
	vehicle.config.set_value("net_buoyancy", 0.0)
	vehicle.apply_config(vehicle.config)
	var arm := vehicle.manipulator
	var brush := _tool_by_type(arm, CleaningBrush)
	_mount(engine, arm, brush)
	_aim(vehicle, spot + Vector3.UP * (brush.tip_radius + 0.03), -80.0)
	_run(engine, 6.0)
	var start := vehicle.position
	vehicle.is_dynamic = true
	_aim(vehicle, spot + Vector3.UP * (brush.tip_radius - 0.05), -80.0)
	_run(engine, 3.0)
	check(vehicle.position.y - start.y > 0.02, "pressing the brush down pushes a free vehicle up (%.3f m)" % (vehicle.position.y - start.y))
	engine.free()


func test_cp_probe_readings() -> void:
	var engine := _engine()
	var pipeline: Pipeline = Site.populate(engine)["pipeline"]
	var flange := Vector3(6.0, pipeline.axis_y() + pipeline.flange_radius(), pipeline.axis_z())
	var vehicle := _vehicle_at(engine, flange, Vector3(0.0, -0.3, -0.6))
	var arm := vehicle.manipulator
	var probe := _tool_by_type(arm, CpProbe) as CpProbe
	_mount(engine, arm, probe)
	# Coated pipe next to the flange: no metallic contact.
	var coated := Vector3(5.6, pipeline.axis_y() + pipeline.radius(), pipeline.axis_z())
	_aim(vehicle, coated + Vector3.UP * (probe.tip_radius - 0.012), -80.0)
	_run(engine, 6.0)
	check(probe.contact_force > probe.min_force and probe.status.begins_with("No metallic contact") and is_nan(probe.reading), "no reading on marine growth (%s)" % probe.status)
	check(probe.action(0.0).begins_with("No valid") and probe.log.is_empty(), "nothing to log")
	_aim(vehicle, flange + Vector3.UP * 0.1, -80.0)
	_run(engine, 3.0)
	_aim(vehicle, flange + Vector3.UP * (probe.tip_radius - 0.012), -80.0)
	_run(engine, 6.0)
	var truth := pipeline.cp_potential(probe.contact["point"])
	check(not is_nan(probe.reading) and absf(probe.reading - truth) < 4.0 * CpProbe.NOISE_MV, "flange reading %.1f mV vs model %.1f mV" % [probe.reading, truth])
	check(truth > Pipeline.CP_CRITERION, "E 6 is under-protected (depleted anode at E 0)")
	arm.tool_action(engine.clock.sim_time)
	check(probe.log.size() == 1 and absf(probe.log[0]["east"] - 6.0) < 0.05 and probe.log[0]["surface"] == "flange", "G logs the reading with its position")
	# Corrosion product: no contact until cleaned.
	var corroded := Vector3(10.0, pipeline.axis_y() + pipeline.radius(), pipeline.axis_z())
	vehicle.position += corroded - flange
	_aim(vehicle, corroded + Vector3.UP * 0.1, -80.0)
	_run(engine, 3.0)
	_aim(vehicle, corroded + Vector3.UP * (probe.tip_radius - 0.012), -80.0)
	_run(engine, 5.0)
	check(is_nan(probe.reading), "no reading through corrosion product (%s)" % probe.status)
	pipeline.clean(corroded, 0.08, 10.0)
	_run(engine, 3.0)
	check(not is_nan(probe.reading) and probe.status.contains("bare steel"), "reading on cleaned steel (%s)" % probe.status)
	engine.reset()
	check(probe.log.is_empty() and arm.tool == null, "reset empties the log and returns the tool")
	engine.free()


func test_cp_model_and_retrofit_anode() -> void:
	var engine := _engine()
	var site := Site.populate(engine)
	var pipeline: Pipeline = site["pipeline"]
	var anode: RetrofitAnode = site["anode"]
	var top := func(x: float) -> Vector3: return Vector3(x, pipeline.axis_y() + pipeline.radius(), pipeline.axis_z())
	check(pipeline.cp_potential(top.call(-24.0)) < -1000.0, "at a working bracelet: %.0f mV" % pipeline.cp_potential(top.call(-24.0)))
	var worst := pipeline.least_protected()
	check(worst["potential"] > Pipeline.CP_CRITERION and absf(worst["east"]) < 12.0, "middle section under-protected: %.0f mV at E %.1f" % [worst["potential"], worst["east"]])
	_run(engine, 3.0)
	check(not anode.connected and anode.distance_to_pipeline() > RetrofitAnode.CABLE_LENGTH, "staged anode out of cable reach, not connected")
	anode.position = engine.world.place_on_seabed(2.0, Pipeline.NORTH - 1.5, anode.bottom_clearance)
	_run(engine, 3.0)
	check(anode.connected and pipeline.retrofit_anodes.size() == 1, "anode set down 1.5 m from the pipe connects")
	worst = pipeline.least_protected()
	check(worst["potential"] <= Pipeline.CP_CRITERION, "whole line protected after the retrofit (worst %.0f mV)" % worst["potential"])
	var holder := RefCounted.new()
	anode.held_by = holder
	_run(engine, 0.1)
	check(not anode.connected and pipeline.retrofit_anodes.is_empty(), "picking it up disconnects it")
	anode.held_by = null
	anode.position = engine.world.place_on_seabed(2.0, Pipeline.NORTH - 3.0, anode.bottom_clearance)
	_run(engine, 3.0)
	check(not anode.connected, "3 m away is out of cable reach")
	engine.free()


func _release_clamp_at(arm: Manipulator, clamp: RepairClamp, position: Vector3, rotation: Quaternion) -> void:
	clamp.position = position
	clamp.orientation = rotation
	clamp.is_dynamic = false
	arm.grasped = clamp
	clamp.held_by = arm
	arm.release()


func test_clamp_installation_rules() -> void:
	var engine := _engine()
	var site := Site.populate(engine)
	var pipeline: Pipeline = site["pipeline"]
	var clamp: RepairClamp = site["clamp"]
	var arm := Manipulator.new(VehicleConfig.new())
	var axis := func(x: float) -> Vector3: return Vector3(x, pipeline.axis_y(), pipeline.axis_z())
	_release_clamp_at(arm, clamp, axis.call(-10.5), Quaternion(Vector3.UP, deg_to_rad(45.0)))
	check(not clamp.installed and clamp.is_dynamic and arm.status_message.contains("off the pipe axis"), "misaligned clamp not installed (%s)" % arm.status_message)
	_release_clamp_at(arm, clamp, axis.call(-10.5) + Vector3.UP * 0.06, Quaternion.IDENTITY)
	check(not clamp.installed and arm.status_message.contains("not seated"), "clamp 60 mm high not seated (%s)" % arm.status_message)
	_release_clamp_at(arm, clamp, axis.call(-9.0), Quaternion.IDENTITY)
	check(not clamp.installed and arm.status_message.contains("support"), "clamp over a support is obstructed (%s)" % arm.status_message)
	_release_clamp_at(arm, clamp, axis.call(-6.0), Quaternion.IDENTITY)
	check(not clamp.installed and arm.status_message.contains("flange"), "clamp over a flange is obstructed")
	_release_clamp_at(arm, clamp, axis.call(-10.0), Quaternion.IDENTITY)
	check(clamp.installed and pipeline.crack_status() == "open", "clamp 0.5 m from the crack installs but does not repair it")
	engine.reset()
	check(not clamp.installed and pipeline.clamps.is_empty() and clamp.position.z > -5.0, "reset removes the clamp")
	_release_clamp_at(arm, clamp, axis.call(-10.45) + Vector3.UP * 0.01, Quaternion(Vector3.UP, deg_to_rad(5.0)))
	check(clamp.installed and pipeline.crack_status() == "clamped", "clamp seated over the crack repairs it (%s)" % arm.status_message)
	check(clamp.position.distance_to(axis.call(-10.45)) < 1e-4 and clamp.orientation.is_equal_approx(Quaternion.IDENTITY), "closing pulls the clamp concentric")
	var hit := engine.world.raycast(axis.call(-10.45) + Vector3.UP * 3.0, Vector3.DOWN, 10.0)
	check_near(3.0 - hit, clamp.outer_radius, 1e-3, "ray from above lands on the clamp (part of the structure)")
	check(not clamp.can_be_grasped(), "an installed clamp cannot be picked up")
	pipeline.set_value("diameter", 0.7)
	_run(engine, 0.05)
	check(not clamp.installed and clamp.is_dynamic and pipeline.crack_status() == "open", "editing the diameter releases the clamp")
	pipeline.set_value("diameter", 0.6)
	engine.free()


func test_clamp_installed_with_the_arm() -> void:
	var engine := _engine()
	var site := Site.populate(engine)
	var pipeline: Pipeline = site["pipeline"]
	var clamp: RepairClamp = site["clamp"]
	var handle := clamp.grasp_point()
	var vehicle := _vehicle_at(engine, handle, Vector3(0.0, -0.7, -0.45))
	var arm := vehicle.manipulator
	_aim(vehicle, handle + Vector3.UP * 0.1, -80.0)
	_run(engine, 8.0)
	_aim(vehicle, handle, -80.0)
	_run(engine, 4.0)
	arm.set_gripper_closed(true)
	_run(engine, 2.0)
	check(arm.grasped == clamp, "clamp picked up by its handle")
	# Lift it clear of the pipe with the arm, then fly over the pipe (the
	# static vehicle is moved directly).
	_aim(vehicle, handle + Vector3.UP * 0.56, -80.0)
	_run(engine, 10.0)
	vehicle.position += Vector3(0.0, 0.3, pipeline.axis_z() - clamp.position.z)
	_run(engine, 0.5)
	check(clamp.position.y - clamp.outer_radius > pipeline.axis_y() + pipeline.radius(), "clamp carried above the pipe")
	# Lower onto the pipe as an operator would: re-aim a few times so the clamp
	# centre goes to just below the pipe axis; the crown stops on the pipe top.
	var goal := Vector3(clamp.position.x, pipeline.axis_y() - 0.02, pipeline.axis_z())
	for attempt in 4:
		var tool_world := vehicle.local_to_world_point(arm.tool_transform().origin)
		_aim(vehicle, tool_world + (goal - clamp.position), -80.0)
		_run(engine, 5.0)
	check(arm.blocked and arm.collision_info.begins_with("Repair clamp"), "lowering stops when the clamp sits on the pipe (%s)" % arm.collision_info)
	var radial := Vector2(clamp.position.y - pipeline.axis_y(), clamp.position.z - pipeline.axis_z()).length()
	check(radial < Pipeline.CLAMP_RADIAL_TOLERANCE, "seated within %.0f mm of the centreline (%.1f mm)" % [Pipeline.CLAMP_RADIAL_TOLERANCE * 1000.0, radial * 1000.0])
	arm.set_gripper_closed(false)
	_run(engine, 0.5)
	check(clamp.installed and pipeline.crack_status() == "clamped", "released clamp closes over the crack (%s)" % arm.status_message)
	engine.free()
