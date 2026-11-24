## Simulation engine: owns simulation state and advances it in fixed steps.
##
## Responsibilities
##   * State machine: READY (t = 0) -> RUNNING <-> PAUSED; reset -> READY.
##   * Fixed-step time advancement through SimClock (independent of frame rate).
##   * Per-step pipeline: objects.pre_step -> physics.step -> objects.post_step.
##   * Ownership of the shared simulation data: EnvironmentConfig, WorldModel,
##     ObjectRegistry and PhysicsWorld.
##
## The engine never references rendering, camera or UI code. Those layers call
## its public methods and listen to its signals, so the simulation can also
## run headless (see tests/).
class_name SimulationEngine
extends Node

enum State { READY, RUNNING, PAUSED }

const STATE_NAMES := {
	State.READY: "READY",
	State.RUNNING: "RUNNING",
	State.PAUSED: "PAUSED",
}
const MIN_TIME_SCALE := 0.05
const MAX_TIME_SCALE := 20.0
## Window over which the measured real-time factor is averaged, s.
const RTF_WINDOW := 0.5

signal state_changed(new_state: int, previous_state: int)
signal time_scale_changed(time_scale: float)
## Emitted after every fixed step. Future sensors and data loggers hook in here.
signal step_completed(sim_time: float, dt: float)
## Emitted once per rendered frame in which at least one step ran.
signal frame_advanced(sim_time: float, steps: int)
signal simulation_reset()

var environment: EnvironmentConfig
var world: WorldModel
var objects: ObjectRegistry
var physics: PhysicsWorld
var clock: SimClock
var state: State = State.READY
## Measured simulated seconds per real second (0 while not running).
var real_time_factor: float = 0.0
## When false the engine does not advance itself each frame; call advance()
## manually instead (used by tests and future external drivers).
var auto_advance: bool = true

var _context: StepContext
var _rtf_real := 0.0
var _rtf_sim := 0.0
var _last_water_depth := 0.0


func _init() -> void:
	environment = EnvironmentConfig.new()
	world = WorldModel.new(environment)
	objects = ObjectRegistry.new()
	physics = PhysicsWorld.new()
	physics.add_default_models()
	clock = SimClock.new()
	_context = StepContext.new()
	_context.environment = environment
	_context.world = world
	_context.objects = objects
	_last_water_depth = environment.water_depth
	environment.parameter_changed.connect(_on_environment_changed)


## Fraction for interpolating object poses between steps (1 when not running,
## so a paused or single-stepped simulation shows the exact current state).
func interpolation_fraction() -> float:
	return clock.interpolation_fraction() if state == State.RUNNING else 1.0


func _process(delta: float) -> void:
	if auto_advance:
		advance(delta)


## Advances the simulation by a real-time interval (scaled by the clock's
## time_scale). Returns the number of fixed steps that were run.
func advance(real_delta: float) -> int:
	if state != State.RUNNING:
		return 0
	var steps := clock.consume(real_delta)
	if steps > 0:
		var bodies := objects.get_bodies()
		for i in steps:
			_run_step(bodies)
		frame_advanced.emit(clock.sim_time, steps)
	_measure_real_time_factor(real_delta, steps * clock.fixed_dt)
	return steps


func start() -> void:
	if state == State.RUNNING:
		return
	_rtf_real = 0.0
	_rtf_sim = 0.0
	_set_state(State.RUNNING)


func pause() -> void:
	if state != State.RUNNING:
		return
	clock.discard_pending()
	real_time_factor = 0.0
	_set_state(State.PAUSED)


func toggle_running() -> void:
	if state == State.RUNNING:
		pause()
	else:
		start()


## Runs exactly one fixed step while the simulation is not running.
## Returns false (and does nothing) while running.
func step_once() -> bool:
	if state == State.RUNNING:
		return false
	_run_step(objects.get_bodies())
	frame_advanced.emit(clock.sim_time, 1)
	if state == State.READY:
		_set_state(State.PAUSED)
	return true


## Returns simulation time to zero and every registered object to its
## initial state. Environment parameters are intentionally left unchanged.
func reset() -> void:
	clock.reset()
	for structure in world.structures:
		structure.reset_state()
	objects.reset_all()
	real_time_factor = 0.0
	_set_state(State.READY)
	simulation_reset.emit()


func set_time_scale(value: float) -> void:
	var v := clampf(value, MIN_TIME_SCALE, MAX_TIME_SCALE)
	if v == clock.time_scale:
		return
	clock.time_scale = v
	time_scale_changed.emit(v)


func is_running() -> bool:
	return state == State.RUNNING


func get_state_name() -> String:
	return STATE_NAMES[state]


func get_sim_time() -> float:
	return clock.sim_time


func _run_step(bodies: Array[SimBody]) -> void:
	_context.dt = clock.fixed_dt
	_context.sim_time = clock.sim_time
	objects.pre_step(_context)
	physics.step(bodies, _context)
	objects.post_step(_context)
	clock.advance_step()
	step_completed.emit(clock.sim_time, clock.fixed_dt)


# Changing the water depth moves the seabed; every object moves with it so
# experiments keep their height above the seabed.
func _on_environment_changed(key: String, value: float) -> void:
	if key == "water_depth":
		var offset := Vector3(0.0, _last_water_depth - value, 0.0)
		world.shift_structures(offset)
		objects.shift_all(offset)
		_last_water_depth = value


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var previous := state
	state = new_state
	state_changed.emit(new_state, previous)


func _measure_real_time_factor(real_delta: float, sim_delta: float) -> void:
	_rtf_real += real_delta
	_rtf_sim += sim_delta
	if _rtf_real >= RTF_WINDOW:
		real_time_factor = _rtf_sim / _rtf_real
		_rtf_real = 0.0
		_rtf_sim = 0.0
