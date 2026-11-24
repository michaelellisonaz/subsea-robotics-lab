## Pressure (depth) sensor.
##
## Measures absolute pressure at its mounting point from the hydrostatic model
## (p_atm + rho · g · depth) with Gaussian noise and a fixed bias, then
## converts it to depth with its OWN assumed density and standard gravity.
## If the real water density differs from the assumed one, the reported depth
## is proportionally wrong - as on a real instrument.
class_name DepthSensor
extends Sensor

const STANDARD_GRAVITY := 9.81
const PARAMETERS := {
	"pressure_noise": {"label": "Pressure noise (1σ)", "unit": "Pa", "min": 0.0, "max": 2000.0, "default": 50.0, "step": 1.0,
		"description": "Random pressure error per reading. 100 Pa ≈ 1 cm of seawater."},
	"pressure_bias": {"label": "Pressure offset", "unit": "Pa", "min": -5000.0, "max": 5000.0, "default": 0.0, "step": 10.0,
		"description": "Fixed calibration offset of the pressure reading."},
	"assumed_density": {"label": "Conversion density", "unit": "kg/m³", "min": 990.0, "max": 1060.0, "default": 1025.0, "step": 0.5,
		"description": "Density the instrument uses to convert pressure to depth (with g = 9.81 m/s²)."},
}


func _init() -> void:
	sensor_name = "Depth"
	sensor_type = "depth"
	description = "Pressure sensor converted to depth."
	define_default("rate_hz", 10.0)
	define_default("latency", 0.02)


func _own_parameters() -> Dictionary:
	return PARAMETERS


func _measure(reading: SensorReading, context: StepContext, host: RigidSimBody) -> void:
	var true_depth := maxf(-mount_world_position(host).y, 0.0)
	var pressure := context.environment.absolute_pressure_at_depth(true_depth) \
		+ get_param("pressure_bias") + gaussian(get_param("pressure_noise"))
	var depth := (pressure - EnvironmentConfig.STANDARD_ATMOSPHERE_PA) / (get_param("assumed_density") * STANDARD_GRAVITY)
	reading.values = {"depth": depth, "pressure_bar": pressure / 1.0e5}
	reading.truth = {"depth": true_depth}
