## End-to-end test of the main scene: loads the real application, drives it
## through the dashboard widgets and through injected mouse / keyboard events,
## and checks the effect on the simulation, vehicle, renderer and cameras.
extends "res://tests/test_suite.gd"

const VIEW_POINT := Vector2(800, 450)  # centre of the 3D view, between the panels
const TEST_CONFIG_PATH := "user://test_dashboard_environment.json"
const TEST_VEHICLE_PATH := "user://test_dashboard_vehicle.json"

var scene: Node
var engine: SimulationEngine
var dashboard: Dashboard
var camera: OrbitCamera
var renderer: EnvironmentRenderer
var views: ViewController
var vehicle: RovVehicle
var visual: RovVisual


func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(scene)
	await _frames(5)
	engine = scene.get_node("SimulationEngine")
	dashboard = scene.get_node("Dashboard")
	camera = scene.get_node("OrbitCamera")
	renderer = scene.get_node("UnderwaterEnvironment")
	views = scene.get_node("ViewController")
	visual = scene.get_node("RovVisual")
	vehicle = scene.vehicle
	_test_structure()
	await _test_simulation_controls()
	await _test_views_and_pilot()
	await _test_vehicle_config_panel()
	await _test_sensors_ui()
	await _test_arm_and_pipeline_ui()
	await _test_autonomy_ui()
	views.set_mode(ViewController.ViewMode.FREE)
	await _test_environment_controls()
	await _test_camera_mouse()
	await _test_camera_keyboard_and_panel()
	await _test_camera_limits()
	await _test_shortcuts_and_display()
	scene.queue_free()
	await _frames(2)
	done()


func _test_structure() -> void:
	check(engine != null and dashboard != null and camera != null and renderer != null, "main scene modules present")
	check(engine.objects.count() == 5 and engine.objects.get_all().has(vehicle), "the ROV, two loose items, the repair clamp and the retrofit anode are registered")
	check(vehicle.thrusters.size() == 8, "default vehicle has eight thrusters")
	check(views.mode == ViewController.ViewMode.CHASE and views.is_piloting(), "starts in the chase view, piloting")
	check(visual.global_position.distance_to(vehicle.position) < 1e-4, "vehicle visual placed at the simulated pose")
	check_near(vehicle.altitude(engine.world), 1.5 - (0.5 * 0.55 - 0.08), 1e-3, "vehicle starts hovering above the seabed")
	check(renderer.seabed.get_child_count() > 0, "seabed mesh built")
	check_near(renderer.seabed.position.y, -30.0, 1e-6, "seabed at default depth")
	check_near(renderer.get_fog_density(), 3.912 / engine.environment.visibility, 1e-6, "fog density from default visibility")
	check(camera.camera.current, "orbit camera is the active camera")
	check(dashboard.get_help_text().begins_with("PILOT"), "help bar shows pilot controls")


func _test_simulation_controls() -> void:
	var bar := dashboard.simulation_bar
	check(engine.state == SimulationEngine.State.READY and engine.get_sim_time() == 0.0, "starts READY at t = 0")
	await _seconds(0.2)
	check(engine.get_sim_time() == 0.0, "time does not advance before Start")

	bar.run_button.pressed.emit()
	check(engine.is_running() and bar.run_button.text == "Pause", "Start button runs the clock")
	check(renderer.marine_snow.speed_scale == 1.0, "particles move with the clock while running")
	var real_start := Time.get_ticks_usec()
	await _seconds(0.6)
	var real_elapsed := (Time.get_ticks_usec() - real_start) / 1.0e6
	var sim_elapsed := engine.get_sim_time()
	check(absf(sim_elapsed - real_elapsed) < 0.1, "1x speed tracks real time (sim %.3f s vs real %.3f s)" % [sim_elapsed, real_elapsed])
	check(renderer.surface.sim_time > 0.0, "surface shimmer follows sim time")
	check(bar.get_time_text() != "00:00:00.000", "time display updates")

	bar.run_button.pressed.emit()
	check(engine.state == SimulationEngine.State.PAUSED and bar.run_button.text == "Resume", "Pause button pauses")
	check(renderer.marine_snow.speed_scale == 0.0, "particles freeze while paused")
	var paused_time := engine.get_sim_time()
	await _seconds(0.3)
	check(engine.get_sim_time() == paused_time, "time frozen while paused")

	bar.step_button.pressed.emit()
	check_near(engine.get_sim_time(), paused_time + 0.01, 1e-9, "Step advances exactly one dt")

	bar.speed_option.select(5)
	bar.speed_option.item_selected.emit(5)
	check_near(engine.clock.time_scale, 5.0, 1e-9, "speed selector sets 5x")
	bar.run_button.pressed.emit()
	check(renderer.marine_snow.speed_scale == 5.0, "particle motion follows time scale")
	var t0 := engine.get_sim_time()
	real_start = Time.get_ticks_usec()
	await _seconds(0.5)
	real_elapsed = (Time.get_ticks_usec() - real_start) / 1.0e6
	var ratio := (engine.get_sim_time() - t0) / real_elapsed
	check(ratio > 4.0 and ratio < 6.0, "5x speed advances ~5 s per real s (got %.2f)" % ratio)

	bar.reset_button.pressed.emit()
	check(engine.state == SimulationEngine.State.READY and engine.get_sim_time() == 0.0, "Reset returns to READY at t = 0")
	check(bar.run_button.text == "Start", "button label back to Start")
	bar.speed_option.select(3)
	bar.speed_option.item_selected.emit(3)
	check_near(engine.clock.time_scale, 1.0, 1e-9, "speed back to 1x")


func _test_environment_controls() -> void:
	var panel := dashboard.environment_panel
	var env := engine.environment
	panel.config_path = TEST_CONFIG_PATH

	panel.get_slider("visibility").value = 10.0
	check_near(env.visibility, 10.0, 1e-9, "visibility slider updates the config")
	check_near(panel.get_spin("visibility").value, 10.0, 1e-9, "spin box follows slider")
	check_near(renderer.get_fog_density(), 0.3912, 1e-6, "fog density follows visibility")
	check(dashboard.info_panel.get_value_text("visibility") == "10.0 m", "info panel shows new visibility")

	var light_shallow := renderer.get_light_energy()
	var focus_before := camera.focus.y
	var vehicle_before := vehicle.position.y
	panel.get_spin("water_depth").value = 80.0
	await _frames(2)
	check_near(env.water_depth, 80.0, 1e-9, "depth field updates the config")
	check_near(renderer.seabed.position.y, -80.0, 1e-6, "seabed moves with water depth")
	check(renderer.get_light_energy() < light_shallow, "deeper seabed receives less light")
	check_near(camera.focus.y, focus_before - 50.0, 0.05, "free camera keeps its height above the seabed")
	check_near(vehicle.position.y, vehicle_before - 50.0, 1e-3, "vehicle moves with the seabed")
	check(dashboard.info_panel.get_value_text("pressure_abs") == "%.2f bar" % (env.absolute_pressure_at_depth(80.0) / 1e5), "pressure readout updated")

	panel.get_spin("dynamic_viscosity").value = 1.5
	check_near(env.dynamic_viscosity, 0.0015, 1e-12, "viscosity entered in mPa·s, stored in Pa·s")
	panel.get_spin("water_density").value = 5000.0
	check_near(env.water_density, 1060.0, 1e-9, "out-of-range density clamped")
	panel.get_spin("gravity").value = 3.71
	check_near(env.gravity, 3.71, 1e-9, "gravity editable")
	panel.get_spin("water_temperature").value = 4.0
	check_near(env.water_temperature, 4.0, 1e-9, "temperature editable")
	panel.get_slider("current_speed").value = 1.0
	panel.get_spin("current_heading").value = 180.0
	check_vec_near(env.current_velocity(), Vector3(0, 0, 1.0), 1e-6, "current set to 1 m/s toward south (+Z)")
	check(dashboard.info_panel.get_value_text("current") == "1.00 m/s toward 180° (S)", "current readout")

	panel.save_button.pressed.emit()
	check(FileAccess.file_exists(TEST_CONFIG_PATH), "Save writes the config file")
	check(not panel.load_button.disabled, "Load enabled after saving")
	panel.get_spin("water_depth").value = 40.0
	panel.load_button.pressed.emit()
	check_near(env.water_depth, 80.0, 1e-9, "Load restores saved depth")
	check_near(panel.get_spin("water_depth").value, 80.0, 1e-9, "Load updates the widgets")

	panel.defaults_button.pressed.emit()
	await _frames(2)
	for key in EnvironmentConfig.PARAMETER_ORDER:
		check_near(env.get_value(key), EnvironmentConfig.get_spec(key)["default"], 1e-9, "Defaults restores " + key)
	check_near(renderer.seabed.position.y, -30.0, 1e-6, "seabed back at default depth")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG_PATH))


func _test_camera_mouse() -> void:
	camera.reset_view(true)
	await _frames(2)
	var heading_0 := camera.heading
	var elevation_0 := camera.elevation
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	_mouse_motion(Vector2(40, 0), MOUSE_BUTTON_MASK_LEFT)
	_mouse_motion(Vector2(0, 20), MOUSE_BUTTON_MASK_LEFT)
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	check_near(camera.heading, heading_0 + 40 * camera.orbit_sensitivity, 1e-6, "left-drag right orbits heading")
	check_near(camera.elevation, elevation_0 - 20 * camera.orbit_sensitivity, 1e-6, "left-drag down raises the view")
	_mouse_motion(Vector2(50, 0), 0)
	await _frames(1)
	check_near(camera.heading, heading_0 + 40 * camera.orbit_sensitivity, 1e-6, "no orbit after release")

	var distance_0 := camera.distance
	_mouse_button(MOUSE_BUTTON_WHEEL_UP, true)
	await _frames(1)
	check_near(camera.distance, distance_0 / OrbitCamera.ZOOM_STEP, 1e-6, "wheel up zooms in")
	_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	await _frames(1)
	check_near(camera.distance, distance_0 * OrbitCamera.ZOOM_STEP, 1e-6, "wheel down zooms out")

	var focus_0 := camera.focus
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	_mouse_motion(Vector2(120, 0), MOUSE_BUTTON_MASK_RIGHT)
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	await _frames(1)
	check(camera.focus.distance_to(focus_0) > 0.5, "right-drag pans the focus")
	check_near(camera.heading, heading_0 + 40 * camera.orbit_sensitivity, 1e-6, "panning does not orbit")
	var focus_1 := camera.focus
	_mouse_button(MOUSE_BUTTON_MIDDLE, true)
	_mouse_motion(Vector2(0, -80), MOUSE_BUTTON_MASK_MIDDLE)
	_mouse_button(MOUSE_BUTTON_MIDDLE, false)
	await _frames(1)
	check(camera.focus.distance_to(focus_1) > 0.3, "middle-drag pans the focus")

	await _seconds(0.6)
	var expected := camera.focus - Vector3(
		sin(deg_to_rad(camera.heading)) * cos(deg_to_rad(camera.elevation)),
		sin(deg_to_rad(camera.elevation)),
		-cos(deg_to_rad(camera.heading)) * cos(deg_to_rad(camera.elevation))) * camera.distance
	check_vec_near(camera.get_camera_position(), expected, 0.05, "visible camera eases onto the target view")


func _test_camera_keyboard_and_panel() -> void:
	camera.reset_view(true)
	var focus_0 := camera.focus
	Input.action_press("camera_forward")
	await _seconds(0.3)
	Input.action_release("camera_forward")
	var moved := camera.focus - focus_0
	var forward := WorldFrame.direction_from_heading(camera.get_heading())
	check(moved.dot(forward) > 0.5 and absf(moved.y) < 1e-6, "W moves the focus forward horizontally")

	var y_0 := camera.focus.y
	Input.action_press("camera_up")
	await _seconds(0.3)
	Input.action_release("camera_up")
	check(camera.focus.y > y_0 + 0.3, "E raises the focus")

	var heading_0 := camera.heading
	Input.action_press("camera_orbit_right")
	await _seconds(0.3)
	Input.action_release("camera_orbit_right")
	check(camera.heading > heading_0 + 10.0, "right arrow orbits")

	var distance_0 := camera.distance
	Input.action_press("camera_zoom_out")
	await _seconds(0.3)
	Input.action_release("camera_zoom_out")
	check(camera.distance > distance_0 * 1.1, "minus key zooms out")

	_key(KEY_HOME)
	await _frames(1)
	check_near(camera.get_heading(), OrbitCamera.PRESETS["default"]["heading"], 1e-6, "F resets the view heading")
	check_vec_near(camera.focus, camera.default_focus(), 1e-6, "F resets the focus")

	var panel := dashboard.camera_panel
	panel.preset_buttons["top"].pressed.emit()
	check_near(camera.elevation, -89.0, 1e-6, "Top preset looks straight down")
	panel.reset_button.pressed.emit()
	check_near(camera.elevation, OrbitCamera.PRESETS["default"]["elevation"], 1e-6, "Reset view button")
	panel.get_field("east").value = 12.0
	panel.get_field("north").value = -7.0
	check_near(camera.focus.x, 12.0, 1e-6, "focus east field")
	check_near(camera.focus.z, 7.0, 1e-6, "focus north field (north = -Z)")
	panel.get_field("distance").value = 33.0
	check_near(camera.distance, 33.0, 1e-6, "distance field")
	panel.get_field("heading").value = 200.0
	check_near(camera.get_heading(), 200.0, 1e-6, "heading field")
	await _frames(3)
	check_near(panel.get_field("east").value, 12.0, 0.051, "fields show live camera values")


func _test_camera_limits() -> void:
	camera.reset_view(true)
	camera.set_elevation(75.0)
	camera.set_distance(250.0)
	camera.snap()
	var p := camera.get_camera_position()
	check(p.y >= engine.world.seabed_y_at(p.x, p.z) + OrbitCamera.SEABED_MARGIN - 1e-4, "camera stays above the seabed when looking up")
	camera.set_elevation(-89.0)
	camera.snap()
	p = camera.get_camera_position()
	check(p.y <= -OrbitCamera.SURFACE_MARGIN + 1e-4, "camera stays below the sea surface")
	camera.set_focus(Vector3(10000, -10000, 10000))
	camera.snap()
	check(engine.world.is_in_water(camera.focus), "focus clamped into the water column")
	check(engine.world.is_within_bounds(camera.get_camera_position()), "camera clamped to the domain")
	camera.reset_view(true)


func _test_shortcuts_and_display() -> void:
	_key(KEY_P)
	check(engine.is_running(), "P starts the simulation")
	_key(KEY_P)
	check(engine.state == SimulationEngine.State.PAUSED, "P pauses the simulation")
	var t := engine.get_sim_time()
	_key(KEY_PERIOD)
	check_near(engine.get_sim_time(), t + 0.01, 1e-9, "'.' steps once")
	_key(KEY_BACKSPACE)
	check(engine.state == SimulationEngine.State.READY and engine.get_sim_time() == 0.0, "Backspace resets")
	_key(KEY_SPACE)
	check(engine.state == SimulationEngine.State.READY, "Space no longer toggles the simulation")
	_key(KEY_H)
	check(not dashboard.panels_visible, "H hides panels")
	_key(KEY_H)
	check(dashboard.panels_visible, "H shows panels again")

	var panel := dashboard.environment_panel
	panel.grid_toggle.button_pressed = false
	check(not renderer.seabed.grid_visible, "grid toggle")
	panel.axes_toggle.button_pressed = false
	check(not renderer.markers.are_axes_visible(), "axes toggle")
	panel.labels_toggle.button_pressed = false
	check(not renderer.markers.are_labels_visible(), "labels toggle")
	panel.particles_toggle.button_pressed = false
	check(not renderer.marine_snow.visible, "particles toggle")
	for toggle in [panel.grid_toggle, panel.axes_toggle, panel.labels_toggle, panel.particles_toggle]:
		toggle.button_pressed = true
	check(renderer.seabed.grid_visible and renderer.marine_snow.visible, "toggles restore display")
	var energy := renderer.get_light_energy()
	panel.brightness_slider.value = 2.0
	check_near(renderer.get_light_energy(), energy * 2.0, 1e-4, "brightness scales rendered light")
	panel.brightness_slider.value = 1.0


func _test_views_and_pilot() -> void:
	var start := vehicle.position
	_key(KEY_TAB)
	check(views.mode == ViewController.ViewMode.FREE and not views.is_piloting(), "Tab switches to the free camera")
	check(dashboard.get_help_text().begins_with("FREE CAMERA"), "help bar shows camera controls")
	check(not camera.is_following(), "free camera detached from the vehicle")
	_key(KEY_TAB)
	check(views.mode == ViewController.ViewMode.CHASE, "Tab returns to the chase view")
	_key(KEY_V)
	check(views.mode == ViewController.ViewMode.ORBIT, "V cycles to the orbit view")
	_key(KEY_V)
	check(views.mode == ViewController.ViewMode.ONBOARD, "V cycles to the onboard camera")
	check(visual.onboard_camera.current, "onboard camera is active")
	check(dashboard.onboard_hud.visible, "onboard HUD shown")
	check(visual.onboard_view and not visual._overlays_shown(), "engineering overlays hidden in the onboard view")
	await _frames(2)
	_key(KEY_V)
	check(views.mode == ViewController.ViewMode.CHASE and camera.camera.current, "V returns to the chase view")
	check(not dashboard.onboard_hud.visible, "HUD hidden outside the onboard view")
	dashboard.simulation_bar.view_option.select(1)
	dashboard.simulation_bar.view_option.item_selected.emit(1)
	check(views.mode == ViewController.ViewMode.ORBIT, "view selector sets the view")
	views.set_mode(ViewController.ViewMode.CHASE)

	_key(KEY_P)
	check(engine.is_running(), "simulation running for the pilot test")
	Input.action_press("pilot_forward")
	Input.action_press("pilot_full_power")
	await _seconds(1.5)
	check(vehicle.thrusters[0].thrust > 10.0, "pilot command produces thrust")
	check(dashboard.telemetry_panel.get_value_text("control").begins_with("PILOT"), "telemetry shows pilot control")
	Input.action_release("pilot_forward")
	Input.action_release("pilot_full_power")
	check(start.z - vehicle.position.z > 0.3, "W drives the vehicle forward (north) (moved %.2f m)" % (start.z - vehicle.position.z))
	await _frames(2)
	check(camera.focus.distance_to(visual.global_position) < 0.05, "chase camera follows the vehicle")
	var y_before := vehicle.position.y
	Input.action_press("pilot_ascend")
	await _seconds(1.0)
	Input.action_release("pilot_ascend")
	check(vehicle.position.y > y_before + 0.1, "Space ascends")
	var heading_before := vehicle.heading_degrees()
	Input.action_press("pilot_yaw_right")
	await _seconds(1.0)
	Input.action_release("pilot_yaw_right")
	check(wrapf(vehicle.heading_degrees() - heading_before, -180.0, 180.0) > 5.0, "E yaws clockwise")
	var lights := vehicle.lights_on
	_key(KEY_L)
	check(vehicle.lights_on != lights, "L toggles the lights")
	_key(KEY_L)

	_key(KEY_TAB)
	Input.action_press("pilot_forward")
	await _frames(3)
	check(vehicle.pilot_command[RovVehicle.Axis.SURGE] == 0.0, "free camera mode does not pilot the vehicle")
	Input.action_release("pilot_forward")
	_key(KEY_TAB)
	_key(KEY_BACKSPACE)
	await _frames(2)
	check(engine.state == SimulationEngine.State.READY, "reset after the pilot test")
	check_vec_near(vehicle.position, start, 1e-4, "reset returns the vehicle to its start pose")
	check(vehicle.velocity == Vector3.ZERO and vehicle.distance_travelled == 0.0, "reset clears motion and trip data")


func _test_vehicle_config_panel() -> void:
	var panel := dashboard.vehicle_config_panel
	panel.config_path = TEST_VEHICLE_PATH
	check(panel.apply_button.disabled, "Apply disabled while nothing is edited")
	panel.get_spin("dry_mass").value = 120.0
	check(panel.is_dirty() and not panel.apply_button.disabled, "editing a value enables Apply")
	check_near(vehicle.mass, 85.0, 1e-9, "edits do not touch the vehicle before Apply")
	panel.layout_option.select(2)
	panel.layout_option.item_selected.emit(2)
	check(panel.get_draft().layout == "basic_2h_2v", "layout selector edits the draft")
	_key(KEY_P)
	await _frames(3)
	panel.apply_button.pressed.emit()
	await _frames(2)
	check_near(vehicle.mass, 120.0, 1e-9, "Apply rebuilds the vehicle mass")
	check(vehicle.thrusters.size() == 4, "Apply rebuilds the thruster layout")
	check(engine.state == SimulationEngine.State.READY and engine.get_sim_time() == 0.0, "Apply resets the simulation")
	check(dashboard.telemetry_panel.get_characteristic_text("mass").begins_with("%.0f" % (120.0 * 9.81)), "characteristics follow the applied configuration")
	check(dashboard.telemetry_panel.get_characteristic_text("thrust_sway") == "0 N", "2H+2V layout reports no sway thrust")
	panel.save_button.pressed.emit()
	check(FileAccess.file_exists(TEST_VEHICLE_PATH), "vehicle Save writes a file")
	panel.defaults_button.pressed.emit()
	check(panel.get_draft().layout == "vectored_4h_4v" and panel.is_dirty(), "Defaults loads default values into the draft")
	panel.load_button.pressed.emit()
	check(not panel.is_dirty(), "Load restores the saved (applied) values")
	panel.defaults_button.pressed.emit()
	panel.apply_button.pressed.emit()
	await _frames(2)
	check(vehicle.thrusters.size() == 8 and vehicle.mass == 85.0, "defaults re-applied")
	check(panel.apply_button.disabled, "nothing left to apply")
	panel.markers_toggle.button_pressed = false
	check(not visual.markers_visible, "marker toggle hides CG/CB and thrust arrows")
	panel.markers_toggle.button_pressed = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_VEHICLE_PATH))


func _test_sensors_ui() -> void:
	var config_panel := dashboard.sensor_config_panel
	var readings_panel := dashboard.sensor_readings_panel
	var overlay: SensorOverlay = scene.get_node("SensorOverlay")
	var stereo: StereoFeed = scene.get_node("StereoFeed")
	check(dashboard.left_tabs.get_tab_count() == 3 and dashboard.right_tabs.get_tab_count() == 6, "Sensors tabs added on both sides")
	check(readings_panel.get_cell_text("depth", 0) == "-", "no readings before the simulation runs")
	_key(KEY_J)
	check(not vehicle.aids.depth_hold, "J does nothing without sensor data")

	dashboard.right_tabs.current_tab = 2
	_key(KEY_P)
	await _seconds(1.5)
	readings_panel.refresh()
	check(readings_panel.get_cell_text("depth", 0) != "-", "readings panel shows measured depth")
	check(readings_panel.get_cell_text("depth", 2) != "-", "readings panel shows the depth error")
	check(readings_panel.sonar_display.pings_shown > 0, "sonar display shows pings")
	check(overlay.segment_count() > 10, "sensor coverage drawn in 3D")
	check(not is_nan(dashboard.onboard_hud.measured_values()["depth"]), "HUD uses the depth sensor")

	_key(KEY_J)
	_key(KEY_K)
	check(vehicle.aids.depth_hold and vehicle.aids.heading_hold, "J and K engage depth and heading hold")
	await _frames(2)
	dashboard.telemetry_panel.refresh()
	check(dashboard.telemetry_panel.depth_hold_toggle.button_pressed, "telemetry shows depth hold engaged")
	dashboard.telemetry_panel.heading_hold_toggle.button_pressed = false
	check(not vehicle.aids.heading_hold, "telemetry checkbox releases heading hold")
	_key(KEY_J)
	check(not vehicle.aids.depth_hold, "J releases depth hold")

	config_panel.get_spin("DVL", "max_altitude").value = 1.0
	check_near(vehicle.sensors.get_sensor("DVL").get_param("max_altitude"), 1.0, 1e-9, "settings panel edits sensor parameters")
	await _seconds(0.6)
	readings_panel.refresh()
	check(readings_panel._status["DVL"].text.begins_with("NO BOTTOM LOCK"), "status shows the lost bottom lock")
	config_panel.get_enable_box("Altimeter").button_pressed = false
	check(not vehicle.sensors.get_sensor("Altimeter").enabled, "enable box switches a sensor off")
	readings_panel.refresh()
	check(readings_panel._status["Altimeter"].text == "off", "status shows the sensor off")

	config_panel.get_enable_box("Stereo camera").button_pressed = true
	await _frames(3)
	check(stereo.is_active() and stereo.left_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "stereo pair renders when enabled")
	check(readings_panel.stereo_left.visible and readings_panel.stereo_left.texture != null, "stereo feed shown in the readings tab")

	config_panel.get_spin("Camera", "gain").value = 4.0
	config_panel.get_spin("Camera", "fov").value = 90.0
	views.set_mode(ViewController.ViewMode.ONBOARD)
	await _frames(3)
	check(dashboard.camera_noise.visible, "low-light gain adds image noise in the onboard view")
	check_near(visual.onboard_camera.fov, 90.0, 1e-4, "camera field of view applied")
	check(overlay.segment_count() == 0, "coverage overlay hidden in the onboard view")
	views.set_mode(ViewController.ViewMode.CHASE)
	await _frames(2)
	check(not dashboard.camera_noise.visible, "no camera noise outside the onboard view")
	config_panel.overlay_toggle.button_pressed = false
	await _frames(2)
	check(overlay.segment_count() == 0, "overlay toggle hides the coverage lines")
	config_panel.overlay_toggle.button_pressed = true

	config_panel.defaults_button.pressed.emit()
	check(vehicle.sensors.get_sensor("Altimeter").enabled and not vehicle.sensors.get_sensor("Stereo camera").enabled
		and vehicle.sensors.get_sensor("DVL").get_param("max_altitude") == 50.0, "Defaults restores sensor settings")
	check_near(config_panel.get_spin("DVL", "max_altitude").value, 50.0, 1e-9, "widgets follow the defaults")
	_key(KEY_P)
	_key(KEY_BACKSPACE)
	await _frames(2)
	check(vehicle.sensors.get_sensor("Depth").latest == null and not vehicle.aids.depth_hold, "reset clears readings and aids")


func _test_arm_and_pipeline_ui() -> void:
	var arm := vehicle.manipulator
	var panel := dashboard.arm_panel
	var pilot: PilotInput = scene.get_node("PilotInput")
	var pipeline: Pipeline = scene.pipeline
	check(engine.world.structures.has(pipeline), "pipeline registered with the world")
	check(scene.get_node("PipelineRenderer").get_child_count() > 0, "pipeline model built")
	check(scene.get_node("ObjectVisuals").get_child_count() == 4, "four graspable items drawn")
	check(arm.is_installed() and arm.joints.size() == 5, "default 5-DOF arm fitted")
	check(visual.arm_visual != null and visual.arm_visual.get_child_count() > 5, "arm model built")

	_key(KEY_P)
	await _seconds(1.2)
	_key(KEY_M)
	check(pilot.arm_mode, "M switches to arm control")
	check(vehicle.aids.depth_hold and vehicle.aids.heading_hold, "arm control engages depth and heading hold")
	check(dashboard.get_help_text().begins_with("ARM CONTROL"), "help bar shows arm controls")
	check(panel.arm_mode_button.button_pressed, "arm panel shows arm control")
	arm.ready_pose()
	await _seconds(4.0)
	var target_before := arm.tool_target_position
	Input.action_press("pilot_forward")
	await _seconds(0.5)
	Input.action_release("pilot_forward")
	check(target_before.z - arm.tool_target_position.z > 0.02, "W moves the tool target forward")
	check(absf(vehicle.pilot_command[RovVehicle.Axis.SURGE]) == 0.0, "the vehicle is not driven in arm control")
	_key(KEY_G)
	check(arm.gripper_closing, "G closes the gripper")
	_key(KEY_G)
	check(not arm.gripper_closing, "G opens it again")

	panel.get_slider(0).value = 30.0
	check_near(rad_to_deg(arm.joints[0].target), 30.0, 1e-6, "joint slider sets the joint target")
	panel.move_fields["forward"].value = 0.6
	panel.move_fields["starboard"].value = 0.0
	panel.move_fields["up"].value = -0.3
	panel.move_fields["pitch"].value = -45.0
	panel.go_button.pressed.emit()
	check(arm.ik_status == "ok", "Go solves IK for a reachable point")
	panel.envelope_toggle.button_pressed = true
	check(visual.arm_visual.envelope_visible, "reach envelope shown")
	panel.envelope_toggle.button_pressed = false
	panel.test_button.pressed.emit()
	check(arm.accuracy_test_running, "accuracy test started from the panel")
	_key(KEY_X)
	check_near(rad_to_deg(arm.joints[2].target), -165.0, 1e-6, "X commands the stow pose")

	# Stage 5: tools from the Arm tab and the keyboard.
	check(panel.tool_option.item_count == 3, "tool selector lists gripper, brush and CP probe")
	panel.tool_option.select(1)
	panel.change_tool_button.pressed.emit()
	check(arm.tool_change_phase != "", "Change starts a tool change")
	engine.set_time_scale(10.0)
	await _seconds(2.5)
	engine.set_time_scale(1.0)
	check(arm.tool is CleaningBrush and panel.get_value_text("tool_name") == "Cleaning brush", "brush mounted and shown in the panel")
	_key(KEY_G)
	check(arm.tool.active, "G spins the brush")
	await _frames(6)
	check(visual.arm_visual.get_child_count() > 0 and dashboard.get_help_text().contains("N change tool"), "help shows the tool keys")
	_key(KEY_N)
	check(arm.tool_change_phase != "", "N starts changing to the next tool")
	engine.set_time_scale(10.0)
	await _seconds(2.5)
	engine.set_time_scale(1.0)
	check(arm.tool is CpProbe, "N cycled to the CP probe")
	await _seconds(0.3)
	check(panel.tool_option.selected == 2, "tool selector follows the mounted tool")
	check(dashboard.pipeline_panel.get_status_text("crack") == "open" and dashboard.pipeline_panel.get_status_text("cp").contains("UNDER-PROTECTED"),
		"repair status: crack open, line under-protected")
	_key(KEY_M)
	check(not pilot.arm_mode, "M returns to piloting")

	var setup := dashboard.vehicle_config_panel
	setup.arm_layout_option.select(3)
	setup.arm_layout_option.item_selected.emit(3)
	setup.apply_button.pressed.emit()
	await _frames(2)
	check(arm.joints.size() == 3 and panel.get_slider(2) != null, "3-DOF layout applied; arm panel rebuilt")
	setup.defaults_button.pressed.emit()
	setup.apply_button.pressed.emit()
	await _frames(2)
	check(arm.joints.size() == 5, "default arm restored")

	dashboard.pipeline_panel.get_spin("diameter").value = 0.9
	check_near(pipeline.radius(), 0.45, 1e-6, "pipeline diameter editable")
	dashboard.pipeline_panel.markers_toggle.button_pressed = true
	check(scene.get_node("PipelineRenderer").defect_markers_visible, "defect markers toggle")
	dashboard.pipeline_panel.markers_toggle.button_pressed = false
	dashboard.pipeline_panel.get_spin("diameter").value = 0.6
	_key(KEY_P)
	_key(KEY_BACKSPACE)
	await _frames(2)
	check(not vehicle.aids.depth_hold and arm.grasped == null, "reset clears aids and the gripper")
	check(arm.tool == null and pipeline.retrofit_anodes.is_empty(), "reset returns the tool to the skid and the site to its initial state")


func _test_autonomy_ui() -> void:
	var panel := dashboard.autonomy_panel
	var camera: InspectionCamera = scene.get_node("InspectionCamera")
	check(dashboard.right_tabs.get_tab_title(5) == "Autonomy" and panel.mission_option.item_count == Mission.PRESETS.size(), "Autonomy tab lists the preset missions")
	check(vehicle.autonomy.pipeline == scene.pipeline, "autonomy uses the pipeline as-built data")
	_key(KEY_P)
	await _seconds(2.5)
	panel.refresh()
	check(vehicle.autonomy.nav.initialized and panel.get_value_text("est").begins_with("E "), "navigation estimate shown once USBL fixes arrive")
	panel.mission_option.select(Mission.PRESETS.find("Return to start"))
	check(panel.start_selected() and vehicle.autonomy.mission_running(), "Start runs the selected mission")
	await _seconds(0.5)
	panel.refresh()
	check(panel.start_button.disabled and panel.get_value_text("mission").contains("running"), "panel shows the running mission")
	panel.abort_button.pressed.emit()
	check(vehicle.autonomy.mission.state == "aborted" and not vehicle.autonomy.autopilot.active, "Abort stops it and releases the autopilot")
	panel.vision_toggle.button_pressed = true
	check(camera.is_active(), "detector switch activates the inspection camera")
	await _seconds(1.2)
	check(vehicle.autonomy.inspection.frames_analysed >= 0, "inspection frames processed without errors")
	panel.vision_toggle.button_pressed = false
	check(not camera.is_active(), "and switches it off")
	_key(KEY_P)
	_key(KEY_BACKSPACE)
	await _frames(2)
	check(vehicle.autonomy.mission == null and not vehicle.autonomy.nav.initialized, "reset clears the autonomy state")


# --- helpers -----------------------------------------------------------------

func _frames(count: int) -> void:
	for i in count:
		await tree.process_frame


func _seconds(duration: float) -> void:
	await tree.create_timer(duration).timeout


func _mouse_button(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = VIEW_POINT
	event.global_position = VIEW_POINT
	tree.root.push_input(event)


func _mouse_motion(relative: Vector2, mask: int) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.position = VIEW_POINT
	event.global_position = VIEW_POINT
	event.button_mask = mask
	tree.root.push_input(event)


func _key(keycode: Key, ctrl: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.keycode = keycode
		event.ctrl_pressed = ctrl
		event.pressed = pressed
		tree.root.push_input(event)
