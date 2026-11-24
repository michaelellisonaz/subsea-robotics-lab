## Solid finite cylinder between two end points (pipe sections, flanges).
class_name CylinderPrimitive
extends StructurePrimitive

var start: Vector3
var end: Vector3
var radius: float


func _init(p_start: Vector3 = Vector3.ZERO, p_end: Vector3 = Vector3.RIGHT, p_radius: float = 0.5, p_tag: String = "") -> void:
	start = p_start
	end = p_end
	radius = p_radius
	tag = p_tag
	_update_aabb()


func length() -> float:
	return start.distance_to(end)


func axis() -> Vector3:
	return (end - start).normalized()


func shift(offset: Vector3) -> void:
	start += offset
	end += offset
	_update_aabb()


func intersect_ray(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	if not StructurePrimitive.ray_hits_aabb(aabb, origin, direction, max_distance):
		return INF
	var u := axis()
	var span := length()
	var oc := origin - start
	var d_perp := direction - u * direction.dot(u)
	var oc_perp := oc - u * oc.dot(u)
	var a := d_perp.length_squared()
	var b := 2.0 * oc_perp.dot(d_perp)
	var c := oc_perp.length_squared() - radius * radius
	var best := INF
	if a > 1e-12:
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var root := sqrt(discriminant)
			for t in [(-b - root) / (2.0 * a), (-b + root) / (2.0 * a)]:
				if t >= 0.0 and t <= max_distance:
					var s: float = (oc + direction * t).dot(u)
					if s >= 0.0 and s <= span:
						best = minf(best, t)
	var dn := direction.dot(u)
	if absf(dn) > 1e-12:
		for cap in [start, end]:
			var t: float = (cap - origin).dot(u) / dn
			if t >= 0.0 and t <= minf(max_distance, best):
				if (origin + direction * t - cap).length_squared() <= radius * radius:
					best = t
	return best


func penetration(point: Vector3, sphere_radius: float) -> Dictionary:
	var u := axis()
	var span := length()
	var s := (point - start).dot(u)
	if s < -sphere_radius or s > span + sphere_radius:
		return {}
	var radial := (point - start) - u * s
	var distance := radial.length()
	var reach := radius + sphere_radius
	if distance >= reach:
		return {}
	var normal := Vector3.UP
	if distance > 1e-6:
		normal = radial / distance
	var depth := reach - distance
	var cap_depth := minf(s + sphere_radius, span + sphere_radius - s)
	if cap_depth < depth:
		depth = cap_depth
		normal = -u if s < span * 0.5 else u
	return {"depth": depth, "normal": normal}


func _update_aabb() -> void:
	var lo := Vector3(minf(start.x, end.x), minf(start.y, end.y), minf(start.z, end.z)) - Vector3.ONE * radius
	var hi := Vector3(maxf(start.x, end.x), maxf(start.y, end.y), maxf(start.z, end.z)) + Vector3.ONE * radius
	aabb = AABB(lo, hi - lo)
