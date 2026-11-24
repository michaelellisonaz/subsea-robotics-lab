## Magnetic compass (heading).
##
## Reports the vehicle heading plus a fixed deviation (e.g. from the vehicle's
## own steel and electrical currents, or uncorrected declination) and white
## noise. Magnetic field variation over the site and tilt errors are not
## modelled.
class_name CompassSensor
extends Sensor

const PARAMETERS := {
	"heading_noise": {"label": "Heading noise (1σ)", "unit": "°", "min": 0.0, "max": 10.0, "default": 0.5, "step": 0.1,
		"description": "Random heading error per reading."},
	"deviation": {"label": "Deviation", "unit": "°", "min": -30.0, "max": 30.0, "default": 0.0, "step": 0.1,
		"description": "Fixed heading offset (uncompensated magnetic deviation)."},
}


func _init() -> void:
	sensor_name = "Compass"
	sensor_type = "compass"
	description = "Magnetic heading."
	define_default("rate_hz", 10.0)
	define_default("latency", 0.05)


func _own_parameters() -> Dictionary:
	return PARAMETERS


func _measure(reading: SensorReading, _context: StepContext, host: RigidSimBody) -> void:
	var heading := WorldFrame.attitude_of(host.orientation).z
	reading.values = {"heading": fposmod(heading + get_param("deviation") + gaussian(get_param("heading_noise")), 360.0)}
	reading.truth = {"heading": heading}
