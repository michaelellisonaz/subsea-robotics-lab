## Renders the real application in a window and saves screenshots of several
## views, for visual verification. Needs a GPU (not headless):
##
##   godot --path . -s res://tests/capture_views.gd -- --out=C:/some/folder
##
## Without --out, images go to user://captures. Also prints the default
## vehicle's predicted characteristics.
extends SceneTree

var _out_dir: String = "user://captures"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir) if _out_dir.begins_with("user://") else _out_dir)

	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var engine: SimulationEngine = scene.get_node("SimulationEngine")
	var camera: OrbitCamera = scene.get_node("OrbitCamera")
	var views: ViewController = scene.get_node("ViewController")
	var dashboard: Dashboard = scene.get_node("Dashboard")
	var vehicle: RovVehicle = scene.vehicle
	var visual: RovVisual = scene.get_node("RovVisual")
	var env := engine.environment

	var c := vehicle.characteristics(env)
	for key in c:
		print("characteristic %s = %s" % [key, c[key]])

	await _wait(1.5)
	await _capture("01_chase_ready.png")

	engine.start()
	Input.action_press("pilot_forward")
	Input.action_press("pilot_full_power")
	Input.action_press("pilot_yaw_right")
	await _wait(2.5)
	camera.set_heading(vehicle.heading_degrees() + 120.0)
	camera.set_distance(3.2)
	await _wait(0.8)
	await _capture("02_driving_thrust_arrows.png")
	Input.action_release("pilot_yaw_right")
	await _wait(1.5)
	views.set_mode(ViewController.ViewMode.ONBOARD)
	await _wait(1.0)
	await _capture("03_onboard_hud.png")
	Input.action_release("pilot_forward")
	Input.action_release("pilot_full_power")

	engine.reset()
	views.set_mode(ViewController.ViewMode.ORBIT)
	camera.set_heading(215.0)
	camera.set_elevation(-12.0)
	camera.set_distance(2.4)
	await _wait(1.2)
	await _capture("04_vehicle_closeup.png")

	views.set_mode(ViewController.ViewMode.FREE)
	camera.reset_view()
	camera.set_distance(18.0)
	await _wait(1.2)
	await _capture("05_free_camera_site.png")

	env.water_depth = 300.0
	views.set_mode(ViewController.ViewMode.CHASE)
	views.frame_vehicle()
	await _wait(1.2)
	await _capture("06_deep_300m_lights.png")
	env.water_depth = 30.0

	var panel := dashboard.vehicle_config_panel
	panel.layout_option.select(2)
	panel.layout_option.item_selected.emit(2)
	panel.apply_button.pressed.emit()
	dashboard.left_tabs.current_tab = 1
	views.set_mode(ViewController.ViewMode.ORBIT)
	camera.set_heading(150.0)
	camera.set_elevation(-35.0)
	camera.set_distance(3.0)
	await _wait(1.2)
	await _capture("07_four_thruster_layout.png")

	# Stage 3: sensors.
	panel.defaults_button.pressed.emit()
	panel.apply_button.pressed.emit()
	dashboard.left_tabs.current_tab = 2
	dashboard.right_tabs.current_tab = 1
	views.set_mode(ViewController.ViewMode.ORBIT)
	camera.set_heading(70.0)
	camera.set_elevation(-18.0)
	camera.set_distance(7.0)
	engine.start()
	await _wait(2.5)
	await _capture("09_sensor_coverage_and_sonar.png")

	vehicle.toggle_depth_hold()
	vehicle.toggle_heading_hold()
	env.water_depth = 120.0
	var camera_sensor := vehicle.sensors.get_sensor("Camera")
	camera_sensor.set_param("gain", 4.0)
	views.set_mode(ViewController.ViewMode.ONBOARD)
	await _wait(1.5)
	await _capture("10_onboard_low_light_gain_holds.png")
	camera_sensor.set_param("gain", 1.0)
	env.water_depth = 30.0

	vehicle.sensors.get_sensor("Stereo camera").enabled = true
	views.set_mode(ViewController.ViewMode.CHASE)
	var scroll: ScrollContainer = dashboard.right_tabs.get_current_tab_control()
	await _wait(0.5)
	scroll.scroll_vertical = 100000
	await _wait(1.0)
	await _capture("11_stereo_and_multibeam.png")
	vehicle.sensors.get_sensor("Stereo camera").enabled = false
	engine.reset()

	# Stage 4: pipeline and manipulator.
	var pipeline: Pipeline = scene.pipeline
	var markers := dashboard.pipeline_panel.markers_toggle
	engine.pause()
	views.set_mode(ViewController.ViewMode.FREE)
	dashboard.left_tabs.current_tab = 0
	markers.button_pressed = true
	camera.set_focus(Vector3(10.0, pipeline.axis_y(), -4.5))
	camera.set_heading(330.0)
	camera.set_elevation(-25.0)
	camera.set_distance(4.5)
	await _wait(1.5)
	await _capture("12_pipeline_corrosion.png")
	camera.set_focus(Vector3(-10.5, pipeline.axis_y(), -6.0))
	camera.set_heading(150.0)
	camera.set_elevation(-30.0)
	camera.set_distance(3.2)
	await _wait(1.5)
	await _capture("13_pipeline_crack.png")
	markers.button_pressed = false
	camera.set_focus(Vector3(-18.0, pipeline.axis_y(), -6.0))
	camera.set_heading(300.0)
	camera.set_elevation(-18.0)
	camera.set_distance(4.5)
	await _wait(1.5)
	await _capture("14_pipeline_flange_supports.png")

	# Grasp the debris block the way an operator would: hover, holds on,
	# re-aim the tool at the item a few times, close the gripper, lift.
	var arm := vehicle.manipulator
	var pilot: PilotInput = scene.get_node("PilotInput")
	var debris: GraspableObject = engine.objects.find_by_name("Debris block")
	vehicle.position = debris.position - (arm.mount_position + Vector3(0.0, -0.45, -0.6))
	vehicle.capture_initial_state()
	engine.start()
	await _wait(1.0)
	pilot.set_arm_mode(true)
	dashboard.right_tabs.current_tab = 1
	views.set_mode(ViewController.ViewMode.ORBIT)
	camera.set_heading(240.0)
	camera.set_elevation(-10.0)
	camera.set_distance(2.6)
	visual.arm_visual.set_envelope_visible(true)
	for attempt in 4:
		arm.command_tool(vehicle.orientation.inverse() * (debris.position - vehicle.position), -70.0, 0.0, true)
		await _wait(4.0)
	await _capture("15_arm_reach_envelope.png")
	visual.arm_visual.set_envelope_visible(false)
	arm.set_gripper_closed(true)
	await _wait(2.5)
	print("grasped: %s" % (arm.grasped == debris))
	arm.command_tool(arm.tool_target_position + Vector3(0.0, 0.3, 0.0), -40.0, 0.0, true)
	await _wait(6.0)
	print("pitch while holding: %.2f°" % vehicle.pitch_degrees())
	await _capture("16_arm_grasp_lift.png")
	views.set_mode(ViewController.ViewMode.ONBOARD)
	await _wait(1.0)
	await _capture("17_onboard_arm_control.png")
	pilot.set_arm_mode(false)
	engine.reset()

	# Stage 5: tools and repairs. For repeatable framing the vehicle is held
	# still (is_dynamic = false) and moved between work sites directly; the
	# arm, tools, contact, cleaning, probe and clamp all run in the simulation.
	var brush: WorkTool = arm.tools[0]
	var probe: WorkTool = arm.tools[1]
	var aim := func(world_point: Vector3, pitch: float) -> void:
		arm.command_tool(vehicle.orientation.inverse() * (world_point - vehicle.position), pitch, 0.0, true)
	var top := pipeline.axis_y() + pipeline.radius()
	var spot := Vector3(9.6, top, pipeline.axis_z())
	vehicle.is_dynamic = false
	vehicle.position = spot - (arm.mount_position + Vector3(0.0, -0.3, -0.6))
	pilot.set_arm_mode(true)
	engine.start()
	engine.set_time_scale(10.0)
	arm.request_tool(brush)
	await _wait(2.5)
	engine.set_time_scale(4.0)
	arm.tool_action(0.0)
	for k in 4:
		var p := spot + Vector3(0.09 * k, 0.0, 0.0)
		aim.call(p + Vector3.UP * 0.12, -80.0)
		await _wait(1.0)
		aim.call(p + Vector3.UP * (brush.tip_radius - 0.03), -80.0)
		await _wait(1.5)
	engine.set_time_scale(1.0)
	views.set_mode(ViewController.ViewMode.ORBIT)
	camera.set_heading(235.0)
	camera.set_elevation(-12.0)
	camera.set_distance(2.4)
	await _wait(1.0)
	await _capture("18_brush_cleaning.png")
	arm.tool_action(0.0)
	aim.call(spot + Vector3(0.15, 0.35, 0.0), -60.0)
	await _wait(3.0)
	print("cleaned area: %.3f m², brush force while pressing ~75 N" % pipeline.cleaned_area())
	views.set_mode(ViewController.ViewMode.FREE)
	camera.set_focus(spot + Vector3(0.15, 0.0, 0.0))
	camera.set_heading(200.0)
	camera.set_elevation(-35.0)
	camera.set_distance(1.6)
	await _wait(1.5)
	await _capture("19_cleaned_patch.png")

	# CP probe: flange at E 6, then the cleaned steel.
	engine.set_time_scale(10.0)
	arm.request_tool(probe)
	await _wait(2.5)
	engine.set_time_scale(1.0)
	var flange := Vector3(6.0, pipeline.axis_y() + pipeline.flange_radius(), pipeline.axis_z())
	for target in [flange, spot + Vector3(0.1, 0.0, 0.0)]:
		vehicle.position = target - (arm.mount_position + Vector3(0.0, -0.3, -0.6))
		aim.call(target + Vector3.UP * 0.1, -80.0)
		await _wait(6.0)
		aim.call(target + Vector3.UP * (probe.tip_radius - 0.012), -80.0)
		await _wait(3.0)
		arm.tool_action(engine.clock.sim_time)
	print("CP log: %s" % [probe.log])
	views.set_mode(ViewController.ViewMode.ORBIT)
	camera.set_heading(250.0)
	camera.set_elevation(-15.0)
	camera.set_distance(2.2)
	dashboard.right_tabs.current_tab = 1
	var arm_scroll: ScrollContainer = dashboard.right_tabs.get_current_tab_control()
	await _wait(0.3)
	arm_scroll.scroll_vertical = 330
	await _wait(1.0)
	await _capture("20_cp_probe.png")

	# Repair clamp over the crack, with the gripper.
	engine.set_time_scale(10.0)
	arm.request_tool(null)
	await _wait(2.5)
	engine.set_time_scale(4.0)
	var clamp: RepairClamp = engine.objects.find_by_name("Repair clamp")
	var handle := clamp.grasp_point()
	vehicle.position = handle - (arm.mount_position + Vector3(0.0, -0.7, -0.45))
	aim.call(handle + Vector3.UP * 0.1, -80.0)
	await _wait(2.0)
	aim.call(handle, -80.0)
	await _wait(1.0)
	arm.set_gripper_closed(true)
	await _wait(0.6)
	aim.call(handle + Vector3.UP * 0.56, -80.0)
	await _wait(2.5)
	vehicle.position += Vector3(0.0, 0.3, pipeline.axis_z() - clamp.position.z)
	await _wait(0.2)
	var goal := Vector3(clamp.position.x, pipeline.axis_y() - 0.02, pipeline.axis_z())
	for attempt in 4:
		aim.call(vehicle.local_to_world_point(arm.tool_transform().origin) + (goal - clamp.position), -80.0)
		await _wait(1.3)
	engine.set_time_scale(1.0)
	views.set_mode(ViewController.ViewMode.FREE)
	camera.set_focus(clamp.position)
	camera.set_heading(240.0)
	camera.set_elevation(-12.0)
	camera.set_distance(2.4)
	await _wait(1.0)
	await _capture("21_clamp_seated.png")
	arm.set_gripper_closed(false)
	await _wait(0.5)
	print("clamp: %s / crack %s" % [arm.status_message, pipeline.crack_status()])
	aim.call(vehicle.local_to_world_point(arm.tool_transform().origin) + Vector3(0.0, 0.35, 0.3), -60.0)
	await _wait(3.0)
	camera.set_heading(160.0)
	camera.set_elevation(-20.0)
	await _wait(1.0)
	await _capture("22_clamp_installed.png")

	# Retrofit anode set down near the depleted bracelet (placed directly).
	var anode: RetrofitAnode = engine.objects.find_by_name("Retrofit anode")
	anode.position = engine.world.place_on_seabed(1.0, Pipeline.NORTH - 1.4, anode.bottom_clearance)
	await _wait(2.0)
	print("anode connected: %s, least protected %s" % [anode.connected, pipeline.least_protected()])
	pilot.set_arm_mode(false)
	views.set_mode(ViewController.ViewMode.FREE)
	camera.set_focus(Vector3(0.6, pipeline.axis_y() - 0.2, pipeline.axis_z() + 0.8))
	camera.set_heading(45.0)
	camera.set_elevation(-25.0)
	camera.set_distance(3.2)
	dashboard.left_tabs.current_tab = 0
	var env_scroll: ScrollContainer = dashboard.left_tabs.get_current_tab_control()
	await _wait(0.3)
	env_scroll.scroll_vertical = 100000
	await _wait(1.5)
	await _capture("23_anode_and_repair_status.png")
	vehicle.is_dynamic = true
	engine.reset()

	# Stage 6: autonomous survey with the defect detector, then autonomous
	# cleaning and CP readings. Nothing is placed or moved directly here.
	var autonomy_panel := dashboard.autonomy_panel
	var auto_scroll: ScrollContainer
	views.set_mode(ViewController.ViewMode.CHASE)
	engine.start()
	await _wait(2.5)
	autonomy_panel.mission_option.select(Mission.PRESETS.find("Pipeline survey (vision)"))
	print("survey started: %s" % autonomy_panel.start_selected())
	dashboard.right_tabs.current_tab = 5
	auto_scroll = dashboard.right_tabs.get_current_tab_control()
	engine.set_time_scale(6.0)
	while vehicle.autonomy.mission_running() and not (vehicle.autonomy.vision_active and vehicle.position.x > -11.3):
		await _wait(0.25)
	engine.set_time_scale(1.0)
	views.set_mode(ViewController.ViewMode.ORBIT)
	camera.set_heading(200.0)
	camera.set_elevation(-25.0)
	camera.set_distance(3.5)
	await _wait(0.3)
	auto_scroll.scroll_vertical = 420
	await _wait(1.5)
	await _capture("24_autonomous_survey.png")
	engine.set_time_scale(6.0)
	while vehicle.autonomy.mission_running():
		await _wait(0.25)
	engine.set_time_scale(1.0)
	print("survey: %s / %s" % [vehicle.autonomy.mission.status, vehicle.autonomy.inspection.evaluate(pipeline)["text"]])
	auto_scroll.scroll_vertical = 100000
	camera.set_heading(160.0)
	await _wait(1.5)
	await _capture("25_survey_findings.png")
	autonomy_panel.mission_option.select(Mission.PRESETS.find("Clean and measure corrosion"))
	print("cleaning started: %s" % autonomy_panel.start_selected())
	auto_scroll.scroll_vertical = 0
	engine.set_time_scale(6.0)
	while vehicle.autonomy.mission_running() and not (vehicle.autonomy.mission.index == 2 and vehicle.manipulator.tool != null and vehicle.manipulator.tool.contact_force > 60.0):
		await _wait(0.1)
	engine.set_time_scale(1.0)
	camera.set_heading(235.0)
	camera.set_elevation(-15.0)
	camera.set_distance(2.6)
	await _wait(1.0)
	await _capture("26_autonomous_cleaning.png")
	engine.set_time_scale(8.0)
	while vehicle.autonomy.mission_running():
		await _wait(0.25)
	engine.set_time_scale(1.0)
	print("cleaning mission: %s, cleaned %.3f m², CP log %d" % [vehicle.autonomy.mission.state, pipeline.cleaned_area(), (vehicle.manipulator.tools[1] as CpProbe).log.size()])
	auto_scroll.scroll_vertical = 200
	await _wait(1.0)
	await _capture("27_mission_report.png")
	engine.reset()

	dashboard.set_panels_visible(false)
	views.set_mode(ViewController.ViewMode.CHASE)
	views.frame_vehicle()
	await _wait(1.0)
	await _capture("08_panels_hidden.png")

	print("FPS at end of capture: %d" % Engine.get_frames_per_second())
	quit(0)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var err := image.save_png(_out_dir.path_join(file_name))
	print("captured %s -> %s" % [file_name, error_string(err)])
