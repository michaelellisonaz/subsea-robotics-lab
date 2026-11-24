## Geometric description of the simulated world: horizontal extent, sea
## surface and seabed. Pure data and queries - no rendering.
##
## Positioning helpers convert between east/north/depth (how people and
## future mission files describe locations) and the internal world frame.
class_name WorldModel
extends RefCounted

## The sea surface is the plane y = 0.
const SURFACE_Y := 0.0

## Half the side length of the square simulation domain, m.
var half_extent: float = 500.0
var environment: EnvironmentConfig
var bathymetry: Bathymetry
## Fixed structures on the site (pipelines ...). Sensors and contact use them.
var structures: Array[Structure] = []


func _init(p_environment: EnvironmentConfig, p_bathymetry: Bathymetry = null) -> void:
	environment = p_environment
	bathymetry = p_bathymetry if p_bathymetry != null else Bathymetry.new()


## Y coordinate of the seabed reference level (the configured water depth).
func seabed_reference_y() -> float:
	return SURFACE_Y - environment.water_depth


## Y coordinate of the actual seabed at world (x, z), including relief.
func seabed_y_at(x: float, z: float) -> float:
	return seabed_reference_y() + bathymetry.height_offset(x, z)


## Water current velocity at a point, m/s. Above the bottom boundary layer
## the current is uniform; inside it the speed follows a 1/7 power law of the
## height above the local seabed (zero at the seabed).
func current_velocity_at(p: Vector3) -> Vector3:
	var free_stream := environment.current_velocity()
	var layer := environment.current_boundary_layer
	if layer <= 0.0:
		return free_stream
	var height := p.y - seabed_y_at(p.x, p.z)
	if height >= layer:
		return free_stream
	if height <= 0.0:
		return Vector3.ZERO
	return free_stream * pow(height / layer, 1.0 / 7.0)


## Distance along a ray from origin to the seabed, or INF if the seabed is not
## reached within max_distance. Ray marching with a step that grows with the
## height above the seabed (safe because the relief is bounded), refined by
## bisection to millimetre level. Used by acoustic and range sensors.
func raycast_seabed(origin: Vector3, direction: Vector3, max_distance: float, min_step: float = 0.4) -> float:
	var d := direction.normalized()
	var height := origin.y - seabed_y_at(origin.x, origin.z)
	if height <= 0.0:
		return 0.0
	var relief_margin := 2.0 * bathymetry.max_relief()
	if d.y >= 0.0 and height > relief_margin:
		return INF
	# Exact answer when the whole ray segment to the plane hit lies inside the
	# level test area (a disc, so the segment between two inside points is too).
	if d.y < 0.0 and bathymetry.is_level_at(origin.x, origin.z):
		var t_plane := (origin.y - seabed_reference_y()) / -d.y
		var plane_hit := origin + d * t_plane
		if bathymetry.is_level_at(plane_hit.x, plane_hit.z):
			return t_plane if t_plane <= max_distance else INF
	var previous_t := 0.0
	var t := 0.0
	while t < max_distance:
		t = minf(t + maxf(min_step, (height - relief_margin) * 0.9), max_distance)
		var p := origin + d * t
		height = p.y - seabed_y_at(p.x, p.z)
		if height <= 0.0:
			var lo := previous_t
			var hi := t
			for i in 14:
				var mid := (lo + hi) * 0.5
				var q := origin + d * mid
				if q.y - seabed_y_at(q.x, q.z) > 0.0:
					lo = mid
				else:
					hi = mid
			return (lo + hi) * 0.5
		if d.y >= 0.0 and height > relief_margin:
			return INF
		previous_t = t
	return INF


func add_structure(structure: Structure) -> void:
	if not structures.has(structure):
		structures.append(structure)


func remove_structure(structure: Structure) -> void:
	structures.erase(structure)


## Moves every structure (the seabed moved because the water depth changed).
func shift_structures(offset: Vector3) -> void:
	for structure in structures:
		structure.shift(offset)


## Distance along a ray to the nearest surface: seabed or structure (or INF).
func raycast(origin: Vector3, direction: Vector3, max_distance: float, min_step: float = 0.4) -> float:
	var d := direction.normalized()
	var best := raycast_seabed(origin, d, max_distance, min_step)
	for structure in structures:
		var t := structure.raycast(origin, d, minf(best, max_distance))
		if t < best:
			best = t
	return best


## Structures whose bounds come within `radius` of `center`.
func structures_near(center: Vector3, radius: float) -> Array[Structure]:
	var result: Array[Structure] = []
	for structure in structures:
		if structure.aabb.grow(radius).has_point(center):
			result.append(structure)
	return result


## Deepest overlap of a sphere with the given structures (all if null):
## {"depth", "normal", "primitive", "structure"} or {}.
func structure_penetration(point: Vector3, radius: float, candidates: Array[Structure] = []) -> Dictionary:
	var best := {}
	for structure in (candidates if not candidates.is_empty() else structures):
		var result := structure.penetration(point, radius)
		if not result.is_empty() and (best.is_empty() or result["depth"] > best["depth"]):
			best = result
	return best


func is_within_bounds(p: Vector3) -> bool:
	return absf(p.x) <= half_extent and absf(p.z) <= half_extent


## True if the point is inside the domain, below the surface and above the seabed.
func is_in_water(p: Vector3) -> bool:
	return is_within_bounds(p) and p.y <= SURFACE_Y and p.y >= seabed_y_at(p.x, p.z)


func clamp_to_bounds(p: Vector3, margin: float = 0.0) -> Vector3:
	var limit := maxf(half_extent - margin, 0.0)
	return Vector3(clampf(p.x, -limit, limit), p.y, clampf(p.z, -limit, limit))


## Clamps a point into the water column: inside the domain, between the
## seabed (+ seabed_margin) and the surface (- surface_margin).
func clamp_to_water(p: Vector3, seabed_margin: float = 0.0, surface_margin: float = 0.0) -> Vector3:
	var q := clamp_to_bounds(p)
	var floor_y := seabed_y_at(q.x, q.z) + seabed_margin
	var ceiling_y := maxf(SURFACE_Y - surface_margin, floor_y)
	q.y = clampf(q.y, floor_y, ceiling_y)
	return q


## World position from metres east, metres north and depth below the surface.
func position_from_enu_depth(east: float, north: float, depth: float) -> Vector3:
	return Vector3(east, -depth, -north)


## World position on the seabed at (east, north), raised by a clearance.
func place_on_seabed(east: float, north: float, clearance: float = 0.0) -> Vector3:
	var p := position_from_enu_depth(east, north, 0.0)
	p.y = seabed_y_at(p.x, p.z) + clearance
	return p
