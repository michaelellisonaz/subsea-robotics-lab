## A fixed subsea structure made of solid primitives, registered with the
## WorldModel. Sensors ray-cast against it, vehicles and objects collide with
## it. Defects (corrosion, cracks ...) are kept as metadata with their true
## positions, for rendering and for evaluating future inspection tasks.
class_name Structure
extends RefCounted

## Emitted when the geometry is rebuilt or moved (renderers listen).
signal geometry_changed()

var structure_name: String = "Structure"
var primitives: Array[StructurePrimitive] = []
var aabb: AABB = AABB()
## Each defect: {"type": ..., "position": Vector3, ... type-specific keys}.
var defects: Array[Dictionary] = []


func raycast(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	if primitives.is_empty() or not StructurePrimitive.ray_hits_aabb(aabb, origin, direction, max_distance):
		return INF
	var best := max_distance
	var hit := false
	for primitive in primitives:
		var t := primitive.intersect_ray(origin, direction, best)
		if t <= best:
			best = t
			hit = true
	return best if hit else INF


## Deepest overlap of a sphere with any primitive:
## {"depth", "normal", "primitive", "structure"} or {}.
func penetration(point: Vector3, radius: float) -> Dictionary:
	if not aabb.grow(radius).has_point(point):
		return {}
	var best := {}
	for primitive in primitives:
		if not primitive.aabb.grow(radius).has_point(point):
			continue
		var result := primitive.penetration(point, radius)
		if not result.is_empty() and (best.is_empty() or result["depth"] > best["depth"]):
			best = result
			best["primitive"] = primitive
	if not best.is_empty():
		best["structure"] = self
	return best


## Returns repair / work state to the initial condition (simulation reset).
func reset_state() -> void:
	pass


func shift(offset: Vector3) -> void:
	for primitive in primitives:
		primitive.shift(offset)
	for defect in defects:
		defect["position"] += offset
	_update_aabb()
	geometry_changed.emit()


func _update_aabb() -> void:
	if primitives.is_empty():
		aabb = AABB()
		return
	aabb = primitives[0].aabb
	for primitive in primitives:
		aabb = aabb.merge(primitive.aabb)
