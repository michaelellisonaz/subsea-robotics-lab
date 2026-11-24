## Forward-looking imaging (multibeam) sonar, simplified.
##
## The head looks forward (sensor -Z), tilted down by `tilt`. It forms BEAMS
## horizontal beams across `horizontal_fov`; each beam has a vertical width
## sampled by VERTICAL_RAYS rays cast against the bathymetry. Between
## consecutive hits of a beam the seabed is treated as continuous, so every
## range bin it spans receives an echo. Echo strength follows Lambert's law
## (cos² of the incidence angle on the - assumed horizontal - seabed) with
## time-varied gain compensating spreading loss, then multiplicative speckle
## and an additive noise floor.
##
## Output image: BEAMS x BINS intensities 0..1, stored bin-major
## (index = bin * BEAMS + beam), range bins spanning 0..max_range.
##
## The ray casting for one ping is spread over the physics steps of the ping
## period to keep frame times smooth, so one image combines poses from up to
## one period (≤ 0.5 s at the default rate) - a small time smear.
##
## Only the seabed is detected (no other structures exist yet); acoustic
## multipath, absorption, beam side lobes and water-column targets are not
## modelled.
class_name ImagingSonar
extends Sensor

const BEAMS := 64
const BINS := 128
const VERTICAL_RAYS := 6
const PARAMETERS := {
	"max_range": {"label": "Range", "unit": "m", "min": 5.0, "max": 100.0, "default": 30.0, "step": 1.0,
		"description": "Maximum displayed and processed range."},
	"horizontal_fov": {"label": "Horizontal field of view", "unit": "°", "min": 30.0, "max": 130.0, "default": 120.0, "step": 1.0,
		"description": "Total width of the fan of beams."},
	"tilt": {"label": "Tilt", "unit": "°", "min": -45.0, "max": 0.0, "default": -15.0, "step": 0.5,
		"description": "Downward tilt of the sonar head."},
	"vertical_beamwidth": {"label": "Vertical beam width", "unit": "°", "min": 5.0, "max": 30.0, "default": 20.0, "step": 0.5,
		"description": "Vertical opening of every beam."},
	"speckle": {"label": "Speckle", "unit": "", "min": 0.0, "max": 1.0, "default": 0.35, "step": 0.01,
		"description": "Strength of multiplicative speckle noise."},
	"noise_floor": {"label": "Noise floor", "unit": "", "min": 0.0, "max": 0.3, "default": 0.04, "step": 0.005,
		"description": "Additive background noise level."},
}

## Ray-march step for sonar rays, m (the seabed relief is smooth over tens of
## metres, and every hit is refined by bisection).
const MARCH_STEP := 1.0
## Size of the table of standard-normal samples used for speckle / noise.
const NOISE_TABLE_SIZE := 4093

var _buffer := PackedFloat32Array()
var _next_beam: int = 0
var _noise_table := PackedFloat32Array()


func _init() -> void:
	sensor_name = "Imaging sonar"
	sensor_type = "imaging_sonar"
	description = "Forward-looking acoustic image of the seabed ahead."
	define_default("rate_hz", 4.0)
	define_default("latency", 0.05)
	_clear_buffer()


func _own_parameters() -> Dictionary:
	return PARAMETERS


func _reset_state() -> void:
	_clear_buffer()
	_noise_table.resize(NOISE_TABLE_SIZE)
	for i in NOISE_TABLE_SIZE:
		_noise_table[i] = gaussian(1.0)


func _clear_buffer() -> void:
	_buffer.resize(BEAMS * BINS)
	_buffer.fill(0.0)
	_next_beam = 0


func _on_step(context: StepContext, host: RigidSimBody) -> void:
	var steps_per_ping := maxi(1, floori(1.0 / (get_param("rate_hz") * context.dt)))
	var per_step := ceili(float(BEAMS) / steps_per_ping)
	for i in per_step:
		if _next_beam >= BEAMS:
			break
		_scan_beam(_next_beam, context.world, host)
		_next_beam += 1


func _measure(reading: SensorReading, context: StepContext, host: RigidSimBody) -> void:
	while _next_beam < BEAMS:
		_scan_beam(_next_beam, context.world, host)
		_next_beam += 1
	var image := PackedFloat32Array()
	image.resize(BEAMS * BINS)
	# Speckle and noise floor: Gaussian samples drawn from a pre-generated
	# table at a random offset each ping (cheap; a prime-sized table and two
	# different strides keep the pattern from repeating visibly).
	if _noise_table.is_empty():
		_reset_state()
	var speckle := get_param("speckle")
	var floor_level := get_param("noise_floor")
	var offset := _rng.randi_range(0, NOISE_TABLE_SIZE - 1)
	for i in image.size():
		var echo := _buffer[i]
		if echo > 0.0:
			echo *= maxf(0.0, 1.0 + speckle * _noise_table[(offset + i * 7) % NOISE_TABLE_SIZE])
		image[i] = clampf(echo + floor_level * absf(_noise_table[(offset + i * 13 + 101) % NOISE_TABLE_SIZE]), 0.0, 1.0)
	reading.values = {
		"image": image, "beams": BEAMS, "bins": BINS,
		"max_range": get_param("max_range"), "horizontal_fov": get_param("horizontal_fov"),
	}
	_clear_buffer()


## Azimuth of a beam centre, radians (positive to starboard).
func beam_azimuth(beam: int) -> float:
	var half := deg_to_rad(get_param("horizontal_fov")) * 0.5
	return -half + (beam + 0.5) / BEAMS * 2.0 * half


func _scan_beam(beam: int, world: WorldModel, host: RigidSimBody) -> void:
	var origin := mount_world_position(host)
	var to_world := mount_world_basis(host)
	var max_range := get_param("max_range")
	var azimuth := beam_azimuth(beam)
	var tilt := deg_to_rad(get_param("tilt"))
	var width := deg_to_rad(get_param("vertical_beamwidth"))
	var previous_range := INF
	var previous_strength := 0.0
	for v in VERTICAL_RAYS:
		var fraction := (v + 0.5) / VERTICAL_RAYS
		var elevation := tilt + width * (fraction - 0.5)
		var direction := to_world * Vector3(cos(elevation) * sin(azimuth), sin(elevation), -cos(elevation) * cos(azimuth))
		var r := world.raycast(origin, direction, max_range, MARCH_STEP)
		if r >= max_range:
			previous_range = INF
			continue
		var weight := 1.0 - absf(fraction - 0.5)  # beam pattern: stronger at the centre
		var incidence := absf(direction.normalized().y)
		var strength := weight * (0.25 + 0.75 * incidence * incidence) * 1.6
		var bin := clampi(int(r / max_range * BINS), 0, BINS - 1)
		if previous_range == INF:
			_add_echo(bin, beam, strength)
		else:
			var start := clampi(int(previous_range / max_range * BINS), 0, BINS - 1)
			var count := absi(bin - start)
			for k in count + 1:
				var t := float(k) / maxf(count, 1)
				_add_echo(start + signi(bin - start) * k, beam, lerpf(previous_strength, strength, t) / maxf(1.0, count * 0.35))
		previous_range = r
		previous_strength = strength


func _add_echo(bin: int, beam: int, strength: float) -> void:
	var index := bin * BEAMS + beam
	_buffer[index] = maxf(_buffer[index], strength)
