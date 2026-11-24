## Solid axis-aligned box (pipe supports, sleepers, small structures).
class_name BoxPrimitive
extends StructurePrimitive

var center: Vector3
var half_extents: Vector3


func _init(p_center: Vector3 = Vector3.ZERO, p_half_extents: Vector3 = Vector3.ONE * 0.5, p_tag: String = "") -> void:
	center = p_center
	half_extents = p_half_extents
	tag = p_tag
	_update_aabb()


func shift(offset: Vector3) -> void:
	center += offset
	_update_aabb()


func intersect_ray(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	var t_min := 0.0
	var t_max := max_distance
	for axis in 3:
		var o := origin[axis] - center[axis]
		var d := direction[axis]
		var h := half_extents[axis]
		if absf(d) < 1e-12:
			if absf(o) > h:
				return INF
		else:
			var t1 := (-h - o) / d
			var t2 := (h - o) / d
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			t_min = maxf(t_min, t1)
			t_max = minf(t_max, t2)
			if t_min > t_max:
				return INF
	return t_min


func penetration(point: Vector3, sphere_radius: float) -> Dictionary:
	var local := point - center
	var best_depth := INF
	var best_normal := Vector3.UP
	for axis in 3:
		var reach: float = half_extents[axis] + sphere_radius
		var overlap: float = reach - absf(local[axis])
		if overlap <= 0.0:
			return {}
		if overlap < best_depth:
			best_depth = overlap
			best_normal = Vector3.ZERO
			best_normal[axis] = 1.0 if local[axis] >= 0.0 else -1.0
	return {"depth": best_depth, "normal": best_normal}


func _update_aabb() -> void:
	aabb = AABB(center - half_extents, half_extents * 2.0)
