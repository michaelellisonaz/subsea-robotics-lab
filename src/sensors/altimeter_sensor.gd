## Single-beam acoustic altimeter pointing down along the sensor's -Y axis.
## Range to the seabed by ray cast, with noise sigma = absolute + relative ·
## range. Invalid when the seabed is closer than the minimum range or beyond
## the maximum range. (Echo detection, beam width and bottom type are not
## modelled.)
class_name AltimeterSensor
extends Sensor

const PARAMETERS := {
	"max_range": {"label": "Max range", "unit": "m", "min": 1.0, "max": 100.0, "default": 30.0, "step": 0.5,
		"description": "Beyond this range there is no echo."},
	"min_range": {"label": "Min range", "unit": "m", "min": 0.05, "max": 2.0, "default": 0.15, "step": 0.05,
		"description": "Blanking distance."},
	"noise_abs": {"label": "Range noise (abs, 1σ)", "unit": "m", "min": 0.0, "max": 0.5, "default": 0.01, "step": 0.005,
		"description": "Range-independent noise."},
	"noise_rel": {"label": "Range noise (rel, 1σ)", "unit": "%", "min": 0.0, "max": 2.0, "default": 0.1, "step": 0.05,
		"description": "Range-proportional noise."},
}


func _init() -> void:
	sensor_name = "Altimeter"
	sensor_type = "altimeter"
	description = "Distance to the seabed below the bow."
	define_default("rate_hz", 5.0)
	define_default("latency", 0.05)


func _own_parameters() -> Dictionary:
	return PARAMETERS


func _measure(reading: SensorReading, context: StepContext, host: RigidSimBody) -> void:
	var origin := mount_world_position(host)
	var direction := mount_world_basis(host) * Vector3.DOWN
	var r := context.world.raycast(origin, direction, get_param("max_range"))
	reading.truth = {"range": r}
	if r == INF or r < get_param("min_range"):
		reading.valid = false
		reading.values = {"range": INF}
		return
	reading.values = {"range": r + gaussian(get_param("noise_abs") + get_param("noise_rel") / 100.0 * r)}
