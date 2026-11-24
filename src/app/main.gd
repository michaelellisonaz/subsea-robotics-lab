## Composition root. Contains no simulation, rendering or UI logic of its own:
## it creates the vehicle and connects the independent modules.
##
##   SimulationEngine  --signals-->  EnvironmentRenderer, RovVisual (sim time, time flow)
##   EnvironmentConfig --signals-->  renderer, dashboard, camera (parameter changes)
##   RovVehicle        --read by-->  RovVisual, TelemetryPanel, OnboardHud
##   PilotInput        --commands->  RovVehicle
##   ViewController    --signals-->  renderer (active camera), dashboard, PilotInput
##   Dashboard         --calls---->  engine / config / vehicle / views / renderer APIs
extends Node

## Where the vehicle starts: metres east / north of the site origin, and
## height of its CG above the seabed.
const VEHICLE_START_EAST := 4.0
const VEHICLE_START_NORTH := -8.0
const VEHICLE_START_HEIGHT := 1.5

@onready var engine: SimulationEngine = $SimulationEngine
@onready var environment_view: EnvironmentRenderer = $UnderwaterEnvironment
@onready var orbit_camera: OrbitCamera = $OrbitCamera
@onready var vehicle_visual: RovVisual = $RovVisual
@onready var view_controller: ViewController = $ViewController
@onready var pilot_input: PilotInput = $PilotInput
@onready var dashboard: Dashboard = $Dashboard
@onready var sensor_overlay: SensorOverlay = $SensorOverlay
@onready var stereo_feed: StereoFeed = $StereoFeed
@onready var pipeline_renderer: PipelineRenderer = $PipelineRenderer
@onready var object_visuals: ObjectVisuals = $ObjectVisuals

var vehicle: RovVehicle
var pipeline: Pipeline
var inspection_camera: InspectionCamera


func _enter_tree() -> void:
	InputBindings.ensure_registered()


func _ready() -> void:
	environment_view.setup(engine.world, engine.environment)
	orbit_camera.setup(engine.world)
	var site := Site.populate(engine)
	pipeline = site["pipeline"]
	pipeline_renderer.bind(pipeline)
	object_visuals.bind(engine.objects, engine.interpolation_fraction)

	vehicle = RovVehicle.new(VehicleConfig.new(),
		engine.world.place_on_seabed(VEHICLE_START_EAST, VEHICLE_START_NORTH, VEHICLE_START_HEIGHT))
	engine.objects.register(vehicle)
	vehicle_visual.bind(vehicle, engine.interpolation_fraction)
	sensor_overlay.bind(vehicle, vehicle_visual)
	stereo_feed.bind(vehicle, vehicle_visual)
	pilot_input.vehicle = vehicle

	view_controller.view_mode_changed.connect(func(_mode: int) -> void:
		pilot_input.enabled = view_controller.is_piloting())
	view_controller.active_camera_changed.connect(environment_view.set_view_camera)
	view_controller.setup(orbit_camera, vehicle_visual, vehicle)

	# Simulation -> rendering (one way): time-driven visuals follow the sim clock.
	engine.frame_advanced.connect(func(sim_time: float, _steps: int) -> void:
		environment_view.set_sim_time(sim_time))
	engine.simulation_reset.connect(func() -> void:
		environment_view.set_sim_time(0.0))
	engine.state_changed.connect(func(_new_state: int, _previous_state: int) -> void:
		_sync_time_flow())
	engine.time_scale_changed.connect(func(_time_scale: float) -> void:
		_sync_time_flow())
	_sync_time_flow()

	# Keep the free camera at the same height above the seabed when depth changes
	# (the engine moves the simulation objects itself).
	engine.environment.parameter_changed.connect(func(key: String, _value: float) -> void:
		if key == "water_depth":
			orbit_camera.on_seabed_moved())

	dashboard.setup(engine, orbit_camera, environment_view, vehicle, vehicle_visual, view_controller,
		sensor_overlay, stereo_feed, pilot_input, pipeline, pipeline_renderer)

	# Stage 6: autonomy uses the pipeline's as-built data; the inspection
	# camera feeds the defect detector.
	vehicle.autonomy.pipeline = pipeline
	inspection_camera = InspectionCamera.new()
	inspection_camera.name = "InspectionCamera"
	add_child(inspection_camera)
	inspection_camera.bind(engine, vehicle, vehicle_visual)
	dashboard.bind_autonomy(engine, vehicle, inspection_camera, pipeline)


func _sync_time_flow() -> void:
	var rate := engine.clock.time_scale if engine.is_running() else 0.0
	environment_view.set_time_flow(rate)
	vehicle_visual.set_time_flow(rate)
