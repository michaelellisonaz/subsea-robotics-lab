## Downward-looking multibeam echosounder (bathymetric swath), simplified.
##
## BEAMS beams fan out across-track (in the sensor's X-Y plane, boresight -Y)
## over `swath_angle`. Each beam's range to the seabed comes from a ray cast,
## with range noise sigma = relative · range. The output is the seabed profile
## in sensor coordinates: across-track offset (+ starboard) and distance below
## the transducer, uncorrected for vehicle roll / pitch and not
## georeferenced (that needs navigation, a later stage).
##
## Beams that miss (beyond max range) are NAN.
class_name MultibeamSonar
extends Sensor

const BEAMS := 48
const PARAMETERS := {
	"swath_angle": {"label": "Swath angle", "unit": "°", "min": 30.0, "max": 150.0, "default": 120.0, "step": 1.0,
		"description": "Total across-track opening of the fan."},
	"max_range": {"label": "Max range", "unit": "m", "min": 5.0, "max": 200.0, "default": 60.0, "step": 1.0,
		"description": "Beams with no echo within this range report nothing."},
	"range_noise_rel": {"label": "Range noise (rel, 1σ)", "unit": "%", "min": 0.0, "max": 2.0, "default": 0.2, "step": 0.05,
		"description": "Range-proportional noise on each beam."},
}


func _init() -> void:
	sensor_name = "Multibeam"
	sensor_type = "multibeam"
	description = "Across-track seabed profile below the vehicle."
	define_default("rate_hz", 2.0)
	define_default("latency", 0.1)


func _own_parameters() -> Dictionary:
	return PARAMETERS


func beam_angle(beam: int) -> float:
	var half := deg_to_rad(get_param("swath_angle")) * 0.5
	return -half + beam * 2.0 * half / (BEAMS - 1)


func _measure(reading: SensorReading, context: StepContext, host: RigidSimBody) -> void:
	var origin := mount_world_position(host)
	var to_world := mount_world_basis(host)
	var across := PackedFloat32Array()
	var below := PackedFloat32Array()
	var true_across := PackedFloat32Array()
	var true_below := PackedFloat32Array()
	var hits := 0
	for beam in BEAMS:
		var angle := beam_angle(beam)
		var direction_s := Vector3(sin(angle), -cos(angle), 0.0)
		var r := context.world.raycast(origin, to_world * direction_s, get_param("max_range"))
		if r == INF:
			across.append(NAN)
			below.append(NAN)
			true_across.append(NAN)
			true_below.append(NAN)
			continue
		hits += 1
		var measured := r + gaussian(get_param("range_noise_rel") / 100.0 * r)
		across.append(measured * sin(angle))
		below.append(measured * cos(angle))
		true_across.append(r * sin(angle))
		true_below.append(r * cos(angle))
	reading.valid = hits > 0
	reading.values = {"across": across, "below": below, "hits": hits}
	reading.truth = {"across": true_across, "below": true_below}
