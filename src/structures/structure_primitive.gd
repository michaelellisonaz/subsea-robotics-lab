## Base class for a simple solid shape that structures are made of.
## Primitives provide what sensors and contact need: ray intersection and the
## penetration (depth + outward normal) of a sphere centred at a point.
class_name StructurePrimitive
extends RefCounted

## World-space bounding box (kept up to date by the primitive).
var aabb: AABB = AABB()
## Optional tag for visuals / metadata ("pipe", "flange", "support" ...).
var tag: String = ""


## Distance along a ray (unit direction) to the surface, or INF.
func intersect_ray(_origin: Vector3, _direction: Vector3, _max_distance: float) -> float:
	return INF


## For a sphere of `radius` at `point`: {"depth": > 0 if overlapping, "normal": outward}.
## Returns an empty dictionary when there is no overlap.
func penetration(_point: Vector3, _radius: float) -> Dictionary:
	return {}


func shift(_offset: Vector3) -> void:
	pass


## Slab test of a ray against an AABB: true if it may hit within max_distance.
static func ray_hits_aabb(box: AABB, origin: Vector3, direction: Vector3, max_distance: float) -> bool:
	var t_min := 0.0
	var t_max := max_distance
	for axis in 3:
		var o := origin[axis]
		var d := direction[axis]
		var lo := box.position[axis]
		var hi := lo + box.size[axis]
		if absf(d) < 1e-12:
			if o < lo or o > hi:
				return false
		else:
			var t1 := (lo - o) / d
			var t2 := (hi - o) / d
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			t_min = maxf(t_min, t1)
			t_max = minf(t_max, t2)
			if t_min > t_max:
				return false
	return true
