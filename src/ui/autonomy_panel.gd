## Autonomy tab: navigation filter state, mission selection and execution,
## the inspection camera with the defect detector, and the evaluation of
## navigation and detections against the ground truth (marked as such).
class_name AutonomyPanel
extends VBoxContainer

const REFRESH_INTERVAL := 0.2

var mission_option: OptionButton
var start_button: Button
var abort_button: Button
var vision_toggle: CheckBox

var _engine: SimulationEngine
var _vehicle: RovVehicle
var _camera: InspectionCamera
var _pipeline: Pipeline
var _home: Vector3
var _values: Dictionary = {}
var _tasks_label: Label
var _log_label: Label
var _features_label: Label
var _preview: TextureRect
var _elapsed: float = 0.0


func _init() -> void:
	name = "AutonomyPanel"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func bind(engine: SimulationEngine, vehicle: RovVehicle, camera: InspectionCamera, pipeline: Pipeline) -> void:
	_engine = engine
	_vehicle = vehicle
	_camera = camera
	_pipeline = pipeline
	_home = vehicle.get("_initial_position")
	add_child(UIWidgets.section_header("Navigation filter (DVL + USBL)"))
	add_child(_grid([
		["est", "Estimate", "Kalman-filtered position from DVL dead reckoning and USBL fixes; depth from the depth sensor, heading from the compass."],
		["sigma", "Uncertainty (1σ)", "Filter's own estimate of its horizontal position error."],
		["fixes", "USBL fixes", "Fixes used / rejected by the outlier gate."],
		["dvl", "DVL", "Bottom lock state and velocity over the seabed."],
		["error", "Error vs truth", "EVALUATION ONLY: distance between the estimate and the simulated true position (not used by the vehicle)."],
	]))

	add_child(UIWidgets.spacer(2.0))
	add_child(UIWidgets.section_header("Mission"))
	mission_option = OptionButton.new()
	mission_option.focus_mode = Control.FOCUS_NONE
	mission_option.clip_text = true
	for preset in Mission.PRESETS:
		mission_option.add_item(preset)
	add_child(mission_option)
	var row := HBoxContainer.new()
	start_button = UIWidgets.button("Start mission", "Runs the selected mission (the simulation must be running). Any pilot key aborts it.")
	abort_button = UIWidgets.button("Abort", "Stops the mission and releases the autopilot.")
	for b in [start_button, abort_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	add_child(row)
	start_button.pressed.connect(start_selected)
	abort_button.pressed.connect(func() -> void: _vehicle.autonomy.abort(_vehicle.last_update_time, "operator abort"))
	add_child(_grid([["mission", "State", ""], ["task", "Current", ""], ["mission_nav", "Nav error in mission", "EVALUATION ONLY: mean / max estimate error vs truth during the mission."]]))
	_tasks_label = UIWidgets.dim_label("")
	_tasks_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_tasks_label)
	_log_label = UIWidgets.dim_label("")
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_log_label)

	add_child(UIWidgets.spacer(2.0))
	add_child(UIWidgets.section_header("Inspection camera and defect detector"))
	vision_toggle = CheckBox.new()
	vision_toggle.text = "Run the detector now (surveys switch it on)"
	vision_toggle.focus_mode = Control.FOCUS_NONE
	vision_toggle.toggled.connect(func(on: bool) -> void: _camera.manual = on)
	add_child(vision_toggle)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(InspectionCamera.WIDTH, InspectionCamera.HEIGHT) * 0.75
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_preview)
	add_child(_grid([["frames", "Frames analysed", ""], ["last", "Last frame", "Rust-coloured blobs / thin dark lines found in the last analysed image."]]))
	_features_label = UIWidgets.dim_label("")
	_features_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_features_label)
	add_child(_grid([["score", "Evaluation vs truth", "EVALUATION ONLY: confirmed findings compared with the pipeline's true defects."]]))
	refresh()


## Starts the mission selected in the list. Returns false if it cannot start.
func start_selected() -> bool:
	var preset: String = Mission.PRESETS[mission_option.selected]
	var mission := Mission.preset(preset, _pipeline, _home)
	return _vehicle.autonomy.start_mission(mission, _vehicle.last_update_time)


func get_value_text(key: String) -> String:
	return _values[key].text


func _grid(rows: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	for r in rows:
		grid.add_child(UIWidgets.dim_label(r[1], r[2]))
		var value := Label.new()
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.custom_minimum_size = Vector2(110.0, 0.0)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(value)
		_values[r[0]] = value
	return grid


func _process(delta: float) -> void:
	if _vehicle == null:
		return
	_elapsed += delta
	if _elapsed >= REFRESH_INTERVAL and is_visible_in_tree():
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	var autonomy := _vehicle.autonomy
	var nav := autonomy.nav
	if nav.initialized:
		_values["est"].text = "E %.2f  N %.2f  D %.2f  HDG %05.1f°" % [nav.east, nav.north, nav.depth, nav.heading]
		_values["sigma"].text = "%.3f m" % nav.sigma()
		_values["error"].text = "%.3f m" % autonomy.nav_error
	else:
		_values["est"].text = "waiting for the first USBL fix (simulation must run)"
		_values["sigma"].text = "-"
		_values["error"].text = "-"
	_values["fixes"].text = "%d used / %d rejected" % [nav.fixes_used, nav.fixes_rejected]
	_values["dvl"].text = ("bottom lock, %.2f m/s" % nav.velocity_en.length()) if nav.dvl_ok else "no bottom lock"
	var mission := autonomy.mission
	start_button.disabled = autonomy.mission_running()
	abort_button.disabled = not autonomy.mission_running()
	if mission == null:
		_values["mission"].text = "none"
		_values["task"].text = "-"
		_values["mission_nav"].text = "-"
		_tasks_label.text = ""
		_log_label.text = ""
	else:
		var elapsed: float = (mission.end_time if not is_nan(mission.end_time) else _vehicle.last_update_time) - mission.start_time
		_values["mission"].text = "%s: %s (%.0f s)" % [mission.mission_name, mission.state, elapsed]
		_values["task"].text = mission.status
		_values["mission_nav"].text = "%.3f / %.3f m" % [autonomy.nav_error_mean(), autonomy.nav_error_max]
		var lines: Array[String] = []
		for i in mission.tasks.size():
			var mark := "✓" if i < mission.index else ("▶" if i == mission.index and mission.state == "running" else "·")
			lines.append("%s %s" % [mark, mission.task_label(mission.tasks[i])])
		_tasks_label.text = "\n".join(lines)
		_log_label.text = "\n".join(mission.log_lines.slice(maxi(0, mission.log_lines.size() - 6)))
	_preview.texture = _camera.texture() if _camera.is_active() else null
	var log := autonomy.inspection
	_values["frames"].text = "%d (%d detections)" % [log.frames_analysed, log.detections]
	var last := _camera.last_result
	_values["last"].text = ("%d rust, %d crack-like" % [last["corrosion"].size(), last["crack"].size()]) if not last.is_empty() else "-"
	var confirmed := log.confirmed()
	if confirmed.is_empty():
		_features_label.text = "No confirmed findings yet."
	else:
		var text: Array[String] = ["Confirmed findings:"]
		for f in confirmed:
			text.append("%s at E %.2f%s, clock %+.0f°, %d hits" % [f["type"], f["east"],
				(" (E %.1f to %.1f)" % [f["east_from"], f["east_to"]]) if f["east_to"] - f["east_from"] > 0.3 else "", f["clock"], f["hits"]])
		_features_label.text = "\n".join(text)
	_values["score"].text = log.evaluate(_pipeline)["text"] if log.frames_analysed > 0 else "-"
