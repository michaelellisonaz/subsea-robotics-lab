## Base class for a simulated sensor mounted on a vehicle.
##
## Timing: update() runs after every physics step. When a sample is due
## (update rate), _measure() fills a SensorReading from the current simulated
## state; the reading is delivered as `latest` once its latency has elapsed.
## Measurement times are quantised to the 10 ms physics step.
##
## Noise: every sensor owns a RandomNumberGenerator with a fixed seed that is
## restored on reset(), so a run is exactly repeatable. Noise is Gaussian
## (randfn); biases and random walks are added by the subclasses.
##
## Parameters: subclasses declare a PARAMETERS table (label, unit, min, max,
## default, step, description); the dashboard builds its rows from it, and
## to_dict()/apply_dict() save and restore them.
##
## Mounting: mount_position (body axes, relative to the CG) and mount_basis
## (sensor axes expressed in body axes). Sensor axes follow the body
## convention: +X starboard, +Y up, -Z forward.
class_name Sensor
extends RefCounted

const COMMON_PARAMETERS := {
	"rate_hz": {"label": "Update rate", "unit": "Hz", "min": 0.2, "max": 100.0, "default": 10.0, "step": 0.1,
		"description": "Measurements per second of simulation time (quantised to the 10 ms physics step)."},
	"latency": {"label": "Latency", "unit": "s", "min": 0.0, "max": 2.0, "default": 0.0, "step": 0.01,
		"description": "Delay between taking a measurement and delivering it."},
}

var sensor_name: String = "Sensor"
var sensor_type: String = "sensor"
var description: String = ""
var enabled: bool = true
var mount_position: Vector3 = Vector3.ZERO
var mount_basis: Basis = Basis.IDENTITY
var noise_seed: int = 1
## Most recent delivered reading (null until the first one arrives).
var latest: SensorReading = null
var samples_taken: int = 0

var _rng := RandomNumberGenerator.new()
var _params: Dictionary = {}
var _defaults: Dictionary = {}
var _next_sample_time: float = 0.0
var _pending: Array[SensorReading] = []
var _params_ready: bool = false


func _init() -> void:
	_rng.seed = noise_seed


# Parameters are built on first use: subclass overrides of _own_parameters()
# are not dispatched while the base-class constructor is still running.
func _ensure_params() -> void:
	if _params_ready:
		return
	_params_ready = true
	var specs := parameter_specs()
	for key in specs:
		_defaults[key] = float(specs[key].get("default", 0.0))
	_params = _defaults.duplicate()


## Parameters of this sensor: the common timing parameters (if used) plus its own.
func parameter_specs() -> Dictionary:
	var specs: Dictionary = {}
	if _uses_timing():
		specs = COMMON_PARAMETERS.duplicate(true)
	specs.merge(_own_parameters())
	return specs


## Override: the sensor's own parameter table.
func _own_parameters() -> Dictionary:
	return {}


## Override and return false for sensors that are not sampled (cameras).
func _uses_timing() -> bool:
	return true


## Sets the default (and current) value of a parameter; used by subclasses.
func define_default(key: String, value: float) -> void:
	_ensure_params()
	_defaults[key] = value
	_params[key] = value


func has_param(key: String) -> bool:
	_ensure_params()
	return _params.has(key)


func get_param(key: String) -> float:
	_ensure_params()
	return _params.get(key, 0.0)


func set_param(key: String, value: float) -> float:
	_ensure_params()
	var specs := parameter_specs()
	if not specs.has(key) or is_nan(value):
		return get_param(key)
	_params[key] = clampf(value, specs[key]["min"], specs[key]["max"])
	return _params[key]


func get_default(key: String) -> float:
	_ensure_params()
	return _defaults.get(key, 0.0)


func reset_parameters() -> void:
	_ensure_params()
	_params = _defaults.duplicate()


func to_dict() -> Dictionary:
	_ensure_params()
	return {"enabled": enabled, "parameters": _params.duplicate()}


func apply_dict(data: Dictionary) -> void:
	if typeof(data.get("enabled")) == TYPE_BOOL:
		enabled = data["enabled"]
	var parameters = data.get("parameters", {})
	if typeof(parameters) == TYPE_DICTIONARY:
		for key in parameters:
			if has_param(key) and (typeof(parameters[key]) == TYPE_FLOAT or typeof(parameters[key]) == TYPE_INT):
				set_param(key, float(parameters[key]))


## Restores the seeded noise sequence and clears readings (simulation reset).
func reset() -> void:
	_rng.seed = noise_seed
	_next_sample_time = 0.0
	_pending.clear()
	latest = null
	samples_taken = 0
	_reset_state()


## Override: clear internal state such as biases or partial scans.
func _reset_state() -> void:
	pass


## Called by SensorSuite after every physics step.
func update(context: StepContext, host: RigidSimBody) -> void:
	var now := context.sim_time + context.dt
	if enabled and _uses_timing():
		_on_step(context, host)
		if now + 1e-9 >= _next_sample_time:
			var period := 1.0 / maxf(get_param("rate_hz"), 1e-3)
			_next_sample_time += period
			if _next_sample_time <= now + 1e-9:
				_next_sample_time = now + period
			var reading := SensorReading.new()
			reading.time = now
			reading.available_time = now + get_param("latency")
			_measure(reading, context, host)
			samples_taken += 1
			_pending.append(reading)
	while not _pending.is_empty() and _pending[0].available_time <= now + 1e-9:
		latest = _pending.pop_front()


## Override: work done every physics step (integrating biases, partial scans).
func _on_step(_context: StepContext, _host: RigidSimBody) -> void:
	pass


## Override: fill reading.values, reading.truth and reading.valid.
func _measure(_reading: SensorReading, _context: StepContext, _host: RigidSimBody) -> void:
	pass


## True if enabled and a valid reading no older than max_age is available.
func has_fresh_reading(now: float, max_age: float) -> bool:
	return enabled and latest != null and latest.valid and latest.age(now) <= max_age


func gaussian(sigma: float) -> float:
	return _rng.randfn(0.0, sigma) if sigma > 0.0 else 0.0


func mount_world_position(host: SimBody) -> Vector3:
	return host.local_to_world_point(mount_position)


func mount_world_basis(host: SimBody) -> Basis:
	return Basis(host.orientation) * mount_basis
