## Structures: primitive ray / penetration geometry, the pipeline model, and
## how sensors, the vehicle hull and loose objects interact with it.
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


func test_cylinder_primitive() -> void:
	var c := CylinderPrimitive.new(Vector3(-5, 0, 0), Vector3(5, 0, 0), 0.3)
	check_near(c.intersect_ray(Vector3(0, 5, 0), Vector3.DOWN, 100.0), 4.7, 1e-6, "ray from above hits the top")
	check_near(c.intersect_ray(Vector3(1, 0, 5), Vector3.FORWARD, 100.0), 4.7, 1e-6, "horizontal ray hits the side")
	check(c.intersect_ray(Vector3(0, 5, 0.5), Vector3.DOWN, 100.0) == INF, "ray beside the cylinder misses")
	check_near(c.intersect_ray(Vector3(-10, 0, 0), Vector3.RIGHT, 100.0), 5.0, 1e-6, "ray along the axis hits the end cap")
	check(c.intersect_ray(Vector3(0, 5, 0), Vector3.DOWN, 4.0) == INF, "hit beyond max distance ignored")
	var hit := c.penetration(Vector3(0, 0.25, 0), 0.0)
	check_near(hit["depth"], 0.05, 1e-6, "penetration depth")
	check_vec_near(hit["normal"], Vector3.UP, 1e-6, "penetration normal points out")
	check(c.penetration(Vector3(0, 0.5, 0), 0.1).is_empty(), "no overlap outside")
	check_near(c.penetration(Vector3(0, 0.35, 0), 0.1)["depth"], 0.05, 1e-6, "sphere radius inflates the shape")


func test_box_primitive() -> void:
	var b := BoxPrimitive.new(Vector3(0, 1, 0), Vector3(0.5, 1, 0.5))
	check_near(b.intersect_ray(Vector3(0, 5, 0), Vector3.DOWN, 100.0), 3.0, 1e-6, "ray hits the box top")
	check(b.intersect_ray(Vector3(2, 5, 0), Vector3.DOWN, 100.0) == INF, "ray misses the box")
	var hit := b.penetration(Vector3(0.45, 1, 0), 0.0)
	check_near(hit["depth"], 0.05, 1e-6, "box penetration depth (nearest face)")
	check_vec_near(hit["normal"], Vector3.RIGHT, 1e-6, "box penetration normal")


func test_pipeline_model() -> void:
	var pipeline := Pipeline.new(-30.0)
	check_near(pipeline.axis_y(), -30.0 + 0.25 + 0.3, 1e-6, "pipe axis = seabed + gap + radius")
	check(pipeline.joint_positions().size() == 4 and pipeline.support_positions().size() == 10, "4 flanged joints and 10 supports on 60 m")
	check(pipeline.defects.size() == 2, "corrosion and crack defects defined")
	var top := pipeline.raycast(Vector3(1.0, -20.0, -6.0), Vector3.DOWN, 100.0)
	check_near(-20.0 - top, -30.0 + 0.25 + 0.6, 1e-4, "ray from above lands on the pipe top")
	var flange_top := pipeline.raycast(Vector3(-18.0, -20.0, -6.0), Vector3.DOWN, 100.0)
	check(-20.0 - flange_top > -30.0 + 0.25 + 0.6 + 0.05, "flanges stand proud of the pipe")
	var changes: Array = [0]
	pipeline.geometry_changed.connect(func() -> void: changes[0] += 1)
	pipeline.set_value("diameter", 1.0)
	check(changes[0] == 1 and absf(pipeline.radius() - 0.5) < 1e-9, "diameter change rebuilds the geometry")
	check_near(pipeline.set_value("diameter", 5.0), 1.2, 1e-9, "diameter clamped")


func test_pipeline_follows_depth_and_sensors_see_it() -> void:
	var engine := _engine()
	var site := Site.populate(engine)
	var pipeline: Pipeline = site["pipeline"]
	var gap_before := pipeline.axis_y() - pipeline.radius() - engine.world.seabed_reference_y()
	engine.environment.water_depth = 60.0
	check_near(pipeline.axis_y() - pipeline.radius() - engine.world.seabed_reference_y(), gap_before, 1e-5, "pipeline moves with the seabed")
	engine.environment.water_depth = 30.0
	var vehicle := RovVehicle.new(VehicleConfig.new(), Vector3.ZERO)
	var altimeter: Sensor = vehicle.sensors.get_sensor("Altimeter")
	# Put the altimeter itself (0.42 m ahead of the CG) over the pipe axis.
	vehicle.position = Vector3(1.0, pipeline.axis_y() + 2.0, pipeline.axis_z() - altimeter.mount_position.z)
	vehicle.is_dynamic = false
	engine.objects.register(vehicle)
	altimeter.set_param("noise_abs", 0.0)
	altimeter.set_param("noise_rel", 0.0)
	_run(engine, 1.0)
	var mount := altimeter.mount_world_position(vehicle)
	var pipe_top := pipeline.axis_y() + pipeline.radius()
	check_near(altimeter.latest.values["range"], mount.y - pipe_top, 1e-3, "altimeter over the pipe measures the distance to the pipe top")
	check(altimeter.latest.values["range"] < mount.y - engine.world.seabed_y_at(mount.x, mount.z) - 0.5, "... not the seabed below it")
	engine.free()


func test_vehicle_cannot_pass_through_pipeline() -> void:
	var engine := _engine()
	var site := Site.populate(engine)
	var pipeline: Pipeline = site["pipeline"]
	var config := VehicleConfig.new()
	config.set_value("net_buoyancy", 0.0)
	var vehicle := RovVehicle.new(config, Vector3(1.0, pipeline.axis_y(), -1.0))
	engine.objects.register(vehicle)
	vehicle.set_pilot_command(RovVehicle.Axis.SURGE, 1.0)
	var deepest: Array = [0.0]
	engine.step_completed.connect(func(_t: float, _dt: float) -> void:
		for local_point in vehicle.contact.contact_points:
			var hit := pipeline.penetration(vehicle.local_to_world_point(local_point), 0.0)
			if not hit.is_empty():
				deepest[0] = maxf(deepest[0], hit["depth"]))
	_run(engine, 10.0)
	check(vehicle.position.z > pipeline.axis_z(), "vehicle stays on its side of the pipeline (z %.2f)" % vehicle.position.z)
	check(vehicle.contact.structure_points_in_contact > 0, "hull is pressed against the pipe")
	check(deepest[0] < 0.05, "hull penetration stays small (max %.3f m)" % deepest[0])
	engine.free()


func test_object_lands_on_pipeline() -> void:
	var engine := _engine()
	var site := Site.populate(engine)
	var pipeline: Pipeline = site["pipeline"]
	var item := GraspableObject.new("Test block", "box", Vector3(0.1, 0.1, 0.1), 3.0, 2500.0, Color.WHITE, Vector3(1.0, pipeline.axis_y() + 2.0, -6.0))
	engine.objects.register(item)
	_run(engine, 15.0)
	var top := pipeline.axis_y() + pipeline.radius()
	check_near(item.position.y, top + item.collision_radius, 0.01, "dropped item comes to rest on top of the pipe")
	engine.free()


func test_items_stay_put_in_current() -> void:
	var engine := _engine()
	engine.environment.current_speed = 0.5
	var site := Site.populate(engine)
	var items: Array = site["items"]
	var start: Array = []
	for item in items:
		start.append(item.position)
	_run(engine, 30.0)
	for i in items.size():
		check(items[i].position.distance_to(start[i]) < 0.01, "%s resting on the seabed is held by friction in a 0.5 m/s current" % items[i].display_name)
	engine.free()
