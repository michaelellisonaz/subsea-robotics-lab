## USBL acoustic positioning: a transceiver on the support vessel (at the sea
## surface above the site origin) interrogates the vehicle's transponder.
##
## The fix is computed from slant range and the two arrival angles, each with
## Gaussian error, so position error grows with distance (angle error x
## range). Delivery delay = two-way acoustic travel time (sound speed
## 1500 m/s) + processing delay + the common latency. Ray bending, multipath,
## vessel motion and dropouts are not modelled.
class_name UsblSensor
extends Sensor

const SOUND_SPEED := 1500.0
const TRANSCEIVER_POSITION := Vector3.ZERO
const PARAMETERS := {
	"range_noise": {"label": "Range noise (1σ)", "unit": "m", "min": 0.0, "max": 2.0, "default": 0.1, "step": 0.01,
		"description": "Error of the measured slant range."},
	"angle_noise": {"label": "Angle noise (1σ)", "unit": "°", "min": 0.0, "max": 3.0, "default": 0.25, "step": 0.01,
		"description": "Error of each arrival angle; position error grows with distance."},
	"processing_delay": {"label": "Processing delay", "unit": "s", "min": 0.0, "max": 2.0, "default": 0.2, "step": 0.01,
		"description": "Time to compute the fix after the reply arrives."},
}


func _init() -> void:
	sensor_name = "USBL"
	sensor_type = "usbl"
	description = "Acoustic position fix from the support vessel."
	define_default("rate_hz", 1.0)
	define_default("latency", 0.0)


func _own_parameters() -> Dictionary:
	return PARAMETERS


func _measure(reading: SensorReading, _context: StepContext, host: RigidSimBody) -> void:
	var p := mount_world_position(host)
	var relative := p - TRANSCEIVER_POSITION
	var slant := relative.length()
	var direction := relative / maxf(slant, 1e-6)
	var azimuth := atan2(direction.x, direction.z) + deg_to_rad(gaussian(get_param("angle_noise")))
	var elevation := asin(clampf(direction.y, -1.0, 1.0)) + deg_to_rad(gaussian(get_param("angle_noise")))
	var measured_range := slant + gaussian(get_param("range_noise"))
	var fix := TRANSCEIVER_POSITION + Vector3(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth)) * measured_range
	reading.available_time += 2.0 * slant / SOUND_SPEED + get_param("processing_delay")
	reading.values = {"east": fix.x, "north": -fix.z, "depth": -fix.y, "slant_range": measured_range}
	reading.truth = {"east": p.x, "north": -p.z, "depth": -p.y, "slant_range": slant}
