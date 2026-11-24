## Top bar: simulation state, clock, start/pause/step/reset and speed control.
class_name SimulationBar
extends PanelContainer

const SPEED_PRESETS := [0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0]

var run_button: Button
var step_button: Button
var reset_button: Button
var speed_option: OptionButton
var view_option: OptionButton

var _engine: SimulationEngine
var _views: ViewController
var _state_indicator: ColorRect
var _state_label: Label
var _time_label: Label
var _detail_label: Label
var _perf_label: Label


func _init() -> void:
	name = "SimulationBar"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	var title := Label.new()
	title.text = "SUBSEA ROBOTICS LABORATORY"
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.add_theme_font_size_override("font_size", 14)
	row.add_child(title)
	row.add_child(UIWidgets.dim_label("Stage 6"))
	row.add_child(VSeparator.new())

	_state_indicator = ColorRect.new()
	_state_indicator.custom_minimum_size = Vector2(10.0, 10.0)
	_state_indicator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_state_indicator)
	_state_label = Label.new()
	_state_label.custom_minimum_size = Vector2(72.0, 0.0)
	row.add_child(_state_label)

	row.add_child(UIWidgets.dim_label("SIM TIME"))
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 16)
	_time_label.custom_minimum_size = Vector2(118.0, 0.0)
	_time_label.tooltip_text = "Simulation time (hh:mm:ss.mmm)"
	_time_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_time_label)
	_detail_label = UIWidgets.dim_label("", "Completed fixed steps and the fixed step size")
	_detail_label.custom_minimum_size = Vector2(130.0, 0.0)
	row.add_child(_detail_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	row.add_child(UIWidgets.dim_label("View", "Chase, orbit and onboard follow the vehicle and the keyboard pilots it; free camera moves the camera instead.\nV cycles vehicle views, Tab toggles the free camera."))
	view_option = OptionButton.new()
	view_option.focus_mode = Control.FOCUS_NONE
	for mode_name in ViewController.MODE_NAMES:
		view_option.add_item(mode_name)
	row.add_child(view_option)
	row.add_child(VSeparator.new())

	run_button = UIWidgets.button("Start", "Start / pause the simulation clock  (P)")
	run_button.custom_minimum_size = Vector2(84.0, 0.0)
	row.add_child(run_button)
	step_button = UIWidgets.button("Step", "Advance exactly one fixed time step while not running  (.)")
	row.add_child(step_button)
	reset_button = UIWidgets.button("Reset", "Return simulation time and all objects to their initial state  (Backspace).\nEnvironment parameters are kept.")
	row.add_child(reset_button)

	row.add_child(UIWidgets.dim_label("Speed", "Simulated seconds per real second"))
	speed_option = OptionButton.new()
	speed_option.focus_mode = Control.FOCUS_NONE
	speed_option.tooltip_text = "Simulation speed (time scale)"
	for scale_value in SPEED_PRESETS:
		speed_option.add_item(String.num(scale_value, 2) + "×")
	row.add_child(speed_option)
	row.add_child(VSeparator.new())

	_perf_label = UIWidgets.dim_label("", "RTF: measured real-time factor (simulated s per real s)")
	_perf_label.custom_minimum_size = Vector2(130.0, 0.0)
	row.add_child(_perf_label)


func bind(engine: SimulationEngine, views: ViewController) -> void:
	_engine = engine
	_views = views
	view_option.item_selected.connect(func(index: int) -> void: views.set_mode(index))
	views.view_mode_changed.connect(func(mode: int) -> void: view_option.select(mode))
	view_option.select(views.mode)
	run_button.pressed.connect(engine.toggle_running)
	step_button.pressed.connect(engine.step_once)
	reset_button.pressed.connect(engine.reset)
	speed_option.item_selected.connect(_on_speed_selected)
	engine.state_changed.connect(_on_state_changed)
	engine.time_scale_changed.connect(_on_time_scale_changed)
	_on_state_changed(engine.state, engine.state)
	_on_time_scale_changed(engine.clock.time_scale)


func get_time_text() -> String:
	return _time_label.text


static func format_time(seconds: float) -> String:
	var total_ms := int(round(seconds * 1000.0))
	var total_s := floori(total_ms / 1000.0)
	return "%02d:%02d:%02d.%03d" % [
		floori(total_s / 3600.0), floori(total_s / 60.0) % 60, total_s % 60, total_ms % 1000]


func _process(_delta: float) -> void:
	if _engine == null:
		return
	_time_label.text = format_time(_engine.clock.sim_time)
	_detail_label.text = "step %d  ·  dt %d ms" % [_engine.clock.step_count, int(round(_engine.clock.fixed_dt * 1000.0))]
	var rtf := "%.2f" % _engine.real_time_factor if _engine.is_running() else "-"
	_perf_label.text = "RTF %s   ·   %d FPS" % [rtf, Engine.get_frames_per_second()]


func _on_speed_selected(index: int) -> void:
	_engine.set_time_scale(SPEED_PRESETS[index])


func _on_state_changed(_new_state: int, _previous_state: int) -> void:
	var color := UITheme.STATE_READY
	match _engine.state:
		SimulationEngine.State.RUNNING:
			run_button.text = "Pause"
			color = UITheme.STATE_RUNNING
		SimulationEngine.State.PAUSED:
			run_button.text = "Resume"
			color = UITheme.STATE_PAUSED
		_:
			run_button.text = "Start"
	_state_label.text = _engine.get_state_name()
	_state_label.add_theme_color_override("font_color", color)
	_state_indicator.color = color
	step_button.disabled = _engine.is_running()


func _on_time_scale_changed(time_scale: float) -> void:
	var best := 0
	for i in SPEED_PRESETS.size():
		if absf(SPEED_PRESETS[i] - time_scale) < absf(SPEED_PRESETS[best] - time_scale):
			best = i
	speed_option.select(best)
