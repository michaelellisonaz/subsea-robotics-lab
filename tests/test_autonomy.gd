## Stage 6: navigation filter, autopilot, missions (survey, autonomous
## cleaning, CP readings), operator override, and the image defect detector.
extends "res://tests/test_suite.gd"


func _engine(current: float = 0.25) -> SimulationEngine:
	var engine := SimulationEngine.new()
	engine.auto_advance = false
	engine.clock.max_steps_per_frame = 1000000
	engine.environment.water_depth = 30.0
	engine.environment.current_speed = current
	return engine


func _run(engine: SimulationEngine, seconds: float) -> void:
	engine.start()
	engine.advance(seconds)
	engine.pause()


func _vehicle(engine: SimulationEngine, east: float, north: float, height: float = 1.5) -> RovVehicle:
	var vehicle := RovVehicle.new(VehicleConfig.new(), engine.world.place_on_seabed(east, north, height))
	engine.objects.register(vehicle)
	return vehicle


## Runs until the mission ends or `limit` seconds pass; returns the time taken.
func _run_mission(engine: SimulationEngine, vehicle: RovVehicle, limit: float) -> float:
	var time := 0.0
	while vehicle.autonomy.mission_running() and time < limit:
		_run(engine, 1.0)
		time += 1.0
	return time


func test_navigation_filter_tracks_truth() -> void:
	var engine := _engine(0.25)
	var vehicle := _vehicle(engine, 4.0, -8.0)
	_run(engine, 3.0)
	var nav := vehicle.autonomy.nav
	check(nav.initialized, "filter initialised from the first USBL fix")
	check(vehicle.toggle_depth_hold() and vehicle.toggle_heading_hold(), "holds on")
	var worst := 0.0
	for k in 120:
		_run(engine, 1.0)
		worst = maxf(worst, vehicle.autonomy.nav_error)
	var drift := vehicle.position.distance_to(engine.world.place_on_seabed(4.0, -8.0, 1.5))
	check(drift > 5.0, "the vehicle drifted %.1f m in the current" % drift)
	check(worst < 0.25, "estimate within 0.25 m of truth throughout (worst %.3f m)" % worst)
	check(nav.sigma() < 0.2 and nav.fixes_used > 100, "filter confident (σ %.3f m) with %d fixes used" % [nav.sigma(), nav.fixes_used])
	var forward_est := nav.world_basis() * Vector3.FORWARD
	var forward_true := vehicle.orientation * Vector3.FORWARD
	check(rad_to_deg(forward_est.angle_to(forward_true)) < 3.0, "estimated orientation matches the vehicle (%.1f°)" % rad_to_deg(forward_est.angle_to(forward_true)))
	# USBL outage: DVL dead reckoning carries the estimate.
	vehicle.sensors.get_sensor("USBL").enabled = false
	_run(engine, 60.0)
	var outage_error := vehicle.autonomy.nav_error
	check(outage_error < 0.5, "60 s without USBL: error %.3f m (DVL dead reckoning)" % outage_error)
	vehicle.sensors.get_sensor("USBL").enabled = true
	_run(engine, 20.0)
	check(vehicle.autonomy.nav_error < 0.2, "fixes pull the estimate back (%.3f m)" % vehicle.autonomy.nav_error)
	engine.free()


func test_filter_rejects_outlier_fixes() -> void:
	var nav := NavigationFilter.new()
	nav.initialized = true
	nav.east = 0.0
	nav.north = 0.0
	nav.pee = 0.01
	nav.pnn = 0.01
	var engine := _engine(0.0)
	var vehicle := _vehicle(engine, 0.0, 0.0)
	_run(engine, 2.0)
	var usbl := vehicle.sensors.get_sensor("USBL")
	var reading := SensorReading.new()
	reading.time = 100.0
	reading.values = {"east": 25.0, "north": 0.0, "depth": 28.0, "slant_range": 28.0}
	usbl.latest = reading
	nav.update(vehicle, 100.1, 0.01)
	check(nav.fixes_rejected == 1 and absf(nav.east) < 0.1, "a fix 25 m off is rejected by the gate")
	engine.free()


func test_autopilot_goto() -> void:
	var engine := _engine(0.25)
	var site := Site.populate(engine)
	var vehicle := _vehicle(engine, 4.0, -8.0)
	vehicle.autonomy.pipeline = site["pipeline"]
	_run(engine, 3.0)
	var mission := Mission.new("test", [{"type": "goto", "east": -6.0, "north": -2.0, "heading": 90.0, "altitude": 1.0, "timeout": 200.0}] as Array[Dictionary])
	check(vehicle.autonomy.start_mission(mission, engine.clock.sim_time), "mission started")
	var time := _run_mission(engine, vehicle, 200.0)
	check(mission.state == "done", "goto completed in %.0f s (%s)" % [time, mission.status])
	var error := Vector2(vehicle.position.x + 6.0, -vehicle.position.z + 2.0).length()
	check(error < 0.35, "true position within 0.35 m of the goal (%.2f m)" % error)
	check(absf(wrapf(vehicle.heading_degrees() - 90.0, -180.0, 180.0)) < 5.0, "heading 090 (%.1f°)" % vehicle.heading_degrees())
	check(absf(vehicle.altitude(engine.world) - 1.0) < 0.25, "altitude mode holds ~1 m (%.2f m)" % vehicle.altitude(engine.world))
	_run(engine, 5.0)
	check(not vehicle.autonomy.autopilot.active, "autopilot released after the mission")
	engine.free()


func test_survey_tracks_the_pipeline() -> void:
	var engine := _engine(0.25)
	var site := Site.populate(engine)
	var pipeline: Pipeline = site["pipeline"]
	var vehicle := _vehicle(engine, -4.0, 2.0)
	vehicle.autonomy.pipeline = pipeline
	_run(engine, 3.0)
	var north := Pipeline.NORTH - 2.2
	var tasks: Array[Dictionary] = [{"type": "survey", "east_from": -3.0, "east_to": 3.0, "north": north, "altitude": 1.2, "speed": 0.2, "timeout": 200.0}]
	var mission := Mission.new("survey", tasks)
	vehicle.autonomy.start_mission(mission, engine.clock.sim_time)
	var cross_track: Array = [0.0]
	var vision_seen: Array = [false]
	engine.step_completed.connect(func(_t: float, _dt: float) -> void:
		if vehicle.autonomy.vision_active:
			vision_seen[0] = true
			cross_track[0] = maxf(cross_track[0], absf(-vehicle.position.z - north)))
	var time := _run_mission(engine, vehicle, 200.0)
	check(mission.state == "done" and vehicle.position.x > 2.5, "survey reached the end in %.0f s (E %.1f)" % [time, vehicle.position.x])
	check(vision_seen[0] and not vehicle.autonomy.vision_active, "vision requested during the run only")
	check(cross_track[0] < 0.3, "cross-track error under 0.3 m (max %.2f m)" % cross_track[0])
	engine.free()


func test_autonomous_cleaning_and_cp() -> void:
	var engine := _engine(0.25)
	var site := Site.populate(engine)
	var pipeline: Pipeline = site["pipeline"]
	var vehicle := _vehicle(engine, 9.0, 3.0)
	vehicle.autonomy.pipeline = pipeline
	_run(engine, 3.0)
	var tasks: Array[Dictionary] = [
		{"type": "tool", "tool": "brush", "timeout": 60.0},
		{"type": "clean", "spots": [9.0, 9.4], "timeout": 300.0},
		{"type": "tool", "tool": "cp_probe", "timeout": 60.0},
		{"type": "cp", "points": [{"east": 9.0, "kind": "pipe"}, {"east": 6.0, "kind": "flange"}, {"east": 7.5, "kind": "pipe"}], "timeout": 300.0},
	]
	var mission := Mission.new("work", tasks)
	vehicle.autonomy.start_mission(mission, engine.clock.sim_time)
	var time := _run_mission(engine, vehicle, 700.0)
	check(mission.state == "done", "work mission finished in %.0f s (%s)" % [time, mission.status])
	for east in [9.0, 9.4]:
		# Nearest bare-steel point to the intended spot (the brush lands where the
		# navigation estimate puts it).
		var nearest := INF
		for dx in range(-15, 16):
			for clock in range(-90, 91, 10):
				var c := deg_to_rad(float(clock))
				var p := Vector3(east + dx * 0.01, pipeline.axis_y() + pipeline.radius() * cos(c), pipeline.axis_z() - pipeline.radius() * sin(c))
				if pipeline.surface_kind(p, pipeline.primitives[0]) == "bare steel":
					nearest = minf(nearest, Vector2(dx * 0.01, pipeline.radius() * c).length())
		check(nearest < 0.1, "spot E %.1f cleaned to bare steel by force-controlled brushing (patch %.0f mm from the target)" % [east, nearest * 1000.0])
	var probe := vehicle.manipulator.tools[1] as CpProbe
	check(probe.log.size() == 2, "two CP readings logged (%d)" % probe.log.size())
	for entry in probe.log:
		check(absf(entry["potential"] - entry["truth"]) < 15.0, "reading at E %.2f on %s: %.0f mV (model %.0f)" % [entry["east"], entry["surface"], entry["potential"], entry["truth"]])
	var no_reading := false
	for line in mission.log_lines:
		if line.contains("No CP reading at E 7.50"):
			no_reading = true
	check(no_reading, "uncleaned pipe at E 7.5 (marine growth) gives no reading")
	check(vehicle.autonomy.nav_error_max < 0.3, "navigation error during the mission under 0.3 m (max %.2f)" % vehicle.autonomy.nav_error_max)
	engine.free()


func test_manual_input_aborts_mission() -> void:
	var engine := _engine(0.0)
	var site := Site.populate(engine)
	var vehicle := _vehicle(engine, 4.0, -8.0)
	vehicle.autonomy.pipeline = site["pipeline"]
	_run(engine, 3.0)
	vehicle.autonomy.start_mission(Mission.preset("Return to start", site["pipeline"], Vector3(-10.0, 0.0, 10.0)), engine.clock.sim_time)
	_run(engine, 2.0)
	check(vehicle.autonomy.mission_running(), "mission running")
	vehicle.set_pilot_command(RovVehicle.Axis.SURGE, 0.5)
	_run(engine, 0.1)
	check(vehicle.autonomy.mission.state == "aborted" and not vehicle.autonomy.autopilot.active, "pilot input aborts the mission")
	engine.reset()
	check(vehicle.autonomy.mission == null and not vehicle.autonomy.nav.initialized, "reset clears the autonomy state")
	engine.free()


func test_presets_build() -> void:
	var pipeline := Pipeline.new(-30.0)
	for name in Mission.PRESETS:
		var mission := Mission.preset(name, pipeline, Vector3.ZERO)
		check(mission.tasks.size() > 0, "preset '%s' has %d tasks" % [name, mission.tasks.size()])


func _image(width: int, height: int, color: Color) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	image.fill(color)
	return image


func test_detector_on_synthetic_images() -> void:
	var water := Color(0.10, 0.22, 0.24)
	var image := _image(160, 120, water)
	image.fill_rect(Rect2i(40, 50, 20, 12), Color(0.55, 0.25, 0.08))  # rust patch
	var result := DefectDetector.analyze(image)
	check(result["corrosion"].size() == 1 and (result["corrosion"][0]["center"] as Vector2).distance_to(Vector2(49.5, 55.5)) < 0.6, "rust patch found at its centre")
	check(result["crack"].is_empty(), "no crack in it")
	var cracked := _image(160, 120, Color(0.20, 0.25, 0.22))
	for x in range(60, 90):
		cracked.set_pixel(x, 70 + (x - 60) / 10, Color(0.02, 0.02, 0.02))
	cracked.fill_rect(Rect2i(10, 10, 25, 25), Color(0.03, 0.03, 0.03))  # a shadow
	result = DefectDetector.analyze(cracked)
	check(result["crack"].size() == 1 and (result["crack"][0]["box"] as Rect2i).position.x == 60, "thin dark line found as a crack")
	check(result["corrosion"].is_empty(), "no false rust")
	var big := _image(640, 480, water)
	big.fill_rect(Rect2i(300, 200, 40, 40), Color(0.6, 0.3, 0.1))
	result = DefectDetector.analyze(big)
	check(result["width"] == 160 and result["corrosion"].size() == 1, "large images are downsampled first")


func test_projection_onto_the_pipe() -> void:
	var pipeline := Pipeline.new(-30.0)
	var top := Vector3(9.0, pipeline.axis_y() + pipeline.radius(), pipeline.axis_z())
	# Camera 1 m above the pipe top, looking straight down.
	var pose := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), top + Vector3.UP)
	var hit := DefectDetector.project_to_pipe(Vector2(79.5, 59.5), 160, 120, 60.0, pose, pipeline)
	check(not hit.is_empty() and absf(hit["east"] - 9.0) < 0.01 and absf(hit["clock"]) < 1.0, "image centre lands on the pipe top at E 9")
	var side := DefectDetector.project_to_pipe(Vector2(159.0, 59.5), 160, 120, 60.0, pose, pipeline)
	check(not side.is_empty() and side["east"] > 9.4, "right edge of the image is further east (E %.2f)" % side.get("east", 0.0))
	var miss := DefectDetector.project_to_pipe(Vector2(79.5, 59.5), 160, 120, 60.0, Transform3D(Basis.IDENTITY, top + Vector3(0, 1, 5)), pipeline)
	check(miss.is_empty(), "a ray that misses the pipe gives no detection")


func test_inspection_log_merging_and_score() -> void:
	var pipeline := Pipeline.new(-30.0)
	var log := InspectionLog.new()
	for k in 10:
		log.add("corrosion", 8.6 + k * 0.3, 10.0, k)
	log.add("corrosion", 20.0, 0.0, 1.0)
	for k in 4:
		log.add("crack", -10.45 + k * 0.01, 25.0, k)
	for k in 3:
		log.add("crack", 3.0, 0.0, k)
	check(log.confirmed("corrosion").size() == 1, "corrosion detections merged into one feature; single hit ignored")
	var score := log.evaluate(pipeline)
	check(score["corrosion_found"] and score["corrosion_coverage"] > 0.85, "corrosion coverage %.0f %%" % (score["corrosion_coverage"] * 100.0))
	check(score["crack_found"] and score["crack_error"] < 0.1, "crack located within 0.1 m")
	check(score["false_positives"] == 1, "the confirmed crack at E 3 is a false positive")


func test_detector_rejects_lines_along_the_pipe() -> void:
	var image := _image(160, 120, Color(0.25, 0.28, 0.24))
	for y in range(20, 100):
		image.set_pixel(70, y, Color(0.03, 0.03, 0.03))
	check(DefectDetector.analyze(image)["crack"].is_empty(), "a line along the image (pipe edge direction) is not a crack")


func test_known_fittings_from_the_as_built() -> void:
	var pipeline := Pipeline.new(-30.0)
	check(pipeline.known_fitting_near(6.1, 0.35) and pipeline.known_fitting_near(0.3, 0.35), "flange at E 6 and anode band at E 0 are known fittings")
	check(not pipeline.known_fitting_near(-10.5, 0.35), "the crack position is not near a fitting")
	var engine := _engine(0.0)
	var vehicle := _vehicle(engine, 0.0, 0.0)
	vehicle.autonomy.pipeline = pipeline
	var top := Vector3(6.0, pipeline.axis_y() + pipeline.radius(), pipeline.axis_z())
	var pose := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), top + Vector3.UP)
	vehicle.autonomy.add_vision_frame({"width": 160, "height": 120, "corrosion": [], "crack": [{"center": Vector2(79.5, 59.5)}]}, pose, 60.0, 0.0)
	check(vehicle.autonomy.inspection.features.is_empty() and vehicle.autonomy.inspection.known_fitting_hits == 1, "a crack-like line at the flange is logged as a known fitting")
	engine.free()


func test_clean_and_measure_preset() -> void:
	var engine := _engine(0.25)
	var site := Site.populate(engine)
	var pipeline: Pipeline = site["pipeline"]
	var vehicle := _vehicle(engine, 4.0, -8.0)
	vehicle.autonomy.pipeline = pipeline
	_run(engine, 3.0)
	var mission := Mission.preset("Clean and measure corrosion", pipeline, vehicle.position)
	vehicle.autonomy.start_mission(mission, engine.clock.sim_time)
	var time := _run_mission(engine, vehicle, 1500.0)
	check(mission.state == "done", "preset mission completed in %.0f s (%s)" % [time, mission.status])
	check(pipeline.cleaned_area() > 0.02, "it cleaned %.3f m² of the corroded section" % pipeline.cleaned_area())
	var probe := vehicle.manipulator.tools[1] as CpProbe
	var readings := probe.log.size()
	check(readings >= 2, "it logged %d CP readings" % readings)
	check(vehicle.manipulator.tool == null, "and returned the probe to the skid")
	engine.free()
