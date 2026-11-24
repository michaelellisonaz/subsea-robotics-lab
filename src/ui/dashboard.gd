## Engineering dashboard: lays out the panels around the 3D view, shows the
## onboard HUD in the onboard view, and maps the simulation shortcuts. The UI
## only calls public methods of the engine, vehicle, views, camera and
## renderer and reads their state; it holds no simulation state of its own.
class_name Dashboard
extends CanvasLayer

const MARGIN := 8.0
const TOP_BAR_HEIGHT := 44.0
const HELP_BAR_HEIGHT := 30.0
const LEFT_WIDTH := 350.0
const RIGHT_WIDTH := 350.0
const PILOT_HELP := "PILOT   W/S surge  ·  A/D sway  ·  Space/Ctrl up/down  ·  Q/E yaw  ·  R/F pitch  ·  Z/C roll  ·  Shift full power  ·  J/K/B/T depth/heading/position/level hold  ·  L lights  ·  Mouse orbit/zoom  ·  V view  ·  Tab free camera  ·  Home reset view  ·  P start/pause  ·  . step  ·  Backspace reset  ·  H panels"
const ARM_HELP := "ARM CONTROL   W/S forward/back  ·  A/D port/stbd  ·  Space/Ctrl up/down  ·  R/F tool pitch  ·  Q/E wrist roll  ·  G gripper / tool  ·  N change tool  ·  X stow  ·  Shift faster  ·  M back to piloting  ·  J/K/B/T holds  ·  V view  ·  P start/pause  ·  Backspace reset  ·  H panels"
const CAMERA_HELP := "FREE CAMERA   LMB drag orbit  ·  RMB/MMB drag pan  ·  Wheel or +/- zoom  ·  W A S D move  ·  Q/E down/up  ·  Arrows orbit  ·  Shift faster  ·  Home reset view  ·  Tab back to vehicle  ·  P start/pause  ·  . step  ·  Backspace reset  ·  H panels"
const FRAME_TEXT := "World frame: +X East, +Y Up, +Z South (North = -Z). Origin on the sea surface above the site centre; depth = -Y. Headings are compass degrees (0° N, 90° E). Grid: 1 m minor, 10 m major lines."

var simulation_bar: SimulationBar
var environment_panel: EnvironmentPanel
var vehicle_config_panel: VehicleConfigPanel
var telemetry_panel: TelemetryPanel
var info_panel: InfoPanel
var camera_panel: CameraPanel
var onboard_hud: OnboardHud
var camera_noise: ColorRect
var sensor_config_panel: SensorConfigPanel
var sensor_readings_panel: SensorReadingsPanel
var arm_panel: ArmPanel
var pipeline_panel: PipelinePanel
var autonomy_panel: AutonomyPanel
var left_tabs: TabContainer
var right_tabs: TabContainer
var panels_visible: bool = true

var _engine: SimulationEngine
var _views: ViewController
var _vehicle: RovVehicle
var _pilot: PilotInput
var _root: Control
var _help: PanelContainer
var _help_label: Label


func _ready() -> void:
	InputBindings.ensure_registered()
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.build()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	camera_noise = ColorRect.new()
	camera_noise.name = "CameraNoise"
	camera_noise.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var noise_material := ShaderMaterial.new()
	noise_material.shader = preload("res://src/rendering/shaders/camera_noise.gdshader")
	camera_noise.material = noise_material
	_root.add_child(camera_noise)
	camera_noise.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	camera_noise.visible = false

	onboard_hud = OnboardHud.new()
	_root.add_child(onboard_hud)
	onboard_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	onboard_hud.visible = false

	simulation_bar = SimulationBar.new()
	_root.add_child(simulation_bar)
	_place(simulation_bar, Vector4(0, 0, 1, 0), Vector4(MARGIN, MARGIN, -MARGIN, MARGIN + TOP_BAR_HEIGHT))

	var side_top := MARGIN * 2.0 + TOP_BAR_HEIGHT
	var side_bottom := -(MARGIN * 2.0 + HELP_BAR_HEIGHT)

	left_tabs = _make_tabs("LeftTabs")
	_place(left_tabs, Vector4(0, 0, 0, 1), Vector4(MARGIN, side_top, MARGIN + LEFT_WIDTH, side_bottom))
	environment_panel = EnvironmentPanel.new()
	var environment_tab := _add_tab(left_tabs, "Environment")
	environment_tab.add_child(environment_panel)
	environment_tab.add_child(UIWidgets.spacer(6.0))
	pipeline_panel = PipelinePanel.new()
	environment_tab.add_child(pipeline_panel)
	vehicle_config_panel = VehicleConfigPanel.new()
	_add_tab(left_tabs, "Vehicle setup").add_child(vehicle_config_panel)
	sensor_config_panel = SensorConfigPanel.new()
	_add_tab(left_tabs, "Sensors").add_child(sensor_config_panel)

	right_tabs = _make_tabs("RightTabs")
	_place(right_tabs, Vector4(1, 0, 1, 1), Vector4(-MARGIN - RIGHT_WIDTH, side_top, -MARGIN, side_bottom))
	telemetry_panel = TelemetryPanel.new()
	_add_tab(right_tabs, "Vehicle").add_child(telemetry_panel)
	arm_panel = ArmPanel.new()
	_add_tab(right_tabs, "Arm").add_child(arm_panel)
	sensor_readings_panel = SensorReadingsPanel.new()
	_add_tab(right_tabs, "Sensors").add_child(sensor_readings_panel)
	info_panel = InfoPanel.new()
	_add_tab(right_tabs, "Environment").add_child(info_panel)
	var camera_tab := _add_tab(right_tabs, "Camera")
	camera_panel = CameraPanel.new()
	camera_tab.add_child(camera_panel)
	autonomy_panel = AutonomyPanel.new()
	_add_tab(right_tabs, "Autonomy").add_child(autonomy_panel)
	camera_tab.add_child(UIWidgets.spacer(8.0))
	var frame_note := UIWidgets.dim_label(FRAME_TEXT)
	frame_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	camera_tab.add_child(frame_note)

	_help = PanelContainer.new()
	_help.name = "HelpBar"
	_root.add_child(_help)
	_place(_help, Vector4(0, 1, 1, 1), Vector4(MARGIN, -MARGIN - HELP_BAR_HEIGHT, -MARGIN, -MARGIN))
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.add_theme_stylebox_override("panel", UITheme.box(UITheme.BG, UITheme.BORDER, 4, 6.0))
	_help_label = UIWidgets.dim_label(PILOT_HELP)
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_label.add_theme_font_size_override("font_size", 12)
	_help.add_child(_help_label)


## Connects the panels to the systems they control. Called by main.gd.
func setup(engine: SimulationEngine, camera: OrbitCamera, renderer: EnvironmentRenderer,
		vehicle: RovVehicle, visual: RovVisual, views: ViewController,
		sensor_overlay: SensorOverlay, stereo_feed: StereoFeed,
		pilot: PilotInput, pipeline: Pipeline, pipeline_renderer: PipelineRenderer) -> void:
	_engine = engine
	_views = views
	_vehicle = vehicle
	_pilot = pilot
	arm_panel.bind(vehicle, visual, pilot, engine.environment)
	telemetry_panel.pilot = pilot
	pipeline_panel.bind(pipeline, pipeline_renderer)
	pilot.arm_mode_changed.connect(func(_active: bool) -> void: _on_view_mode_changed(views.mode))
	sensor_config_panel.bind(vehicle.sensors, sensor_overlay)
	sensor_readings_panel.bind(vehicle, stereo_feed)
	simulation_bar.bind(engine, views)
	environment_panel.bind(engine.environment, renderer)
	vehicle_config_panel.bind(engine, vehicle, visual)
	telemetry_panel.bind(engine, vehicle, views)
	info_panel.bind(engine)
	camera_panel.bind(camera, engine.world, views)
	onboard_hud.bind(vehicle, engine.world, engine)
	views.view_mode_changed.connect(_on_view_mode_changed)
	_on_view_mode_changed(views.mode)
	set_panels_visible(panels_visible)


## Connects the Autonomy tab (navigation, missions, inspection camera).
func bind_autonomy(engine: SimulationEngine, vehicle: RovVehicle, camera: InspectionCamera, pipeline: Pipeline) -> void:
	autonomy_panel.bind(engine, vehicle, camera, pipeline)


func set_panels_visible(value: bool) -> void:
	panels_visible = value
	left_tabs.visible = value
	right_tabs.visible = value
	_help.visible = value
	onboard_hud.inset_left = MARGIN + LEFT_WIDTH if value else 0.0
	onboard_hud.inset_right = MARGIN + RIGHT_WIDTH if value else 0.0


func toggle_panels() -> void:
	set_panels_visible(not panels_visible)


func get_help_text() -> String:
	return _help_label.text


func _process(_delta: float) -> void:
	if _vehicle == null:
		return
	var camera_sensor: CameraSensor = _vehicle.sensors.get_sensor("Camera")
	var amount := camera_sensor.noise_amount() if onboard_hud.visible else 0.0
	camera_noise.visible = amount > 0.0
	camera_noise.material.set_shader_parameter("amount", amount)


func _on_view_mode_changed(mode: int) -> void:
	onboard_hud.visible = mode == ViewController.ViewMode.ONBOARD
	if not _views.is_piloting():
		_help_label.text = CAMERA_HELP
	else:
		_help_label.text = ARM_HELP if _pilot != null and _pilot.arm_mode else PILOT_HELP
	onboard_hud.arm_mode = _pilot != null and _pilot.arm_mode


func _unhandled_input(event: InputEvent) -> void:
	if _engine == null or not (event is InputEventKey):
		return
	if event.is_action_pressed("sim_toggle_run"):
		_engine.toggle_running()
	elif event.is_action_pressed("sim_step"):
		_engine.step_once()
	elif event.is_action_pressed("sim_reset"):
		_engine.reset()
	elif event.is_action_pressed("ui_toggle_panels"):
		toggle_panels()
	else:
		return
	get_viewport().set_input_as_handled()


func _make_tabs(tabs_name: String) -> TabContainer:
	var tabs := TabContainer.new()
	tabs.name = tabs_name
	tabs.focus_mode = Control.FOCUS_NONE
	tabs.set("tab_focus_mode", Control.FOCUS_NONE)
	_root.add_child(tabs)
	return tabs


## Adds a scrollable tab and returns its content container.
func _add_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)
	tabs.add_child(scroll)
	return content


## anchors = (left, top, right, bottom); offsets likewise, in pixels.
func _place(control: Control, anchors: Vector4, offsets: Vector4) -> void:
	control.anchor_left = anchors.x
	control.anchor_top = anchors.y
	control.anchor_right = anchors.z
	control.anchor_bottom = anchors.w
	control.offset_left = offsets.x
	control.offset_top = offsets.y
	control.offset_right = offsets.z
	control.offset_bottom = offsets.w
