## Doppler velocity log (DVL) with four beams in a Janus configuration.
##
## Each beam points `beam_angle` from the downward boresight, at 45°, 135°,
## 225° and 315° azimuth. A beam has bottom lock when the seabed lies within
## range along it (ray cast against the bathymetry). Each locked beam measures
## the velocity of the transducer over the seabed projected on its axis, with
## noise sigma = absolute + relative · speed. With three or four locked beams
## the 3-D velocity is solved by least squares, as real DVLs do; with fewer
## the reading is invalid (no bottom lock). Altitude = mean beam range ×
## cos(beam angle).
##
## Simplifications: no water-track mode, beam-pattern footprint, sound-speed
## error or bottom-type dependence; velocity is reported in the vehicle frame.
class_name DvlSensor
extends Sensor

const PARAMETERS := {
	"max_altitude": {"label": "Max bottom-lock altitude", "unit": "m", "min": 0.5, "max": 200.0, "default": 50.0, "step": 0.5,
		"description": "Beyond this altitude the beams lose the seabed and the DVL has no bottom lock."},
	"min_altitude": {"label": "Min altitude", "unit": "m", "min": 0.05, "max": 3.0, "default": 0.3, "step": 0.05,
		"description": "Blanking distance: closer than this a beam cannot measure."},
	"beam_angle": {"label": "Beam angle", "unit": "°", "min": 15.0, "max": 45.0, "default": 30.0, "step": 0.5,
		"description": "Angle of each beam from the vertical boresight."},
	"velocity_noise_abs": {"label": "Velocity noise (abs, 1σ)", "unit": "mm/s", "min": 0.0, "max": 50.0, "default": 2.0, "step": 0.5,
		"description": "Speed-independent noise on each beam velocity."},
	"velocity_noise_rel": {"label": "Velocity noise (rel, 1σ)", "unit": "%", "min": 0.0, "max": 5.0, "default": 0.3, "step": 0.05,
		"description": "Speed-proportional noise on each beam velocity."},
}
const BEAM_AZIMUTHS := [45.0, 135.0, 225.0, 315.0]


func _init() -> void:
	sensor_name = "DVL"
	sensor_type = "dvl"
	description = "Velocity over the seabed and altitude (4-beam Doppler)."
	define_default("rate_hz", 5.0)
	define_default("latency", 0.1)


func _own_parameters() -> Dictionary:
	return PARAMETERS


## Beam unit vectors in sensor axes (boresight = -Y).
func beam_directions() -> Array[Vector3]:
	var a := deg_to_rad(get_param("beam_angle"))
	var beams: Array[Vector3] = []
	for azimuth in BEAM_AZIMUTHS:
		var az := deg_to_rad(azimuth)
		beams.append(Vector3(sin(a) * cos(az), -cos(a), sin(a) * sin(az)))
	return beams


func _measure(reading: SensorReading, context: StepContext, host: RigidSimBody) -> void:
	var world := context.world
	var origin := mount_world_position(host)
	var to_world := mount_world_basis(host)
	var cos_a := cos(deg_to_rad(get_param("beam_angle")))
	var max_slant := get_param("max_altitude") / cos_a
	var v_point := host.velocity_at_point(origin)
	var v_sensor := to_world.transposed() * v_point
	var sigma := get_param("velocity_noise_abs") / 1000.0 + get_param("velocity_noise_rel") / 100.0 * v_point.length()
	var ranges: Array = []
	var locked: Array[Vector3] = []
	var radial: Array[float] = []
	for beam in beam_directions():
		var r := world.raycast(origin, to_world * beam, max_slant)
		ranges.append(r)
		if r < INF and r * cos_a >= get_param("min_altitude"):
			locked.append(beam)
			radial.append(beam.dot(v_sensor) + gaussian(sigma))
	var true_body := host.orientation.inverse() * v_point
	# True altitude: vertical distance to the nearest surface below (seabed or structure).
	var true_altitude := world.raycast(origin, Vector3.DOWN, 1000.0)
	var truth_vehicle := WorldFrame.body_to_vehicle(true_body)
	reading.truth = {"forward": truth_vehicle.x, "starboard": truth_vehicle.y, "up": truth_vehicle.z, "altitude": true_altitude}
	reading.values = {"beam_ranges": ranges, "beams_locked": locked.size()}
	if locked.size() < 3:
		reading.valid = false
		return
	# Least squares: (Σ b bᵀ) v = Σ b r
	var normal := DenseMatrix.new(3, 3)
	var rhs := PackedFloat64Array([0.0, 0.0, 0.0])
	for i in locked.size():
		var b := locked[i]
		var comps := [b.x, b.y, b.z]
		for r in 3:
			rhs[r] += comps[r] * radial[i]
			for c in 3:
				normal.set_at(r, c, normal.at(r, c) + comps[r] * comps[c])
	var solution := normal.inverse().multiply_vector(rhs)
	var v_measured_body := mount_basis * Vector3(solution[0], solution[1], solution[2])
	var measured := WorldFrame.body_to_vehicle(v_measured_body)
	var altitude_sum := 0.0
	for i in ranges.size():
		if ranges[i] < INF:
			altitude_sum += ranges[i] * cos_a
	var finite := ranges.filter(func(r): return r < INF).size()
	reading.values.merge({
		"forward": measured.x, "starboard": measured.y, "up": measured.z,
		"altitude": altitude_sum / maxf(finite, 1),
	})
