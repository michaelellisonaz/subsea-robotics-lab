## Seabed shape (bathymetry) relative to the seabed reference depth.
##
## The central test area is kept level so the reference grid reads cleanly;
## gentle procedural relief fades in beyond it. The same function is used by
## the renderer (to build the mesh) and by simulation code (seabed contact,
## camera limits), so visuals and simulation agree on where the seabed is.
## Heights are deterministic for a given seed.
class_name Bathymetry
extends RefCounted

## Radius of the level test area around the origin, m.
var flat_radius: float = 35.0
## Distance over which relief fades in beyond the level area, m.
var transition_width: float = 60.0
## Amplitude of broad seabed undulations, m.
var broad_amplitude: float = 2.5
## Amplitude of smaller sediment mounds, m.
var detail_amplitude: float = 0.6

var _broad := FastNoiseLite.new()
var _detail := FastNoiseLite.new()


func _init(noise_seed: int = 7) -> void:
	_broad.seed = noise_seed
	_broad.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_broad.frequency = 0.008
	_broad.fractal_octaves = 3
	_detail.seed = noise_seed + 101
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 0.05
	_detail.fractal_octaves = 2


## Height of the seabed above the reference level at world (x, z), m.
func height_offset(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var weight := smoothstep(flat_radius, flat_radius + transition_width, r)
	if weight <= 0.0:
		return 0.0
	return weight * (_broad.get_noise_2d(x, z) * broad_amplitude + _detail.get_noise_2d(x, z) * detail_amplitude)


## True where the seabed is exactly the reference level (the level test area).
func is_level_at(x: float, z: float) -> bool:
	return x * x + z * z <= flat_radius * flat_radius


## Largest possible absolute height offset, m.
func max_relief() -> float:
	return broad_amplitude + detail_amplitude
